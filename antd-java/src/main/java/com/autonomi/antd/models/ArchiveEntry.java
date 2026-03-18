package com.autonomi.antd.models;

/**
 * A single entry in a file archive.
 *
 * @param path     file path within the archive
 * @param address  hex-encoded data address
 * @param created  creation timestamp (Unix epoch)
 * @param modified modification timestamp (Unix epoch)
 * @param size     file size in bytes
 */
public record ArchiveEntry(String path, String address, long created, long modified, long size) {}
