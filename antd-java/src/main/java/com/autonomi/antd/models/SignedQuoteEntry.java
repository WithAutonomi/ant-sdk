package com.autonomi.antd.models;

/**
 * One signed wave-batch quote from a prepare response, as opaque base64
 * (msgpack) blobs. The same strings come back over REST and gRPC.
 *
 * @param quoteHash         quote hash (hex with 0x prefix); matches the
 *                          {@code payments} entry
 * @param quote             base64 of the msgpack-serialized signed quote. Opaque.
 * @param commitmentSidecar base64 of the msgpack-serialized storage commitment
 *                          the quote pins, or {@code null} for baseline quotes
 */
public record SignedQuoteEntry(String quoteHash, String quote, String commitmentSidecar) {}
