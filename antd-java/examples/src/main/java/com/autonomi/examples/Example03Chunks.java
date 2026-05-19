package com.autonomi.examples;

import com.autonomi.antd.AntdClient;
import com.autonomi.antd.models.PutResult;

import java.util.Arrays;

/**
 * Example 03 — Store and retrieve a raw chunk.
 *
 * Chunks are the lowest-level storage primitive on Autonomi. The daemon's
 * internal wallet pays for the put; for the external-signer chunk path see
 * the dedicated 07_external_signer example.
 */
public class Example03Chunks {
    public static void main(String[] args) {
        try (var client = new AntdClient()) {
            byte[] payload = "Raw chunk payload from antd-java".getBytes();
            PutResult result = client.chunkPut(payload);
            System.out.println("Chunk stored at: " + result.address());
            System.out.println("Cost:            " + result.cost() + " atto");

            byte[] retrieved = client.chunkGet(result.address());
            System.out.println("Retrieved:       " + retrieved.length + " bytes");

            if (!Arrays.equals(retrieved, payload)) {
                System.err.println("Chunk round-trip mismatch");
                System.exit(1);
            }
            System.out.println("Chunk round-trip OK!");
        }
    }
}
