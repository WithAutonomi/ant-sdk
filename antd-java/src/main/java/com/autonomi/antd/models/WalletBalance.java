package com.autonomi.antd.models;

/**
 * Wallet balance from the antd daemon.
 *
 * @param balance    balance in atto tokens (as a string to preserve precision)
 * @param gasBalance gas balance in atto tokens (as a string to preserve precision)
 */
public record WalletBalance(String balance, String gasBalance) {}
