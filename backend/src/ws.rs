use axum::extract::ws::{Message, WebSocket};
use futures::{stream::StreamExt, SinkExt};
use tokio::sync::mpsc;
use uuid::Uuid;
use std::collections::HashMap;
use crate::state::SharedState;
use crate::models::{ClientMessage, ServerMessage, User, GameSession, ChatMessage};
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

                        // Use the ID provided by frontend (from Supabase Auth)
                        let target_uuid = Uuid::parse_str(&auth_user_id).unwrap_or(Uuid::new_v4());
                        let target_uuid_str = target_uuid.to_string();

                        // Upsert logic to ensure user exists in our DB and store email
                        let fetch_user = sqlx::query("SELECT id, username FROM users WHERE id = $1")
                            .bind(&target_uuid_str)
                            .fetch_optional(&db_pool)
                            .await;

                        let (final_id, final_username) = match fetch_user {
                            Ok(Some(row)) => {
                                let id_str: String = row.get("id");
                                let username_str: String = row.get("username");

                                // Update email if provided
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
                                let email_val = email.unwrap_or_default(); // Store empty string if no email, or use NULL logic if schema permits
                                // Insert with email
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
                            println!("Updated profile for user {}", uid);
                        }
                    }
                    ClientMessage::FindMatch => {
                        if let Some(uid) = user_id {
                            let mut state_guard = state.lock().unwrap();

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
                                    let _ = sqlx::query("UPDATE matches SET affinity = $1, chat_unlocked = $2 WHERE id = $3")
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
                                                .bind(session_id_str)
                                                .bind(sender_id_str)
                                                .bind(content_clone)
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
                    ClientMessage::FetchHistory => {
                        if let Some(uid) = user_id {
                            let db_pool = {
                                let state_guard = state.lock().unwrap();
                                state_guard.db.clone()
                            };

                            let uid_str = uid.to_string();

                            // Postgres uses LIMIT 1, but "ORDER BY last_activity DESC" needs a column
                            let match_record = sqlx::query(
                                r#"
                                SELECT id, user1_id, user2_id, affinity, chat_unlocked
                                FROM matches
                                WHERE user1_id = $1 OR user2_id = $2
                                ORDER BY last_activity DESC
                                LIMIT 1
                                "#
                            )
                            .bind(&uid_str)
                            .bind(&uid_str)
                            .fetch_optional(&db_pool)
                            .await;

                            if let Ok(Some(record)) = match_record {
                                let match_id: String = record.get("id");
                                let u1_str: String = record.get("user1_id");
                                let u2_str: String = record.get("user2_id");
                                let aff: i32 = record.get("affinity");
                                let unlocked: bool = record.get("chat_unlocked");

                                let messages_result = sqlx::query(
                                    "SELECT sender_id, content, created_at FROM messages WHERE match_id = $1 ORDER BY created_at ASC"
                                )
                                .bind(&match_id)
                                .fetch_all(&db_pool)
                                .await;

                                if let Ok(msgs) = messages_result {
                                    let history: Vec<ChatMessage> = msgs.into_iter().map(|m| {
                                        let sid: String = m.get("sender_id");
                                        let content: String = m.get("content");
                                        let created_at: chrono::NaiveDateTime = m.get("created_at");
                                        ChatMessage {
                                            sender_id: Uuid::parse_str(&sid).unwrap_or_default(),
                                            content,
                                            timestamp: created_at.to_string(),
                                        }
                                    }).collect();

                                    let mut state_guard = state.lock().unwrap();

                                    let session_id = Uuid::parse_str(&match_id).unwrap_or_default();
                                    let u1 = Uuid::parse_str(&u1_str).unwrap_or_default();
                                    let u2 = Uuid::parse_str(&u2_str).unwrap_or_default();

                                    if !state_guard.sessions.contains_key(&session_id) {
                                        let session = GameSession {
                                            id: session_id,
                                            user_ids: vec![u1, u2],
                                            affinity: aff as u32,
                                            current_question_index: 0,
                                            chat_unlocked: unlocked,
                                            current_answers: HashMap::new(),
                                        };
                                        state_guard.sessions.insert(session_id, session);
                                        state_guard.user_sessions.insert(u1, session_id);
                                        state_guard.user_sessions.insert(u2, session_id);
                                    } else {
                                         state_guard.user_sessions.insert(uid, session_id);
                                    }

                                    if let Some(tx) = state_guard.tx_map.get(&uid) {
                                        let response = ServerMessage::History { messages: history };
                                        let _ = tx.send(Message::Text(serde_json::to_string(&response).unwrap()));

                                        let update_msg = ServerMessage::AffinityUpdate {
                                            score: aff as u32,
                                            unlocked
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
        if let Some(_sid) = state_guard.user_sessions.remove(&uid) {
             // Leave session in memory for reconnect
        }
        println!("User disconnected: {}", uid);
    }
}
