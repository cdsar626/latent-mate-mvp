use serde::{Deserialize, Serialize};
use uuid::Uuid;
use std::collections::HashMap;

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
    pub timestamp: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActiveMatch {
    pub id: Uuid,
    pub opponent_username: String,
    pub avatar_config: Option<String>,
    pub affinity: u32,
    pub last_activity: String,
    pub is_online: bool,
}

// WebSocket Communication Models

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum ClientMessage {
    Connect { user_id: String, username: String, email: Option<String> },
    UpdateProfile { bio: String, tags: Vec<String>, avatar_config: String },
    FindMatch,
    AnswerQuestion { choice: String, comment: Option<String> }, // choice: "A" or "B"
    SendMessage { content: String },
    FetchHistory,
    FetchActiveMatches,
    Ping,
    Pong,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum ServerMessage {
    Ping,
    Pong,
    Connected { user_id: Uuid },
    MatchFound { opponent_name: String },
    Question { id: Uuid, text: String, option_a: String, option_b: String },
    AffinityUpdate { score: u32, unlocked: bool },
    ChatMessage { sender_id: Uuid, content: String },
    History { messages: Vec<ChatMessage> },
    ActiveMatches { matches: Vec<ActiveMatch> },
    UserStatus { user_id: Uuid, is_online: bool },
    Error { message: String },
}
