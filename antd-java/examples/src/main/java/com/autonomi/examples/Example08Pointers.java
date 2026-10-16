package com.autonomi.examples;

import com.autonomi.antd.AntdClient;
import com.autonomi.antd.errors.AlreadyExistsException;
import com.autonomi.antd.models.PointerFinality;
import com.autonomi.antd.models.PointerRecord;
import com.autonomi.antd.models.PointerTarget;
import com.autonomi.antd.models.PointerWriteResult;

import java.io.PrintStream;
import java.nio.charset.StandardCharsets;

/**
 * Example 08 — Pointers: a mutable, owner-signed reference to data.
 *
 * <p>Uploads two small pieces of public data, creates a pointer at the first,
 * updates it to the second, resolves and reads it back, and prints its
 * finality.
 *
 * <p>The daemon signs with owner keys it loaded at startup
 * ({@code antd --pointer-keys}), so a pointer is named by its address. Set
 * {@code ANTD_POINTER_OWNER} to one of the addresses
 * {@code client.pointerKeys()} lists. {@code ANTD_BASE_URL} overrides the
 * daemon URL (default {@code http://localhost:8082}).
 *
 * <p>Every pointer write pays (about the price of one chunk) and every attempt
 * pays again, so the SDK never retries one and neither does this example.
 */
public class Example08Pointers {

    public static void main(String[] args) {
        String owner = System.getenv("ANTD_POINTER_OWNER");
        if (owner == null || owner.isBlank()) {
            System.err.println("Set ANTD_POINTER_OWNER to a pointer address the daemon holds a key for "
                    + "(antd --pointer-keys; see client.pointerKeys()).");
            System.exit(1);
        }
        String baseUrl = System.getenv("ANTD_BASE_URL");
        try (var client = baseUrl == null || baseUrl.isBlank()
                ? new AntdClient()
                : new AntdClient(baseUrl.trim())) {
            run(client, owner.trim(), System.out);
        }
    }

    /** The example's flow, separated from {@code main} so it can be tested against a mock daemon. */
    static void run(AntdClient client, String owner, PrintStream out) {
        // 1. Two small pieces of public data to point at.
        String first = client.dataPutPublic("pointer target one".getBytes(StandardCharsets.UTF_8)).address();
        String second = client.dataPutPublic("pointer target two".getBytes(StandardCharsets.UTF_8)).address();
        out.println("Data one:  " + first);
        out.println("Data two:  " + second);

        // 2. Create the pointer at the first. A pointer that already exists is
        //    refused before anything is paid; the update below still works.
        try {
            PointerWriteResult created = client.pointerCreate(owner, first);
            out.println("Created:   " + created.address() + " (counter " + created.counter() + ")");
        } catch (AlreadyExistsException e) {
            out.println("Pointer " + owner + " already exists; updating it instead.");
        }

        // 3. Point it at the second.
        PointerWriteResult updated = client.pointerUpdate(owner, second);
        out.println("Updated:   counter " + updated.counter() + ", state " + updated.stateId());

        // 4. Resolve it to the data it ends at, and read its record.
        PointerTarget resolved = client.pointerResolve(owner);
        byte[] data = client.dataGetPublic(resolved.target());
        out.println("Resolves:  " + resolved.target() + " -> \"" + new String(data, StandardCharsets.UTF_8) + "\"");
        PointerRecord record = client.pointerGet(owner);
        out.println("Record:    counter " + record.counter() + ", kind " + record.kind()
                + ", final " + record.isFinal());

        // 5. Where the close group says it stands.
        PointerFinality finality = client.pointerFinality(owner);
        out.println("Finality:  " + finality.rawStatus() + " (" + finality.answered() + "/" + finality.group()
                + " peers answered" + (finality.counter() != null ? ", counter " + finality.counter() : "") + ")");
    }
}
