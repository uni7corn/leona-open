/*
 * Copyright 2026 Leona Contributors.
 * Licensed under the Apache License, Version 2.0.
 */
package io.leonasec.leona.internal.identity

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceEnvironmentEvidenceCollectorTest {

    @Test
    fun `test and dev keys become neutral build evidence`() {
        val evidence = DeviceEnvironmentEvidenceCollector.summarize(
            DeviceEnvironmentEvidenceCollector.BuildProfile(
                tags = "release-keys,test-keys dev-keys",
                type = "userdebug",
                fingerprint = "lineage/device/userdebug/15/AP3A/test-keys",
                verifiedBootState = "orange",
                vbmetaDeviceState = "unlocked",
                flashLocked = "0",
            ),
        )

        assertTrue("expected test-keys evidence", "build.tags.test_keys" in evidence.evidenceIds)
        assertTrue("expected dev-keys evidence", "build.tags.dev_keys" in evidence.evidenceIds)
        assertTrue("expected userdebug evidence", "build.type.userdebug_or_eng" in evidence.evidenceIds)
        assertTrue("expected verified boot evidence", "verified_boot.orange" in evidence.evidenceIds)
        assertTrue("expected bootloader evidence", "bootloader.unlocked" in evidence.evidenceIds)
        assertTrue("expected ROM evidence", "rom.custom_aosp_like" in evidence.evidenceIds)
        assertEquals("test-keys/dev-keys must not be root evidence", false, evidence.evidenceIds.any { it == "root.basic" })
    }

    @Test
    fun `gsi and custom rom identifiers are grouped separately`() {
        val evidence = DeviceEnvironmentEvidenceCollector.summarize(
            DeviceEnvironmentEvidenceCollector.BuildProfile(
                tags = "release-keys",
                type = "user",
                fingerprint = "google/panther/panther:15/AP3A/release-keys",
                display = "crDroid-11.0",
                gsiImageRunning = "true",
                systemProductName = "aosp_arm64",
            ),
        )

        assertTrue("expected gsi evidence", "gsi.running" in evidence.evidenceIds)
        assertTrue("expected crDroid evidence", "rom.crdroid_like" in evidence.evidenceIds)
        assertTrue("expected ROM rollup evidence", "rom.custom_aosp_like" in evidence.evidenceIds)
        assertEquals("true", evidence.gsi["imageRunning"])
    }

    @Test
    fun `clean Huawei release build is not generic custom rom evidence`() {
        val evidence = DeviceEnvironmentEvidenceCollector.summarize(
            DeviceEnvironmentEvidenceCollector.BuildProfile(
                tags = "release-keys",
                type = "user",
                fingerprint = "HUAWEI/HMA-TL00/HWHMA:10/HUAWEIHMA-TL00/10.0.0.180C01:user/release-keys",
                brand = "HUAWEI",
                manufacturer = "HUAWEI",
                product = "HMA-TL00",
                device = "HWHMA",
                model = "HMA-TL00",
                display = "HMA-TL00 10.0.0.180(C01E180R1P3)",
                incremental = "10.0.0.180_generic_patch",
                verifiedBootState = "green",
                vbmetaDeviceState = "locked",
                flashLocked = "1",
                verityMode = "enforcing",
            ),
        )

        assertEquals(false, "rom.generic_aosp_like" in evidence.evidenceIds)
        assertEquals(false, "rom.custom_aosp_like" in evidence.evidenceIds)
    }

    @Test
    fun `generic aosp gsi build remains custom rom evidence`() {
        val evidence = DeviceEnvironmentEvidenceCollector.summarize(
            DeviceEnvironmentEvidenceCollector.BuildProfile(
                tags = "test-keys",
                type = "userdebug",
                fingerprint = "generic/aosp_arm64/gsi_arm64:15/AP3A/userdebug/test-keys",
                product = "aosp_arm64",
                device = "generic_arm64",
                systemProductName = "aosp_arm64",
                gsiImageRunning = "true",
            ),
        )

        assertTrue("expected generic AOSP evidence", "rom.generic_aosp_like" in evidence.evidenceIds)
        assertTrue("expected custom ROM rollup", "rom.custom_aosp_like" in evidence.evidenceIds)
    }
}
