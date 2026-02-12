mod models;
mod state;
mod handlers;
mod ws;
mod questions;

use axum::{
    routing::get,
    Router,
};
use std::sync::{Arc, Mutex};
use state::AppState;
use handlers::ws_handler;

#[tokio::main]
async fn main() {
    // Initialize shared state
    let shared_state = Arc::new(Mutex::new(AppState::new()));

    // Build our application with a route
    let app = Router::new()
        .route("/ws", get(ws_handler))
        .with_state(shared_state);

    // Run it
    let listener = tokio::net::TcpListener::bind("127.0.0.1:3000")
        .await
        .unwrap();
    println!("listening on {}", listener.local_addr().unwrap());
    axum::serve(listener, app).await.unwrap();
}
