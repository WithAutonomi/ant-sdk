package com.autonomi.antd;

import java.util.*;

/**
 * Minimal zero-dependency JSON parser and builder for internal use.
 * Supports the subset of JSON needed by the antd REST client:
 * objects, arrays, strings, numbers, booleans, and null.
 */
final class Json {

    private Json() {}

    // ── Parsing ──

    static Map<String, Object> parseObject(String json) {
        return new Parser(json.trim()).readObject();
    }

    // ── Building ──

    static String object(Object... kvPairs) {
        if (kvPairs.length % 2 != 0) throw new IllegalArgumentException("odd number of args");
        StringBuilder sb = new StringBuilder("{");
        for (int i = 0; i < kvPairs.length; i += 2) {
            if (i > 0) sb.append(',');
            sb.append('"').append(escape(kvPairs[i].toString())).append("\":");
            appendValue(sb, kvPairs[i + 1]);
        }
        return sb.append('}').toString();
    }

    static String array(List<?> items) {
        StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < items.size(); i++) {
            if (i > 0) sb.append(',');
            appendValue(sb, items.get(i));
        }
        return sb.append(']').toString();
    }

    private static void appendValue(StringBuilder sb, Object v) {
        if (v == null) {
            sb.append("null");
        } else if (v instanceof String s) {
            sb.append('"').append(escape(s)).append('"');
        } else if (v instanceof Number || v instanceof Boolean) {
            sb.append(v);
        } else if (v instanceof Map<?, ?> m) {
            sb.append('{');
            int i = 0;
            for (var entry : m.entrySet()) {
                if (i++ > 0) sb.append(',');
                sb.append('"').append(escape(entry.getKey().toString())).append("\":");
                appendValue(sb, entry.getValue());
            }
            sb.append('}');
        } else if (v instanceof List<?> list) {
            sb.append(array(list));
        } else {
            sb.append('"').append(escape(v.toString())).append('"');
        }
    }

    private static String escape(String s) {
        StringBuilder sb = new StringBuilder(s.length());
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                default -> {
                    if (c < 0x20) sb.append(String.format("\\u%04x", (int) c));
                    else sb.append(c);
                }
            }
        }
        return sb.toString();
    }

    // ── Minimal recursive-descent JSON parser ──

    private static class Parser {
        private final String src;
        private int pos;

        Parser(String src) { this.src = src; this.pos = 0; }

        Map<String, Object> readObject() {
            expect('{');
            Map<String, Object> map = new LinkedHashMap<>();
            skipWhitespace();
            if (peek() == '}') { pos++; return map; }
            while (true) {
                skipWhitespace();
                String key = readString();
                skipWhitespace();
                expect(':');
                skipWhitespace();
                Object value = readValue();
                map.put(key, value);
                skipWhitespace();
                if (peek() == ',') { pos++; continue; }
                break;
            }
            expect('}');
            return map;
        }

        private List<Object> readArray() {
            expect('[');
            List<Object> list = new ArrayList<>();
            skipWhitespace();
            if (peek() == ']') { pos++; return list; }
            while (true) {
                skipWhitespace();
                list.add(readValue());
                skipWhitespace();
                if (peek() == ',') { pos++; continue; }
                break;
            }
            expect(']');
            return list;
        }

        private Object readValue() {
            skipWhitespace();
            char c = peek();
            return switch (c) {
                case '"' -> readString();
                case '{' -> readObject();
                case '[' -> readArray();
                case 't', 'f' -> readBoolean();
                case 'n' -> readNull();
                default -> readNumber();
            };
        }

        private String readString() {
            expect('"');
            StringBuilder sb = new StringBuilder();
            while (pos < src.length()) {
                char c = src.charAt(pos++);
                if (c == '"') return sb.toString();
                if (c == '\\') {
                    char next = src.charAt(pos++);
                    switch (next) {
                        case '"' -> sb.append('"');
                        case '\\' -> sb.append('\\');
                        case '/' -> sb.append('/');
                        case 'n' -> sb.append('\n');
                        case 'r' -> sb.append('\r');
                        case 't' -> sb.append('\t');
                        case 'u' -> {
                            String hex = src.substring(pos, pos + 4);
                            sb.append((char) Integer.parseInt(hex, 16));
                            pos += 4;
                        }
                        default -> sb.append(next);
                    }
                } else {
                    sb.append(c);
                }
            }
            throw error("unterminated string");
        }

        private Number readNumber() {
            int start = pos;
            if (peek() == '-') pos++;
            while (pos < src.length() && isDigit(peek())) pos++;
            boolean isFloat = false;
            if (pos < src.length() && peek() == '.') {
                isFloat = true;
                pos++;
                while (pos < src.length() && isDigit(peek())) pos++;
            }
            if (pos < src.length() && (peek() == 'e' || peek() == 'E')) {
                isFloat = true;
                pos++;
                if (pos < src.length() && (peek() == '+' || peek() == '-')) pos++;
                while (pos < src.length() && isDigit(peek())) pos++;
            }
            String num = src.substring(start, pos);
            if (isFloat) return Double.parseDouble(num);
            long val = Long.parseLong(num);
            if (val >= Integer.MIN_VALUE && val <= Integer.MAX_VALUE) return (int) val;
            return val;
        }

        private boolean readBoolean() {
            if (src.startsWith("true", pos)) { pos += 4; return true; }
            if (src.startsWith("false", pos)) { pos += 5; return false; }
            throw error("expected boolean");
        }

        private Object readNull() {
            if (src.startsWith("null", pos)) { pos += 4; return null; }
            throw error("expected null");
        }

        private char peek() { return pos < src.length() ? src.charAt(pos) : 0; }
        private void expect(char c) {
            skipWhitespace();
            if (pos >= src.length() || src.charAt(pos) != c)
                throw error("expected '" + c + "'");
            pos++;
        }
        private void skipWhitespace() {
            while (pos < src.length() && Character.isWhitespace(src.charAt(pos))) pos++;
        }
        private boolean isDigit(char c) { return c >= '0' && c <= '9'; }
        private RuntimeException error(String msg) {
            return new RuntimeException("JSON parse error at " + pos + ": " + msg);
        }
    }
}
