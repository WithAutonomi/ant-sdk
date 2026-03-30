package com.autonomi.antd.models;

/**
 * Result of finalizing an externally-signed upload.
 *
 * @param address      hex address of the stored data
 * @param chunksStored number of chunks stored
 */
public record FinalizeUploadResult(String address, long chunksStored) {}
