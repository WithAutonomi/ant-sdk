//! Byte-range downloads (V2-1425), shared by the REST and gRPC streaming
//! handlers.
//!
//! ant-core's `Client::data_download_range` fetches and decrypts only the
//! chunks overlapping a range (their neighbours' hashes are already in the
//! DataMap, so no neighbour chunks are fetched), but it returns one buffered
//! `Bytes`. An open-ended range such as `bytes=0-` on a multi-GB object would
//! then buffer the whole object. So a range is read in windows aligned to
//! chunk boundaries: each window is one `data_download_range` call over at
//! most [`RANGE_WINDOW_CHUNKS`] chunks, so every chunk is fetched exactly once
//! and memory stays bounded however large the range is.

use std::sync::Arc;

use ant_core::data::{Client, DataMap, Error};
use bytes::Bytes;
use tokio::sync::mpsc;

/// Chunks fetched and decrypted per window. Chunks are at most ~4 MiB, so a
/// window holds at most ~32 MiB of plaintext. The producer reads the next
/// window while the previous one drains, so a ranged stream holds two or three
/// windows in memory at once.
pub const RANGE_WINDOW_CHUNKS: usize = 8;

/// A satisfiable, non-empty, half-open plaintext byte range `[start, end)`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ByteRange {
    pub start: u64,
    pub end: u64,
}

impl ByteRange {
    /// Number of bytes in the range (never 0).
    pub fn len(&self) -> u64 {
        self.end - self.start
    }

    /// The `Content-Range` value for this range of an object of `size` bytes:
    /// `bytes first-last/size`, with an inclusive `last`.
    pub fn content_range(&self, size: u64) -> String {
        format!("bytes {}-{}/{}", self.start, self.end - 1, size)
    }
}

/// Why a requested range could not be served.
#[derive(Debug, PartialEq, Eq)]
pub enum RangeError {
    /// Malformed, multi-range, or a zero/negative length: a caller bug.
    Invalid(String),
    /// Well-formed, but starts at or past the end of the object.
    Unsatisfiable,
}

/// Parse an HTTP `Range` header value against an object of `size` bytes.
///
/// One `bytes` range is supported, in any of the RFC 9110 forms: `first-last`,
/// `first-` (to the end) and `-suffix` (the last `suffix` bytes). A `last` or
/// `suffix` past the end is clamped. Multiple ranges are rejected as
/// [`RangeError::Invalid`] rather than silently answered with the whole
/// object, since that could be many GB the caller didn't ask for.
pub fn parse_range_header(value: &str, size: u64) -> Result<ByteRange, RangeError> {
    let invalid = |why: &str| RangeError::Invalid(format!("invalid Range {value:?}: {why}"));
    let (unit, spec) = value
        .split_once('=')
        .ok_or_else(|| invalid("expected bytes=first-last"))?;
    if !unit.trim().eq_ignore_ascii_case("bytes") {
        return Err(invalid("only the bytes unit is supported"));
    }
    if spec.contains(',') {
        return Err(invalid("multiple ranges are not supported"));
    }
    let (first, last) = spec
        .trim()
        .split_once('-')
        .ok_or_else(|| invalid("expected bytes=first-last"))?;
    // Digits only: `u64::from_str` also accepts a leading `+`.
    let number = |s: &str| {
        if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
            return Err(invalid("positions must be decimal integers"));
        }
        s.parse::<u64>()
            .map_err(|_| invalid("position out of range"))
    };
    let (first, last) = (first.trim(), last.trim());

    if first.is_empty() {
        // Suffix range: the last `n` bytes.
        let n = number(last)?;
        if n == 0 || size == 0 {
            return Err(RangeError::Unsatisfiable);
        }
        return Ok(ByteRange {
            start: size.saturating_sub(n),
            end: size,
        });
    }

    let start = number(first)?;
    let last = if last.is_empty() {
        None
    } else {
        Some(number(last)?)
    };
    if last.is_some_and(|last| last < start) {
        return Err(invalid("last position is before first"));
    }
    if start >= size {
        return Err(RangeError::Unsatisfiable);
    }
    let end = last.map_or(size, |last| last.saturating_add(1).min(size));
    Ok(ByteRange { start, end })
}

/// Build a range from the gRPC `offset` / `length` fields against an object of
/// `size` bytes. An absent `length` reads to the end and one past the end is
/// clamped; `length` 0 is [`RangeError::Invalid`] and an `offset` at or past
/// the end is [`RangeError::Unsatisfiable`].
pub fn range_from_offset(
    offset: u64,
    length: Option<u64>,
    size: u64,
) -> Result<ByteRange, RangeError> {
    if length == Some(0) {
        return Err(RangeError::Invalid("length must be positive".into()));
    }
    if offset >= size {
        return Err(RangeError::Unsatisfiable);
    }
    let end = length.map_or(size, |length| offset.saturating_add(length).min(size));
    Ok(ByteRange { start: offset, end })
}

/// Split `range` into windows of at most `chunks_per_window` chunks, aligned to
/// chunk boundaries so adjacent windows never fetch the same chunk.
/// `chunk_sizes` are the plaintext chunk sizes in index order.
fn plan_windows(chunk_sizes: &[u64], range: ByteRange, chunks_per_window: usize) -> Vec<ByteRange> {
    let mut windows = Vec::new();
    let mut window_start = None;
    let mut chunks_in_window = 0;
    let mut chunk_start = 0u64;
    for &chunk_size in chunk_sizes {
        let chunk_end = chunk_start.saturating_add(chunk_size);
        if chunk_start >= range.end {
            break;
        }
        if chunk_end > range.start {
            let start = *window_start.get_or_insert(chunk_start.max(range.start));
            chunks_in_window += 1;
            if chunks_in_window == chunks_per_window {
                windows.push(ByteRange {
                    start,
                    end: chunk_end.min(range.end),
                });
                window_start = None;
                chunks_in_window = 0;
            }
        }
        chunk_start = chunk_end;
    }
    if let Some(start) = window_start {
        windows.push(ByteRange {
            start,
            end: range.end,
        });
    }
    windows
}

/// Stream `range` of a resolved root `data_map` as plaintext batches, one
/// window at a time. A failed window sends its error and ends the stream after
/// the bytes already delivered, which is the same contract as the whole-object
/// stream: a short body on REST, a terminal `Status` on gRPC. Dropping the
/// receiver stops the producer at the next window.
pub fn spawn_range_stream(
    client: Arc<Client>,
    data_map: DataMap,
    range: ByteRange,
) -> mpsc::Receiver<Result<Bytes, Error>> {
    let mut infos = data_map.infos().to_vec();
    infos.sort_by_key(|info| info.index);
    let chunk_sizes: Vec<u64> = infos.iter().map(|info| info.src_size as u64).collect();
    let windows = plan_windows(&chunk_sizes, range, RANGE_WINDOW_CHUNKS);

    let (tx, rx) = mpsc::channel(1);
    tokio::spawn(async move {
        for window in windows {
            let result = match (usize::try_from(window.start), usize::try_from(window.len())) {
                (Ok(start), Ok(len)) => client.data_download_range(&data_map, start, len).await,
                _ => Err(Error::InvalidData("range exceeds the address space".into())),
            };
            let failed = result.is_err();
            if tx.send(result).await.is_err() || failed {
                break;
            }
        }
    });
    rx
}

#[cfg(test)]
mod tests {
    use super::*;

    fn r(start: u64, end: u64) -> ByteRange {
        ByteRange { start, end }
    }

    fn invalid(result: Result<ByteRange, RangeError>) -> bool {
        matches!(result, Err(RangeError::Invalid(_)))
    }

    #[test]
    fn parses_first_last() {
        assert_eq!(parse_range_header("bytes=0-99", 1000), Ok(r(0, 100)));
        assert_eq!(parse_range_header("bytes=10-10", 1000), Ok(r(10, 11)));
        assert_eq!(parse_range_header(" bytes = 5 - 9 ", 1000), Ok(r(5, 10)));
        assert_eq!(parse_range_header("BYTES=5-9", 1000), Ok(r(5, 10)));
    }

    #[test]
    fn clamps_last_past_eof() {
        assert_eq!(parse_range_header("bytes=900-5000", 1000), Ok(r(900, 1000)));
        assert_eq!(
            parse_range_header("bytes=0-18446744073709551615", 10),
            Ok(r(0, 10))
        );
    }

    #[test]
    fn parses_open_ended() {
        assert_eq!(parse_range_header("bytes=990-", 1000), Ok(r(990, 1000)));
        assert_eq!(parse_range_header("bytes=0-", 1), Ok(r(0, 1)));
    }

    #[test]
    fn parses_suffix() {
        assert_eq!(parse_range_header("bytes=-100", 1000), Ok(r(900, 1000)));
        assert_eq!(parse_range_header("bytes=-5000", 1000), Ok(r(0, 1000)));
    }

    #[test]
    fn start_at_or_past_eof_is_unsatisfiable() {
        assert_eq!(
            parse_range_header("bytes=1000-", 1000),
            Err(RangeError::Unsatisfiable)
        );
        assert_eq!(
            parse_range_header("bytes=2000-3000", 1000),
            Err(RangeError::Unsatisfiable)
        );
        assert_eq!(
            parse_range_header("bytes=-0", 1000),
            Err(RangeError::Unsatisfiable)
        );
        assert_eq!(
            parse_range_header("bytes=0-", 0),
            Err(RangeError::Unsatisfiable)
        );
        assert_eq!(
            parse_range_header("bytes=-1", 0),
            Err(RangeError::Unsatisfiable)
        );
    }

    #[test]
    fn rejects_malformed() {
        for value in [
            "",
            "bytes",
            "bytes=",
            "bytes=-",
            "bytes=abc-",
            "bytes=+1-2",
            "bytes=1-+2",
            "bytes=1--2",
            "bytes=10-5",
            "items=0-1",
            "bytes=0-1,5-6",
            "bytes=99999999999999999999-",
        ] {
            assert!(invalid(parse_range_header(value, 1000)), "{value:?}");
        }
    }

    #[test]
    fn offset_length() {
        assert_eq!(range_from_offset(0, None, 10), Ok(r(0, 10)));
        assert_eq!(range_from_offset(4, Some(3), 10), Ok(r(4, 7)));
        assert_eq!(range_from_offset(4, Some(100), 10), Ok(r(4, 10)));
        assert_eq!(range_from_offset(9, Some(u64::MAX), 10), Ok(r(9, 10)));
        assert_eq!(
            range_from_offset(10, None, 10),
            Err(RangeError::Unsatisfiable)
        );
        assert_eq!(
            range_from_offset(0, None, 0),
            Err(RangeError::Unsatisfiable)
        );
        assert!(invalid(range_from_offset(0, Some(0), 10)));
    }

    #[test]
    fn content_range_is_inclusive() {
        assert_eq!(r(0, 100).content_range(1000), "bytes 0-99/1000");
        assert_eq!(r(999, 1000).content_range(1000), "bytes 999-999/1000");
    }

    #[test]
    fn windows_within_one_chunk() {
        assert_eq!(
            plan_windows(&[100, 100, 100], r(110, 150), 8),
            [r(110, 150)]
        );
    }

    #[test]
    fn windows_span_a_chunk_boundary() {
        assert_eq!(plan_windows(&[100, 100, 100], r(90, 110), 8), [r(90, 110)]);
        // One chunk per window: the boundary splits the range in two.
        assert_eq!(
            plan_windows(&[100, 100, 100], r(90, 110), 1),
            [r(90, 100), r(100, 110)]
        );
    }

    #[test]
    fn windows_cover_the_last_partial_chunk() {
        assert_eq!(
            plan_windows(&[100, 100, 37], r(150, 237), 1),
            [r(150, 200), r(200, 237)]
        );
    }

    #[test]
    fn windows_are_chunk_aligned_and_cover_the_range_exactly() {
        let sizes = [100u64; 20];
        let range = r(250, 1730);
        let windows = plan_windows(&sizes, range, 4);
        // 250..1730 overlaps chunks 2..=17 (16 chunks): 4 windows of 4.
        assert_eq!(
            windows,
            [r(250, 600), r(600, 1000), r(1000, 1400), r(1400, 1730)]
        );
        // Contiguous, and every interior boundary is a chunk boundary.
        assert_eq!(windows.first().unwrap().start, range.start);
        assert_eq!(windows.last().unwrap().end, range.end);
        for pair in windows.windows(2) {
            assert_eq!(pair[0].end, pair[1].start);
            assert_eq!(pair[0].end % 100, 0);
        }
    }

    #[test]
    fn whole_object_window() {
        assert_eq!(plan_windows(&[100, 100, 37], r(0, 237), 8), [r(0, 237)]);
    }
}
