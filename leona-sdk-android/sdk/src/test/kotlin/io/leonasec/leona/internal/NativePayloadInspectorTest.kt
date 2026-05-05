/*
 * Copyright 2026 Leona Contributors.
 * Licensed under the Apache License, Version 2.0.
 */
@file:Suppress("DEPRECATION")

package io.leonasec.leona.internal

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativePayloadInspectorTest {

    @Test
    fun `inspect decodes native findings and maps stable risk tags`() {
        val payload = buildPayload(
            Event(
                id = "injection.frida.known_library",
                severity = 3,
                category = 1,
                message = "frida gadget",
                evidence = "path=/data/local/tmp/frida",
            ),
            Event(
                id = "tamper.signature.untrusted",
                severity = 4,
                category = 4,
                message = "signature mismatch",
                evidence = "actual=abc",
            ),
            Event(
                id = "unidbg.parent.non_zygote",
                severity = 3,
                category = 3,
                message = "java parent",
                evidence = "parent=java",
            ),
            Event(
                id = "env.emulator.fs.virtio_9p_shared_mount",
                severity = 3,
                category = 2,
                message = "virtio 9p shared mount",
                evidence = "path=/proc/mounts",
            ),
        )

        val summary = NativePayloadInspector.inspect(payload)

        assertEquals(4, summary.eventCount)
        assertEquals(4, summary.highestSeverity)
        assertEquals(
            listOf(
                "injection.frida.known_library",
                "tamper.signature.untrusted",
                "unidbg.parent.non_zygote",
                "env.emulator.fs.virtio_9p_shared_mount",
            ),
            summary.findingIds,
        )
        assertTrue("expected frida tag", "hook.frida.native" in summary.riskTags)
        assertTrue("expected tamper tag", "tamper.native" in summary.riskTags)
        assertTrue("expected signature tag", "signature.untrusted.native" in summary.riskTags)
        assertTrue("expected unidbg tag", "environment.unidbg.native" in summary.riskTags)
        assertTrue("expected emulator tag", "environment.emulator.native" in summary.riskTags)
        assertTrue("expected frida fact", "runtime.frida.evidence" in summary.factTags)
        assertTrue("expected tamper fact", "app.integrity.evidence" in summary.factTags)
        assertTrue("expected emulator fact", "environment.emulator.evidence" in summary.factTags)
    }

    @Test
    fun `inspect returns empty summary for malformed payload`() {
        val summary = NativePayloadInspector.inspect("not-a-leona-payload".toByteArray())
        assertEquals(0, summary.eventCount)
        assertTrue(summary.riskTags.isEmpty())
        assertTrue(summary.factTags.isEmpty())
    }

    @Test
    fun `runtime mapping facts do not become hook or injection risk tags`() {
        val payload = buildPayload(
            Event(
                id = "runtime.mapping.memfd_executable",
                severity = 2,
                category = 0,
                message = "Executable memfd mapping is present",
                evidence = "path=/memfd:payload",
            ),
        )

        val summary = NativePayloadInspector.inspect(payload)

        assertEquals(1, summary.eventCount)
        assertEquals(listOf("runtime.mapping.memfd_executable"), summary.findingIds)
        assertEquals(setOf("runtime.mapping.memfd_executable"), summary.factTags)
        assertTrue("runtime facts should not imply hook risk", "hook.injection.native" !in summary.riskTags)
        assertTrue("runtime facts should not imply frida risk", "hook.frida.native" !in summary.riskTags)
    }

    @Test
    fun `rom build bootloader native facts remain neutral risk telemetry`() {
        val payload = buildPayload(
            Event(
                id = "rom.custom_aosp_like",
                severity = 3,
                category = 2,
                message = "custom ROM evidence",
                evidence = "family=lineage",
            ),
            Event(
                id = "gsi.running",
                severity = 3,
                category = 2,
                message = "GSI evidence",
                evidence = "imageRunning=true",
            ),
            Event(
                id = "bootloader.unlocked",
                severity = 3,
                category = 2,
                message = "bootloader state",
                evidence = "flashLocked=0",
            ),
            Event(
                id = "verified_boot.orange",
                severity = 3,
                category = 2,
                message = "verified boot state",
                evidence = "state=orange",
            ),
            Event(
                id = "vbmeta.unlocked",
                severity = 3,
                category = 2,
                message = "vbmeta state",
                evidence = "deviceState=unlocked",
            ),
            Event(
                id = "build.tags.test_keys",
                severity = 3,
                category = 2,
                message = "build tags",
                evidence = "tags=test-keys",
            ),
            Event(
                id = "build.type.userdebug_or_eng",
                severity = 3,
                category = 2,
                message = "build type",
                evidence = "type=userdebug",
            ),
        )

        val summary = NativePayloadInspector.inspect(payload)

        assertEquals(7, summary.eventCount)
        assertEquals(
            listOf(
                "rom.custom_aosp_like",
                "gsi.running",
                "bootloader.unlocked",
                "verified_boot.orange",
                "vbmeta.unlocked",
                "build.tags.test_keys",
                "build.type.userdebug_or_eng",
            ),
            summary.findingIds,
        )
        assertEquals(summary.findingIds.toSet(), summary.factTags)

        val forbidden = setOf(
            "environment.emulator.native",
            "environment.unidbg.native",
            "root.native",
            "hook.frida.native",
            "hook.injection.native",
            "hook.xposed.native",
            "tamper.native",
            "signature.untrusted.native",
            "installer.untrusted.native",
            "app.debuggable.native",
        )
        assertTrue(
            "ROM facts should not imply risk tags: ${summary.riskTags}",
            summary.riskTags.intersect(forbidden).isEmpty(),
        )
        assertFalse("ROM facts should not create risk.* tags", summary.riskTags.any { it.startsWith("risk.") })
        assertFalse(
            "ROM facts should not create critical/block tags",
            summary.riskTags.any {
                it.contains("critical", ignoreCase = true) || it.contains("block", ignoreCase = true)
            },
        )
    }

    @Test
    fun `inspect advances offsets by utf8 byte length`() {
        val payload = buildPayload(
            Event(
                id = "environment.emulator.detected",
                severity = 3,
                category = 2,
                message = "检测到模拟器环境",
                evidence = "说明=包含非 ASCII 文本",
            ),
            Event(
                id = "injection.frida.known_library",
                severity = 3,
                category = 1,
                message = "frida agent",
                evidence = "path=/memfd:frida-agent-64.so (deleted)",
            ),
        )

        val summary = NativePayloadInspector.inspect(payload)

        assertEquals(
            listOf(
                "environment.emulator.detected",
                "injection.frida.known_library",
            ),
            summary.findingIds,
        )
        assertTrue("expected frida tag", "hook.frida.native" in summary.riskTags)
    }

    @Test
    fun `mumu guest metadata upload fixture redacts player uuid evidence`() {
        val rawPlayerUuid = "8f56b1f4-8d99-4a47-b13a-611d0f337eaa"
        val payload = buildPayload(
            Event(
                id = "env.emulator.runtime.guest_metadata_props",
                severity = 3,
                category = 2,
                message = "Guest-visible metadata exposes emulator host integration",
                evidence = listOf(
                    "nemud.player_package=com.netease.mumu",
                    "nemud.player_engine=MuMuPlayer",
                    "nemud.player_uuid=<redacted>",
                    "metadataPropCount=3",
                ).joinToString(";"),
            ),
        )

        val parsed = parsePayload(payload).single()
        assertEquals("env.emulator.runtime.guest_metadata_props", parsed.id)
        assertFalse(
            "uploaded native evidence must not include raw MuMu player UUID",
            parsed.evidence.contains(rawPlayerUuid),
        )
        assertTrue(
            "uploaded native evidence should keep only a redacted marker or digest",
            parsed.evidence.contains("nemud.player_uuid=<redacted>") ||
                Regex("""nemud\.player_uuid_sha256=[0-9a-f]{64}""").containsMatchIn(parsed.evidence),
        )

        val summary = NativePayloadInspector.inspect(payload)
        assertEquals(listOf("env.emulator.runtime.guest_metadata_props"), summary.findingIds)
        assertTrue("expected emulator fact", "environment.emulator.evidence" in summary.factTags)
        assertFalse(
            "parsed native findings must not expose raw MuMu player UUID",
            summary.findings.joinToString().contains(rawPlayerUuid),
        )
    }

    private data class Event(
        val id: String,
        val severity: Int,
        val category: Int,
        val message: String,
        val evidence: String,
    )

    private data class ParsedEvent(
        val id: String,
        val severity: Int,
        val category: Int,
        val message: String,
        val evidence: String,
    )

    private fun buildPayload(vararg events: Event): ByteArray {
        val raw = ArrayList<Byte>()
        raw += listOf('L'.code.toByte(), 'N'.code.toByte(), 'A'.code.toByte(), '1'.code.toByte())
        raw += 0x01.toByte()
        raw += 0x00.toByte()
        raw.writeU16(events.size)
        events.forEach { event ->
            raw.writeString(event.id)
            raw += event.severity.toByte()
            raw += event.category.toByte()
            raw.writeString(event.message)
            raw.writeString(event.evidence)
        }
        return scramble(raw.toByteArray())
    }

    private fun parsePayload(payload: ByteArray): List<ParsedEvent> {
        val decoded = scramble(payload.copyOf())
        assertEquals('L'.code.toByte(), decoded[0])
        assertEquals('N'.code.toByte(), decoded[1])
        assertEquals('A'.code.toByte(), decoded[2])
        assertEquals('1'.code.toByte(), decoded[3])
        assertEquals(0x01.toByte(), decoded[4])

        var offset = 8
        return buildList {
            repeat(decoded.u16(6)) {
                val id = decoded.readString(offset)
                offset = id.nextOffset
                val severity = decoded.u8(offset)
                offset += 1
                val category = decoded.u8(offset)
                offset += 1
                val message = decoded.readString(offset)
                offset = message.nextOffset
                val evidence = decoded.readString(offset)
                offset = evidence.nextOffset
                add(
                    ParsedEvent(
                        id = id.value,
                        severity = severity,
                        category = category,
                        message = message.value,
                        evidence = evidence.value,
                    ),
                )
            }
        }
    }

    private fun ArrayList<Byte>.writeU16(value: Int) {
        add((value and 0xFF).toByte())
        add(((value shr 8) and 0xFF).toByte())
    }

    private fun ArrayList<Byte>.writeString(value: String) {
        val bytes = value.toByteArray(Charsets.UTF_8)
        writeU16(bytes.size)
        bytes.forEach(::add)
    }

    private fun scramble(bytes: ByteArray): ByteArray {
        var k = 0x5C
        for (i in bytes.indices) {
            bytes[i] = (bytes[i].toInt() xor k).toByte()
            k = (k * 31 + 17) and 0xFF
        }
        return bytes
    }

    private data class ParsedString(
        val value: String,
        val nextOffset: Int,
    )

    private fun ByteArray.u8(offset: Int): Int =
        getOrNull(offset)?.toInt()?.and(0xFF)
            ?: error("Invalid payload offset=$offset")

    private fun ByteArray.u16(offset: Int): Int {
        val b0 = u8(offset)
        val b1 = u8(offset + 1)
        return b0 or (b1 shl 8)
    }

    private fun ByteArray.readString(offset: Int): ParsedString {
        val len = u16(offset)
        val start = offset + 2
        val end = start + len
        if (end > size) error("Malformed payload string")
        return ParsedString(
            value = decodeToString(start, end),
            nextOffset = end,
        )
    }
}
