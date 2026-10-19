package com.autonomi.antd;

import com.autonomi.antd.errors.AntdException;
import com.autonomi.antd.models.*;

import antd.v1.Common;
import antd.v1.Pointers;

import java.math.BigInteger;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Wire shapes of the pointer API, shared by {@link AntdClient},
 * {@link AsyncAntdClient} (REST JSON) and {@link GrpcAntdClient} (proto).
 *
 * <p>Counters are decimal strings on both transports, because a final state
 * sits at 2<sup>64</sup> - 1, past what a JSON number keeps exactly in many
 * languages. They are read strictly into a {@link BigInteger}: ASCII digits
 * only, at most 2<sup>64</sup> - 1. Anything else is an {@link AntdException},
 * never a silent zero.
 *
 * <p>Unset values differ by transport (REST sends {@code null}; gRPC an empty
 * string or an absent message) and both read as {@code null}.
 */
final class PointerWire {

    private PointerWire() {}

    // ── Counters ──

    /** Parses a decimal u64 counter: ASCII digits only, at most 2^64 - 1. */
    static BigInteger parseCounter(String field, Object value) {
        if (value instanceof String s && isDecimalU64(s)) {
            return new BigInteger(s);
        }
        throw new AntdException(0, "invalid pointer " + field + " "
                + (value instanceof String s ? "\"" + s + "\"" : String.valueOf(value))
                + ": expected a decimal unsigned 64-bit counter");
    }

    private static boolean isDecimalU64(String s) {
        if (s.isEmpty()) return false;
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            // Not Character.isDigit: BigInteger would also accept non-ASCII
            // digits and a leading sign.
            if (c < '0' || c > '9') return false;
        }
        return new BigInteger(s).compareTo(PointerRecord.FINAL_COUNTER) <= 0;
    }

    /** A REST counter that may be unset ({@code null} or absent). */
    private static BigInteger optionalCounter(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v == null ? null : parseCounter(key, v);
    }

    /** A gRPC counter that may be unset (the empty string). */
    private static BigInteger optionalCounter(String field, String s) {
        return s.isEmpty() ? null : parseCounter(field, s);
    }

    // ── REST: request bodies ──

    static String writeBody(String owner, String target, PointerTargetKind kind) {
        return Json.object("owner", owner, "target", target, "kind", kindOrDefault(kind).wireValue());
    }

    static String transferBody(String owner, String recipient) {
        return Json.object("owner", owner, "recipient", recipient);
    }

    static String prepareBody(String owner, PointerOp op, PointerPrepareOptions options) {
        List<Object> kv = new ArrayList<>();
        Collections.addAll(kv, "owner", owner, "op", op.wireName());
        if (op instanceof PointerOp.Create c) {
            Collections.addAll(kv, "target", c.target(), "kind", c.kind().wireValue());
        } else if (op instanceof PointerOp.Update u) {
            Collections.addAll(kv, "target", u.target(), "kind", u.kind().wireValue());
        } else if (op instanceof PointerOp.Transfer t) {
            Collections.addAll(kv, "recipient", t.recipient());
        }
        if (options != null && options.includeSignedQuotes()) {
            Collections.addAll(kv, "include_signed_quotes", true);
        }
        return Json.object(kv.toArray());
    }

    static String finalizeBody(String uploadId, Map<String, String> txHashes) {
        Map<String, String> hashes = txHashes == null ? Map.of() : new LinkedHashMap<>(txHashes);
        return Json.object("upload_id", uploadId, "tx_hashes", hashes);
    }

    static PointerTargetKind kindOrDefault(PointerTargetKind kind) {
        return kind == null ? PointerTargetKind.CHUNK : kind;
    }

    static String addressPath(String address) {
        return "/v1/pointers/" + address;
    }

    // ── REST: responses ──

    static List<String> parseKeys(Map<String, Object> j) {
        List<String> keys = new ArrayList<>();
        for (Map<String, Object> k : listOfMaps(orEmpty(j), "keys")) {
            keys.add(str(k, "address"));
        }
        return Collections.unmodifiableList(keys);
    }

    static PointerWriteResult parseWrite(Map<String, Object> j) {
        j = orEmpty(j);
        return new PointerWriteResult(
                str(j, "address"),
                str(j, "state_id"),
                parseCounter("counter", j.get("counter")));
    }

    static PointerTransferResult parseTransfer(Map<String, Object> j) {
        j = orEmpty(j);
        Map<String, Object> f = map(j, "finality");
        return new PointerTransferResult(
                str(j, "address"),
                str(j, "state_id"),
                f == null ? null : parseFinality(f),
                optStr(j, "finality_error"));
    }

    static PointerRecord parseRecord(Map<String, Object> j) {
        j = orEmpty(j);
        return new PointerRecord(
                str(j, "address"),
                str(j, "owner"),
                parseCounter("counter", j.get("counter")),
                str(j, "kind"),
                (int) num(j, "kind_tag"),
                str(j, "target"),
                str(j, "state_id"),
                bool(j, "is_final"),
                optStr(j, "transferred_to"));
    }

    static PointerTarget parseTarget(Map<String, Object> j) {
        j = orEmpty(j);
        return new PointerTarget(str(j, "kind"), (int) num(j, "kind_tag"), str(j, "target"));
    }

    static PointerFinalState parseFinalState(Map<String, Object> m) {
        return new PointerFinalState(
                str(m, "state_id"),
                str(m, "kind"),
                (int) num(m, "kind_tag"),
                str(m, "target"),
                (int) num(m, "holders"),
                optStr(m, "transferred_to"));
    }

    static PointerFinality parseFinality(Map<String, Object> j) {
        j = orEmpty(j);
        String status = str(j, "status");
        Map<String, Object> state = map(j, "state");
        Map<String, Object> majority = map(j, "majority");
        List<PointerFinalState> states = new ArrayList<>();
        for (Map<String, Object> s : listOfMaps(j, "states")) {
            states.add(parseFinalState(s));
        }
        return new PointerFinality(
                str(j, "address"),
                (int) num(j, "group"),
                (int) num(j, "answered"),
                PointerFinalityStatus.fromWire(status),
                status,
                optionalCounter(j, "counter"),
                state == null ? null : parseFinalState(state),
                Collections.unmodifiableList(states),
                majority == null ? null : parseFinalState(majority),
                optStr(j, "transferred_to"));
    }

    static PointerController parseController(Map<String, Object> j) {
        j = orEmpty(j);
        List<String> transfers = new ArrayList<>();
        if (j.get("transfers") instanceof List<?> list) {
            for (Object t : list) {
                if (t instanceof String s) transfers.add(s);
            }
        }
        return new PointerController(str(j, "pointer"), Collections.unmodifiableList(transfers), bool(j, "frozen"));
    }

    static PointerPrepareResult parsePrepare(Map<String, Object> j) {
        j = orEmpty(j);
        List<PaymentInfo> payments = new ArrayList<>();
        for (Map<String, Object> p : listOfMaps(j, "payments")) {
            payments.add(new PaymentInfo(str(p, "quote_hash"), str(p, "rewards_address"), str(p, "amount")));
        }
        List<SignedQuoteEntry> signedQuotes = new ArrayList<>();
        for (Map<String, Object> q : listOfMaps(j, "signed_quotes")) {
            signedQuotes.add(new SignedQuoteEntry(
                    str(q, "quote_hash"), str(q, "quote"), optStr(q, "commitment_sidecar")));
        }
        return new PointerPrepareResult(
                str(j, "upload_id"),
                str(j, "op"),
                str(j, "address"),
                str(j, "state_id"),
                parseCounter("counter", j.get("counter")),
                str(j, "payment_type"),
                Collections.unmodifiableList(payments),
                str(j, "total_amount"),
                str(j, "payment_vault_address"),
                str(j, "payment_token_address"),
                str(j, "rpc_url"),
                Collections.unmodifiableList(signedQuotes));
    }

    static PointerFinalizeResult parseFinalize(Map<String, Object> j) {
        j = orEmpty(j);
        Map<String, Object> f = map(j, "finality");
        return new PointerFinalizeResult(
                str(j, "address"),
                str(j, "state_id"),
                parseCounter("counter", j.get("counter")),
                f == null ? null : parseFinality(f));
    }

    // ── gRPC: requests ──

    static Pointers.PreparePointerRequest prepareRequest(
            String owner, PointerOp op, PointerPrepareOptions options) {
        Pointers.PreparePointerRequest.Builder b = Pointers.PreparePointerRequest.newBuilder()
                .setOwner(owner)
                .setOp(op.wireName());
        if (op instanceof PointerOp.Create c) {
            b.setTarget(c.target()).setKind(c.kind().wireValue());
        } else if (op instanceof PointerOp.Update u) {
            b.setTarget(u.target()).setKind(u.kind().wireValue());
        } else if (op instanceof PointerOp.Transfer t) {
            b.setRecipient(t.recipient());
        }
        if (options != null && options.includeSignedQuotes()) {
            b.setIncludeSignedQuotes(true);
        }
        return b.build();
    }

    // ── gRPC: responses ──

    static List<String> fromProto(Pointers.ListPointerKeysResponse r) {
        List<String> keys = new ArrayList<>(r.getKeysCount());
        for (Pointers.PointerKey k : r.getKeysList()) {
            keys.add(k.getAddress());
        }
        return Collections.unmodifiableList(keys);
    }

    static PointerWriteResult fromProto(Pointers.PointerWriteResponse r) {
        return new PointerWriteResult(r.getAddress(), r.getStateId(), parseCounter("counter", r.getCounter()));
    }

    static PointerTransferResult fromProto(Pointers.PointerTransferResponse r) {
        return new PointerTransferResult(
                r.getAddress(),
                r.getStateId(),
                r.hasFinality() ? fromProto(r.getFinality()) : null,
                emptyToNull(r.getFinalityError()));
    }

    static PointerRecord fromProto(Pointers.PointerRecord r) {
        return new PointerRecord(
                r.getAddress(),
                r.getOwner(),
                parseCounter("counter", r.getCounter()),
                r.getKind(),
                r.getKindTag(),
                r.getTarget(),
                r.getStateId(),
                r.getIsFinal(),
                emptyToNull(r.getTransferredTo()));
    }

    static PointerTarget fromProto(Pointers.PointerResolved r) {
        return new PointerTarget(r.getKind(), r.getKindTag(), r.getTarget());
    }

    static PointerFinalState fromProto(Pointers.PointerFinalState s) {
        return new PointerFinalState(
                s.getStateId(),
                s.getKind(),
                s.getKindTag(),
                s.getTarget(),
                s.getHolders(),
                emptyToNull(s.getTransferredTo()));
    }

    static PointerFinality fromProto(Pointers.PointerFinality f) {
        List<PointerFinalState> states = new ArrayList<>(f.getStatesCount());
        for (Pointers.PointerFinalState s : f.getStatesList()) {
            states.add(fromProto(s));
        }
        return new PointerFinality(
                f.getAddress(),
                f.getGroup(),
                f.getAnswered(),
                PointerFinalityStatus.fromWire(f.getStatus()),
                f.getStatus(),
                optionalCounter("counter", f.getCounter()),
                f.hasState() ? fromProto(f.getState()) : null,
                Collections.unmodifiableList(states),
                f.hasMajority() ? fromProto(f.getMajority()) : null,
                emptyToNull(f.getTransferredTo()));
    }

    static PointerController fromProto(Pointers.PointerController c) {
        return new PointerController(c.getPointer(), List.copyOf(c.getTransfersList()), c.getFrozen());
    }

    static PointerPrepareResult fromProto(Pointers.PreparePointerResponse r) {
        List<PaymentInfo> payments = new ArrayList<>(r.getPaymentsCount());
        for (Common.PaymentEntry p : r.getPaymentsList()) {
            payments.add(new PaymentInfo(p.getQuoteHash(), p.getRewardsAddress(), p.getAmount()));
        }
        // Base64, so a quote reads the same as over REST.
        Base64.Encoder b64 = Base64.getEncoder();
        List<SignedQuoteEntry> signedQuotes = new ArrayList<>(r.getSignedQuotesCount());
        for (Common.SignedQuoteEntry q : r.getSignedQuotesList()) {
            signedQuotes.add(new SignedQuoteEntry(
                    q.getQuoteHash(),
                    b64.encodeToString(q.getQuote().toByteArray()),
                    q.getCommitmentSidecar().isEmpty()
                            ? null
                            : b64.encodeToString(q.getCommitmentSidecar().toByteArray())));
        }
        return new PointerPrepareResult(
                r.getUploadId(),
                r.getOp(),
                r.getAddress(),
                r.getStateId(),
                parseCounter("counter", r.getCounter()),
                r.getPaymentType(),
                Collections.unmodifiableList(payments),
                r.getTotalAmount(),
                r.getPaymentVaultAddress(),
                r.getPaymentTokenAddress(),
                r.getRpcUrl(),
                Collections.unmodifiableList(signedQuotes));
    }

    static PointerFinalizeResult fromProto(Pointers.FinalizePointerResponse r) {
        return new PointerFinalizeResult(
                r.getAddress(),
                r.getStateId(),
                parseCounter("counter", r.getCounter()),
                r.hasFinality() ? fromProto(r.getFinality()) : null);
    }

    // ── JSON field helpers ──

    private static Map<String, Object> orEmpty(Map<String, Object> j) {
        return j == null ? Map.of() : j;
    }

    private static String str(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v != null ? v.toString() : "";
    }

    /** A string that may be unset: {@code null}, absent and empty all read as {@code null}. */
    private static String optStr(Map<String, Object> m, String key) {
        return m.get(key) instanceof String s && !s.isEmpty() ? s : null;
    }

    private static String emptyToNull(String s) {
        return s == null || s.isEmpty() ? null : s;
    }

    private static long num(Map<String, Object> m, String key) {
        return m.get(key) instanceof Number n ? n.longValue() : 0L;
    }

    private static boolean bool(Map<String, Object> m, String key) {
        return m.get(key) instanceof Boolean b && b;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> map(Map<String, Object> m, String key) {
        return m.get(key) instanceof Map<?, ?> v ? (Map<String, Object>) v : null;
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> listOfMaps(Map<String, Object> m, String key) {
        List<Map<String, Object>> result = new ArrayList<>();
        if (m.get(key) instanceof List<?> list) {
            for (Object item : list) {
                if (item instanceof Map<?, ?> map) result.add((Map<String, Object>) map);
            }
        }
        return result;
    }
}
