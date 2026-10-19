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
import java.util.Base64;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Runs {@link Example08Pointers#run} against a mock daemon: the calls it makes,
 * in order, and that a pointer that already exists falls through to the update.
 */
class Example08PointersTest {

    private static final String OWNER = "a1".repeat(32);
    private static final String ONE = "c3".repeat(32);
    private static final String TWO = "d4".repeat(32);

    /** A scripted daemon; {@code exists} makes the create answer 409 ALREADY_EXISTS. */
    private static final class Daemon extends Dispatcher {
        final boolean exists;
        final List<String> calls = new ArrayList<>();
        private int uploads;

        Daemon(boolean exists) {
            this.exists = exists;
        }

        private static MockResponse json(int status, String body) {
            return new MockResponse().setResponseCode(status).setHeader("Content-Type", "application/json")
                    .setBody(body);
        }

        @Override
        public MockResponse dispatch(RecordedRequest req) {
            String call = req.getMethod() + " " + req.getPath();
            calls.add(call);
            String p = "/v1/pointers/" + OWNER;
            if (call.equals("POST /v1/data/public")) {
                return json(200, "{\"address\":\"" + (uploads++ == 0 ? ONE : TWO) + "\",\"chunks_stored\":1}");
            }
            if (call.equals("POST /v1/pointers")) {
                return exists
                        ? json(409, "{\"error\":\"Already exists: pointer\",\"code\":\"ALREADY_EXISTS\"}")
                        : json(200, "{\"address\":\"" + OWNER + "\",\"state_id\":\"ee\",\"counter\":\"0\"}");
            }
            if (call.equals("POST /v1/pointers/update")) {
                return json(200, "{\"address\":\"" + OWNER + "\",\"state_id\":\"ff\",\"counter\":\"1\"}");
            }
            if (call.equals("GET " + p + "/resolve")) {
                return json(200, "{\"kind\":\"chunk\",\"kind_tag\":0,\"target\":\"" + TWO + "\"}");
            }
            if (call.equals("GET /v1/data/public/" + TWO)) {
                String b64 = Base64.getEncoder().encodeToString("pointer target two".getBytes(StandardCharsets.UTF_8));
                return json(200, "{\"data\":\"" + b64 + "\"}");
            }
            if (call.equals("GET " + p)) {
                return json(200, "{\"address\":\"" + OWNER + "\",\"owner\":\"ab\",\"counter\":\"1\","
                        + "\"kind\":\"chunk\",\"kind_tag\":0,\"target\":\"" + TWO + "\",\"state_id\":\"ff\","
                        + "\"is_final\":false,\"transferred_to\":null}");
            }
            if (call.equals("GET " + p + "/finality")) {
                return json(200, "{\"address\":\"" + OWNER + "\",\"group\":7,\"answered\":7,\"status\":\"open\","
                        + "\"counter\":\"1\",\"state\":null,\"states\":[],\"majority\":null,\"transferred_to\":null}");
            }
            return json(404, "{\"error\":\"unexpected " + call + "\",\"code\":\"NOT_FOUND\"}");
        }
    }

    private static String runAgainst(Daemon daemon) throws Exception {
        try (MockWebServer server = new MockWebServer()) {
            server.setDispatcher(daemon);
            server.start();
            ByteArrayOutputStream buf = new ByteArrayOutputStream();
            try (var client = new AntdClient(server.url("/").toString(), Duration.ofSeconds(10))) {
                Example08Pointers.run(client, OWNER, new PrintStream(buf, true, StandardCharsets.UTF_8));
            }
            return buf.toString(StandardCharsets.UTF_8);
        }
    }

    @Test
    void uploadsCreatesUpdatesResolvesAndChecksFinality() throws Exception {
        Daemon daemon = new Daemon(false);
        String out = runAgainst(daemon);
        String p = "/v1/pointers/" + OWNER;
        assertEquals(List.of(
                "POST /v1/data/public",
                "POST /v1/data/public",
                "POST /v1/pointers",
                "POST /v1/pointers/update",
                "GET " + p + "/resolve",
                "GET /v1/data/public/" + TWO,
                "GET " + p,
                "GET " + p + "/finality"), daemon.calls);
        assertTrue(out.contains("Created:   " + OWNER + " (counter 0)"), out);
        assertTrue(out.contains("Updated:   counter 1"), out);
        assertTrue(out.contains("\"pointer target two\""), out);
        assertTrue(out.contains("Finality:  open (7/7 peers answered, counter 1)"), out);
    }

    @Test
    void anExistingPointerIsUpdatedInstead() throws Exception {
        Daemon daemon = new Daemon(true);
        String out = runAgainst(daemon);
        assertTrue(out.contains("already exists; updating it instead"), out);
        assertTrue(out.contains("Updated:   counter 1"), out);
        // The create is attempted exactly once, never retried.
        assertEquals(1, daemon.calls.stream().filter("POST /v1/pointers"::equals).count());
    }
}
