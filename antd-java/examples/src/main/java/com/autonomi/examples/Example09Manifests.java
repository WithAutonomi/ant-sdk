package com.autonomi.examples;

import com.autonomi.antd.AntdClient;
import com.autonomi.antd.models.BuildManifestOptions;
import com.autonomi.antd.models.BuiltManifest;
import com.autonomi.antd.models.DecodedManifest;
import com.autonomi.antd.models.ManifestEntryInfo;
import com.autonomi.antd.models.ManifestEntryInput;

import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * Example 09 — Manifests: one {@code ant://} link for a set of files.
 *
 * <p>Uploads two small pieces of public data, builds a manifest that names them
 * {@code notes/one.txt} and {@code notes/two.txt}, prints its link and entries,
 * then decodes the link with {@code resolve} to print each file's exact size.
 *
 * <p>The two uploads pay; building and decoding the manifest upload and pay
 * for nothing. {@code ANTD_BASE_URL} overrides the daemon URL (default
 * {@code http://localhost:8082}).
 */
public class Example09Manifests {

    public static void main(String[] args) {
        String baseUrl = System.getenv("ANTD_BASE_URL");
        try (var client = baseUrl == null || baseUrl.isBlank()
                ? new AntdClient()
                : new AntdClient(baseUrl.trim())) {
            run(client, System.out);
        }
    }

    /** The example's flow, separated from {@code main} so it can be tested against a mock daemon. */
    static void run(AntdClient client, PrintStream out) {
        // 1. Two small pieces of public data (these uploads pay).
        String one = client.dataPutPublic("manifest note one".getBytes(StandardCharsets.UTF_8)).address();
        String two = client.dataPutPublic("manifest note two, a little longer".getBytes(StandardCharsets.UTF_8))
                .address();
        out.println("Data one: " + one);
        out.println("Data two: " + two);

        // 2. A manifest naming them. Free: nothing is uploaded.
        BuiltManifest built = client.buildManifest(
                List.of(
                        ManifestEntryInput.ofAddress(one).withPath("notes/one.txt"),
                        ManifestEntryInput.ofAddress(two).withPath("notes/two.txt")),
                BuildManifestOptions.DEFAULT.withName("example"));
        out.println("Manifest: " + built.manifest().length + " bytes");
        out.println("Link:     " + (built.link() != null ? built.link() : "(too long for a link)"));
        for (ManifestEntryInfo e : built.entries()) {
            out.println("  " + e.effectiveName() + " -> " + e.contentAddress());
        }

        // 3. Decode it again, fetching each DataMap for the exact sizes.
        DecodedManifest decoded = built.link() != null
                ? client.decodeManifestLink(built.link(), true)
                : client.decodeManifest(built.manifest(), true);
        out.println("Decoded:  \"" + decoded.name() + "\" (" + decoded.source() + ")");
        for (ManifestEntryInfo e : decoded.entries()) {
            out.println("  " + e.effectiveName() + ": "
                    + (e.error() != null ? "error: " + e.error()
                    : e.exactSize() != null ? e.exactSize() + " bytes" : "size unknown"));
        }
    }
}
