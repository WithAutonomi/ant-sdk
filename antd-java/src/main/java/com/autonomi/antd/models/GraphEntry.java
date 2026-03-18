package com.autonomi.antd.models;

import java.util.List;

/**
 * A DAG node from the network.
 *
 * @param owner       the owner public key
 * @param parents     list of parent addresses
 * @param content     hex-encoded content
 * @param descendants list of descendant entries
 */
public record GraphEntry(
        String owner,
        List<String> parents,
        String content,
        List<GraphDescendant> descendants) {}
