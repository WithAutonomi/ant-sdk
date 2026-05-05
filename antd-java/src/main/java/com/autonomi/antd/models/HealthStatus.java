package com.autonomi.antd.models;

/**
 * Result of a daemon health check.
 *
 * <p>The diagnostic fields ({@code version}, {@code evmNetwork},
 * {@code uptimeSeconds}, {@code buildCommit}, {@code paymentTokenAddress},
 * {@code paymentVaultAddress}) were added in antd 0.4.0. They are populated
 * with empty strings / 0 when talking to a pre-0.4.0 daemon that doesn't
 * report them.
 *
 * @param ok                   whether the daemon is healthy
 * @param network              the network the daemon is connected to
 * @param version              antd crate version, e.g. "0.4.0"; "" if unknown
 * @param evmNetwork           "arbitrum-one", "arbitrum-sepolia", "local", "custom"
 * @param uptimeSeconds        seconds since the daemon process started
 * @param buildCommit          short git SHA, "" if unknown
 * @param paymentTokenAddress  payment token contract address, "" if unconfigured
 * @param paymentVaultAddress  payment vault contract address, "" if unconfigured
 */
public record HealthStatus(
        boolean ok,
        String network,
        String version,
        String evmNetwork,
        long uptimeSeconds,
        String buildCommit,
        String paymentTokenAddress,
        String paymentVaultAddress) {

    /**
     * Backward-compatible constructor for callers that only need the original
     * two fields. Diagnostic fields default to empty / 0.
     */
    public HealthStatus(boolean ok, String network) {
        this(ok, network, "", "", 0L, "", "", "");
    }
}
