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
use sqlx::postgres::PgPoolOptions;
use dotenv::dotenv;
use std::env;

#[tokio::main]
async fn main() {
    dotenv().ok();

    // Default to a placeholder if not set, but this will fail connection if run
    let database_url = env::var("DATABASE_URL").expect("DATABASE_URL must be set");

    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await
        .expect("Failed to connect to database");

    // Initialize database schema
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("Failed to migrate database");

    // Initialize shared state
    let shared_state = Arc::new(Mutex::new(AppState::new(pool)));

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
