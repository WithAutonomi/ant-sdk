package com.autonomi.examples;

import com.autonomi.antd.AntdClient;
import com.autonomi.antd.models.FilePutPublicResult;
import com.autonomi.antd.models.UploadCostEstimate;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.stream.Stream;

/**
 * Example 03 — Upload and download a file with round-trip assertion.
 */
public class Example03Files {
    public static void main(String[] args) throws Exception {
        Path tmp = Files.createTempDirectory("antd-java-03-files-");
        try (var client = new AntdClient()) {
            String fileContent = "Hello from a file on Autonomi!";
            Path src = tmp.resolve("hello.txt");
            Files.writeString(src, fileContent);

            UploadCostEstimate cost = client.fileCost(src.toString(), true);
            System.out.println("Estimated cost: " + cost.cost() + " atto (" + cost.chunkCount() + " chunks)");

            FilePutPublicResult result = client.filePutPublic(src.toString());
            System.out.println("Uploaded to:  " + result.address());
            System.out.println("Storage cost: " + result.storageCostAtto() + " atto");
            System.out.println("Gas cost:     " + result.gasCostWei() + " wei");
            System.out.println("Chunks:       " + result.chunksStored());
            System.out.println("Mode:         " + result.paymentModeUsed());

            Path dst = tmp.resolve("hello.txt.downloaded");
            client.fileGetPublic(result.address(), dst.toString());
            System.out.println("Downloaded to: " + dst);

            String got = Files.readString(dst);
            if (!got.equals(fileContent)) {
                System.err.println("round-trip mismatch on hello.txt");
                System.exit(1);
            }

            System.out.println("File upload/download OK!");
        } finally {
            try (Stream<Path> walk = Files.walk(tmp)) {
                walk.sorted(Comparator.reverseOrder()).forEach(p -> {
                    try { Files.deleteIfExists(p); } catch (Exception ignored) {}
                });
            }
        }
    }
}
