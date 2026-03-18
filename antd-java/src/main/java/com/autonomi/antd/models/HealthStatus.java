package com.autonomi.antd.models;

/**
 * Result of a daemon health check.
 *
 * @param ok      whether the daemon is healthy
 * @param network the network the daemon is connected to
 */
public record HealthStatus(boolean ok, String network) {}
