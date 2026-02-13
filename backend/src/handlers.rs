use axum::{
    extract::{
        ws::WebSocketUpgrade,
        State,
    },
    response::IntoResponse,
};
use crate::state::SharedState;
use crate::ws::handle_socket;

pub async fn ws_handler(ws: WebSocketUpgrade, State(state): State<SharedState>) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, state))
}
