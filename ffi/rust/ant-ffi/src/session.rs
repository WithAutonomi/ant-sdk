//! External-signer session store: the state a `prepare_*` call leaves behind
//! so a later `finalize_*` can store the chunks after the wallet has paid.
//!
//! A session moves through two states under one `upload_id`:
//!
//! - **Prepared** — quotes collected, chunks (or their on-disk spill) held,
//!   nothing paid yet. Created by `prepare_*`.
//! - **Resume** — the wallet paid and a finalize stored *some* chunks but not
//!   all. The entry now owns the resume handle ant-core returned: the paid
//!   proofs plus the still-unstored chunks. A repeat finalize with the same
//!   `upload_id` drives that handle against the **same** on-chain payment —
//!   no re-quote, no second signature.
//!
//! The store is generic over the two payloads because the real ones
//! (`ant_core::data::PreparedUpload`, `ant_core::data::FinalizeResume`) cannot
//! be constructed outside ant-core, so the state machine is unit-tested with
//! stand-ins and instantiated with the real types in `client.rs`.

use std::collections::HashMap;
use std::sync::{Mutex, MutexGuard};

use crate::ClientError;

/// Which external-signer payment shape a session carries. Used to route
/// `finalize_upload` (wave) vs `finalize_upload_merkle` and reject mismatches.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum PaymentKind {
    Wave,
    Merkle,
}

impl PaymentKind {
    /// Human labels for the mis-routed-finalize error: (what the upload used,
    /// which finalize method the caller should have called).
    fn labels(self) -> (&'static str, &'static str) {
        match self {
            PaymentKind::Merkle => ("merkle", "finalize_upload_merkle"),
            PaymentKind::Wave => ("wave-batch", "finalize_upload"),
        }
    }
}

/// Anything that can say which payment shape it belongs to. `None` means a
/// shape this SDK has no finalize route for (ant-core's enums are
/// `#[non_exhaustive]`, so a future variant must not be silently mis-routed).
pub(crate) trait PaymentShape {
    fn payment_kind(&self) -> Option<PaymentKind>;
}

/// One session's state: see the module docs.
#[derive(Debug)]
pub(crate) enum Session<P, R> {
    Prepared(P),
    Resume(R),
}

impl<P: PaymentShape, R: PaymentShape> PaymentShape for Session<P, R> {
    fn payment_kind(&self) -> Option<PaymentKind> {
        match self {
            Session::Prepared(p) => p.payment_kind(),
            Session::Resume(r) => r.payment_kind(),
        }
    }
}

/// Session map keyed by `upload_id`. Lifecycle & memory cost the caller must
/// know:
///
/// - An entry is created by every successful `prepare_*` call and removed by
///   a **complete** `finalize_upload*`, or by an explicit `cancel_upload`.
///   There is no TTL or automatic eviction.
/// - A finalize that stores only some chunks after payment does **not**
///   remove the entry: it is replaced by the resume handle so the same
///   `upload_id` can be finalized again against the same payment.
/// - So a caller that prepares repeatedly without finalizing (e.g. the user
///   backs out of the confirm sheet) retains one payload-sized buffer per
///   abandoned upload for the life of the `Client`. Call `cancel_upload` to
///   release one, or drop the whole `Client`.
///
/// A bounded cache / TTL is a possible follow-up if this proves a problem.
pub(crate) struct SessionStore<P, R> {
    entries: Mutex<HashMap<String, Session<P, R>>>,
}

impl<P: PaymentShape, R: PaymentShape> SessionStore<P, R> {
    pub(crate) fn new() -> Self {
        Self {
            entries: Mutex::new(HashMap::new()),
        }
    }

    fn lock(&self) -> MutexGuard<'_, HashMap<String, Session<P, R>>> {
        self.entries.lock().expect("sessions mutex poisoned")
    }

    /// Stash a freshly prepared upload under `upload_id`.
    pub(crate) fn insert_prepared(&self, upload_id: String, prepared: P) {
        self.lock().insert(upload_id, Session::Prepared(prepared));
    }

    /// Keep the resume handle a partial finalize handed back, under the same
    /// `upload_id`, so the next finalize call resumes instead of failing with
    /// "unknown upload_id".
    pub(crate) fn retain_resume(&self, upload_id: String, resume: R) {
        self.lock().insert(upload_id, Session::Resume(resume));
    }

    /// Discard a session, freeing whatever it holds (prepared chunk content,
    /// or the retained paid chunks of a resume handle). Returns `true` if an
    /// entry was present.
    pub(crate) fn cancel(&self, upload_id: &str) -> bool {
        self.lock().remove(upload_id).is_some()
    }

    /// Run `f` against the session for `upload_id` without removing it.
    pub(crate) fn peek<T>(
        &self,
        upload_id: &str,
        f: impl FnOnce(&Session<P, R>) -> Result<T, ClientError>,
    ) -> Result<T, ClientError> {
        let map = self.lock();
        let session = map.get(upload_id).ok_or_else(|| unknown(upload_id))?;
        f(session)
    }

    /// Run `f` against the **prepared** upload for `upload_id`. A session that
    /// has already been paid and partially stored (resume state) is rejected:
    /// there is nothing left to pay for, only to finalize.
    pub(crate) fn with_prepared<T>(
        &self,
        upload_id: &str,
        f: impl FnOnce(&P) -> Result<T, ClientError>,
    ) -> Result<T, ClientError> {
        self.peek(upload_id, |session| match session {
            Session::Prepared(p) => f(p),
            Session::Resume(_) => Err(ClientError::InvalidInput {
                reason: format!(
                    "upload {upload_id} is already paid and partially stored; \
                     call the same finalize method again to store the remainder"
                ),
            }),
        })
    }

    /// Remove and return the session for `upload_id`, but only if it matches
    /// the expected payment shape. An unknown id, or a call routed to the
    /// wrong finalize method, errors WITHOUT removing anything — so a
    /// mis-routed finalize is lossless and retryable via the correct method.
    pub(crate) fn take(
        &self,
        upload_id: &str,
        expect: PaymentKind,
    ) -> Result<Session<P, R>, ClientError> {
        let mut map = self.lock();
        let actual = map
            .get(upload_id)
            .ok_or_else(|| unknown(upload_id))?
            .payment_kind();
        match actual {
            Some(kind) if kind == expect => {}
            Some(kind) => {
                let (used, want) = kind.labels();
                return Err(ClientError::InvalidInput {
                    reason: format!("upload {upload_id} used {used} payment; call {want} instead"),
                });
            }
            None => {
                return Err(ClientError::InvalidInput {
                    reason: format!(
                        "upload {upload_id} uses a payment shape this SDK cannot finalize; \
                         cancel_upload it and re-prepare with a newer SDK"
                    ),
                });
            }
        }
        Ok(map
            .remove(upload_id)
            .expect("session entry present while holding the lock"))
    }
}

fn unknown(upload_id: &str) -> ClientError {
    ClientError::InvalidInput {
        reason: format!("unknown or already-finalized upload_id: {upload_id}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Stand-in for both `PreparedUpload` and `FinalizeResume`, which cannot
    /// be constructed outside ant-core.
    #[derive(Debug, PartialEq)]
    struct Shape(PaymentKind);

    impl PaymentShape for Shape {
        fn payment_kind(&self) -> Option<PaymentKind> {
            Some(self.0)
        }
    }

    /// A shape this SDK has no route for (a future ant-core variant).
    #[derive(Debug)]
    struct Foreign;

    impl PaymentShape for Foreign {
        fn payment_kind(&self) -> Option<PaymentKind> {
            None
        }
    }

    fn store() -> SessionStore<Shape, Shape> {
        SessionStore::new()
    }

    fn is_invalid_input_containing(err: &ClientError, needle: &str) -> bool {
        matches!(err, ClientError::InvalidInput { reason } if reason.contains(needle))
    }

    #[test]
    fn prepared_is_taken_once_and_then_unknown() {
        let s = store();
        s.insert_prepared("upl-1".into(), Shape(PaymentKind::Wave));
        assert!(matches!(
            s.take("upl-1", PaymentKind::Wave),
            Ok(Session::Prepared(Shape(PaymentKind::Wave)))
        ));
        let err = s.take("upl-1", PaymentKind::Wave).unwrap_err();
        assert!(is_invalid_input_containing(
            &err,
            "unknown or already-finalized"
        ));
    }

    #[test]
    fn wrong_method_is_lossless_for_prepared_and_resume() {
        let s = store();
        s.insert_prepared("upl-1".into(), Shape(PaymentKind::Merkle));
        let err = s.take("upl-1", PaymentKind::Wave).unwrap_err();
        assert!(is_invalid_input_containing(
            &err,
            "call finalize_upload_merkle instead"
        ));
        // Still there, and the right method takes it.
        assert!(s.take("upl-1", PaymentKind::Merkle).is_ok());

        s.retain_resume("upl-2".into(), Shape(PaymentKind::Wave));
        let err = s.take("upl-2", PaymentKind::Merkle).unwrap_err();
        assert!(is_invalid_input_containing(
            &err,
            "call finalize_upload instead"
        ));
        assert!(matches!(
            s.take("upl-2", PaymentKind::Wave),
            Ok(Session::Resume(Shape(PaymentKind::Wave)))
        ));
    }

    #[test]
    fn partial_finalize_retains_resume_under_same_id_until_complete() {
        // prepare -> take (finalize #1) -> Partial -> retain -> take
        // (finalize #2) -> Complete -> gone. The id never changes across the
        // round trip.
        let s = store();
        s.insert_prepared("upl-7".into(), Shape(PaymentKind::Wave));
        let Ok(Session::Prepared(_)) = s.take("upl-7", PaymentKind::Wave) else {
            panic!("first finalize takes the prepared upload");
        };
        s.retain_resume("upl-7".into(), Shape(PaymentKind::Wave));
        let Ok(Session::Resume(_)) = s.take("upl-7", PaymentKind::Wave) else {
            panic!("second finalize takes the resume handle");
        };
        assert!(
            !s.cancel("upl-7"),
            "a completed upload leaves no entry behind"
        );
    }

    #[test]
    fn cancel_drops_prepared_and_resume_entries() {
        let s = store();
        s.insert_prepared("a".into(), Shape(PaymentKind::Wave));
        s.retain_resume("b".into(), Shape(PaymentKind::Merkle));
        assert!(s.cancel("a"));
        assert!(s.cancel("b"));
        assert!(!s.cancel("a"));
        assert!(!s.cancel("nope"));
        assert!(s.take("a", PaymentKind::Wave).is_err());
        assert!(s.take("b", PaymentKind::Merkle).is_err());
    }

    #[test]
    fn with_prepared_rejects_resume_state_as_already_paid() {
        let s = store();
        s.insert_prepared("a".into(), Shape(PaymentKind::Wave));
        s.retain_resume("b".into(), Shape(PaymentKind::Wave));
        assert_eq!(
            s.with_prepared("a", |p| Ok(p.0)).unwrap(),
            PaymentKind::Wave
        );
        let err = s.with_prepared("b", |p| Ok(p.0)).unwrap_err();
        assert!(is_invalid_input_containing(&err, "already paid"));
        let err = s.with_prepared("zzz", |p| Ok(p.0)).unwrap_err();
        assert!(is_invalid_input_containing(
            &err,
            "unknown or already-finalized"
        ));
        // Neither call removed anything.
        assert!(s.cancel("a"));
        assert!(s.cancel("b"));
    }

    #[test]
    fn peek_sees_both_states_without_removing() {
        let s = store();
        s.retain_resume("r".into(), Shape(PaymentKind::Merkle));
        let kind = s.peek("r", |session| Ok(session.payment_kind())).unwrap();
        assert_eq!(kind, Some(PaymentKind::Merkle));
        assert!(s.cancel("r"));
    }

    #[test]
    fn unroutable_shape_is_refused_without_removal() {
        let s: SessionStore<Foreign, Foreign> = SessionStore::new();
        s.retain_resume("f".into(), Foreign);
        let err = s.take("f", PaymentKind::Wave).unwrap_err();
        assert!(is_invalid_input_containing(&err, "cannot finalize"));
        assert!(s.cancel("f"), "refusal must not drop the paid attempt");
    }
}
