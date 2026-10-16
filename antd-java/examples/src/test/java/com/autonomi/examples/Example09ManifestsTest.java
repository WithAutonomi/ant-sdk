package com.autonomi.examples;

import com.autonomi.antd.AntdClient;
import okhttp3.mockwebserver.Dispatcher;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import okhttp3.mockwebserver.RecordedRequest;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Runs {@link Example09Manifests#run} against a mock daemon: the calls it makes,
 * in order, what it builds, and that a manifest too long for a link is decoded
 * from its bytes instead.
 */
class Example09ManifestsTest {

    private static final String ONE = "c3".repeat(32);
    private static final String TWO = "d4".repeat(32);
    private static final String LINK = "ant://manifest/wUFOVAE";

    /** A scripted daemon; {@code withLink} decides whether the build returns a link. */
    private static final class Daemon extends Dispatcher {
        final boolean withLink;
        final List<String> calls = new ArrayList<>();
        final List<String> bodies = new ArrayList<>();
        private int uploads;

        Daemon(boolean withLink) {
            this.withLink = withLink;
        }

        private static MockResponse json(String body) {
            return new MockResponse().setResponseCode(200).setHeader("Content-Type", "application/json")
                    .setBody(body);
        }

        private static String entry(String name, String address, String extra) {
            return "{\"effective_name\":\"" + name + "\",\"path\":\"" + name + "\",\"kind\":\"public\","
                    + "\"content_address\":\"" + address + "\"" + extra + "}";
        }

        @Override
        public MockResponse dispatch(RecordedRequest req) {
            String call = req.getMethod() + " " + req.getPath();
            calls.add(call);
            bodies.add(req.getBody().readUtf8());
            switch (call) {
                case "POST /v1/data/public":
                    return json("{\"address\":\"" + (uploads++ == 0 ? ONE : TWO) + "\",\"chunks_stored\":3}");
                case "POST /v1/manifests/build":
                    return json("{\"manifest\":\"wUFOVAE=\"," + (withLink ? "\"link\":\"" + LINK + "\"," : "")
                            + "\"entries\":[" + entry("notes/one.txt", ONE, "") + ","
                            + entry("notes/two.txt", TWO, "") + "]}");
                case "POST /v1/manifests/decode":
                    return json("{\"source\":\"manifest\",\"name\":\"example\",\"entries\":["
                            + entry("notes/one.txt", ONE, ",\"exact_size\":17") + ","
                            + entry("notes/two.txt", TWO, ",\"exact_size\":34") + "]}");
                default:
                    return new MockResponse().setResponseCode(404)
                            .setBody("{\"error\":\"unexpected " + call + "\",\"code\":\"NOT_FOUND\"}");
            }
        }
    }

    private static String runAgainst(Daemon daemon) throws Exception {
        try (MockWebServer server = new MockWebServer()) {
            server.setDispatcher(daemon);
            server.start();
            ByteArrayOutputStream buf = new ByteArrayOutputStream();
            try (var client = new AntdClient(server.url("/").toString(), Duration.ofSeconds(10))) {
                Example09Manifests.run(client, new PrintStream(buf, true, StandardCharsets.UTF_8));
            }
            return buf.toString(StandardCharsets.UTF_8);
        }
    }

    @Test
    void uploadsBuildsAndDecodesTheLink() throws Exception {
        Daemon daemon = new Daemon(true);
        String out = runAgainst(daemon);
        assertEquals(List.of(
                "POST /v1/data/public",
                "POST /v1/data/public",
                "POST /v1/manifests/build",
                "POST /v1/manifests/decode"), daemon.calls);

        String build = daemon.bodies.get(2);
        assertTrue(build.contains("\"name\":\"example\""), build);
        assertTrue(build.contains("\"embed_roots\":true"), build);
        assertTrue(build.contains("{\"path\":\"notes/one.txt\",\"address\":\"" + ONE + "\"}"), build);
        assertTrue(build.contains("{\"path\":\"notes/two.txt\",\"address\":\"" + TWO + "\"}"), build);
        assertEquals("{\"link\":\"" + LINK + "\",\"resolve\":true}", daemon.bodies.get(3));

        assertTrue(out.contains("Link:     " + LINK), out);
        assertTrue(out.contains("  notes/one.txt -> " + ONE), out);
        assertTrue(out.contains("  notes/two.txt -> " + TWO), out);
        assertTrue(out.contains("  notes/one.txt: 17 bytes"), out);
        assertTrue(out.contains("  notes/two.txt: 34 bytes"), out);
    }

    @Test
    void aManifestWithoutALinkIsDecodedFromItsBytes() throws Exception {
        Daemon daemon = new Daemon(false);
        String out = runAgainst(daemon);
        assertTrue(out.contains("(too long for a link)"), out);
        assertEquals("{\"manifest\":\"wUFOVAE=\",\"resolve\":true}", daemon.bodies.get(3));
        assertTrue(out.contains("  notes/two.txt: 34 bytes"), out);
    }
}
