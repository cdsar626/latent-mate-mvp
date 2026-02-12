use std::{collections::HashMap, sync::{Arc, Mutex}};
use uuid::Uuid;
use crate::models::{User, GameSession, Question};
use crate::questions::get_questions;
use tokio::sync::mpsc;
use axum::extract::ws::Message;

pub type Tx = mpsc::UnboundedSender<Message>;

pub struct AppState {
    pub users: HashMap<Uuid, User>,
    pub sessions: HashMap<Uuid, GameSession>,
    pub user_sessions: HashMap<Uuid, Uuid>,
    pub queue: Vec<Uuid>,
    pub tx_map: HashMap<Uuid, Tx>,
    pub questions: Vec<Question>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            users: HashMap::new(),
            sessions: HashMap::new(),
            user_sessions: HashMap::new(),
            queue: Vec::new(),
            tx_map: HashMap::new(),
            questions: get_questions(),
        }
    }
}

pub type SharedState = Arc<Mutex<AppState>>;
