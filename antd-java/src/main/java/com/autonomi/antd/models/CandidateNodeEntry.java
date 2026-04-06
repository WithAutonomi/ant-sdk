package com.autonomi.antd.models;

/**
 * A candidate node in a pool commitment for merkle payments.
 *
 * @param rewardsAddress hex-encoded rewards address with 0x prefix
 * @param amount         node price as decimal string
 */
public record CandidateNodeEntry(String rewardsAddress, String amount) {}
