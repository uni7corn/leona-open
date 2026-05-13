/*
 * Copyright 2026 Leona Contributors.
 * Licensed under the Apache License, Version 2.0.
 */
package io.leonasec.leona.internal.spi

import java.io.IOException
import java.io.InterruptedIOException
import java.net.SocketTimeoutException

enum class SecureReportingErrorCode(val wireValue: String, val retryableByDefault: Boolean) {
    TIMESTAMP_SKEW("timestamp_skew", true),
    NETWORK_TIMEOUT("network_timeout", true),
    AUTH_FAILED("auth_failed", false),
    SERVER_5XX("server_5xx", true),
    UNKNOWN("unknown", false),
}

data class SecureReportingErrorClassification(
    val code: SecureReportingErrorCode,
    val httpStatus: Int? = null,
    val retryable: Boolean = code.retryableByDefault,
)

class SecureReportingException(
    val classification: SecureReportingErrorClassification,
    message: String,
    cause: Throwable? = null,
) : IOException(message, cause) {
    val code: SecureReportingErrorCode = classification.code
}

object SecureReportingErrorClassifier {
    fun classifyHttpFailure(
        statusCode: Int,
        errorBody: String?,
        headers: Map<String, String> = emptyMap(),
    ): SecureReportingErrorClassification {
        val diagnosticText = buildString {
            append(errorBody.orEmpty())
            headers.forEach { (name, value) ->
                append('\n')
                append(name)
                append(':')
                append(value)
            }
        }
        val code = when {
            hasTimestampSkewMarker(diagnosticText) -> SecureReportingErrorCode.TIMESTAMP_SKEW
            statusCode == 401 || statusCode == 403 -> SecureReportingErrorCode.AUTH_FAILED
            statusCode in 500..599 -> SecureReportingErrorCode.SERVER_5XX
            else -> SecureReportingErrorCode.UNKNOWN
        }
        return SecureReportingErrorClassification(
            code = code,
            httpStatus = statusCode,
        )
    }

    fun classifyNetworkFailure(error: IOException): SecureReportingErrorClassification {
        val code = when (error) {
            is SocketTimeoutException -> SecureReportingErrorCode.NETWORK_TIMEOUT
            is InterruptedIOException -> SecureReportingErrorCode.NETWORK_TIMEOUT
            else -> SecureReportingErrorCode.UNKNOWN
        }
        return SecureReportingErrorClassification(code = code)
    }

    fun exception(
        operation: String,
        classification: SecureReportingErrorClassification,
        detail: String? = null,
        cause: Throwable? = null,
    ): SecureReportingException {
        val message = buildString {
            append(operation)
            append(" failed: diagnostic=")
            append(classification.code.wireValue)
            classification.httpStatus?.let {
                append(", httpStatus=")
                append(it)
            }
            append(", retryable=")
            append(classification.retryable)
            detail
                ?.takeIf { it.isNotBlank() }
                ?.let {
                    append(", ")
                    append(it.take(512))
                }
        }
        return SecureReportingException(classification, message, cause)
    }

    private fun hasTimestampSkewMarker(text: String): Boolean {
        val normalized = text.lowercase()
        return "leona_timestamp_skew" in normalized ||
            "timestamp_skew" in normalized ||
            "request timestamp outside acceptable window" in normalized ||
            "outside acceptable window" in normalized ||
            "clock skew" in normalized
    }
}
