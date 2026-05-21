package com.autonomi.examples;

import com.autonomi.antd.AntdClient;
import com.autonomi.antd.models.DataPutResult;

/**
 * Example 06 — Store and retrieve private (encrypted) data.
 */
public class Example06PrivateData {
    public static void main(String[] args) {
        try (var client = new AntdClient()) {
            // Store private data (encrypted by the daemon)
            byte[] secret = "sensitive enterprise data".getBytes();
            DataPutResult result = client.dataPut(secret);
            System.out.println("Data map: " + result.dataMap());
            System.out.println("Chunks:   " + result.chunksStored() + ", mode: " + result.paymentModeUsed());

            // Retrieve private data (decrypted by the daemon)
            byte[] retrieved = client.dataGet(result.dataMap());
            System.out.println("Retrieved: " + new String(retrieved));

            // Estimate cost
            com.autonomi.antd.models.UploadCostEstimate cost = client.dataCost(secret);
            System.out.println("Estimated cost: " + cost.cost() + " atto (" + cost.chunkCount() + " chunks)");
        }
    }
}
