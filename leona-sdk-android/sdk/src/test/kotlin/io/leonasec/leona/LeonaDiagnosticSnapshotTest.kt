/*
 * Copyright 2026 Leona Contributors.
 * Licensed under the Apache License, Version 2.0.
 */
package io.leonasec.leona

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LeonaDiagnosticSnapshotTest {

    @Test
    fun `diagnostic snapshot serializes to pretty json`() {
        val snapshot = LeonaDiagnosticSnapshot(
            deviceId = "Tdevice",
            installId = "install-1",
            canonicalDeviceId = "Lcanon",
            fingerprintHash = "hash-1",
            fingerprintSchemaVersion = 3,
            fingerprintSource = "virtual_instance_anchor_v3",
            identityAnchorSource = "virtual_instance_anchor",
            canonicalDeviceIdSource = "server_persisted",
            packageName = "io.leonasec.demo",
            appVersionName = "1.0.0",
            appVersionCode = 1L,
            installerPackage = "com.android.vending",
            androidId = "android-1",
            signingCertSha256 = listOf("aa", "bb"),
            localeTag = "zh-CN",
            timeZoneId = "Asia/Shanghai",
            screenSummary = "1080x2400@440",
            localRiskSignals = setOf("root.basic"),
            evidenceSignals = setOf("root.su_or_busybox_path_present"),
            deviceEnvironmentEvidence = LeonaDeviceEnvironmentEvidence(
                evidenceIds = setOf("build.tags.test_keys", "bootloader.unlocked"),
                build = mapOf("tags" to "test-keys"),
                bootloader = mapOf("flashLocked" to "0"),
            ),
            nativeRiskTags = setOf("hook.frida.native"),
            nativeFactTags = setOf("runtime.frida.evidence"),
            nativeFindingIds = listOf("injection.frida.known_library"),
            nativeHighestSeverity = 3,
            nativeEventCount = 1,
            serverDecision = "evidence_collected",
            serverAction = "business_defined",
            serverRiskLevel = "LOW",
            serverRiskScore = 12,
            serverRiskTags = setOf("trusted.device"),
            lastBoxId = "box-1",
        )

        val json = snapshot.toJson(LeonaDebugExportView.FULL_DEBUG)
        val obj = JSONObject(json)

        assertEquals("Tdevice", obj.getString("deviceId"))
        assertEquals("Lcanon", obj.getString("canonicalDeviceId"))
        assertEquals(3, obj.getInt("fingerprintSchemaVersion"))
        assertEquals("virtual_instance_anchor_v3", obj.getString("fingerprintSource"))
        assertEquals("virtual_instance_anchor", obj.getString("identityAnchorSource"))
        assertEquals("server_persisted", obj.getString("canonicalDeviceIdSource"))
        assertEquals(
            "root.su_or_busybox_path_present",
            obj.getJSONArray("evidenceSignals").getString(0),
        )
        assertEquals("root.basic", obj.getJSONArray("localRiskSignals").getString(0))
        assertEquals("runtime.frida.evidence", obj.getJSONArray("nativeFactTags").getString(0))
        assertEquals("hook.frida.native", obj.getJSONArray("nativeRiskTags").getString(0))
        assertEquals(1, obj.getInt("nativeEventCount"))
        assertEquals("LOW", obj.getString("serverRiskLevel"))
        assertEquals(
            "build.tags.test_keys",
            obj.getJSONObject("deviceEnvironmentEvidence").getJSONArray("evidenceIds").getString(1),
        )
        assertTrue(json.contains("\n"))
    }

    @Test
    fun `diagnostic snapshot redacts stable identifiers by default`() {
        val snapshot = LeonaDiagnosticSnapshot(
            deviceId = "Tdevice-1234567890",
            installId = "install-1234567890",
            canonicalDeviceId = "Lcanonical-1234567890",
            fingerprintHash = "fingerprint-1234567890",
            fingerprintSchemaVersion = 2,
            fingerprintSource = "base_device_v2",
            identityAnchorSource = "android_id",
            canonicalDeviceIdSource = "temporary_from_fingerprint",
            packageName = "io.leonasec.demo",
            appVersionName = "1.0.0",
            appVersionCode = 1L,
            installerPackage = "com.android.vending",
            androidId = "android-1",
            signingCertSha256 = listOf("abcdef1234567890"),
            localeTag = "zh-CN",
            timeZoneId = "Asia/Shanghai",
            screenSummary = "1080x2400@440",
            localRiskSignals = setOf("root.basic"),
            evidenceSignals = setOf("root.su_or_busybox_path_present"),
            deviceEnvironmentEvidence = LeonaDeviceEnvironmentEvidence(
                evidenceIds = setOf("verified_boot.orange"),
                verifiedBoot = mapOf("state" to "orange"),
            ),
            nativeRiskTags = setOf("hook.frida.native"),
            nativeFactTags = setOf("runtime.frida.evidence"),
            nativeFindingIds = listOf("injection.frida.known_library"),
            nativeHighestSeverity = 3,
            nativeEventCount = 1,
            serverDecision = "evidence_collected",
            serverAction = "business_defined",
            serverRiskLevel = "LOW",
            serverRiskScore = 12,
            serverRiskTags = setOf("trusted.device"),
            lastBoxId = "box-1234567890",
        )

        val obj = JSONObject(snapshot.toJson())

        assertEquals("Tdev...7890", obj.getString("deviceId"))
        assertEquals(2, obj.getInt("fingerprintSchemaVersion"))
        assertEquals("base_device_v2", obj.getString("fingerprintSource"))
        assertEquals("android_id", obj.getString("identityAnchorSource"))
        assertEquals("temporary_from_fingerprint", obj.getString("canonicalDeviceIdSource"))
        assertEquals(
            "root.su_or_busybox_path_present",
            obj.getJSONArray("evidenceSignals").getString(0),
        )
        assertEquals("root.basic", obj.getJSONArray("localRiskSignals").getString(0))
        assertEquals("runtime.frida.evidence", obj.getJSONArray("nativeFactTags").getString(0))
        assertEquals("hook.frida.native", obj.getJSONArray("nativeRiskTags").getString(0))
        assertEquals(true, obj.getBoolean("androidIdPresent"))
        assertTrue(!obj.has("androidId"))
        assertEquals("box-...7890", obj.getString("lastBoxId"))
        val redactedVerifiedBoot = obj.getJSONObject("deviceEnvironmentEvidence")
            .getJSONObject("verifiedBoot")
        assertTrue(redactedVerifiedBoot.has("valueSha256ByKey"))
        assertTrue(!redactedVerifiedBoot.has("state"))
    }
}
