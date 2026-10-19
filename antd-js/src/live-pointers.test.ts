import { describe, it, expect } from "vitest";
import { RestClient } from "./rest-client.js";
import { POINTER_FINAL_COUNTER, PointerKind } from "./models.js";
import {
  AlreadyExistsError,
  BadRequestError,
  ConflictError,
  NotFoundError,
  PointerFinalError,
} from "./errors.js";

// ---------------------------------------------------------------------------
// Live pointer round trip against a running antd with a devnet behind it.
//
// Skipped unless both are set:
//
//   ANTD_TEST_URL             the daemon's REST base URL, e.g.
//                             http://127.0.0.1:8082 (use 127.0.0.1, not
//                             localhost: Node 18 resolves localhost to ::1)
//   ANTD_TEST_POINTER_OWNERS  two comma-separated pointer addresses the daemon
//                             holds keys for (antd --pointer-keys) and that
//                             have never been written
//
// The test creates both pointers, transfers the first to the second (which
// leaves the first final for good), and leaves the second with a prepared
// write awaiting payment, so each pair can be used once. Every write is paid
// by the daemon's wallet, so run it against a devnet:
//
//   ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_POINTER_OWNERS=<hex>,<hex> \
//     npx vitest run src/live-pointers.test.ts
// ---------------------------------------------------------------------------

const url = process.env.ANTD_TEST_URL;
const owners = (process.env.ANTD_TEST_POINTER_OWNERS ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter((s) => s !== "");
const enabled = url !== undefined && url !== "" && owners.length === 2;

/** The daemon accepts a 0x prefix but returns bare hex: compare normalised. */
const norm = (s: string) => s.toLowerCase().replace(/^0x/, "");

describe.skipIf(!enabled)("live: pointer round trip", () => {
  it(
    "creates, updates, reads, transfers and prepares pointers over REST",
    async () => {
      const [a, b] = owners;
      const client = new RestClient({ baseUrl: url, timeout: 600_000 });

      // Both owners must be writable through this daemon.
      const keys = (await client.pointerKeys()).map(norm);
      expect(keys).toContain(norm(a));
      expect(keys).toContain(norm(b));

      // Real targets, so the chain can be followed back to bytes.
      const textOne = Buffer.from("antd-js pointer target one");
      const textTwo = Buffer.from("antd-js pointer target two");
      const one = (await client.dataPutPublic(textOne)).address;
      const two = (await client.dataPutPublic(textTwo)).address;

      // ── create, read, update ──
      await expect(
        client.pointerGet(a),
        `owner ${a} has been written before; use a fresh pair`,
      ).rejects.toThrow(NotFoundError);
      let w = await client.pointerCreate(a, one);
      expect(w.counter).toBe(0n);
      expect(norm(w.address)).toBe(norm(a));
      await expect(client.pointerCreate(a, two)).rejects.toThrow(AlreadyExistsError);

      let r = await client.pointerGet(a);
      expect(r.counter).toBe(0n);
      expect(r.target).toBe(one);
      expect(r.isFinal).toBe(false);
      expect(r.kind).toBe("chunk");
      expect(r.kindTag).toBe(0);
      expect(r.transferredTo).toBeNull();
      expect(r.owner).toHaveLength(2 * 1952);
      let res = await client.pointerResolve(a);
      expect(res.target).toBe(one);
      expect((await client.dataGetPublic(res.target)).equals(textOne)).toBe(true);

      w = await client.pointerUpdate(a, two, PointerKind.Chunk);
      expect(w.counter).toBe(1n);
      res = await client.pointerResolve(a);
      expect(res.target).toBe(two);
      expect((await client.dataGetPublic(res.target)).equals(textTwo)).toBe(true);
      let f = await client.pointerFinality(a);
      expect(f.status).toBe("open");
      expect(f.counter).toBe(1n);
      expect(f.answered).toBe(f.group);

      // ── transfer a -> b ──
      w = await client.pointerCreate(b, one);
      expect(w.counter).toBe(0n);
      const t = await client.pointerTransfer(a, b);
      expect(t.finalityError).toBeNull();
      expect(t.finality?.status).toBe("final");
      expect(norm(t.finality?.transferredTo ?? "")).toBe(norm(b));

      r = await client.pointerGet(a);
      expect(r.isFinal).toBe(true);
      expect(r.counter).toBe(POINTER_FINAL_COUNTER);
      expect(norm(r.transferredTo ?? "")).toBe(norm(b));
      const c = await client.pointerController(a);
      expect(norm(c.pointer)).toBe(norm(b));
      expect(c.transfers.map(norm)).toEqual([norm(b)]);
      expect(c.frozen).toBe(false);
      // a now resolves through b.
      expect((await client.pointerResolve(a)).target).toBe(one);
      f = await client.pointerFinality(a);
      expect(f.status).toBe("final");
      expect(f.state?.kind).toBe("pointer");

      // A final pointer refuses every write, before anything is paid.
      await expect(client.pointerUpdate(a, one)).rejects.toThrow(PointerFinalError);
      await expect(client.pointerTransfer(a, b)).rejects.toThrow(PointerFinalError);

      // ── external signer, up to the quote ──
      // Last: the prepared write blocks b's other writes until it expires.
      const p = await client.pointerPrepare(b, { op: "update", target: two, kind: "chunk" });
      expect(p.op).toBe("update");
      expect(p.counter).toBe(1n);
      expect(p.paymentType).toBe("wave_batch");
      expect(p.payments.length).toBeGreaterThan(0);
      expect(p.uploadId).not.toBe("");
      await expect(client.pointerUpdate(b, two)).rejects.toThrow(ConflictError);
      await expect(
        client.pointerPrepare(b, { op: "update", target: two }),
      ).rejects.toThrow(ConflictError);
      // A finalize without the payment is refused and keeps the session.
      await expect(client.pointerFinalize(p.uploadId, {})).rejects.toThrow(BadRequestError);
      await expect(client.pointerUpdate(b, two)).rejects.toThrow(ConflictError);
    },
    30 * 60_000,
  );
});
