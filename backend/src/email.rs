use serde_json::json;
use std::env;

pub async fn send_confirmation_email(email: &str) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let api_key = env::var("RESEND_API_KEY").expect("RESEND_API_KEY must be set");
    let sender_email = env::var("SENDER_EMAIL").expect("SENDER_EMAIL must be set");
    
    let client = reqwest::Client::new();
    
    let html_content = include_str!("templates/welcome_email.html");

    let body = json!({
        "from": sender_email,
        "to": [email],
        "subject": "You are latent! - Latent Mate Waitlist",
        "html": html_content
    });

    let res = client.post("https://api.resend.com/emails")
        .header("Authorization", format!("Bearer {}", api_key))
        .header("Content-Type", "application/json")
        .json(&body)
        .send()
        .await?;
        
    if !res.status().is_success() {
        let status = res.status();
        let error_body = res.text().await.unwrap_or_default();
        tracing::error!("Resend API Error: Status: {}, Body: {}", status, error_body);
        return Err(format!("Resend API Error: Status: {}, Body: {}", status, error_body).into());
    }
        
    Ok(())
}
