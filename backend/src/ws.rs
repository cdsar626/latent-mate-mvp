use axum::extract::ws::{Message, WebSocket};
use futures::{stream::StreamExt, SinkExt};
use tokio::sync::mpsc;
use uuid::Uuid;
use std::collections::HashMap;
use crate::state::SharedState;
use crate::models::{ClientMessage, ServerMessage, User, GameSession};

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
                    ClientMessage::Connect { username } => {
                        let new_id = Uuid::new_v4();
                        user_id = Some(new_id);

                        let user = User {
                            id: new_id,
                            username: username.clone(),
                            socket_id: Some(new_id),
                        };

                        {
                            let mut state_guard = state.lock().unwrap();
                            state_guard.users.insert(new_id, user);
                            state_guard.tx_map.insert(new_id, tx.clone());
                        }

                        let response = ServerMessage::Connected { user_id: new_id };
                        let _ = tx.send(Message::Text(serde_json::to_string(&response).unwrap()));
                        println!("User connected: {} ({})", username, new_id);
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

                                state_guard.sessions.insert(session_id, session);
                                state_guard.user_sessions.insert(user1_id, session_id);
                                state_guard.user_sessions.insert(user2_id, session_id);

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

                        if let Some(uid) = user_id {
                            let mut state_guard = state.lock().unwrap();

                            if let Some(&session_id) = state_guard.user_sessions.get(&uid) {
                                if let Some(session) = state_guard.sessions.get_mut(&session_id) {
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

                            // Block logic finished, dropping lock implicitly if we exit scope, but we are inside 'if let Some(uid)'
                            // We need to release the lock before sending messages if we want to avoid holding it too long,
                            // but more importantly to access 'state_guard.questions' which we can't do if 'session' (from sessions) is borrowed.
                            // The block above `if let Some(session)` limits the borrow scope of `session`.

                            // However, `state_guard` is still locked here.

                            if both_answered {
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
        if let Some(sid) = state_guard.user_sessions.remove(&uid) {
            state_guard.sessions.remove(&sid);
        }
        println!("User disconnected: {}", uid);
    }
}
