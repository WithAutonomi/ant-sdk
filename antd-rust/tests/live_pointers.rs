//! Live pointer round trip against a running antd with a devnet behind it.
//!
//! Skipped unless all three are set:
//!
//! - `ANTD_TEST_URL` — the daemon's REST base URL, e.g. `http://127.0.0.1:8082`
//! - `ANTD_TEST_GRPC` — its gRPC endpoint, e.g. `http://127.0.0.1:50051`
//! - `ANTD_TEST_POINTER_OWNERS` — two comma-separated pointer addresses the
//!   daemon holds keys for (`antd --pointer-keys`) and that have **never been
//!   written**. The test creates both, transfers the first to the second, and
//!   leaves the second with a prepared write awaiting payment, so each pair can
//!   be used once.
//!
//! Every write is paid by the daemon's wallet, so run it against a devnet.
//!
//! ```text
//! ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_GRPC=http://127.0.0.1:50051 \
//! ANTD_TEST_POINTER_OWNERS=<hex>,<hex> cargo test --test live_pointers -- --nocapture
//! ```

use antd_client::{
    AntdError, Client, GrpcClient, PaymentMode, PointerFinalityStatus, PointerKind, PointerOp,
};

struct Env {
    rest: String,
    grpc: String,
    first: String,
    second: String,
}

fn env() -> Option<Env> {
    let rest = std::env::var("ANTD_TEST_URL").ok()?;
    let grpc = std::env::var("ANTD_TEST_GRPC").ok()?;
    let owners = std::env::var("ANTD_TEST_POINTER_OWNERS").ok()?;
    let (first, second) = owners.split_once(',')?;
    Some(Env {
        rest,
        grpc,
        first: first.trim().to_string(),
        second: second.trim().to_string(),
    })
}

#[tokio::test]
async fn live_pointer_round_trip() {
    let Some(env) = env() else {
        eprintln!(
            "live_pointers: set ANTD_TEST_URL, ANTD_TEST_GRPC and ANTD_TEST_POINTER_OWNERS to run"
        );
        return;
    };
    let (a, b) = (env.first.as_str(), env.second.as_str());
    let rest = Client::new(&env.rest);
    let grpc = GrpcClient::connect(&env.grpc).await.expect("grpc connect");

    // Both owners must be writable through this daemon.
    let keys: Vec<String> = rest
        .pointer_keys()
        .await
        .unwrap()
        .into_iter()
        .map(|k| k.address)
        .collect();
    assert!(
        keys.iter().any(|k| k == a) && keys.iter().any(|k| k == b),
        "daemon holds no key for one of the owners: {keys:?}"
    );

    // Real targets, so the chain can be followed back to bytes.
    let one = rest
        .data_put_public(b"antd-rust pointer target one", PaymentMode::Auto)
        .await
        .unwrap()
        .address;
    let two = rest
        .data_put_public(b"antd-rust pointer target two", PaymentMode::Auto)
        .await
        .unwrap()
        .address;

    // ── REST: create, read, update ──
    assert!(
        matches!(rest.pointer_get(a).await, Err(AntdError::NotFound(_))),
        "owner {a} has been written before; use a fresh pair"
    );
    let w = rest
        .pointer_create(a, &one, PointerKind::Chunk)
        .await
        .unwrap();
    assert_eq!(w.counter, 0);
    assert!(matches!(
        rest.pointer_create(a, &two, PointerKind::Chunk).await,
        Err(AntdError::AlreadyExists(_))
    ));
    let r = rest.pointer_get(a).await.unwrap();
    assert_eq!(
        (r.counter, r.target.as_str(), r.is_final),
        (0, one.as_str(), false)
    );
    assert_eq!(r.target_kind(), Some(PointerKind::Chunk));
    assert_eq!(r.owner.len(), 2 * 1952);
    let res = rest.pointer_resolve(a).await.unwrap();
    assert_eq!(res.target, one);
    assert_eq!(
        rest.data_get_public(&res.target).await.unwrap(),
        b"antd-rust pointer target one"
    );

    let w = rest
        .pointer_update(a, &two, PointerKind::Chunk)
        .await
        .unwrap();
    assert_eq!(w.counter, 1);
    assert_eq!(rest.pointer_resolve(a).await.unwrap().target, two);
    let f = rest.pointer_finality(a).await.unwrap();
    assert_eq!(f.status, PointerFinalityStatus::Open);
    assert_eq!(f.counter, Some(1));
    assert_eq!(f.answered, f.group);

    // ── gRPC: a write, then a read ──
    let w = grpc
        .pointer_create(b, &one, PointerKind::Chunk)
        .await
        .unwrap();
    assert_eq!(w.counter, 0);
    let r = grpc.pointer_get(b).await.unwrap();
    assert_eq!((r.counter, r.target.as_str()), (0, one.as_str()));

    // ── transfer a -> b ──
    let t = rest.pointer_transfer(a, b).await.unwrap();
    let f = t
        .finality
        .expect("the close group should answer after the transfer");
    assert_eq!(f.status, PointerFinalityStatus::Final);
    assert_eq!(f.transferred_to.as_deref(), Some(b));
    let r = rest.pointer_get(a).await.unwrap();
    assert!(r.is_final);
    assert_eq!(r.counter, u64::MAX);
    assert_eq!(r.transferred_to.as_deref(), Some(b));
    let c = rest.pointer_controller(a).await.unwrap();
    assert_eq!(
        (c.pointer.as_str(), c.transfers.clone()),
        (b, vec![b.to_string()])
    );
    // a now resolves through b.
    assert_eq!(grpc.pointer_resolve(a).await.unwrap().target, one);
    let f = grpc.pointer_finality(a).await.unwrap();
    assert!(f.is_final());

    // A final pointer refuses every write, before anything is paid.
    assert!(matches!(
        rest.pointer_update(a, &one, PointerKind::Chunk).await,
        Err(AntdError::PointerFinal(_))
    ));
    assert!(matches!(
        grpc.pointer_update(a, &one, PointerKind::Chunk).await,
        Err(AntdError::PointerFinal(_))
    ));
    assert!(matches!(
        rest.pointer_transfer(a, b).await,
        Err(AntdError::PointerFinal(_))
    ));

    // ── external signer, up to the quote ──
    // Last: the prepared write blocks b's other writes until it expires.
    let p = rest
        .pointer_prepare(
            b,
            &PointerOp::Update {
                target: two.clone(),
                kind: PointerKind::Chunk,
            },
        )
        .await
        .unwrap();
    assert_eq!((p.op.as_str(), p.counter), ("update", 1));
    assert_eq!(p.payment_type, "wave_batch");
    assert!(!p.payments.is_empty() && !p.upload_id.is_empty());
    assert!(matches!(
        rest.pointer_update(b, &two, PointerKind::Chunk).await,
        Err(AntdError::Conflict(_))
    ));
    assert!(matches!(
        grpc.pointer_prepare(
            b,
            &PointerOp::Update {
                target: two.clone(),
                kind: PointerKind::Chunk,
            }
        )
        .await,
        Err(AntdError::Conflict(_))
    ));
    // A finalize without the payment is refused and keeps the session.
    assert!(matches!(
        rest.pointer_finalize(&p.upload_id, &Default::default())
            .await,
        Err(AntdError::BadRequest(_))
    ));
    assert!(matches!(
        rest.pointer_update(b, &two, PointerKind::Chunk).await,
        Err(AntdError::Conflict(_))
    ));
}
