//! Byte-range downloads: the stream type returned by `data_stream_range` and
//! `data_stream_public_range` on both [`crate::Client`] and
//! [`crate::GrpcClient`], plus the `Range` / `Content-Range` handling they
//! share.

use std::fmt;
use std::pin::Pin;
use std::task::{Context, Poll};

use bytes::Bytes;
use futures_core::Stream;

use crate::errors::AntdError;

/// A byte-range download. The daemon fetches and decrypts only the chunks
/// that overlap the range.
///
/// `offset` and `length` describe the bytes the stream carries, after the
/// daemon clamps a length past the end of the object; `size` is the whole
/// object's plaintext size. Consume it like any [`Stream`] of [`Bytes`]. A
/// stream that ends before `length` bytes yields a final
/// [`AntdError::Network`] instead of ending quietly, so a short body is never
/// mistaken for the whole range.
pub struct RangeStream {
    /// Position in the object of the first byte the stream carries.
    pub offset: u64,
    /// Number of bytes the stream carries.
    pub length: u64,
    /// The whole object's plaintext size.
    pub size: u64,
    inner: Pin<Box<dyn Stream<Item = Result<Bytes, AntdError>> + Send>>,
    received: u64,
    done: bool,
}

impl RangeStream {
    pub(crate) fn new(
        span: ContentRange,
        inner: impl Stream<Item = Result<Bytes, AntdError>> + Send + 'static,
    ) -> Self {
        Self {
            offset: span.offset,
            length: span.length,
            size: span.size,
            inner: Box::pin(inner),
            received: 0,
            done: false,
        }
    }
}

impl fmt::Debug for RangeStream {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("RangeStream")
            .field("offset", &self.offset)
            .field("length", &self.length)
            .field("size", &self.size)
            .finish_non_exhaustive()
    }
}

impl Stream for RangeStream {
    type Item = Result<Bytes, AntdError>;

    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        if self.done {
            return Poll::Ready(None);
        }
        let item = match self.inner.as_mut().poll_next(cx) {
            Poll::Pending => return Poll::Pending,
            Poll::Ready(item) => item,
        };
        let failure = match item {
            Some(Ok(bytes)) => {
                self.received += bytes.len() as u64;
                if self.received <= self.length {
                    return Poll::Ready(Some(Ok(bytes)));
                }
                format!(
                    "range stream carried more than the {} bytes it announced",
                    self.length
                )
            }
            Some(Err(e)) => {
                self.done = true;
                return Poll::Ready(Some(Err(e)));
            }
            None if self.received == self.length => {
                self.done = true;
                return Poll::Ready(None);
            }
            None => format!(
                "range stream ended after {} of {} bytes",
                self.received, self.length
            ),
        };
        self.done = true;
        Poll::Ready(Some(Err(AntdError::Network(failure))))
    }
}

/// A satisfied range as the daemon reports it: `Content-Range` over REST,
/// `x-content-range` metadata over gRPC, both `bytes first-last/size`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct ContentRange {
    pub offset: u64,
    pub length: u64,
    pub size: u64,
}

/// Rejects a zero length before any request is sent; `None` reads to the end.
pub(crate) fn check_length(length: Option<u64>) -> Result<(), AntdError> {
    if length == Some(0) {
        return Err(AntdError::BadRequest(
            "range length must be positive, or None to read to the end".into(),
        ));
    }
    Ok(())
}

/// Validates the range and renders it as an HTTP `Range` value. A length whose
/// last byte would overflow `u64` reads to the end anyway, so it is sent as an
/// open-ended range.
pub(crate) fn range_header(offset: u64, length: Option<u64>) -> Result<String, AntdError> {
    check_length(length)?;
    match length.and_then(|l| offset.checked_add(l - 1)) {
        Some(last) => Ok(format!("bytes={offset}-{last}")),
        None => Ok(format!("bytes={offset}-")),
    }
}

/// Parses a satisfied range, `bytes first-last/size`, and checks that it starts
/// where it was asked to.
pub(crate) fn parse_content_range(value: &str, requested: u64) -> Result<ContentRange, AntdError> {
    let bad = || AntdError::Internal(format!("malformed content range {value:?}"));
    let spec = value.trim().strip_prefix("bytes ").ok_or_else(bad)?;
    let (span, size) = spec.split_once('/').ok_or_else(bad)?;
    let (first, last) = span.split_once('-').ok_or_else(bad)?;
    let number = |s: &str| {
        if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
            return Err(bad());
        }
        s.parse::<u64>().map_err(|_| bad())
    };
    let (first, last, size) = (number(first)?, number(last)?, number(size)?);
    if last < first || last >= size {
        return Err(bad());
    }
    if first != requested {
        return Err(AntdError::Internal(format!(
            "the daemon returned a range starting at {first}, not the requested {requested}"
        )));
    }
    Ok(ContentRange {
        offset: first,
        length: last - first + 1,
        size,
    })
}

/// Parses the size from an unsatisfiable range's `bytes */size`, or `None`
/// when it is absent or malformed.
pub(crate) fn unsatisfied_size(value: &str) -> Option<u64> {
    let size = value.trim().strip_prefix("bytes */")?;
    if size.is_empty() || !size.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    size.parse().ok()
}

/// Maps the status a ranged gRPC stream call fails with, before any frame is
/// read. There `OUT_OF_RANGE` is the daemon's answer to a range starting at or
/// past the end, with the size as `x-content-range: bytes */size` (the value
/// REST's 416 carries in Content-Range) when the daemon sends it. Elsewhere it
/// stays a plain gRPC error, because tonic also reports a local message-size
/// error as `OUT_OF_RANGE`.
pub(crate) fn range_call_error(status: tonic::Status) -> AntdError {
    if status.code() != tonic::Code::OutOfRange {
        return AntdError::from(status);
    }
    AntdError::RangeNotSatisfiable {
        size: status
            .metadata()
            .get("x-content-range")
            .and_then(|v| v.to_str().ok())
            .and_then(unsatisfied_size),
        message: status.message().to_string(),
    }
}

/// The error for a daemon that answered a range request with the whole
/// object, which only a daemon predating byte-range support (antd < 0.15.0)
/// does.
pub(crate) fn no_range_support() -> AntdError {
    AntdError::Internal(
        "the daemon ignored the byte range (it predates range support); upgrade to antd 0.15.0 or later".into(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio_stream::StreamExt;

    fn span(offset: u64, length: u64, size: u64) -> ContentRange {
        ContentRange {
            offset,
            length,
            size,
        }
    }

    #[test]
    fn range_header_forms() {
        assert_eq!(range_header(0, Some(100)).unwrap(), "bytes=0-99");
        assert_eq!(range_header(10, Some(1)).unwrap(), "bytes=10-10");
        assert_eq!(range_header(5, None).unwrap(), "bytes=5-");
        assert_eq!(
            range_header(u64::MAX - 1, Some(10)).unwrap(),
            format!("bytes={}-", u64::MAX - 1)
        );
        assert!(matches!(
            range_header(0, Some(0)),
            Err(AntdError::BadRequest(_))
        ));
    }

    #[test]
    fn parses_content_range() {
        assert_eq!(
            parse_content_range("bytes 1-3/6", 1).unwrap(),
            span(1, 3, 6)
        );
        assert_eq!(
            parse_content_range(" bytes 0-0/1 ", 0).unwrap(),
            span(0, 1, 1)
        );
        let big = (1u64 << 32) + 12345;
        assert_eq!(
            parse_content_range(&format!("bytes {}-{}/{big}", 1u64 << 32, big - 1), 1 << 32)
                .unwrap(),
            span(1 << 32, 12345, big)
        );
        for bad in [
            "",
            "bytes */1000",
            "bytes 5-4/10",
            "bytes 0-10/10",
            "items 0-1/2",
            "bytes 0-1",
            "bytes +1-2/10",
            "bytes 1-2/",
        ] {
            assert!(parse_content_range(bad, 0).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn content_range_must_start_at_the_requested_offset() {
        assert!(matches!(
            parse_content_range("bytes 0-9/10", 5),
            Err(AntdError::Internal(_))
        ));
    }

    #[test]
    fn parses_unsatisfied_size() {
        assert_eq!(unsatisfied_size("bytes */1234"), Some(1234));
        assert_eq!(unsatisfied_size(" bytes */0"), Some(0));
        for bad in ["", "bytes 0-1/2", "bytes */", "bytes */-1", "bytes */12x"] {
            assert_eq!(unsatisfied_size(bad), None, "{bad:?}");
        }
    }

    fn chunks(parts: &[&'static [u8]]) -> impl Stream<Item = Result<Bytes, AntdError>> + Send {
        tokio_stream::iter(
            parts
                .iter()
                .map(|p| Ok(Bytes::from_static(p)))
                .collect::<Vec<_>>(),
        )
    }

    #[tokio::test]
    async fn range_stream_passes_a_complete_body_through() {
        let mut s = RangeStream::new(span(2, 5, 10), chunks(&[b"ab", b"cde"]));
        let mut got = Vec::new();
        while let Some(item) = s.next().await {
            got.extend_from_slice(&item.unwrap());
        }
        assert_eq!(got, b"abcde");
    }

    #[tokio::test]
    async fn range_stream_reports_a_short_body() {
        let mut s = RangeStream::new(span(0, 5, 10), chunks(&[b"ab"]));
        assert_eq!(s.next().await.unwrap().unwrap(), Bytes::from_static(b"ab"));
        assert!(matches!(s.next().await, Some(Err(AntdError::Network(m))) if m.contains("2 of 5")));
        assert!(s.next().await.is_none());
    }

    #[tokio::test]
    async fn range_stream_reports_a_long_body() {
        let mut s = RangeStream::new(span(0, 2, 10), chunks(&[b"ab", b"c"]));
        assert!(s.next().await.unwrap().is_ok());
        assert!(matches!(s.next().await, Some(Err(AntdError::Network(_)))));
        assert!(s.next().await.is_none());
    }

    #[tokio::test]
    async fn range_stream_ends_after_an_error() {
        let inner = tokio_stream::iter(vec![
            Ok(Bytes::from_static(b"a")),
            Err(AntdError::Network("boom".into())),
            Ok(Bytes::from_static(b"b")),
        ]);
        let mut s = RangeStream::new(span(0, 2, 2), inner);
        assert!(s.next().await.unwrap().is_ok());
        assert!(matches!(s.next().await, Some(Err(AntdError::Network(m))) if m == "boom"));
        assert!(s.next().await.is_none());
    }
}
