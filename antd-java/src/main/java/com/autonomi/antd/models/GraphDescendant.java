package com.autonomi.antd.models;

/**
 * A descendant entry in a graph node.
 *
 * @param publicKey hex-encoded public key
 * @param content   hex-encoded content (32 bytes)
 */
public record GraphDescendant(String publicKey, String content) {}
