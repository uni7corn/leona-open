/*
 * Copyright 2026 Leona Contributors.
 * Licensed under the Apache License, Version 2.0.
 */
package io.leonasec.leona.sample

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.leonasec.leona.Leona
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import java.io.File

class CloudTestSenseReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) {
            return
        }
        val pendingResult = goAsync()
        Thread {
            val startedAt = System.currentTimeMillis()
            try {
                emit("started", JSONObject().put("sdkVersion", Leona.version))
                val boxId = runBlocking { Leona.sense() }
                val diagnostic = Leona.getDiagnosticSnapshot()
                val payload = JSONObject()
                    .put("boxId", boxId.toString())
                    .put("canonicalDeviceIdHint", SampleJsonRedaction.hint(diagnostic.canonicalDeviceId))
                    .put("canonicalDeviceIdSha256", SampleJsonRedaction.hash(diagnostic.canonicalDeviceId))
                    .put("durationMs", System.currentTimeMillis() - startedAt)
                writeResult(context, payload)
                emit("sense", payload)
            } catch (t: Throwable) {
                val payload = JSONObject()
                    .put("class", t.javaClass.name)
                    .put("message", t.message ?: "")
                    .put("durationMs", System.currentTimeMillis() - startedAt)
                writeResult(context, JSONObject().put("error", payload))
                emit("error", payload)
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    private fun emit(event: String, payload: JSONObject) {
        Log.i(LOG_TAG, JSONObject().put("event", event).put("payload", payload).toString())
    }

    private fun writeResult(context: Context, payload: JSONObject) {
        runCatching {
            val dir = context.getExternalFilesDir(null) ?: context.filesDir
            File(dir, "leona-cloudtest-sense-result.json").writeText(payload.toString(2))
        }
    }

    companion object {
        const val ACTION = "io.leonasec.leona.sample.CLOUD_TEST_SENSE"
        private const val LOG_TAG = "LeonaCloudTest"
    }
}
