package com.autonomi.antd.models;

import java.util.List;

/**
 * A collection of archive entries representing a directory manifest.
 *
 * @param entries the archive entries
 */
public record Archive(List<ArchiveEntry> entries) {}
