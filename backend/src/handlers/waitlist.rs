use axum::{
    extract::{State, Json},
    http::StatusCode,
    response::IntoResponse,
};
use serde::Deserialize;
use std::sync::Arc;
use crate::state::SharedState;
use crate::email;

#[derive(Deserialize)]
pub struct JoinWaitlistRequest {
    email: String,
    country: String,
    state: Option<String>,
    website: Option<String>, // Honeypot field
}

pub async fn join_waitlist(
    State(state): State<SharedState>,
    Json(payload): Json<JoinWaitlistRequest>,
) -> impl IntoResponse {
    // Check honeypot
    if let Some(ref honeypot) = payload.website {
        if !honeypot.is_empty() {
            tracing::warn!("Honeypot triggered by: {}", payload.email);
            // Return success to confuse bots
            return (StatusCode::OK, Json(serde_json::json!({"message": "Success"}))).into_response();
        }
    }

    let email = payload.email.clone();
    let country = payload.country.clone();
    let user_state = payload.state.clone();
    
    tracing::info!("Received join waitlist request for: {}", email);

    // Access DB pool from shared state
    let pool = {
        let state_guard = state.lock().unwrap();
        state_guard.db.clone()
    };

    // 1. Save to DB
    let result = sqlx::query(
        "INSERT INTO waitlist (email, country, state) VALUES ($1, $2, $3) ON CONFLICT (email) DO NOTHING"
    )
    .bind(&email)
    .bind(&country)
    .bind(&user_state)
    .execute(&pool)
    .await;

    if let Err(e) = result {
        tracing::error!("Database error: {:?}", e);
        return (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({"error": "Failed to save user"}))).into_response();
    }

    // 2. Send Email (spawn task to avoid blocking)
    tokio::spawn(async move {
        if let Err(e) = email::send_confirmation_email(&email).await {
            tracing::error!("Failed to send email to {}: {:?}", email, e);
        } else {
            tracing::info!("Confirmation email sent to {}", email);
        }
    });

    (StatusCode::OK, Json(serde_json::json!({"message": "Success"}))).into_response()
}
