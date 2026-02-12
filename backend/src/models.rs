use std::collections::HashMap;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    pub id: Uuid,
    pub username: String,
    pub socket_id: Option<Uuid>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Question {
    pub id: Uuid,
    pub text: String,
    pub option_a: String,
    pub option_b: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameSession {
    pub id: Uuid,
    pub user_ids: Vec<Uuid>,
    pub affinity: u32,
    pub current_question_index: usize,
    pub chat_unlocked: bool,
    #[serde(default)]
    pub current_answers: HashMap<Uuid, (String, Option<String>)>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub sender_id: Uuid,
    pub content: String,
    pub timestamp: String, // ISO 8601 string for simplicity
}

// WebSocket Communication Models

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum ClientMessage {
    Connect { username: String },
    FindMatch,
    AnswerQuestion { choice: String, comment: Option<String> }, // choice: "A" or "B"
    SendMessage { content: String },
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum ServerMessage {
    Connected { user_id: Uuid },
    MatchFound { opponent_name: String },
    Question { id: Uuid, text: String, option_a: String, option_b: String },
    AffinityUpdate { score: u32, unlocked: bool },
    ChatMessage { sender_id: Uuid, content: String },
    Error { message: String },
}
