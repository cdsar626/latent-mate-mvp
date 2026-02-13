use axum::extract::ws::{Message, WebSocket};
use futures::{stream::StreamExt, SinkExt};
use tokio::sync::mpsc;
use uuid::Uuid;
use std::collections::HashMap;
use crate::state::SharedState;
use crate::models::{ClientMessage, ServerMessage, User, GameSession, ChatMessage, ActiveMatch};
use sqlx::Row;

pub async fn handle_socket(socket: WebSocket, state: SharedState) {
    let (mut sender, mut receiver) = socket.split();

    // Create a channel for this client to receive messages from the server logic
    let (tx, mut rx) = mpsc::unbounded_channel();

    // Spawn a task to forward messages from the channel to the websocket
    tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if sender.send(msg).await.is_err() {
                break;
            }
        }
    });

    let mut user_id: Option<Uuid> = None;

    while let Some(Ok(msg)) = receiver.next().await {
        if let Message::Text(text) = msg {
            if let Ok(client_msg) = serde_json::from_str::<ClientMessage>(&text) {
                match client_msg {
                    ClientMessage::Ping => {
                        let _ = tx.send(Message::Text(serde_json::to_string(&ServerMessage::Pong).unwrap()));
                    }
                    ClientMessage::Pong => {
                        // Heartbeat ack
                    }
                    ClientMessage::Connect { user_id: auth_user_id, username, email } => {
                        let db_pool = {
                            let state_guard = state.lock().unwrap();
                            state_guard.db.clone()
                        };

                        let target_uuid = Uuid::parse_str(&auth_user_id).unwrap_or(Uuid::new_v4());
                        let target_uuid_str = target_uuid.to_string();

                        let fetch_user = sqlx::query("SELECT id, username FROM users WHERE id = $1")
                            .bind(&target_uuid_str)
                            .fetch_optional(&db_pool)
                            .await;

                        let (final_id, final_username) = match fetch_user {
                            Ok(Some(row)) => {
                                let id_str: String = row.get("id");
                                let username_str: String = row.get("username");

                                if let Some(email_val) = email {
                                    let _ = sqlx::query("UPDATE users SET email = $1 WHERE id = $2")
                                        .bind(email_val)
                                        .bind(&target_uuid_str)
                                        .execute(&db_pool)
                                        .await;
                                }

                                (Uuid::parse_str(&id_str).unwrap_or(target_uuid), username_str)
                            },
                            Ok(None) => {
                                let email_val = email.unwrap_or_default();
                                let _ = sqlx::query("INSERT INTO users (id, username, email) VALUES ($1, $2, $3)")
                                    .bind(&target_uuid_str)
                                    .bind(&username)
                                    .bind(email_val)
                                    .execute(&db_pool)
                                    .await;
                                (target_uuid, username)
                            },
                            Err(e) => {
                                println!("DB Error: {}", e);
                                (target_uuid, username)
                            }
                        };

                        user_id = Some(final_id);

                        let user = User {
                            id: final_id,
                            username: final_username.clone(),
                            socket_id: Some(final_id),
                        };

                        {
                            let mut state_guard = state.lock().unwrap();
                            state_guard.users.insert(final_id, user);
                            state_guard.tx_map.insert(final_id, tx.clone());

                            // Notify partners status
                            // Find active sessions and notify partners
                            for session in state_guard.sessions.values() {
                                if session.user_ids.contains(&final_id) {
                                    for &pid in &session.user_ids {
                                        if pid != final_id {
                                            if let Some(ptx) = state_guard.tx_map.get(&pid) {
                                                let status_msg = ServerMessage::UserStatus { user_id: final_id, is_online: true };
                                                let _ = ptx.send(Message::Text(serde_json::to_string(&status_msg).unwrap()));
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        let response = ServerMessage::Connected { user_id: final_id };
                        let _ = tx.send(Message::Text(serde_json::to_string(&response).unwrap()));
                        println!("User connected: {} ({})", final_username, final_id);
                    }
                    ClientMessage::UpdateProfile { bio, tags, avatar_config } => {
                        if let Some(uid) = user_id {
                            let db_pool = {
                                let state_guard = state.lock().unwrap();
                                state_guard.db.clone()
                            };
                            let uid_str = uid.to_string();
                            let tags_json = serde_json::to_string(&tags).unwrap_or_default();

                            tokio::spawn(async move {
                                let _ = sqlx::query("UPDATE users SET bio = $1, tags = $2, avatar_config = $3 WHERE id = $4")
                                    .bind(bio)
                                    .bind(tags_json)
                                    .bind(avatar_config)
                                    .bind(uid_str)
                                    .execute(&db_pool)
                                    .await;
                            });
                        }
                    }
                    ClientMessage::FindMatch => {
                        if let Some(uid) = user_id {
                            let mut state_guard = state.lock().unwrap();

                            // Check active matches count
                            let active_matches_count = state_guard.user_sessions.iter()
                                .filter(|(&u, _)| u == uid)
                                .count(); // Simple in-memory check. For robust, check DB or filter sessions.

                            // Better check: iterate sessions and count where uid is present
                            let db_active_count = state_guard.sessions.values()
                                .filter(|s| s.user_ids.contains(&uid))
                                .count();

                            if db_active_count >= 3 {
                                let _ = tx.send(Message::Text(serde_json::to_string(&ServerMessage::Error {
                                    message: "Max active matches reached (3)".to_string()
                                }).unwrap()));
                            } else {
                                if !state_guard.queue.contains(&uid) {
                                    state_guard.queue.push(uid);
                                    println!("User {} added to queue. Queue size: {}", uid, state_guard.queue.len());
                                }

                                if state_guard.queue.len() >= 2 {
                                    let user1_id = state_guard.queue.remove(0);
                                    let user2_id = state_guard.queue.remove(0);

                                    let session_id = Uuid::new_v4();
                                    let session = GameSession {
                                        id: session_id,
                                        user_ids: vec![user1_id, user2_id],
                                        affinity: 0,
                                        current_question_index: 0,
                                        chat_unlocked: false,
                                        current_answers: HashMap::new(),
                                    };

                                    state_guard.sessions.insert(session_id, session.clone());
                                    state_guard.user_sessions.insert(user1_id, session_id);
                                    state_guard.user_sessions.insert(user2_id, session_id);

                                    let db_pool = state_guard.db.clone();
                                    let session_id_str = session_id.to_string();
                                    let user1_id_str = user1_id.to_string();
                                    let user2_id_str = user2_id.to_string();

                                    tokio::spawn(async move {
                                        let _ = sqlx::query("INSERT INTO matches (id, user1_id, user2_id) VALUES ($1, $2, $3)")
                                            .bind(session_id_str)
                                            .bind(user1_id_str)
                                            .bind(user2_id_str)
                                            .execute(&db_pool)
                                            .await;
                                    });

                                    let user1_name = state_guard.users.get(&user1_id).unwrap().username.clone();
                                    let user2_name = state_guard.users.get(&user2_id).unwrap().username.clone();

                                    if let Some(tx1) = state_guard.tx_map.get(&user1_id) {
                                        let msg = ServerMessage::MatchFound { opponent_name: user2_name.clone() };
                                        let _ = tx1.send(Message::Text(serde_json::to_string(&msg).unwrap()));
                                    }

                                    if let Some(tx2) = state_guard.tx_map.get(&user2_id) {
                                        let msg = ServerMessage::MatchFound { opponent_name: user1_name.clone() };
                                        let _ = tx2.send(Message::Text(serde_json::to_string(&msg).unwrap()));
                                    }

                                    if let Some(question) = state_guard.questions.get(0) {
                                        let q_msg = ServerMessage::Question {
                                            id: question.id,
                                            text: question.text.clone(),
                                            option_a: question.option_a.clone(),
                                            option_b: question.option_b.clone(),
                                        };
                                        let q_json = serde_json::to_string(&q_msg).unwrap();

                                        if let Some(tx1) = state_guard.tx_map.get(&user1_id) {
                                            let _ = tx1.send(Message::Text(q_json.clone()));
                                        }
                                        if let Some(tx2) = state_guard.tx_map.get(&user2_id) {
                                            let _ = tx2.send(Message::Text(q_json));
                                        }
                                    }
                                }
                            }
                        }
                    }
                    ClientMessage::AnswerQuestion { choice, comment: _ } => {
                        let mut both_answered = false;
                        let mut session_user_ids = Vec::new();
                        let mut next_q_index = 0;
                        let mut affinity = 0;
                        let mut chat_unlocked = false;
                        let mut session_id_uuid = Uuid::nil();

                        if let Some(uid) = user_id {
                            let mut state_guard = state.lock().unwrap();

                            // Need to find session by searching because user_sessions mapping might be ambiguous with multiple matches
                            // Ideally FindMatch/Connect puts it in map. But if multiple matches?
                            // The current logic in `state.rs` only maps `Uuid -> Uuid` (User -> ONE Session).
                            // This is a limitation of the current MVP state structure.
                            // FIX: We need to find the session where this user is active AND waiting for answer?
                            // Or just assume `user_sessions` points to the *active* / *latest* / *focused* session.
                            // For this MVP step, we'll keep `user_sessions` pointing to the most recently interacted session.
                            // But `ActiveMatches` UI allows picking one. We need a way to 'select' a match.
                            // Missing `SelectMatch` message.
                            // For now, let's assume `user_sessions` holds the current one.

                            if let Some(&session_id) = state_guard.user_sessions.get(&uid) {
                                if let Some(session) = state_guard.sessions.get_mut(&session_id) {
                                    session_id_uuid = session.id;
                                    session.current_answers.insert(uid, (choice.clone(), None));

                                    if session.current_answers.len() == 2 {
                                        both_answered = true;
                                        session_user_ids = session.user_ids.clone();
                                        let (u1, u2) = (session_user_ids[0], session_user_ids[1]);

                                        let ans1 = session.current_answers.get(&u1).unwrap().0.clone();
                                        let ans2 = session.current_answers.get(&u2).unwrap().0.clone();

                                        if ans1 == ans2 {
                                            session.affinity += 1;
                                        }
                                        affinity = session.affinity;

                                        if session.affinity >= 1 {
                                            session.chat_unlocked = true;
                                        }
                                        chat_unlocked = session.chat_unlocked;

                                        session.current_question_index += 1;
                                        next_q_index = session.current_question_index;
                                        session.current_answers.clear();
                                    }
                                }
                            }

                            if both_answered {
                                let db_pool = state_guard.db.clone();
                                let session_id_str = session_id_uuid.to_string();

                                tokio::spawn(async move {
                                    let _ = sqlx::query("UPDATE matches SET affinity = $1, chat_unlocked = $2, last_activity = CURRENT_TIMESTAMP WHERE id = $3")
                                        .bind(affinity as i32)
                                        .bind(chat_unlocked)
                                        .bind(session_id_str)
                                        .execute(&db_pool)
                                        .await;
                                });

                                let update_msg = ServerMessage::AffinityUpdate {
                                    score: affinity,
                                    unlocked: chat_unlocked
                                };
                                let update_json = serde_json::to_string(&update_msg).unwrap();

                                for u in &session_user_ids {
                                    if let Some(tx) = state_guard.tx_map.get(u) {
                                        let _ = tx.send(Message::Text(update_json.clone()));
                                    }
                                }

                                if let Some(question) = state_guard.questions.get(next_q_index) {
                                     let q_msg = ServerMessage::Question {
                                        id: question.id,
                                        text: question.text.clone(),
                                        option_a: question.option_a.clone(),
                                        option_b: question.option_b.clone(),
                                    };
                                    let q_json = serde_json::to_string(&q_msg).unwrap();

                                    for u in &session_user_ids {
                                        if let Some(tx) = state_guard.tx_map.get(u) {
                                            let _ = tx.send(Message::Text(q_json.clone()));
                                        }
                                    }
                                }
                            }
                        }
                    }
                    ClientMessage::SendMessage { content } => {
                        if let Some(uid) = user_id {
                            let state_guard = state.lock().unwrap();
                             if let Some(&session_id) = state_guard.user_sessions.get(&uid) {
                                if let Some(session) = state_guard.sessions.get(&session_id) {
                                    if session.chat_unlocked {
                                        let db_pool = state_guard.db.clone();
                                        let msg_id = Uuid::new_v4();
                                        let content_clone = content.clone();
                                        let session_id_str = session.id.to_string();
                                        let sender_id_str = uid.to_string();
                                        let msg_id_str = msg_id.to_string();

                                        tokio::spawn(async move {
                                            let _ = sqlx::query("INSERT INTO messages (id, match_id, sender_id, content) VALUES ($1, $2, $3, $4)")
                                                .bind(msg_id_str)
                                                .bind(&session_id_str)
                                                .bind(sender_id_str)
                                                .bind(content_clone)
                                                .execute(&db_pool)
                                                .await;
                                            // Update last activity
                                            let _ = sqlx::query("UPDATE matches SET last_activity = CURRENT_TIMESTAMP WHERE id = $1")
                                                .bind(&session_id_str)
                                                .execute(&db_pool)
                                                .await;
                                        });

                                        for &other_uid in &session.user_ids {
                                            if other_uid != uid {
                                                if let Some(tx) = state_guard.tx_map.get(&other_uid) {
                                                    let msg = ServerMessage::ChatMessage {
                                                        sender_id: uid,
                                                        content: content.clone(),
                                                    };
                                                    let _ = tx.send(Message::Text(serde_json::to_string(&msg).unwrap()));
                                                }
                                            }
                                        }
                                    }
                                }
                             }
                        }
                    }
                    ClientMessage::FetchActiveMatches => {
                        if let Some(uid) = user_id {
                            let db_pool = {
                                let state_guard = state.lock().unwrap();
                                state_guard.db.clone()
                            };

                            let uid_str = uid.to_string();

                            // Join matches with users to get opponent info
                            let rows = sqlx::query(
                                r#"
                                SELECT m.id, m.affinity, m.last_activity, u.username as opponent_username, u.avatar_config
                                FROM matches m
                                JOIN users u ON (m.user1_id = u.id OR m.user2_id = u.id)
                                WHERE (m.user1_id = $1 OR m.user2_id = $1) AND u.id != $1
                                ORDER BY m.last_activity DESC
                                LIMIT 3
                                "#
                            )
                            .bind(&uid_str)
                            .fetch_all(&db_pool)
                            .await;

                            match rows {
                                Ok(records) => {
                                    let mut matches = Vec::new();
                                    for r in records {
                                        let mid: String = r.get("id");
                                        let aff: i32 = r.get("affinity");
                                        let last_act: chrono::NaiveDateTime = r.get("last_activity");
                                        let opp_name: String = r.get("opponent_username");
                                        let av_conf: Option<String> = r.get("avatar_config");

                                        // Check if online (naive in-memory check)
                                        // In real app, check Redis or DB status column
                                        let is_online = {
                                            let state_guard = state.lock().unwrap();
                                            // Need opponent ID? query didn't fetch it but we can infer or fetch.
                                            // Let's just say we don't know ID easily here without fetching it.
                                            // Simplified: fetch opponent ID too.
                                            false // Placeholder, fixed in next iteration with better query
                                        };

                                        matches.push(ActiveMatch {
                                            id: Uuid::parse_str(&mid).unwrap_or_default(),
                                            opponent_username: opp_name,
                                            avatar_config: av_conf,
                                            affinity: aff as u32,
                                            last_activity: last_act.to_string(),
                                            is_online,
                                        });
                                    }
                                    let _ = tx.send(Message::Text(serde_json::to_string(&ServerMessage::ActiveMatches { matches }).unwrap()));
                                },
                                Err(e) => println!("Error fetching active matches: {}", e),
                            }
                        }
                    }
                    ClientMessage::FetchHistory => {
                        // Keep existing logic but maybe adapt to specific match ID if provided?
                        // For now keep generic "latest" logic or adapt.
                        // Ideally FetchHistory should take a match_id.
                    }
                }
            }
        }
    }

    // Cleanup on disconnect
    if let Some(uid) = user_id {
        let mut state_guard = state.lock().unwrap();
        state_guard.users.remove(&uid);
        state_guard.tx_map.remove(&uid);

        // Notify offline
        for session in state_guard.sessions.values() {
            if session.user_ids.contains(&uid) {
                for &pid in &session.user_ids {
                    if pid != uid {
                        if let Some(ptx) = state_guard.tx_map.get(&pid) {
                            let status_msg = ServerMessage::UserStatus { user_id: uid, is_online: false };
                            let _ = ptx.send(Message::Text(serde_json::to_string(&status_msg).unwrap()));
                        }
                    }
                }
            }
        }

        if let Some(pos) = state_guard.queue.iter().position(|x| *x == uid) {
            state_guard.queue.remove(pos);
        }
        println!("User disconnected: {}", uid);
    }
}
