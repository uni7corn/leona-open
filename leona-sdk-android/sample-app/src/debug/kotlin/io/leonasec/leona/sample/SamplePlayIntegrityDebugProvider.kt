/*
 * Copyright 2026 Leona Contributors.
 * Licensed under the Apache License, Version 2.0.
 */
package io.leonasec.leona.sample

import io.leonasec.leona.config.AttestationProvider
import io.leonasec.leona.config.PlayIntegrityAttestationProvider
import io.leonasec.leona.config.PlayIntegrityTokenProvider
import io.leonasec.leona.config.PlayIntegrityTokenRequest

object SamplePlayIntegrityDebugProvider {
    fun createProvider(mode: String, cloudProjectNumber: Long?): AttestationProvider? {
        if (mode != MODE_DEBUG_FAKE) return null
        check(BuildConfig.DEBUG) { "debug_fake attestation is only available in debug builds." }
        return PlayIntegrityAttestationProvider(
            tokenProvider = PlayIntegrityTokenProvider(::buildDebugToken),
            cloudProjectNumber = cloudProjectNumber,
        )
    }

    internal fun buildDebugToken(request: PlayIntegrityTokenRequest): String = buildString {
        append('{')
        append("\"requestDetails\":{")
        append("\"requestHash\":\"").append(jsonEscape(request.requestHash)).append("\",")
        append("\"timestampMillis\":").append(System.currentTimeMillis())
        append("},")
        append("\"appIntegrity\":{")
        append("\"appRecognitionVerdict\":\"PLAY_RECOGNIZED\"")
        append("},")
        append("\"deviceIntegrity\":{")
        append("\"deviceRecognitionVerdict\":[\"MEETS_DEVICE_INTEGRITY\"]")
        append("},")
        append("\"mode\":\"debug_fake\",")
        append("\"installIdSha256\":\"").append(jsonEscape(request.installId)).append("\"")
        request.cloudProjectNumber?.let {
            append(",\"cloudProjectNumber\":").append(it)
        }
        append('}')
    }

    private fun jsonEscape(value: String): String = buildString(value.length + 8) {
        value.forEach { ch ->
            when (ch) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> append(ch)
            }
        }
    }

    private const val MODE_DEBUG_FAKE = "debug_fake"
}
