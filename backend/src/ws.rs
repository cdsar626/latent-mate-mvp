use axum::extract::ws::{Message, WebSocket};
use futures::{stream::StreamExt, SinkExt};
use tokio::sync::mpsc;
use uuid::Uuid;
use std::collections::HashMap;
use crate::state::SharedState;
use crate::models::{ClientMessage, ServerMessage, User, GameSession, ActiveMatch};
use sqlx::Row;
use tracing::{info, warn, error, debug};

pub async fn handle_socket(socket: WebSocket, state: SharedState) {
    let (mut sender, mut receiver) = socket.split();

    let (tx, mut rx) = mpsc::unbounded_channel();

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
                let msg_type = format!("{:?}", &client_msg).split('(').next().unwrap_or("Unknown").split('{').next().unwrap_or("Unknown").trim().to_string();
                debug!(user_id = ?user_id, message_type = %msg_type, "Received client message");

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
                                info!(user_id = %target_uuid, username = %username, "New user created in DB");
                                (target_uuid, username)
                            },
                            Err(e) => {
                                error!(user_id = %target_uuid, error = %e, "DB error during user lookup");
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

                            // Notify partners of online status
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
                        info!(user_id = %final_id, username = %final_username, "User connected");
                    }
                    ClientMessage::UpdateProfile { bio, tags, avatar_config } => {
                        if let Some(uid) = user_id {
                            let db_pool = {
                                let state_guard = state.lock().unwrap();
                                state_guard.db.clone()
                            };
                            let uid_str = uid.to_string();
                            let tags_json = serde_json::to_string(&tags).unwrap_or_default();

                            let tx_clone = tx.clone();
                            tokio::spawn(async move {
                                let result = sqlx::query("UPDATE users SET bio = $1, tags = $2, avatar_config = $3 WHERE id = $4")
                                    .bind(bio)
                                    .bind(tags_json)
                                    .bind(avatar_config)
                                    .bind(&uid_str)
                                    .execute(&db_pool)
                                    .await;
                                match result {
                                    Ok(_) => {
                                        info!(user_id = %uid_str, "Profile updated");
                                        let _ = tx_clone.send(Message::Text(serde_json::to_string(&ServerMessage::ProfileUpdated).unwrap()));
                                    },
                                    Err(e) => error!(user_id = %uid_str, error = %e, "Failed to update profile"),
                                }
                            });
                        }
                    }
                    ClientMessage::FindMatch => {
                        if let Some(uid) = user_id {
                            let mut state_guard = state.lock().unwrap();

                            // Count active sessions for this user
                            let db_active_count = state_guard.sessions.values()
                                .filter(|s| s.user_ids.contains(&uid))
                                .count();

                            if db_active_count >= 3 {
                                let _ = tx.send(Message::Text(serde_json::to_string(&ServerMessage::Error {
                                    message: "Max active matches reached (3)".to_string()
                                }).unwrap()));
                                warn!(user_id = %uid, active_count = db_active_count, "FindMatch rejected: max matches reached");
                            } else if state_guard.queue.contains(&uid) {
                                // Already in queue — send ack but don't re-add
                                let _ = tx.send(Message::Text(serde_json::to_string(&ServerMessage::SearchingAck).unwrap()));
                                info!(user_id = %uid, "FindMatch: user already in queue, ignoring duplicate request");
                            } else {
                                state_guard.queue.push(uid);
                                let _ = tx.send(Message::Text(serde_json::to_string(&ServerMessage::SearchingAck).unwrap()));
                                info!(user_id = %uid, queue_size = state_guard.queue.len(), "User added to matchmaking queue");

                                // Try to match
                                try_match_from_queue(&mut state_guard, &tx);
                            }
                        }
                    }
                    ClientMessage::AnswerQuestion { choice, comment: _ } => {
                        if let Some(uid) = user_id {
                            let mut both_answered = false;
                            let mut session_user_ids = Vec::new();
                            let mut affinity = 0;
                            let mut old_affinity = 0;
                            let mut chat_unlocked = false;
                            let mut session_id_uuid = Uuid::nil();
                            let mut question_text = String::new();
                            let mut answer1 = String::new();
                            let mut answer2 = String::new();
                            let mut answers_matched = false;
                            let mut user1_id_log = Uuid::nil();
                            let mut user2_id_log = Uuid::nil();

                            {
                                let mut state_guard = state.lock().unwrap();

                                // Pre-compute eligible question texts to avoid borrow conflict
                                let session_id_opt = state_guard.user_sessions.get(&uid).copied();

                                if let Some(session_id) = session_id_opt {
                                    // Get current question text before mutable borrow
                                    let q_text_for_log = {
                                        let q_idx_pre = state_guard.sessions.get(&session_id)
                                            .map(|s| s.current_question_index)
                                            .unwrap_or(0);
                                        let old_aff = state_guard.sessions.get(&session_id)
                                            .map(|s| s.affinity)
                                            .unwrap_or(0);
                                        let eligible: Vec<_> = state_guard.questions.iter()
                                            .filter(|q| q.min_affinity <= old_aff)
                                            .collect();
                                        eligible.get(q_idx_pre).map(|q| q.text.clone()).unwrap_or_default()
                                    };

                                    if let Some(session) = state_guard.sessions.get_mut(&session_id) {
                                        session_id_uuid = session.id;
                                        session.current_answers.insert(uid, (choice.clone(), None));
                                        info!(user_id = %uid, session_id = %session_id, choice = %choice, "User answered question");

                                        if session.current_answers.len() == 2 {
                                            both_answered = true;
                                            session_user_ids = session.user_ids.clone();
                                            let (u1, u2) = (session_user_ids[0], session_user_ids[1]);
                                            user1_id_log = u1;
                                            user2_id_log = u2;

                                            let ans1 = session.current_answers.get(&u1).unwrap().0.clone();
                                            let ans2 = session.current_answers.get(&u2).unwrap().0.clone();
                                            answer1 = ans1.clone();
                                            answer2 = ans2.clone();

                                            old_affinity = session.affinity;
                                            answers_matched = ans1 == ans2;
                                            if answers_matched {
                                                session.affinity += 1;
                                            }
                                            affinity = session.affinity;

                                            if session.affinity >= 1 {
                                                session.chat_unlocked = true;
                                            }
                                            chat_unlocked = session.chat_unlocked;

                                            question_text = q_text_for_log;

                                            session.current_question_index += 1;
                                            session.current_answers.clear();
                                        }
                                    }
                                }

                                if both_answered {
                                    // Per-round logging
                                    info!(
                                        session_id = %session_id_uuid,
                                        question = %question_text,
                                        user1_id = %user1_id_log,
                                        user1_answer = %answer1,
                                        user2_id = %user2_id_log,
                                        user2_answer = %answer2,
                                        matched = answers_matched,
                                        affinity_before = old_affinity,
                                        affinity_after = affinity,
                                        chat_unlocked = chat_unlocked,
                                        "Round complete"
                                    );

                                    // Update DB
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

                                    // Send next question (filtered by affinity)
                                    send_next_question(&state_guard, session_id_uuid, &session_user_ids);
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
                                        debug!(user_id = %uid, session_id = %session_id, "Chat message sent");
                                    } else {
                                        warn!(user_id = %uid, session_id = %session_id, "Attempted to send message with chat locked");
                                    }
                                }
                            }
                        }
                    }
                    ClientMessage::FetchActiveMatches => {
                        if let Some(uid) = user_id {
                            fetch_matches_by_status(&state, &tx, uid, "active").await;
                        }
                    }
                    ClientMessage::FetchArchivedMatches => {
                        if let Some(uid) = user_id {
                            fetch_matches_by_status(&state, &tx, uid, "suppressed").await;
                        }
                    }
                    ClientMessage::FetchUserProfile { user_id: target_user_id } => {
                        if let Some(_uid) = user_id {
                            let db_pool = {
                                let state_guard = state.lock().unwrap();
                                state_guard.db.clone()
                            };

                            let row = sqlx::query("SELECT id, username, bio, tags, avatar_config FROM users WHERE id = $1")
                                .bind(&target_user_id)
                                .fetch_optional(&db_pool)
                                .await;

                            match row {
                                Ok(Some(r)) => {
                                    let uid_str: String = r.get("id");
                                    let profile_msg = ServerMessage::UserProfile {
                                        user_id: Uuid::parse_str(&uid_str).unwrap_or_default(),
                                        username: r.get("username"),
                                        bio: r.get("bio"),
                                        tags: r.get("tags"),
                                        avatar_config: r.get("avatar_config"),
                                    };
                                    let _ = tx.send(Message::Text(serde_json::to_string(&profile_msg).unwrap()));
                                    debug!(target_user_id = %target_user_id, "User profile fetched");
                                },
                                Ok(None) => {
                                    let _ = tx.send(Message::Text(serde_json::to_string(&ServerMessage::Error {
                                        message: "User not found".to_string()
                                    }).unwrap()));
                                    warn!(target_user_id = %target_user_id, "FetchUserProfile: user not found");
                                },
                                Err(e) => {
                                    error!(target_user_id = %target_user_id, error = %e, "Error fetching user profile");
                                },
                            }
                        }
                    }
                    ClientMessage::SuppressMatch { match_id } => {
                        if let Some(uid) = user_id {
                            let db_pool = {
                                let state_guard = state.lock().unwrap();
                                state_guard.db.clone()
                            };

                            let result = sqlx::query("UPDATE matches SET status = 'suppressed', last_activity = CURRENT_TIMESTAMP WHERE id = $1 AND (user1_id = $2 OR user2_id = $2) AND status = 'active'")
                                .bind(&match_id)
                                .bind(uid.to_string())
                                .execute(&db_pool)
                                .await;

                            match result {
                                Ok(r) if r.rows_affected() > 0 => {
                                    info!(user_id = %uid, match_id = %match_id, "Match suppressed (archived)");

                                    let match_uuid = Uuid::parse_str(&match_id).unwrap_or_default();

                                    // Remove in-memory session
                                    {
                                        let mut state_guard = state.lock().unwrap();
                                        if let Some(session) = state_guard.sessions.remove(&match_uuid) {
                                            for &sid in &session.user_ids {
                                                if state_guard.user_sessions.get(&sid) == Some(&match_uuid) {
                                                    state_guard.user_sessions.remove(&sid);
                                                }
                                            }
                                            // Notify both users
                                            for &sid in &session.user_ids {
                                                if let Some(stx) = state_guard.tx_map.get(&sid) {
                                                    let _ = stx.send(Message::Text(serde_json::to_string(&ServerMessage::MatchSuppressed { match_id: match_uuid }).unwrap()));
                                                }
                                            }
                                        } else {
                                            // Session not in memory, just notify the requester
                                            let _ = tx.send(Message::Text(serde_json::to_string(&ServerMessage::MatchSuppressed { match_id: match_uuid }).unwrap()));
                                        }
                                    }
                                },
                                Ok(_) => {
                                    warn!(user_id = %uid, match_id = %match_id, "SuppressMatch: no matching active match found");
                                    let _ = tx.send(Message::Text(serde_json::to_string(&ServerMessage::Error {
                                        message: "Match not found or already suppressed".to_string()
                                    }).unwrap()));
                                },
                                Err(e) => {
                                    error!(user_id = %uid, match_id = %match_id, error = %e, "Error suppressing match");
                                },
                            }
                        }
                    }
                    ClientMessage::DeleteMatch { match_id } => {
                        if let Some(uid) = user_id {
                            let db_pool = {
                                let state_guard = state.lock().unwrap();
                                state_guard.db.clone()
                            };

                            let result = sqlx::query("UPDATE matches SET status = 'deleted', last_activity = CURRENT_TIMESTAMP WHERE id = $1 AND (user1_id = $2 OR user2_id = $2) AND status = 'suppressed'")
                                .bind(&match_id)
                                .bind(uid.to_string())
                                .execute(&db_pool)
                                .await;

                            match result {
                                Ok(r) if r.rows_affected() > 0 => {
                                    info!(user_id = %uid, match_id = %match_id, "Match permanently deleted (users can re-match)");
                                    let match_uuid = Uuid::parse_str(&match_id).unwrap_or_default();
                                    let _ = tx.send(Message::Text(serde_json::to_string(&ServerMessage::MatchDeleted { match_id: match_uuid }).unwrap()));
                                },
                                Ok(_) => {
                                    warn!(user_id = %uid, match_id = %match_id, "DeleteMatch: no matching suppressed match found");
                                    let _ = tx.send(Message::Text(serde_json::to_string(&ServerMessage::Error {
                                        message: "Match not found or not archived".to_string()
                                    }).unwrap()));
                                },
                                Err(e) => {
                                    error!(user_id = %uid, match_id = %match_id, error = %e, "Error deleting match");
                                },
                            }
                        }
                    }
                    ClientMessage::FetchHistory => {
                        // TODO: Implement with match_id parameter for per-match history
                        debug!(user_id = ?user_id, "FetchHistory called (not yet implemented with match_id)");
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
            info!(user_id = %uid, "Removed from queue on disconnect");
        }
        info!(user_id = %uid, "User disconnected");
    }
}

/// Try to match users from the queue, checking for duplicate/suppressed pairs
fn try_match_from_queue(state_guard: &mut crate::state::AppState, _requester_tx: &mpsc::UnboundedSender<Message>) {
    if state_guard.queue.len() < 2 {
        return;
    }

    // Try to find a valid pair (not already matched active/suppressed)
    let queue_snapshot = state_guard.queue.clone();

    for i in 0..queue_snapshot.len() {
        for j in (i + 1)..queue_snapshot.len() {
            let user1_id = queue_snapshot[i];
            let user2_id = queue_snapshot[j];

            // In-memory check: do they already have an active session together?
            let already_matched = state_guard.sessions.values().any(|s| {
                s.user_ids.contains(&user1_id) && s.user_ids.contains(&user2_id)
            });

            if already_matched {
                info!(user1_id = %user1_id, user2_id = %user2_id, "Skipping pair: already have active in-memory session");
                continue;
            }

            // We'll do the DB check asynchronously after creating — but for the MVP, 
            // we do a synchronous check via the in-memory sessions.
            // The full DB check for suppressed matches happens asynchronously (see below).
            // For now, proceed with this pair and do a DB insert that will be validated.

            // Remove both from queue
            state_guard.queue.retain(|&id| id != user1_id && id != user2_id);

            let session_id = Uuid::new_v4();
            let session = GameSession {
                id: session_id,
                user_ids: vec![user1_id, user2_id],
                affinity: 0,
                current_question_index: 0,
                chat_unlocked: false,
                current_answers: HashMap::new(),
                answered_question_ids: Vec::new(),
            };

            state_guard.sessions.insert(session_id, session.clone());
            state_guard.user_sessions.insert(user1_id, session_id);
            state_guard.user_sessions.insert(user2_id, session_id);

            let db_pool = state_guard.db.clone();
            let session_id_str = session_id.to_string();
            let user1_id_str = user1_id.to_string();
            let user2_id_str = user2_id.to_string();

            // Spawn async DB insert with duplicate check
            let state_sessions_tx1 = state_guard.tx_map.get(&user1_id).cloned();
            let state_sessions_tx2 = state_guard.tx_map.get(&user2_id).cloned();

            let user1_name = state_guard.users.get(&user1_id).map(|u| u.username.clone()).unwrap_or_default();
            let user2_name = state_guard.users.get(&user2_id).map(|u| u.username.clone()).unwrap_or_default();

            // Get first question
            let first_question = state_guard.questions.iter()
                .find(|q| q.min_affinity == 0);

            let first_q_msg = first_question.map(|q| {
                serde_json::to_string(&ServerMessage::Question {
                    id: q.id,
                    text: q.text.clone(),
                    options: q.options.clone(),
                }).unwrap()
            });

            tokio::spawn(async move {
                // Check DB for existing active/suppressed match between this pair
                let existing = sqlx::query(
                    "SELECT id, status FROM matches WHERE status IN ('active', 'suppressed') AND ((user1_id = $1 AND user2_id = $2) OR (user1_id = $2 AND user2_id = $1))"
                )
                .bind(&user1_id_str)
                .bind(&user2_id_str)
                .fetch_optional(&db_pool)
                .await;

                match existing {
                    Ok(Some(row)) => {
                        let existing_status: String = row.get("status");
                        warn!(
                            user1_id = %user1_id_str,
                            user2_id = %user2_id_str,
                            existing_status = %existing_status,
                            "Blocked duplicate match (existing {} match in DB)", existing_status
                        );
                        // Notify users the match failed
                        if let Some(tx1) = &state_sessions_tx1 {
                            let _ = tx1.send(Message::Text(serde_json::to_string(&ServerMessage::Error {
                                message: "You already have an existing connection with this person".to_string()
                            }).unwrap()));
                        }
                        if let Some(tx2) = &state_sessions_tx2 {
                            let _ = tx2.send(Message::Text(serde_json::to_string(&ServerMessage::SearchingAck).unwrap()));
                        }
                        // Note: in-memory session was already created — it will be cleaned up
                        // when matches are next fetched, or we could send a cleanup message.
                        return;
                    },
                    Ok(None) => {
                        // No existing match, proceed
                    },
                    Err(e) => {
                        error!(error = %e, "Error checking for duplicate matches");
                        // Proceed anyway on error (fail open for MVP)
                    }
                }

                // Insert new match
                let insert_result = sqlx::query("INSERT INTO matches (id, user1_id, user2_id, status) VALUES ($1, $2, $3, 'active')")
                    .bind(&session_id_str)
                    .bind(&user1_id_str)
                    .bind(&user2_id_str)
                    .execute(&db_pool)
                    .await;

                match insert_result {
                    Ok(_) => {
                        info!(session_id = %session_id_str, user1_id = %user1_id_str, user2_id = %user2_id_str, "Match created");
                    },
                    Err(e) => {
                        error!(error = %e, "Failed to insert match into DB");
                        return;
                    }
                }

                // Notify both users
                if let Some(tx1) = &state_sessions_tx1 {
                    let msg = ServerMessage::MatchFound { opponent_name: user2_name.clone() };
                    let _ = tx1.send(Message::Text(serde_json::to_string(&msg).unwrap()));
                }
                if let Some(tx2) = &state_sessions_tx2 {
                    let msg = ServerMessage::MatchFound { opponent_name: user1_name.clone() };
                    let _ = tx2.send(Message::Text(serde_json::to_string(&msg).unwrap()));
                }

                // Send first question
                if let Some(q_json) = first_q_msg {
                    if let Some(tx1) = &state_sessions_tx1 {
                        let _ = tx1.send(Message::Text(q_json.clone()));
                    }
                    if let Some(tx2) = &state_sessions_tx2 {
                        let _ = tx2.send(Message::Text(q_json));
                    }
                }
            });

            return; // Only match one pair per call
        }
    }
}

/// Send the next eligible question to a session
fn send_next_question(state_guard: &crate::state::AppState, session_id: Uuid, user_ids: &[Uuid]) {
    if let Some(session) = state_guard.sessions.get(&session_id) {
        let q_idx = session.current_question_index;

        // Filter questions by affinity threshold
        let eligible: Vec<_> = state_guard.questions.iter()
            .filter(|q| q.min_affinity <= session.affinity)
            .collect();

        if let Some(question) = eligible.get(q_idx) {
            let q_msg = ServerMessage::Question {
                id: question.id,
                text: question.text.clone(),
                options: question.options.clone(),
            };
            let q_json = serde_json::to_string(&q_msg).unwrap();

            for u in user_ids {
                if let Some(tx) = state_guard.tx_map.get(u) {
                    let _ = tx.send(Message::Text(q_json.clone()));
                }
            }
            info!(session_id = %session_id, question_index = q_idx, eligible_count = eligible.len(), "Next question sent");
        } else {
            // No more questions available
            info!(session_id = %session_id, affinity = session.affinity, total_eligible = eligible.len(), "No more questions available");
            for u in user_ids {
                if let Some(tx) = state_guard.tx_map.get(u) {
                    let _ = tx.send(Message::Text(serde_json::to_string(&ServerMessage::NoMoreQuestions).unwrap()));
                }
            }
        }
    }
}

/// Fetch matches by status (active or suppressed) and send to user
async fn fetch_matches_by_status(state: &SharedState, tx: &mpsc::UnboundedSender<Message>, uid: Uuid, status: &str) {
    let db_pool = {
        let state_guard = state.lock().unwrap();
        state_guard.db.clone()
    };

    let uid_str = uid.to_string();

    let rows = sqlx::query(
        r#"
        SELECT m.id, m.affinity, m.last_activity, u.id as opponent_id, u.username as opponent_username, u.avatar_config
        FROM matches m
        JOIN users u ON (m.user1_id = u.id OR m.user2_id = u.id)
        WHERE (m.user1_id = $1 OR m.user2_id = $1) AND u.id != $1 AND m.status = $2
        ORDER BY m.last_activity DESC
        LIMIT 10
        "#
    )
    .bind(&uid_str)
    .bind(status)
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
                let opp_id_str: String = r.get("opponent_id");

                let is_online = {
                    let state_guard = state.lock().unwrap();
                    let opp_uuid = Uuid::parse_str(&opp_id_str).unwrap_or_default();
                    state_guard.tx_map.contains_key(&opp_uuid)
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

            let msg = if status == "active" {
                ServerMessage::ActiveMatches { matches }
            } else {
                ServerMessage::ArchivedMatches { matches }
            };
            let _ = tx.send(Message::Text(serde_json::to_string(&msg).unwrap()));
            debug!(user_id = %uid, status = status, "Fetched matches");
        },
        Err(e) => error!(user_id = %uid, error = %e, "Error fetching matches"),
    }
}
