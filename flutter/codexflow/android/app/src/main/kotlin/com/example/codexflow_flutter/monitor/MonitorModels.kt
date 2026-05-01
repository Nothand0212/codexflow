package com.example.codexflow_flutter.monitor

data class DashboardSnapshot(
    val agentConnected: Boolean,
    val sessions: List<SessionSnapshot>,
    val approvals: List<ApprovalSnapshot>,
)

data class SessionSnapshot(
    val id: String,
    val displayName: String,
    val lifecycleStage: String,
    val lastTurnId: String,
    val lastTurnStatus: String,
    val pendingApprovals: Int = 0,
)

data class ApprovalSnapshot(
    val id: String,
    val threadId: String,
    val summary: String,
    val createdAtEpochSeconds: Long,
)

data class ManagedTurnState(
    val lastTurnId: String,
    val lastTurnStatus: String,
)

data class UrlMonitorSnapshot(
    val initialized: Boolean,
    val manuallyStopped: Boolean,
    val lastUsedAt: Long,
    val lastSuccessAt: Long,
    val seenApprovals: Map<String, Long>,
    val seenTurnResults: Map<String, Long>,
    val managedTurnState: Map<String, ManagedTurnState>,
    val lastRunningManagedCount: Int,
    val lastPendingManualActionCount: Int,
)

data class MonitorSnapshot(
    val version: Int,
    val urls: Map<String, UrlMonitorSnapshot>,
) {
    fun urlState(url: String): UrlMonitorSnapshot = urls[url] ?: emptyUrlState()

    companion object {
        fun empty(): MonitorSnapshot = MonitorSnapshot(version = 1, urls = emptyMap())

        fun emptyUrlState(): UrlMonitorSnapshot = UrlMonitorSnapshot(
            initialized = false,
            manuallyStopped = false,
            lastUsedAt = 0,
            lastSuccessAt = 0,
            seenApprovals = emptyMap(),
            seenTurnResults = emptyMap(),
            managedTurnState = emptyMap(),
            lastRunningManagedCount = 0,
            lastPendingManualActionCount = 0,
        )
    }
}

data class ManualActionEvent(
    val approvalId: String,
    val sessionId: String,
    val sessionLabel: String,
    val summary: String,
)

data class TurnResultEvent(
    val sessionId: String,
    val sessionLabel: String,
    val turnId: String,
    val status: String,
)

data class MonitorStatus(
    val online: Boolean,
    val runningManagedCount: Int,
    val runningTurnCount: Int,
    val pendingManualActionCount: Int,
    val hostPort: String,
    val runningSessionLabels: List<String> = emptyList(),
    val lastCheckedEpochSeconds: Long = 0,
    val lastSuccessEpochSeconds: Long = 0,
)

data class MonitorDecision(
    val snapshot: MonitorSnapshot,
    val status: MonitorStatus,
    val manualActions: List<ManualActionEvent>,
    val turnResults: List<TurnResultEvent>,
)
