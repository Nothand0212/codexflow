package com.example.codexflow_flutter.monitor

import java.net.URI

object MonitorStatusFactory {
    fun cached(url: String, snapshot: MonitorSnapshot, nowEpochSeconds: Long): MonitorStatus? {
        val state = snapshot.urlState(url)
        if (!state.initialized || state.manuallyStopped) {
            return null
        }
        return MonitorStatus(
            online = false,
            runningManagedCount = state.lastRunningManagedCount,
            runningTurnCount = state.managedTurnState.values.count { it.lastTurnStatus == IN_PROGRESS_STATUS },
            pendingManualActionCount = state.lastPendingManualActionCount,
            hostPort = hostPort(url),
            lastCheckedEpochSeconds = nowEpochSeconds,
            lastSuccessEpochSeconds = state.lastSuccessAt,
        )
    }

    fun offline(url: String, prior: MonitorStatus?, nowEpochSeconds: Long): MonitorStatus {
        return MonitorStatus(
            online = false,
            runningManagedCount = prior?.runningManagedCount ?: 0,
            runningTurnCount = prior?.runningTurnCount ?: 0,
            pendingManualActionCount = prior?.pendingManualActionCount ?: 0,
            hostPort = hostPort(url),
            runningSessionLabels = prior?.runningSessionLabels ?: emptyList(),
            lastCheckedEpochSeconds = nowEpochSeconds,
            lastSuccessEpochSeconds = prior?.lastSuccessEpochSeconds ?: 0,
        )
    }

    fun hostPort(url: String): String {
        return runCatching {
            val uri = URI(url)
            if (uri.port > 0) "${uri.host}:${uri.port}" else uri.host.orEmpty()
        }.getOrDefault(url)
    }

    private const val IN_PROGRESS_STATUS = "inProgress"
}
