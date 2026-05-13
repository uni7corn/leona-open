/*
 * Copyright 2026 Leona Contributors.
 * Licensed under the Apache License, Version 2.0.
 */
@file:Suppress("DEPRECATION")

package io.leonasec.leona.internal

import io.leonasec.leona.BoxId
import io.leonasec.leona.LeonaServerVerdict
import io.leonasec.leona.config.LeonaConfig
import io.leonasec.leona.internal.spi.SecureReportingErrorClassifier
import io.leonasec.leona.internal.spi.SecureDeviceContext
import io.leonasec.leona.internal.spi.SecureUploadResult
import okhttp3.CertificatePinner
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okio.ByteString.Companion.toByteString
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.TimeUnit

/**
 * Public-safe hosted upload path used when the closed-source secure reporting
 * engine is not on the runtime classpath. It sends only an opaque native
 * payload plus low-trust evidence metadata; hosted policy and final business
 * decisions remain server-side.
 */
internal class PublicHostedReportingClient(
    private val config: LeonaConfig,
    private val http: OkHttpClient = buildHttpClient(config),
) {
    fun upload(
        endpoint: String,
        apiKey: String,
        sdkVersion: String,
        payload: ByteArray,
        deviceContext: SecureDeviceContext,
    ): SecureUploadResult {
        val body = buildRequestBody(sdkVersion, payload, deviceContext)
        val request = Request.Builder()
            .url(publicSenseUrl(endpoint))
            .post(body.toString().toRequestBody(JSON_MEDIA_TYPE))
            .header("X-Leona-App-Key", apiKey)
            .header("X-Leona-SDK-Version", sdkVersion)
            .header("X-Leona-Reporting-Mode", REPORTING_MODE)
            .build()

        val response = try {
            http.newCall(request).execute()
        } catch (error: IOException) {
            val classification = SecureReportingErrorClassifier.classifyNetworkFailure(error)
            throw SecureReportingErrorClassifier.exception(
                operation = "public hosted reporting",
                classification = classification,
                cause = error,
            )
        }

        response.use {
            if (!response.isSuccessful) {
                val errorBody = response.body?.string()
                    ?.let { sanitizeErrorBody(it, apiKey) }
                    .orEmpty()
                val classification = SecureReportingErrorClassifier.classifyHttpFailure(
                    statusCode = response.code,
                    errorBody = errorBody,
                    headers = response.headers.toMultimap()
                        .mapValues { (_, values) -> values.joinToString(",") },
                )
                throw SecureReportingErrorClassifier.exception(
                    operation = "public hosted reporting",
                    classification = classification,
                    detail = errorBody.takeIf { it.isNotBlank() }?.let { "body=${it.take(512)}" },
                )
            }
            val json = JSONObject(response.body?.string().orEmpty())
            val verdict = parseServerVerdict(json, response)
            val boxId = verdict.boxId
                ?: json.optString("boxId").ifBlank { null }
                ?: throw IOException("public hosted reporting response missing boxId")
            return SecureUploadResult(
                boxId = newBoxId(boxId),
                canonicalDeviceId = verdict.canonicalDeviceId,
                serverVerdict = verdict,
            )
        }
    }

    private fun buildRequestBody(
        sdkVersion: String,
        payload: ByteArray,
        deviceContext: SecureDeviceContext,
    ): JSONObject = JSONObject()
        .put("mode", REPORTING_MODE)
        .put("requestId", UUID.randomUUID().toString())
        .put("sdkVersion", sdkVersion)
        .put("payloadEncoding", "base64")
        .put("payload", payload.toByteString().base64())
        .put("deviceContext", deviceContext.toPublicHostedJson())

    private fun SecureDeviceContext.toPublicHostedJson(): JSONObject = JSONObject()
        .put("installIdSha256", sha256Hex(installId))
        .put("resolvedDeviceIdSha256", sha256Hex(resolvedDeviceId))
        .put("fingerprintHash", fingerprintHash)
        .put("evidenceSignals", JSONArray((evidenceSignals + deviceEnvironmentEvidence.evidenceIds).sorted()))
        .put("deviceEnvironmentEvidence", deviceEnvironmentEvidence.toJsonObject())
        .put("nativeFactTags", JSONArray(nativeFactTags.sorted()))
        .put("nativeFindingIds", JSONArray(nativeFindingIds))
        .put("nativeHighestSeverity", nativeHighestSeverity)
        .put("installerPackage", installerPackage)
        .put("signingCertSha256", JSONArray(signingCertSha256))
        .put("sdkInt", sdkInt)
        .apply {
            canonicalDeviceId
                ?.takeIf { it.isNotBlank() }
                ?.let { put("canonicalDeviceIdSha256", sha256Hex(it)) }
        }

    companion object {
        private const val REPORTING_MODE = "public_hosted"
        private const val PUBLIC_SENSE_PATH = "/v1/sense/public"
        private val JSON_MEDIA_TYPE = "application/json".toMediaType()

        private fun buildHttpClient(config: LeonaConfig): OkHttpClient {
            val builder = OkHttpClient.Builder()
                .callTimeout(10, TimeUnit.SECONDS)
                .connectTimeout(3, TimeUnit.SECONDS)
                .readTimeout(8, TimeUnit.SECONDS)
                .retryOnConnectionFailure(true)
            if (config.certificatePins.isNotEmpty()) {
                val pinner = CertificatePinner.Builder()
                config.certificatePins.forEach { (host, pins) ->
                    pins.forEach { pin -> pinner.add(host, pin) }
                }
                builder.certificatePinner(pinner.build())
            }
            return builder.build()
        }

        private fun publicSenseUrl(endpoint: String): String {
            val normalized = endpoint.trim().trimEnd('/')
            return when {
                normalized.endsWith(PUBLIC_SENSE_PATH) -> normalized
                normalized.endsWith("/v1/sense") -> "$normalized/public"
                normalized.endsWith("/v1") -> "$normalized/sense/public"
                else -> "$normalized$PUBLIC_SENSE_PATH"
            }
        }

        private fun parseServerVerdict(json: JSONObject, response: Response): LeonaServerVerdict {
            val boxId = sequenceOf(
                json.optString("boxId"),
                json.optJSONObject("verdict")?.optString("boxId"),
                response.header("X-Leona-Box-Id"),
            ).mapNotNull(::meaningfulString).firstOrNull()
            val riskTags = buildSet {
                addAll(json.optStringArray("riskTags"))
                addAll(json.optJSONObject("verdict").optStringArray("riskTags"))
                addAll(json.optJSONObject("risk").optStringArray("tags"))
                response.header("X-Leona-Risk-Tags")
                    ?.split(',')
                    ?.mapNotNull(::meaningfulString)
                    ?.let(::addAll)
            }
            return LeonaServerVerdict(
                boxId = boxId,
                canonicalDeviceId = resolveCanonicalDeviceId(json)
                    ?: validCanonicalDeviceId(response.header("X-Leona-Canonical-Device-Id")),
                decision = sequenceOf(
                    json.optString("decision"),
                    json.optJSONObject("verdict")?.optString("decision"),
                    response.header("X-Leona-Decision"),
                ).mapNotNull(::meaningfulString).firstOrNull(),
                action = sequenceOf(
                    json.optString("action"),
                    json.optJSONObject("verdict")?.optString("action"),
                    json.optJSONObject("risk")?.optString("action"),
                    response.header("X-Leona-Action"),
                ).mapNotNull(::meaningfulString).firstOrNull(),
                riskLevel = sequenceOf(
                    json.optString("riskLevel"),
                    json.optJSONObject("verdict")?.optString("riskLevel"),
                    json.optJSONObject("risk")?.optString("level"),
                    response.header("X-Leona-Risk-Level"),
                ).mapNotNull(::meaningfulString).firstOrNull(),
                riskScore = sequenceOf(
                    json.optInt("riskScore", Int.MIN_VALUE).takeUnless { it == Int.MIN_VALUE },
                    json.optJSONObject("verdict")?.optInt("riskScore", Int.MIN_VALUE)
                        ?.takeUnless { it == Int.MIN_VALUE },
                    json.optJSONObject("risk")?.optInt("score", Int.MIN_VALUE)
                        ?.takeUnless { it == Int.MIN_VALUE },
                    response.header("X-Leona-Risk-Score")?.toIntOrNull(),
                ).firstOrNull(),
                riskTags = riskTags,
            )
        }

        private fun resolveCanonicalDeviceId(json: JSONObject): String? =
            sequenceOf(
                json.optString("canonicalDeviceId"),
                json.optJSONObject("verdict")?.optString("canonicalDeviceId"),
                json.optString("serverCanonicalDeviceId"),
                json.optJSONObject("verdict")?.optString("serverCanonicalDeviceId"),
            ).mapNotNull(::validCanonicalDeviceId).firstOrNull()

        private fun JSONObject?.optStringArray(key: String): Set<String> =
            this?.optJSONArray(key)?.let { array ->
                buildSet {
                    for (index in 0 until array.length()) {
                        meaningfulString(array.optString(index))?.let(::add)
                    }
                }
            }.orEmpty()

        private fun meaningfulString(value: String?): String? {
            val trimmed = value?.trim()?.ifEmpty { null } ?: return null
            return trimmed.takeUnless { it.equals("null", ignoreCase = true) }
        }

        private fun validCanonicalDeviceId(value: String?): String? =
            meaningfulString(value)?.takeIf { CANONICAL_DEVICE_ID_PATTERN.matches(it) }

        private fun sanitizeErrorBody(body: String, apiKey: String): String =
            body.replace(apiKey, "<redacted-api-key>")

        private fun sha256Hex(value: String): String =
            MessageDigest.getInstance("SHA-256")
                .digest(value.toByteArray(Charsets.UTF_8))
                .joinToString("") { "%02x".format(it) }

        private fun newBoxId(value: String): BoxId {
            val ctor = BoxId::class.java.getDeclaredConstructor(String::class.java)
            ctor.isAccessible = true
            return ctor.newInstance(value)
        }

        private val CANONICAL_DEVICE_ID_PATTERN = Regex("^L[0-9a-fA-F]{32,64}$")
    }
}
