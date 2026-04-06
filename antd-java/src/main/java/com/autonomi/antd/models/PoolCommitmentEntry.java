package com.autonomi.antd.models;

import java.util.List;

/**
 * A pool commitment for the merkle payment contract.
 *
 * @param poolHash   hex-encoded pool hash, 32 bytes with 0x prefix
 * @param candidates list of candidate nodes (typically 16)
 */
public record PoolCommitmentEntry(String poolHash, List<CandidateNodeEntry> candidates) {}
