package com.autonomi.antd;

import com.autonomi.antd.errors.AntdException;
import com.autonomi.antd.errors.BadRequestException;
import com.autonomi.antd.models.*;

import antd.v1.Manifests;

import com.google.protobuf.ByteString;

import java.util.ArrayList;
import java.util.Base64;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Wire shapes of the manifest API (ADR-0006 {@code .ant} files and
 * {@code ant://} links), shared by {@link AntdClient}, {@link AsyncAntdClient}
 * (REST JSON) and {@link GrpcAntdClient} (proto).
 *
 * <p>The {@code .ant} bytes are base64 in REST's JSON and raw {@code bytes}
 * over gRPC; callers only ever see raw bytes. Sizes are signed {@code long}s,
 * as elsewhere in this SDK (they never get near 2<sup>63</sup>). Unset values
 * read as {@code null} on both transports: REST omits them, and gRPC's
 * proto3 {@code optional} fields are read by presence, never as {@code 0}.
 */
final class ManifestWire {

    private ManifestWire() {}

    /**
     * Per-call gRPC receive limit for manifest calls: a manifest can be 64 MiB,
     * and a decode response also carries its DataMaps in hex (antd-go uses the
     * same ceiling). gRPC's default of 4 MiB would refuse a large one.
     */
    static final int MAX_GRPC_INBOUND_MESSAGE_BYTES = 256 * 1024 * 1024;

    /**
     * Per-call gRPC send limit for manifest calls: the daemon accepts manifest
     * requests up to its REST body limit, 100 MiB, so a larger decode fails
     * here instead of after the upload.
     */
    static final int MAX_GRPC_OUTBOUND_MESSAGE_BYTES = 100 * 1024 * 1024;

    // ── Checks made before anything is sent ──

    /** Invalid entries listed in one message before it is cut short, as in the daemon. */
    private static final int MAX_REPORTED_ENTRY_ERRORS = 20;

    /** The daemon's message for a decode with neither bytes nor a link. */
    static final String EMPTY_DECODE_MESSAGE = "needs a manifest (base64 .ant bytes) or a link";

    /**
     * Refuses what the daemon would, with the daemon's own error: a
     * {@link BadRequestException} (400) listing every bad entry as
     * {@code "<n> invalid entries: entries[i]: ...; entries[j]: ..."}, at most
     * 20 and then {@code "; and <k> more"}, as antd's {@code parse_entries}
     * does. That is an entry with both or neither of {@code dataMap} and
     * {@code address} (an empty string counts as unset). A null entry and a
     * negative size, which a {@code long} can hold but a u64 cannot, are
     * refused the same way, with an {@code entries[i]: } prefix.
     */
    static void checkEntries(List<ManifestEntryInput> entries) {
        if (entries == null) {
            throw new BadRequestException("entries must not be null");
        }
        List<String> errors = new ArrayList<>();
        for (int i = 0; i < entries.size(); i++) {
            ManifestEntryInput e = entries.get(i);
            String problem = null;
            if (e == null) {
                problem = "entry is null";
            } else if (isSet(e.dataMap()) && isSet(e.address())) {
                problem = "give data_map or address, not both";
            } else if (!isSet(e.dataMap()) && !isSet(e.address())) {
                problem = "needs a data_map or an address";
            } else if (e.size() != null && e.size() < 0) {
                problem = "size must not be negative, got " + e.size();
            }
            if (problem != null) errors.add("entries[" + i + "]: " + problem);
        }
        if (errors.isEmpty()) return;
        String shown = String.join("; ", errors.subList(0, Math.min(errors.size(), MAX_REPORTED_ENTRY_ERRORS)));
        throw new BadRequestException(errors.size() > MAX_REPORTED_ENTRY_ERRORS
                ? errors.size() + " invalid entries: " + shown + "; and "
                        + (errors.size() - MAX_REPORTED_ENTRY_ERRORS) + " more"
                : errors.size() + " invalid entries: " + shown);
    }

    static void checkManifest(byte[] manifest) {
        if (manifest == null || manifest.length == 0) {
            throw new BadRequestException(EMPTY_DECODE_MESSAGE);
        }
    }

    static void checkLink(String link) {
        if (!isSet(link)) {
            throw new BadRequestException(EMPTY_DECODE_MESSAGE);
        }
    }

    static BuildManifestOptions optionsOrDefault(BuildManifestOptions options) {
        return options == null ? BuildManifestOptions.DEFAULT : options;
    }

    // ── REST: request bodies ──

    static String buildBody(List<ManifestEntryInput> entries, BuildManifestOptions options) {
        options = optionsOrDefault(options);
        List<Map<String, Object>> wire = new ArrayList<>(entries.size());
        for (ManifestEntryInput e : entries) {
            Map<String, Object> m = new LinkedHashMap<>();
            if (isSet(e.path())) m.put("path", e.path());
            if (e.size() != null) m.put("size", e.size());
            if (isSet(e.dataMap())) {
                m.put("data_map", e.dataMap());
            } else {
                m.put("address", e.address());
            }
            wire.add(m);
        }
        List<Object> kv = new ArrayList<>();
        // Always sent, so a zero-value options object means "embed".
        Collections.addAll(kv, "entries", wire, "embed_roots", !options.keepShrunkDataMaps());
        if (isSet(options.name())) {
            Collections.addAll(kv, "name", options.name());
        }
        if (!options.torrentInfoHashes().isEmpty()) {
            Collections.addAll(kv, "torrent_info_hashes", options.torrentInfoHashes());
        }
        return Json.object(kv.toArray());
    }

    static String decodeBody(byte[] manifest, boolean resolve) {
        return Json.object("manifest", Base64.getEncoder().encodeToString(manifest), "resolve", resolve);
    }

    static String decodeLinkBody(String link, boolean resolve) {
        return Json.object("link", link, "resolve", resolve);
    }

    // ── REST: responses ──

    static BuiltManifest parseBuilt(Map<String, Object> j) {
        j = orEmpty(j);
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(str(j, "manifest"));
        } catch (IllegalArgumentException e) {
            throw new AntdException(0, "buildManifest: manifest is not valid base64: " + e.getMessage());
        }
        return new BuiltManifest(bytes, optStr(j, "link"), parseEntries(j));
    }

    static DecodedManifest parseDecoded(Map<String, Object> j) {
        j = orEmpty(j);
        return new DecodedManifest(
                str(j, "source"),
                optStr(j, "name"),
                optStr(j, "torrent_info_hash_v1"),
                optStr(j, "torrent_info_hash_v2"),
                parseEntries(j));
    }

    private static List<ManifestEntryInfo> parseEntries(Map<String, Object> j) {
        List<ManifestEntryInfo> out = new ArrayList<>();
        for (Map<String, Object> m : listOfMaps(j, "entries")) {
            out.add(new ManifestEntryInfo(
                    str(m, "effective_name"),
                    optStr(m, "path"),
                    optSize(m, "size"),
                    str(m, "kind"),
                    str(m, "content_address"),
                    optStr(m, "data_map"),
                    optSize(m, "exact_size"),
                    optStr(m, "error")));
        }
        return Collections.unmodifiableList(out);
    }

    /** A size the daemon may omit: absent or {@code null} is {@code null}, never 0. */
    private static Long optSize(Map<String, Object> m, String key) {
        return m.get(key) instanceof Number n ? n.longValue() : null;
    }

    // ── gRPC: requests ──

    static Manifests.BuildManifestRequest buildRequest(
            List<ManifestEntryInput> entries, BuildManifestOptions options) {
        options = optionsOrDefault(options);
        Manifests.BuildManifestRequest.Builder b = Manifests.BuildManifestRequest.newBuilder()
                .addAllTorrentInfoHashes(options.torrentInfoHashes())
                // Always set: proto3 optional, so unset would also mean true,
                // but an explicit value matches REST and antd-go.
                .setEmbedRoots(!options.keepShrunkDataMaps());
        if (isSet(options.name())) {
            b.setName(options.name());
        }
        for (ManifestEntryInput e : entries) {
            Manifests.ManifestEntryInput.Builder in = Manifests.ManifestEntryInput.newBuilder();
            if (isSet(e.path())) in.setPath(e.path());
            if (e.size() != null) in.setSize(e.size());
            if (isSet(e.dataMap())) {
                in.setDataMap(e.dataMap());
            } else {
                in.setAddress(e.address());
            }
            b.addEntries(in);
        }
        return b.build();
    }

    static Manifests.DecodeManifestRequest decodeRequest(byte[] manifest, boolean resolve) {
        return Manifests.DecodeManifestRequest.newBuilder()
                .setManifest(ByteString.copyFrom(manifest))
                .setResolve(resolve)
                .build();
    }

    static Manifests.DecodeManifestRequest decodeLinkRequest(String link, boolean resolve) {
        return Manifests.DecodeManifestRequest.newBuilder()
                .setLink(link)
                .setResolve(resolve)
                .build();
    }

    // ── gRPC: responses ──

    static BuiltManifest fromProto(Manifests.BuildManifestResponse r) {
        return new BuiltManifest(r.getManifest().toByteArray(), emptyToNull(r.getLink()),
                fromProto(r.getEntriesList()));
    }

    static DecodedManifest fromProto(Manifests.DecodeManifestResponse r) {
        return new DecodedManifest(
                r.getSource(),
                r.hasName() ? emptyToNull(r.getName()) : null,
                emptyToNull(r.getTorrentInfoHashV1()),
                emptyToNull(r.getTorrentInfoHashV2()),
                fromProto(r.getEntriesList()));
    }

    private static List<ManifestEntryInfo> fromProto(List<Manifests.ManifestEntryInfo> entries) {
        List<ManifestEntryInfo> out = new ArrayList<>(entries.size());
        for (Manifests.ManifestEntryInfo e : entries) {
            out.add(new ManifestEntryInfo(
                    e.getEffectiveName(),
                    e.hasPath() ? emptyToNull(e.getPath()) : null,
                    e.hasSize() ? Long.valueOf(e.getSize()) : null,
                    e.getKind(),
                    e.getContentAddress(),
                    emptyToNull(e.getDataMap()),
                    e.hasExactSize() ? Long.valueOf(e.getExactSize()) : null,
                    emptyToNull(e.getError())));
        }
        return Collections.unmodifiableList(out);
    }

    // ── Field helpers ──

    private static boolean isSet(String s) {
        return s != null && !s.isEmpty();
    }

    private static Map<String, Object> orEmpty(Map<String, Object> j) {
        return j == null ? Map.of() : j;
    }

    private static String str(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v != null ? v.toString() : "";
    }

    /** A string that may be unset: {@code null}, absent and empty all read as {@code null}. */
    private static String optStr(Map<String, Object> m, String key) {
        return m.get(key) instanceof String s && !s.isEmpty() ? s : null;
    }

    private static String emptyToNull(String s) {
        return s == null || s.isEmpty() ? null : s;
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> listOfMaps(Map<String, Object> m, String key) {
        List<Map<String, Object>> result = new ArrayList<>();
        if (m.get(key) instanceof List<?> list) {
            for (Object item : list) {
                if (item instanceof Map<?, ?> map) result.add((Map<String, Object>) map);
            }
        }
        return result;
    }
}
