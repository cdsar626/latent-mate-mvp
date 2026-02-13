use axum::extract::ws::{Message, WebSocket};
use futures::{stream::StreamExt, SinkExt};
use tokio::sync::mpsc;
use uuid::Uuid;
use std::collections::HashMap;
use crate::state::SharedState;
use crate::models::{ClientMessage, ServerMessage, User, GameSession, ChatMessage};
// use sqlx::{Pool, Sqlite}; // Removed unused import

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
                        // Heartbeat ack, can be used for timeouts later
                    }
                    ClientMessage::Connect { username } => {
                        let db_pool = {
                            let state_guard = state.lock().unwrap();
                            state_guard.db.clone()
                        };

                        let fetch_user = sqlx::query!(
                            "SELECT id, username FROM users WHERE username = ?",
                            username
                        )
                        .fetch_optional(&db_pool)
                        .await;

                        let (final_id, final_username) = match fetch_user {
                            Ok(Some(record)) => (Uuid::parse_str(&record.id.unwrap_or_default()).unwrap_or(Uuid::new_v4()), record.username),
                            Ok(None) => {
                                let new_id = Uuid::new_v4();
                                let new_id_str = new_id.to_string();
                                let _ = sqlx::query!(
                                    "INSERT INTO users (id, username) VALUES (?, ?)",
                                    new_id_str,
                                    username
                                )
                                .execute(&db_pool)
                                .await;
                                (new_id, username)
                            },
                            Err(e) => {
                                println!("DB Error: {}", e);
                                (Uuid::new_v4(), username)
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
                                let _ = sqlx::query!(
                                    "UPDATE users SET bio = ?, tags = ?, avatar_config = ? WHERE id = ?",
                                    bio,
                                    tags_json,
                                    avatar_config,
                                    uid_str
                                )
                                .execute(&db_pool)
                                .await;
                            });
                            println!("Updated profile for user {}", uid);
                        }
                    }
                    ClientMessage::FindMatch => {
                        if let Some(uid) = user_id {
                            let mut state_guard = state.lock().unwrap();

                            // Only add if not already in queue
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

                                // Persist Match
                                let db_pool = state_guard.db.clone();
                                let session_id_str = session_id.to_string();
                                let user1_id_str = user1_id.to_string();
                                let user2_id_str = user2_id.to_string();

                                tokio::spawn(async move {
                                    let _ = sqlx::query!(
                                        "INSERT INTO matches (id, user1_id, user2_id) VALUES (?, ?, ?)",
                                        session_id_str,
                                        user1_id_str,
                                        user2_id_str
                                    )
                                    .execute(&db_pool)
                                    .await;
                                });

                                let user1_name = state_guard.users.get(&user1_id).unwrap().username.clone();
                                let user2_name = state_guard.users.get(&user2_id).unwrap().username.clone();

                                // Notify User 1
                                if let Some(tx1) = state_guard.tx_map.get(&user1_id) {
                                    let msg = ServerMessage::MatchFound { opponent_name: user2_name.clone() };
                                    let _ = tx1.send(Message::Text(serde_json::to_string(&msg).unwrap()));
                                }

                                // Notify User 2
                                if let Some(tx2) = state_guard.tx_map.get(&user2_id) {
                                    let msg = ServerMessage::MatchFound { opponent_name: user1_name.clone() };
                                    let _ = tx2.send(Message::Text(serde_json::to_string(&msg).unwrap()));
                                }

                                // Send First Question
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
                    ClientMessage::AnswerQuestion { choice, comment: _ } => {
                        let mut both_answered = false;
                        let mut session_user_ids = Vec::new();
                        let mut next_q_index = 0;
                        let mut affinity = 0;
                        let mut chat_unlocked = false;
                        let mut session_id_uuid = Uuid::nil();

                        if let Some(uid) = user_id {
                            let mut state_guard = state.lock().unwrap();

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

                                        // Unlock logic (Affinity >= 1 for MVP)
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
                                // Persist Affinity Update
                                let db_pool = state_guard.db.clone();
                                let session_id_str = session_id_uuid.to_string();

                                tokio::spawn(async move {
                                    let _ = sqlx::query!(
                                        "UPDATE matches SET affinity = ?, chat_unlocked = ? WHERE id = ?",
                                        affinity,
                                        chat_unlocked,
                                        session_id_str
                                    )
                                    .execute(&db_pool)
                                    .await;
                                });

                                // Send Affinity Update
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

                                // Send Next Question
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
                                            let _ = sqlx::query!(
                                                "INSERT INTO messages (id, match_id, sender_id, content) VALUES (?, ?, ?, ?)",
                                                msg_id_str,
                                                session_id_str,
                                                sender_id_str,
                                                content_clone
                                            )
                                            .execute(&db_pool)
                                            .await;
                                        });

                                        // Find other user
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
                    ClientMessage::FetchHistory => {
                        if let Some(uid) = user_id {
                            let db_pool = {
                                let state_guard = state.lock().unwrap();
                                state_guard.db.clone()
                            };

                            let uid_str = uid.to_string();
                            let uid_str_2 = uid.to_string();

                            // Get active match for this user
                            let match_record = sqlx::query!(
                                r#"
                                SELECT id, user1_id, user2_id, affinity, chat_unlocked
                                FROM matches
                                WHERE user1_id = ? OR user2_id = ?
                                ORDER BY last_activity DESC
                                LIMIT 1
                                "#,
                                uid_str,
                                uid_str_2
                            )
                            .fetch_optional(&db_pool)
                            .await;

                            if let Ok(Some(record)) = match_record {
                                // Fetch messages
                                let messages = sqlx::query!(
                                    "SELECT sender_id, content, created_at FROM messages WHERE match_id = ? ORDER BY created_at ASC",
                                    record.id
                                )
                                .fetch_all(&db_pool)
                                .await;

                                if let Ok(msgs) = messages {
                                    let history: Vec<ChatMessage> = msgs.into_iter().map(|m| ChatMessage {
                                        sender_id: Uuid::parse_str(&m.sender_id).unwrap_or_default(),
                                        content: m.content,
                                        timestamp: m.created_at.map(|t| t.to_string()).unwrap_or_default(),
                                    }).collect();

                                    let mut state_guard = state.lock().unwrap();

                                    // RE-CONNECT USER TO SESSION
                                    // If we found a DB match, we should probably restore it in memory if it's not there
                                    let session_id = Uuid::parse_str(&record.id.unwrap_or_default()).unwrap_or_default();
                                    let u1 = Uuid::parse_str(&record.user1_id).unwrap_or_default();
                                    let u2 = Uuid::parse_str(&record.user2_id).unwrap_or_default();

                                    if !state_guard.sessions.contains_key(&session_id) {
                                        let session = GameSession {
                                            id: session_id,
                                            user_ids: vec![u1, u2],
                                            affinity: record.affinity.unwrap_or(0) as u32,
                                            current_question_index: 0, // Reset question index or persist it too? For MVP reset is okay-ish but weird.
                                            chat_unlocked: record.chat_unlocked.unwrap_or(false),
                                            current_answers: HashMap::new(),
                                        };
                                        state_guard.sessions.insert(session_id, session);
                                        state_guard.user_sessions.insert(u1, session_id);
                                        state_guard.user_sessions.insert(u2, session_id);
                                    } else {
                                        // ensure user_sessions mapping exists
                                         state_guard.user_sessions.insert(uid, session_id);
                                    }

                                    if let Some(tx) = state_guard.tx_map.get(&uid) {
                                        let response = ServerMessage::History { messages: history };
                                        let _ = tx.send(Message::Text(serde_json::to_string(&response).unwrap()));

                                        // Also restore match state if needed (Affinity update)
                                        let update_msg = ServerMessage::AffinityUpdate {
                                            score: record.affinity.unwrap_or(0) as u32,
                                            unlocked: record.chat_unlocked.unwrap_or(false)
                                        };
                                        let _ = tx.send(Message::Text(serde_json::to_string(&update_msg).unwrap()));
                                    }
                                }
                            }
                        }
                    }
                    _ => {}
                }
            } else {
                println!("Failed to parse message: {}", text);
            }
        }
    }

    // Cleanup on disconnect
    if let Some(uid) = user_id {
        let mut state_guard = state.lock().unwrap();
        state_guard.users.remove(&uid);
        state_guard.tx_map.remove(&uid);
        if let Some(pos) = state_guard.queue.iter().position(|x| *x == uid) {
            state_guard.queue.remove(pos);
        }
        // Don't remove session from DB, just from memory mapping if needed
        // For reconnect, we might need to be smarter, but for MVP:
        if let Some(_sid) = state_guard.user_sessions.remove(&uid) {
             // If we remove the session from memory, the other user will be stranded if they are still connected.
             // Ideally we check if both are gone.
             // For now, let's NOT remove the session from memory just because one user disconnected,
             // to allow reconnection. But we should probably have a timeout cleanup.
             // state_guard.sessions.remove(&sid);
        }
        println!("User disconnected: {}", uid);
    }
}
