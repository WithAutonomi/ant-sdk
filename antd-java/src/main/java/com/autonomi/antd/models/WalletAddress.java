package com.autonomi.antd.models;

/**
 * Wallet address from the antd daemon.
 *
 * @param address hex-encoded address, e.g. "0x..."
 */
public record WalletAddress(String address) {}
