//! Bridges a JS progress callback to `ant-ffi`'s `ProgressListener` trait.
//!
//! `ant-ffi`'s `*_with_progress` methods take a `Box<dyn ProgressListener>` and,
//! internally, spawn a tokio task that calls `on_progress` as core events
//! arrive. Those calls land on a background thread, so the JS function must be a
//! napi `ThreadsafeFunction` — which is exactly what it's for. `CalleeHandled =
//! false` makes the JS side a plain `(progress) => void` (no error-first arg).

use napi::bindgen_prelude::*;
use napi::threadsafe_function::{ThreadsafeFunction, ThreadsafeFunctionCallMode};

use crate::convert::ProgressUpdate;

/// The napi callback type for progress: a JS `(progress: ProgressUpdate) => void`.
/// Methods declare the friendly TS signature via `#[napi(ts_args_type = ...)]`.
pub type ProgressTsfn = ThreadsafeFunction<ProgressUpdate, (), ProgressUpdate, Status, false>;

struct ProgressBridge {
    tsfn: ProgressTsfn,
}

impl ant_ffi::ProgressListener for ProgressBridge {
    fn on_progress(&self, update: ant_ffi::ProgressUpdate) {
        // NonBlocking: never stall the core's progress task on a slow JS handler;
        // if the queue is full a tick is dropped (progress is advisory).
        self.tsfn
            .call(update.into(), ThreadsafeFunctionCallMode::NonBlocking);
    }
}

/// Wrap a JS progress callback as an `ant-ffi` listener ready to hand to a
/// `*_with_progress` core method.
pub fn listener(tsfn: ProgressTsfn) -> Box<dyn ant_ffi::ProgressListener> {
    Box::new(ProgressBridge { tsfn })
}
