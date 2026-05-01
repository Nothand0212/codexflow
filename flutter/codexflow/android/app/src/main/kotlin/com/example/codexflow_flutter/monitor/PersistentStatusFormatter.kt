package com.example.codexflow_flutter.monitor

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class PersistentStatusContent(
    val title: String,
    val text: String,
    val expandedText: String,
    val subText: String?,
    val notificationTimeMillis: Long?,
)

object PersistentStatusFormatter {
    fun format(status: MonitorStatus?): PersistentStatusContent {
        if (status == null) {
            return PersistentStatusContent(
                title = "CodexFlow starting",
                text = "Connecting to agent · Tap to open",
                expandedText = listOf(
                    "Agent: starting",
                    "Host: loading saved address",
                    "Status: waiting for first dashboard poll",
                    "Tap to open dashboard",
                ).joinToString("\n"),
                subText = null,
                notificationTimeMillis = null,
            )
        }

        val title = if (status.online) {
            "● CodexFlow online"
        } else {
            "○ CodexFlow offline"
        }
        val host = status.hostPort.ifBlank { "unknown host" }
        val text = listOf(
            "🌐 $host",
            "🗂 ${status.runningManagedCount}",
            "▶ ${status.runningTurnCount}",
            "⚠ ${status.pendingManualActionCount}",
        ).joinToString(" · ")

        val runningLine = if (status.runningSessionLabels.isEmpty()) {
            "Running sessions: none"
        } else {
            "Running sessions: ${status.runningSessionLabels.joinToString(", ")}"
        }
        val expandedLines = mutableListOf(
            "Agent: ${if (status.online) "online" else "offline"}",
            "Host: $host",
            "Managed sessions: ${status.runningManagedCount}",
            "Running turns: ${status.runningTurnCount}",
            "Pending manual actions: ${status.pendingManualActionCount}",
            runningLine,
            "Last checked: ${formatClock(status.lastCheckedEpochSeconds)}",
        )
        if (!status.online && status.lastSuccessEpochSeconds > 0) {
            expandedLines += "Last online: ${formatClock(status.lastSuccessEpochSeconds)}"
        }
        expandedLines += "Tap to open dashboard"

        val notificationTimeMillis = status.lastCheckedEpochSeconds
            .takeIf { it > 0 }
            ?.let { it * 1000L }
        return PersistentStatusContent(
            title = title,
            text = text,
            expandedText = expandedLines.joinToString("\n"),
            subText = status.hostPort.takeIf { it.isNotBlank() },
            notificationTimeMillis = notificationTimeMillis,
        )
    }

    private fun formatClock(epochSeconds: Long): String {
        if (epochSeconds <= 0) {
            return "pending"
        }
        return SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date(epochSeconds * 1000L))
    }

}
