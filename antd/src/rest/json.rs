//! JSON request extractor that fails with antd's structured error body.

use axum::extract::rejection::JsonRejection;
use axum::extract::{FromRequest, Request};
use axum::Json;
use serde::de::DeserializeOwned;

use crate::error::AntdError;

/// Drop-in for `axum::Json` as a request extractor. A body that fails to
/// parse is answered with antd's `{"error", "code"}` JSON instead of axum's
/// plain-text rejection: `BAD_REQUEST` (400) for bad syntax, a field of the
/// wrong type or a missing/wrong `Content-Type`, and `PAYLOAD_TOO_LARGE`
/// (413) for a body over the route's limit. The message keeps axum's text,
/// which names the offending field.
pub struct ApiJson<T>(pub T);

impl<T, S> FromRequest<S> for ApiJson<T>
where
    T: DeserializeOwned,
    S: Send + Sync,
{
    type Rejection = AntdError;

    async fn from_request(req: Request, state: &S) -> Result<Self, Self::Rejection> {
        match Json::<T>::from_request(req, state).await {
            Ok(Json(value)) => Ok(ApiJson(value)),
            Err(rejection) => Err(map_rejection(rejection)),
        }
    }
}

fn map_rejection(rejection: JsonRejection) -> AntdError {
    let message = rejection.body_text();
    if rejection.status() == axum::http::StatusCode::PAYLOAD_TOO_LARGE {
        AntdError::PayloadTooLarge(message)
    } else {
        AntdError::BadRequest(message)
    }
}

#[cfg(test)]
mod tests {
    use axum::body::Body;
    use axum::extract::DefaultBodyLimit;
    use axum::http::{header, Method, Request, StatusCode};
    use axum::routing::post;
    use axum::Router;
    use serde::Deserialize;
    use tower::ServiceExt;

    use super::ApiJson;

    #[derive(Deserialize)]
    struct Probe {
        #[allow(dead_code)]
        size: u64,
    }

    fn app() -> Router {
        Router::new()
            .route("/probe", post(|ApiJson(_): ApiJson<Probe>| async { "ok" }))
            .layer(DefaultBodyLimit::max(64))
    }

    /// Sends `body` and returns the status plus the parsed JSON error body,
    /// asserting the response is `application/json`.
    async fn send(content_type: Option<&str>, body: &str) -> (StatusCode, serde_json::Value) {
        let mut req = Request::builder().method(Method::POST).uri("/probe");
        if let Some(ct) = content_type {
            req = req.header(header::CONTENT_TYPE, ct);
        }
        let resp = app()
            .oneshot(req.body(Body::from(body.to_owned())).unwrap())
            .await
            .unwrap();
        let status = resp.status();
        assert_eq!(
            resp.headers()[header::CONTENT_TYPE],
            "application/json",
            "rejection must be JSON"
        );
        let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
            .await
            .unwrap();
        (status, serde_json::from_slice(&bytes).unwrap())
    }

    #[tokio::test]
    async fn syntax_error_is_structured_bad_request() {
        let (status, body) = send(Some("application/json"), r#"{"size":"#).await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(body["code"], "BAD_REQUEST");
    }

    #[tokio::test]
    async fn data_error_is_structured_bad_request_naming_the_field() {
        let (status, body) = send(Some("application/json"), r#"{"size":-1}"#).await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(body["code"], "BAD_REQUEST");
        assert!(body["error"].as_str().unwrap().contains("size"), "{body}");
    }

    #[tokio::test]
    async fn missing_content_type_is_structured_bad_request() {
        let (status, body) = send(None, r#"{"size":1}"#).await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(body["code"], "BAD_REQUEST");
        assert!(body["error"].as_str().unwrap().contains("Content-Type"));
    }

    #[tokio::test]
    async fn oversized_body_is_structured_payload_too_large() {
        let big = format!(r#"{{"size":1,"pad":"{}"}}"#, "x".repeat(128));
        let (status, body) = send(Some("application/json"), &big).await;
        assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
        assert_eq!(body["code"], "PAYLOAD_TOO_LARGE");
    }

    #[tokio::test]
    async fn valid_body_passes_through() {
        let resp = app()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/probe")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(r#"{"size":1}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
    }
}
