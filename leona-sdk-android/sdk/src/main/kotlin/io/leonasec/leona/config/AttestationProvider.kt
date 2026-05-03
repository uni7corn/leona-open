/*
 * Copyright 2026 Leona Contributors.
 * Licensed under the Apache License, Version 2.0.
 */
package io.leonasec.leona.config

/**
 * Optional plug point for Play Integrity / OEM attestation.
 *
 * The SDK itself ships without a hard dependency on any specific attestation
 * provider so integrators can decide whether to use Play Integrity, an OEM
 * stack, or a custom enterprise attestation flow.
 */
interface AttestationProvider {
    /**
     * Produces an attestation statement bound to [challenge].
     *
     * [installId] is the stable install identity handle included in the
     * challenge contract. In secure-reporting/private-engine flows this value
     * is the SHA-256 install-id handle, not the raw SDK-local install id.
     * Providers should forward or bind it exactly as their server-side
     * verifier expects and must not assume it is raw device-local state.
     */
    suspend fun attest(challenge: String, installId: String): AttestationStatement?
}

/**
 * Opaque attestation statement produced by an [AttestationProvider].
 *
 * - [format] examples: `play_integrity`, `oem_attestation`
 * - [token] is provider specific and forwarded to the Leona server as-is.
 */
data class AttestationStatement(
    val format: String,
    val token: String,
)
