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
    gender: String,
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
    let gender = payload.gender.clone();
    
    tracing::info!("Received join waitlist request for: {}", email);

    // Access DB pool from shared state
    let pool = {
        let state_guard = state.lock().unwrap();
        state_guard.db.clone()
    };

    // 1. Save to DB (Insert or Get existing ID)
    let user_id = match sqlx::query_scalar::<_, i32>(
        "INSERT INTO waitlist (email, country, state, gender, created_at) VALUES ($1, $2, $3, $4, NOW()) ON CONFLICT (email) DO NOTHING RETURNING id"
    )
    .bind(&email)
    .bind(&country)
    .bind(&user_state)
    .bind(&gender)
    .fetch_optional(&pool)
    .await
    {
        Ok(Some(id)) => id,
        Ok(None) => {
             // Email exists, fetch the ID
             match sqlx::query_scalar::<_, i32>("SELECT id FROM waitlist WHERE email = $1")
                .bind(&email)
                .fetch_one(&pool)
                .await 
            {
                Ok(id) => id,
                Err(e) => {
                    tracing::error!("Failed to fetch existing user ID: {:?}", e);
                    return (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({"error": "Database error"}))).into_response();
                }
            }
        },
        Err(e) => {
            tracing::error!("Database error: {:?}", e);
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({"error": "Failed to save user"}))).into_response();
        }
    };

    // 2. Send Email (spawn task to avoid blocking)
    tokio::spawn(async move {
        if let Err(e) = email::send_confirmation_email(&email, user_id).await {
            tracing::error!("Failed to send email to {}: {:?}", email, e);
        } else {
            tracing::info!("Confirmation email sent to {}", email);
        }
    });

    (StatusCode::OK, Json(serde_json::json!({"message": "Success"}))).into_response()
}
