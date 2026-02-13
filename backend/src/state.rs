use std::collections::HashMap;
use uuid::Uuid;
use sqlx::PgPool;
use tokio::sync::mpsc;
use axum::extract::ws::Message;
use crate::models::{User, GameSession, Question};
use crate::questions::get_questions;
use std::sync::{Arc, Mutex};

pub type Tx = mpsc::UnboundedSender<Message>;
pub type SharedState = Arc<Mutex<AppState>>;

pub struct AppState {
    pub users: HashMap<Uuid, User>,
    pub sessions: HashMap<Uuid, GameSession>,
    pub user_sessions: HashMap<Uuid, Uuid>,
    pub queue: Vec<Uuid>,
    pub tx_map: HashMap<Uuid, Tx>,
    pub questions: Vec<Question>,
    pub db: PgPool,
}

impl AppState {
    pub fn new(db: PgPool) -> Self {
        Self {
            users: HashMap::new(),
            sessions: HashMap::new(),
            user_sessions: HashMap::new(),
            queue: Vec::new(),
            tx_map: HashMap::new(),
            questions: get_questions(),
            db,
        }
    }
}
