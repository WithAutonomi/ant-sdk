use axum::response::sse::{Event, KeepAlive, Sse};
use tokio::sync::mpsc;
use tokio_stream::StreamExt;
use tokio_stream::wrappers::ReceiverStream;

use autonomi::client::ClientEvent;

use crate::types::ClientEventDto;

#[allow(dead_code)]
pub fn create_event_stream(
    rx: mpsc::Receiver<ClientEvent>,
) -> Sse<impl tokio_stream::Stream<Item = Result<Event, std::convert::Infallible>>> {
    let stream = ReceiverStream::new(rx).map(|event| {
        let dto = match &event {
            ClientEvent::UploadComplete(summary) => ClientEventDto {
                kind: "upload_complete".into(),
                records_paid: Some(summary.records_paid),
                records_already_paid: Some(summary.records_already_paid),
                tokens_spent: Some(summary.tokens_spent.to_string()),
            },
            _ => ClientEventDto {
                kind: "unknown".into(),
                records_paid: None,
                records_already_paid: None,
                tokens_spent: None,
            },
        };
        let json = serde_json::to_string(&dto).unwrap_or_default();
        Ok(Event::default().data(json))
    });
    Sse::new(stream).keep_alive(KeepAlive::default())
}
