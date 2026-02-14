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
    pub options: Vec<String>,
    pub min_affinity: u32,
    pub language: String,
    pub translatable: bool,
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
    #[serde(default)]
    pub answered_question_ids: Vec<Uuid>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub id: String,
    pub sender_id: Uuid,
    pub content: String,
    pub timestamp: String,
    #[serde(rename = "type")]
    pub type_: String,
    pub metadata: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActiveMatch {
    pub id: Uuid,
    pub opponent_id: Uuid,
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
    JoinSession { match_id: String },
    AnswerQuestion { match_id: String, choice: String, comment: Option<String> },
    SendMessage { match_id: String, content: String },
    FetchHistory { match_id: String },
    FetchActiveMatches,
    FetchArchivedMatches,
    FetchUserProfile { user_id: String },
    SuppressMatch { match_id: String },
    DeleteMatch { match_id: String },
    Typing { match_id: String },
    StopTyping { match_id: String },
    Ping,
    Pong,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum ServerMessage {
    Ping,
    Pong,
    Connected { user_id: Uuid },
    SearchingAck,
    MatchFound { opponent_name: String },
    SessionJoined { match_id: Uuid, affinity: u32, chat_unlocked: bool },
    Question { id: Uuid, text: String, options: Vec<String> },
    NoMoreQuestions,
    AffinityUpdate { score: u32, unlocked: bool },
    ChatMessage { id: String, sender_id: Uuid, content: String, timestamp: String, #[serde(rename = "type")] type_: String, metadata: Option<serde_json::Value> },
    History { messages: Vec<ChatMessage> },
    ActiveMatches { matches: Vec<ActiveMatch> },
    ArchivedMatches { matches: Vec<ActiveMatch> },
    UserStatus { user_id: Uuid, is_online: bool },
    UserProfile { user_id: Uuid, username: String, bio: Option<String>, tags: Option<String>, avatar_config: Option<String> },
    ProfileUpdated,
    MatchSuppressed { match_id: Uuid },
    MatchDeleted { match_id: Uuid },
    PartnerTyping { match_id: Uuid },
    PartnerStopTyping { match_id: Uuid },
    Error { message: String },
}
