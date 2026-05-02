/*
 * Copyright 2026 Leona Contributors.
 * Licensed under the Apache License, Version 2.0.
 */
@file:Suppress("DEPRECATION")

package io.leonasec.leona

import io.leonasec.leona.internal.NativePayloadInspector
import io.leonasec.leona.internal.identity.DeviceFingerprintSnapshot
import org.junit.Assert.assertEquals
import org.junit.Test

class LeonaSecureDeviceContextTest {

    @Test
    fun `sense upload context keeps legacy tags and neutral evidence fields separate`() {
        val snapshot = DeviceFingerprintSnapshot(
            generatedAtMillis = 1L,
            installId = "install-1",
            canonicalDeviceId = "Lcanon",
            resolvedDeviceId = "Tdevice",
            fingerprintHash = "fingerprint-hash",
            packageName = "io.leonasec.demo",
            appVersionName = "1.0.0",
            appVersionCode = 1L,
            installerPackage = "com.android.vending",
            androidId = null,
            signingCertSha256 = listOf("cert"),
            brand = "vivo",
            model = "V2364A",
            manufacturer = "vivo",
            sdkInt = 35,
            abis = listOf("arm64-v8a"),
            localeTag = "zh-CN",
            timeZoneId = "Asia/Shanghai",
            screenSummary = "1080x2400@440",
            riskSignals = setOf("root.basic"),
        )
        val nativeRisk = NativePayloadInspector.NativeRiskSummary(
            findings = listOf(
                NativePayloadInspector.NativeFinding(
                    id = "runtime.mapping.memfd_executable",
                    severity = 2,
                    category = 0,
                    message = "Executable memfd mapping is present",
                ),
                NativePayloadInspector.NativeFinding(
                    id = "injection.frida.known_library",
                    severity = 3,
                    category = 1,
                    message = "Frida library mapping is present",
                ),
            ),
            riskTags = setOf("hook.frida.native", "hook.injection.native"),
            factTags = setOf("runtime.mapping.memfd_executable", "runtime.frida.evidence"),
            highestSeverity = 3,
        )

        val context = Leona.buildSecureDeviceContext(snapshot, nativeRisk)

        assertEquals(
            setOf("root.basic", "hook.frida.native", "hook.injection.native"),
            context.riskSignals,
        )
        assertEquals(setOf("hook.frida.native", "hook.injection.native"), context.nativeRiskTags)
        assertEquals(
            setOf("root.su_or_busybox_path_present", "runtime.mapping.memfd_executable", "runtime.frida.evidence"),
            context.evidenceSignals,
        )
        assertEquals(setOf("runtime.mapping.memfd_executable", "runtime.frida.evidence"), context.nativeFactTags)
        assertEquals(
            listOf("runtime.mapping.memfd_executable", "injection.frida.known_library"),
            context.nativeFindingIds,
        )
    }
}
