package com.autonomi.antd.models;

/**
 * Result of a put/create operation.
 *
 * @param cost    cost in atto tokens (as a string to preserve precision)
 * @param address hex-encoded address on the network
 */
public record PutResult(String cost, String address) {}
