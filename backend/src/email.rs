use serde_json::json;
use std::env;

pub async fn send_confirmation_email(email: &str, user_id: i32) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let api_key = env::var("RESEND_API_KEY").expect("RESEND_API_KEY must be set");
    let sender_email = env::var("SENDER_EMAIL").expect("SENDER_EMAIL must be set");
    
    let client = reqwest::Client::new();
    
    // Prepare social share links
    // "I am the N {id} registered for the next gen of creating significant connections with people. The more people join more people close when matching. JSoin Latent Mate waitlist! https://latentmate.com"
    // Refined: "I’m #{user_id} on the list for Latent Mate. It’s the next gen of meaningful connections—pure essence, no prejudice. The more of us join, the sooner we match. Get on the waitlist! https://latentmate.com"
    
    let share_text = format!(
        "I’m #{} on the list for Latent Mate. It’s the next gen of meaningful connections—pure essence, no prejudice. The more of us join, the sooner we match. Get on the waitlist! https://latentmate.com", 
        user_id
    );
    let twitter_url = format!("https://twitter.com/intent/tweet?text={}", urlencoding::encode(&share_text));
    let whatsapp_url = format!("https://wa.me/?text={}", urlencoding::encode(&share_text));
    // For Instagram, we can't share text directly via link easily. We can link to the profile.
    let instagram_url = "https://instagram.com/latentmateapp"; 

    let mut html_content = include_str!("templates/welcome_email.html").to_string();
    html_content = html_content.replace("{{user_id}}", &user_id.to_string());
    html_content = html_content.replace("{{twitter_url}}", &twitter_url);
    html_content = html_content.replace("{{whatsapp_url}}", &whatsapp_url);
    html_content = html_content.replace("{{instagram_url}}", &instagram_url);

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
