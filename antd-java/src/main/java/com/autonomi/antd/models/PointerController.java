package com.autonomi.antd.models;

import java.util.List;

/**
 * Whose pointer decides what an address resolves to, after following every
 * transfer ({@code pointerController}).
 *
 * @param pointer   the pointer whose owner now decides (hex)
 * @param transfers every pointer the address was handed over to, in order
 * @param frozen    {@code true} when {@code pointer} is final without being
 *                  handed over: nobody can move it
 */
public record PointerController(String pointer, List<String> transfers, boolean frozen) {}
