/*
 * Copyright 2026 Leona Contributors.
 * Licensed under the Apache License, Version 2.0.
 */
package io.leonasec.leona.internal

internal object ClientEvidenceSignalMapper {
    fun toEvidenceSignal(signal: String): String =
        when (signal) {
            "root.basic" -> "root.su_or_busybox_path_present"
            "root.packages" -> "root.manager_package_present"
            "environment.emulator" -> "environment.emulator.local_heuristic"
            "environment.virtual_container" -> "environment.virtual_container.package_present"
            "installer.untrusted" -> "installer.not_allowlisted"
            "signature.untrusted" -> "signature.not_allowlisted"
            else -> signal
        }

    fun toEvidenceSignals(signals: Set<String>): Set<String> =
        signals.mapTo(linkedSetOf(), ::toEvidenceSignal)
}
