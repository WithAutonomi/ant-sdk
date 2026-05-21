package com.autonomi.examples;

import com.autonomi.antd.AntdClient;
import com.autonomi.antd.models.DataPutPublicResult;

/**
 * Example 02 — Store and retrieve public immutable data.
 */
public class Example02PublicData {
    public static void main(String[] args) {
        try (var client = new AntdClient()) {
            // Store data
            byte[] payload = "Hello, Autonomi!".getBytes();
            DataPutPublicResult result = client.dataPutPublic(payload);
            System.out.println("Stored at: " + result.address());
            System.out.println("Chunks:    " + result.chunksStored() + ", mode: " + result.paymentModeUsed());

            // Retrieve data
            byte[] retrieved = client.dataGetPublic(result.address());
            System.out.println("Retrieved: " + new String(retrieved));
        }
    }
}
