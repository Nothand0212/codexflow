package com.example.codexflow_flutter.monitor

class MonitorStateMachine {
    fun evaluate(
        url: String,
        previous: MonitorSnapshot,
        dashboard: DashboardSnapshot,
        nowEpochSeconds: Long,
        forceFreshBaseline: Boolean,
    ): MonitorDecision {
        val previousUrlState = previous.urlState(url)
        val managedSessions = dashboard.sessions.filter { it.lifecycleStage == MANAGED_STAGE }
        val managedIds = managedSessions.map { it.id }.toSet()
        val sessionsById = dashboard.sessions.associateBy { it.id }
        val filteredApprovals = dashboard.approvals.filter { it.threadId in managedIds }
        val currentManagedTurnState = managedSessions.associate { session ->
            session.id to ManagedTurnState(
                lastTurnId = session.lastTurnId,
                lastTurnStatus = session.lastTurnStatus,
            )
        }

        val baseline = forceFreshBaseline || !previousUrlState.initialized || previousUrlState.manuallyStopped
        val seenApprovals = previousUrlState.seenApprovals.toMutableMap()
        val seenTurnResults = previousUrlState.seenTurnResults.toMutableMap()
        val newManualActions = mutableListOf<ManualActionEvent>()
        val newTurnResults = mutableListOf<TurnResultEvent>()

        pruneSeen(seenApprovals, nowEpochSeconds, SEVEN_DAYS_SECONDS)
        pruneSeen(seenTurnResults, nowEpochSeconds, SEVEN_DAYS_SECONDS)

        if (baseline) {
            filteredApprovals.forEach { approval ->
                seenApprovals[approval.id] = nowEpochSeconds
            }
            managedSessions.forEach { session ->
                val key = turnResultKey(session)
                if (key != null && isTerminal(session.lastTurnStatus)) {
                    seenTurnResults[key] = nowEpochSeconds
                }
            }
        } else {
            collectTransitionFinalResults(
                previousUrlState = previousUrlState,
                managedIds = managedIds,
                sessionsById = sessionsById,
                seenTurnResults = seenTurnResults,
                nowEpochSeconds = nowEpochSeconds,
                destination = newTurnResults,
            )
            collectManualActions(
                approvals = filteredApprovals,
                sessionsById = sessionsById,
                seenApprovals = seenApprovals,
                nowEpochSeconds = nowEpochSeconds,
                destination = newManualActions,
            )
            collectCurrentManagedTurnResults(
                previousUrlState = previousUrlState,
                managedSessions = managedSessions,
                seenTurnResults = seenTurnResults,
                nowEpochSeconds = nowEpochSeconds,
                destination = newTurnResults,
            )
        }

        val nextUrlState = UrlMonitorSnapshot(
            initialized = true,
            manuallyStopped = false,
            lastUsedAt = nowEpochSeconds,
            lastSuccessAt = nowEpochSeconds,
            seenApprovals = seenApprovals.toMap(),
            seenTurnResults = seenTurnResults.toMap(),
            managedTurnState = currentManagedTurnState,
            lastRunningManagedCount = managedSessions.size,
            lastPendingManualActionCount = filteredApprovals.size,
        )
        val prunedUrls = previous.urls.filterValues { urlState ->
            nowEpochSeconds - urlState.lastUsedAt <= THIRTY_DAYS_SECONDS
        }.toMutableMap()
        prunedUrls[url] = nextUrlState

        return MonitorDecision(
            snapshot = MonitorSnapshot(version = 1, urls = prunedUrls),
            status = MonitorStatus(
                online = dashboard.agentConnected,
                runningManagedCount = managedSessions.size,
                runningTurnCount = managedSessions.count { it.lastTurnStatus == IN_PROGRESS_STATUS },
                pendingManualActionCount = filteredApprovals.size,
                hostPort = MonitorStatusFactory.hostPort(url),
                runningSessionLabels = managedSessions
                    .filter { it.lastTurnStatus == IN_PROGRESS_STATUS }
                    .map { it.displayName }
                    .take(MAX_RUNNING_LABELS),
                lastCheckedEpochSeconds = nowEpochSeconds,
                lastSuccessEpochSeconds = nowEpochSeconds,
            ),
            manualActions = newManualActions,
            turnResults = newTurnResults,
        )
    }

    private fun collectTransitionFinalResults(
        previousUrlState: UrlMonitorSnapshot,
        managedIds: Set<String>,
        sessionsById: Map<String, SessionSnapshot>,
        seenTurnResults: MutableMap<String, Long>,
        nowEpochSeconds: Long,
        destination: MutableList<TurnResultEvent>,
    ) {
        val leavingManagedIds = previousUrlState.managedTurnState.keys - managedIds
        for (sessionId in leavingManagedIds) {
            val session = sessionsById[sessionId] ?: continue
            if (!isTerminal(session.lastTurnStatus)) continue
            addTurnResultOnce(session, seenTurnResults, nowEpochSeconds, destination)
        }
    }

    private fun collectManualActions(
        approvals: List<ApprovalSnapshot>,
        sessionsById: Map<String, SessionSnapshot>,
        seenApprovals: MutableMap<String, Long>,
        nowEpochSeconds: Long,
        destination: MutableList<ManualActionEvent>,
    ) {
        for (approval in approvals) {
            if (seenApprovals.containsKey(approval.id)) continue
            seenApprovals[approval.id] = nowEpochSeconds
            val session = sessionsById[approval.threadId]
            destination += ManualActionEvent(
                approvalId = approval.id,
                sessionId = approval.threadId,
                sessionLabel = session?.displayName ?: shortId(approval.threadId),
                summary = approval.summary,
            )
        }
    }

    private fun collectCurrentManagedTurnResults(
        previousUrlState: UrlMonitorSnapshot,
        managedSessions: List<SessionSnapshot>,
        seenTurnResults: MutableMap<String, Long>,
        nowEpochSeconds: Long,
        destination: MutableList<TurnResultEvent>,
    ) {
        for (session in managedSessions) {
            if (!isTerminal(session.lastTurnStatus)) continue
            if (previousUrlState.managedTurnState[session.id] == ManagedTurnState(session.lastTurnId, session.lastTurnStatus)) {
                continue
            }
            addTurnResultOnce(session, seenTurnResults, nowEpochSeconds, destination)
        }
    }

    private fun addTurnResultOnce(
        session: SessionSnapshot,
        seenTurnResults: MutableMap<String, Long>,
        nowEpochSeconds: Long,
        destination: MutableList<TurnResultEvent>,
    ) {
        val key = turnResultKey(session) ?: return
        if (seenTurnResults.containsKey(key)) return
        seenTurnResults[key] = nowEpochSeconds
        destination += TurnResultEvent(
            sessionId = session.id,
            sessionLabel = session.displayName,
            turnId = session.lastTurnId,
            status = session.lastTurnStatus,
        )
    }

    private fun turnResultKey(session: SessionSnapshot): String? {
        if (session.id.isBlank() || session.lastTurnId.isBlank() || session.lastTurnStatus.isBlank()) {
            return null
        }
        return "${session.id}:${session.lastTurnId}:${session.lastTurnStatus}"
    }

    private fun isTerminal(status: String): Boolean = status == "completed" || status == "interrupted"

    private fun pruneSeen(values: MutableMap<String, Long>, now: Long, maxAgeSeconds: Long) {
        values.entries.removeIf { now - it.value > maxAgeSeconds }
    }

    private fun shortId(value: String): String = if (value.length <= 8) value else value.substring(0, 8)

    private companion object {
        const val MANAGED_STAGE = "managed"
        const val IN_PROGRESS_STATUS = "inProgress"
        const val MAX_RUNNING_LABELS = 3
        const val SEVEN_DAYS_SECONDS = 7L * 24L * 60L * 60L
        const val THIRTY_DAYS_SECONDS = 30L * 24L * 60L * 60L
    }
}
