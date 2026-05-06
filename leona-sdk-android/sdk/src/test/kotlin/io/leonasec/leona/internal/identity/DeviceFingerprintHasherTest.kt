/*
 * Copyright 2026 Leona Contributors.
 * Licensed under the Apache License, Version 2.0.
 */
package io.leonasec.leona.internal.identity

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceFingerprintHasherTest {

    @Test
    fun `virtual instance anchors are hashed and affect fingerprint`() {
        val baseSeed = mapOf(
            "version" to DeviceFingerprintHasher.VIRTUAL_ANCHOR_SEED_VERSION.toString(),
            "identityAnchor" to "android:cloned",
            "buildFingerprint" to "mumu/build/fingerprint",
            "device" to "mumu",
        )
        val firstAnchor = DeviceFingerprintHasher.hashVirtualInstanceAnchors(
            mapOf("prop.nemud.player_uuid" to "vm-instance-a"),
        )
        val secondAnchor = DeviceFingerprintHasher.hashVirtualInstanceAnchors(
            mapOf("prop.nemud.player_uuid" to "vm-instance-b"),
        )

        assertTrue(firstAnchor!!.matches(Regex("[0-9a-f]{64}")))
        assertTrue(secondAnchor!!.matches(Regex("[0-9a-f]{64}")))
        assertNotEquals(firstAnchor, secondAnchor)
        assertNotEquals(
            DeviceFingerprintHasher.hashFingerprintSeed(baseSeed + ("virtualInstanceAnchorHash" to firstAnchor)),
            DeviceFingerprintHasher.hashFingerprintSeed(baseSeed + ("virtualInstanceAnchorHash" to secondAnchor)),
        )
    }

    @Test
    fun `virtual instance anchor keeps fingerprint stable when app scoped id changes`() {
        val virtualAnchor = DeviceFingerprintHasher.hashVirtualInstanceAnchors(
            mapOf("prop.nemud.player_uuid" to "vm-instance-a"),
        )!!
        val commonSeed = mapOf(
            "version" to DeviceFingerprintHasher.VIRTUAL_ANCHOR_SEED_VERSION.toString(),
            "identityAnchor" to "virtual:$virtualAnchor",
            "virtualInstanceAnchorHash" to virtualAnchor,
            "buildFingerprint" to "mumu/build/fingerprint",
            "device" to "mumu",
        )

        val firstInstallSeed = commonSeed + ("identityAnchor" to "virtual:$virtualAnchor")
        val secondInstallSeed = commonSeed + ("identityAnchor" to "virtual:$virtualAnchor")

        assertEquals(
            DeviceFingerprintHasher.hashFingerprintSeed(firstInstallSeed),
            DeviceFingerprintHasher.hashFingerprintSeed(secondInstallSeed),
        )
        assertNotEquals(
            DeviceFingerprintHasher.hashFingerprintSeed(commonSeed + ("identityAnchor" to "android:first-install")),
            DeviceFingerprintHasher.hashFingerprintSeed(commonSeed + ("identityAnchor" to "android:second-install")),
        )
    }

    @Test
    fun `virtual instance anchor hashing ignores placeholders`() {
        assertNull(
            DeviceFingerprintHasher.hashVirtualInstanceAnchors(
                mapOf(
                    "prop.ro.serialno" to "unknown",
                    "net.eth0" to "02:00:00:00:00:00",
                    "prop.nemud.player_uuid" to "<redacted>",
                ),
            ),
        )
    }

    @Test
    fun `fingerprint versions keep real devices stable while virtual anchors opt in`() {
        assertEquals(2, DeviceFingerprintHasher.BASE_SEED_VERSION)
        assertEquals(3, DeviceFingerprintHasher.VIRTUAL_ANCHOR_SEED_VERSION)
        assertEquals(3, DeviceFingerprintHasher.CACHE_SCHEMA_VERSION)
    }
}
