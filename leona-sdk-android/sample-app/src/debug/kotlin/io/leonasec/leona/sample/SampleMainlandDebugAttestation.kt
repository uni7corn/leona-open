/*
 * Copyright 2026 Leona Contributors.
 * Licensed under the Apache License, Version 2.0.
 */
package io.leonasec.leona.sample

import android.content.Context
import android.os.Build
import io.leonasec.leona.config.AttestationProvider
import io.leonasec.leona.config.AttestationStatement

object SampleMainlandDebugAttestation {
    fun createProvider(context: Context, mode: String): AttestationProvider? {
        if (mode != MODE_OEM_DEBUG_FAKE) return null
        check(BuildConfig.DEBUG) { "oem_debug_fake attestation is only available in debug builds." }
        return object : AttestationProvider {
            override suspend fun attest(challenge: String, installId: String): AttestationStatement =
                AttestationStatement(
                    format = OEM_ATTESTATION_FORMAT,
                    token = buildDebugToken(
                        SampleMainlandAttestation.Request(
                            challenge = challenge,
                            installIdSha256 = installId,
                            packageName = context.packageName,
                            manufacturer = Build.MANUFACTURER.orEmpty(),
                            brand = Build.BRAND.orEmpty(),
                            model = Build.MODEL.orEmpty(),
                            sdkInt = Build.VERSION.SDK_INT,
                            issuedAtMillis = System.currentTimeMillis(),
                        ),
                    ),
                )
        }
    }

    internal fun buildDebugToken(request: SampleMainlandAttestation.Request): String = buildString {
        append('{')
        append("\"version\":1,")
        append("\"provider\":\"sample_mainland_debug\",")
        append("\"trustTier\":\"oem_attested\",")
        append("\"issuedAtMillis\":").append(request.issuedAtMillis).append(',')
        append("\"challenge\":\"").append(jsonEscape(request.challenge)).append("\",")
        append("\"installIdSha256\":\"").append(jsonEscape(request.installIdSha256)).append("\",")
        append("\"packageName\":\"").append(jsonEscape(request.packageName)).append("\",")
        append("\"evidenceLabels\":[\"debug_fake\",\"non_gms_sample\"],")
        append("\"claims\":{")
        append("\"manufacturer\":\"").append(jsonEscape(request.manufacturer)).append("\",")
        append("\"brand\":\"").append(jsonEscape(request.brand)).append("\",")
        append("\"model\":\"").append(jsonEscape(request.model)).append("\",")
        append("\"sdkInt\":\"").append(request.sdkInt).append("\"")
        append("},")
        append("\"mode\":\"oem_debug_fake\"")
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

    private const val OEM_ATTESTATION_FORMAT = "oem_attestation"
    private const val MODE_OEM_DEBUG_FAKE = "oem_debug_fake"
}
