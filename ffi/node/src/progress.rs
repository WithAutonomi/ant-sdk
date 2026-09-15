//! Bridges a JS progress callback to `ant-ffi`'s `ProgressListener` trait.
//!
//! `ant-ffi`'s `*_with_progress` methods take a `Box<dyn ProgressListener>` and,
//! internally, spawn a tokio task that calls `on_progress` as core events
//! arrive. Those calls land on a background thread, so the JS function must be a
//! napi `ThreadsafeFunction` — which is exactly what it's for. `CalleeHandled =
//! false` makes the JS side a plain `(progress) => void` (no error-first arg).
//!
//! ## A throwing callback must never kill the process
//!
//! In napi's direct-call path a JS exception thrown by the callback is routed to
//! `napi_fatal_exception`, which terminates Node. Progress is advisory, so a bug
//! in a consumer's `onProgress` must not abort a paid upload mid-flight — let
//! alone the whole process. Every tick therefore goes through
//! [`ThreadsafeFunction::call_with_return_value`], whose completion closure
//! receives the captured exception as `Err` instead; we report it as a Node
//! warning (`process.emitWarning(..., "AntProgressCallbackError")`) and carry on.

use napi::bindgen_prelude::*;
use napi::threadsafe_function::{ThreadsafeFunction, ThreadsafeFunctionCallMode};
use napi::Env;

use crate::convert::ProgressUpdate;

/// The napi callback type for progress: a JS `(progress: ProgressUpdate) => void`.
/// Methods declare the friendly TS signature via `#[napi(ts_args_type = ...)]`.
pub type ProgressTsfn = ThreadsafeFunction<ProgressUpdate, (), ProgressUpdate, Status, false>;

/// `name` of the Node warning emitted when a progress callback throws.
pub const CALLBACK_ERROR_WARNING: &str = "AntProgressCallbackError";

struct ProgressBridge {
    tsfn: ProgressTsfn,
}

impl ant_ffi::ProgressListener for ProgressBridge {
    fn on_progress(&self, update: ant_ffi::ProgressUpdate) {
        emit(&self.tsfn, update.into());
    }
}

/// Deliver one progress tick to JS. Safe to call from any thread.
///
/// NonBlocking: never stall the core's progress task on a slow JS handler; if
/// the queue is full a tick is dropped (progress is advisory). A JS exception
/// from the callback is captured and reported as a warning, never fatal.
pub fn emit(tsfn: &ProgressTsfn, update: ProgressUpdate) {
    tsfn.call_with_return_value(
        update,
        ThreadsafeFunctionCallMode::NonBlocking,
        |result, env| {
            if let Err(err) = result {
                report_callback_error(&env, err);
            }
            // Returning Ok here is what keeps napi from escalating to
            // `napi_fatal_exception`.
            Ok(())
        },
    );
}

/// `process.emitWarning("progress callback threw: <reason>", "AntProgressCallbackError")`.
/// Best effort: if even that fails, fall back to stderr rather than propagate.
fn report_callback_error(env: &Env, err: Error) {
    let message = format!("progress callback threw: {}", err.reason);
    let emitted = (|| -> Result<()> {
        let global = env.get_global()?;
        let process: Object = global.get_named_property("process")?;
        // `FnArgs` spreads the tuple into two JS arguments (a bare tuple would be
        // passed as one Array).
        let emit_warning: Function<FnArgs<(String, String)>, Unknown> =
            process.get_named_property("emitWarning")?;
        emit_warning.call(FnArgs::from((
            message.clone(),
            CALLBACK_ERROR_WARNING.to_string(),
        )))?;
        Ok(())
    })();
    if let Err(e) = emitted {
        eprintln!("[@withautonomi/ant-sdk] {message} (process.emitWarning unavailable: {e})");
    }
}

/// Wrap a JS progress callback as an `ant-ffi` listener ready to hand to a
/// `*_with_progress` core method.
pub fn listener(tsfn: ProgressTsfn) -> Box<dyn ant_ffi::ProgressListener> {
    Box::new(ProgressBridge { tsfn })
}
