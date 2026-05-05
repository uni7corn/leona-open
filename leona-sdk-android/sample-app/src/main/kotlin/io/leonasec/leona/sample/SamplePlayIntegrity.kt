/*
 * Copyright 2026 Leona Contributors.
 * Licensed under the Apache License, Version 2.0.
 */
package io.leonasec.leona.sample

import io.leonasec.leona.config.AttestationProvider
import io.leonasec.leona.config.PlayIntegrityAttestationProvider
import io.leonasec.leona.config.PlayIntegrityTokenProvider
import io.leonasec.leona.config.PlayIntegrityTokenRequest

/**
 * Sample-app attestation wiring.
 *
 * Modes are controlled by BuildConfig.LEONA_SAMPLE_ATTESTATION_MODE:
 * - off: disable attestation in the sample app
 * - debug_fake: emit a synthetic Play Integrity-like JSON token for local demo only
 * - bridge: require the host app to install a real Play Integrity bridge
 */
object SamplePlayIntegrity {

    /**
     * Real projects should bridge to Google's StandardIntegrityManager flow:
     * prepareIntegrityToken(...) -> StandardIntegrityTokenProvider.request(...).
     *
     * See /Users/a/back/Game/cq/leona-sdk-android/sample-app/PLAY_INTEGRITY_REAL_BRIDGE_TEMPLATE.md
     * for a drop-in template using the official Play Integrity SDK classes.
     */
    interface Bridge {
        suspend fun requestToken(request: PlayIntegrityTokenRequest): String?
    }

    @Volatile
    private var bridge: Bridge? = null

    fun installBridge(bridge: Bridge?) {
        this.bridge = bridge
    }

    fun createProvider(): AttestationProvider? {
        val mode = BuildConfig.LEONA_SAMPLE_ATTESTATION_MODE.trim().lowercase()
        val cloudProjectNumber = BuildConfig.LEONA_SAMPLE_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER
            .trim()
            .toLongOrNull()
        return SamplePlayIntegrityDebugProvider.createProvider(mode, cloudProjectNumber)
            ?: when (mode) {
                MODE_OFF -> null
                MODE_BRIDGE -> bridge?.let { installed ->
                    PlayIntegrityAttestationProvider(
                        tokenProvider = PlayIntegrityTokenProvider(installed::requestToken),
                        cloudProjectNumber = cloudProjectNumber,
                    )
                }

                else -> null
            }
    }

    private const val MODE_OFF = "off"
    private const val MODE_BRIDGE = "bridge"
}
