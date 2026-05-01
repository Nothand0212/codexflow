package com.example.codexflow_flutter.monitor

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MonitorStateMachineTest {
    private val machine = MonitorStateMachine()

    @Test
    fun baselineEmitsNoAlertsAndRecordsManagedTurnState() {
        val result = machine.evaluate(
            url = "http://100.91.5.116:4318",
            previous = MonitorSnapshot.empty(),
            dashboard = dashboard(
                sessions = listOf(session("s1", "managed", "t1", "inProgress")),
                approvals = listOf(approval("req1", "s1")),
            ),
            nowEpochSeconds = 100,
            forceFreshBaseline = true,
        )

        assertTrue(result.manualActions.isEmpty())
        assertTrue(result.turnResults.isEmpty())
        assertEquals("t1", result.snapshot.urlState("http://100.91.5.116:4318").managedTurnState["s1"]?.lastTurnId)
        assertTrue(result.snapshot.urlState("http://100.91.5.116:4318").seenApprovals.containsKey("req1"))
    }

    @Test
    fun approvalAlertsOnlyForManagedSessionsAndTrustsFilteredApprovals() {
        val previous = machine.evaluate(
            url = URL,
            previous = MonitorSnapshot.empty(),
            dashboard = dashboard(sessions = listOf(session("s1", "managed", "", ""))),
            nowEpochSeconds = 100,
            forceFreshBaseline = true,
        ).snapshot

        val result = machine.evaluate(
            url = URL,
            previous = previous,
            dashboard = dashboard(
                sessions = listOf(
                    session("s1", "managed", "", "", pendingApprovals = 99),
                    session("s2", "history_only", "", ""),
                ),
                approvals = listOf(approval("req-managed", "s1"), approval("req-history", "s2")),
            ),
            nowEpochSeconds = 110,
            forceFreshBaseline = false,
        )

        assertEquals(listOf("req-managed"), result.manualActions.map { it.approvalId })
        assertEquals(1, result.status.pendingManualActionCount)
    }

    @Test
    fun transitionFinalAndManagedTurnResultsBatchTogetherOnce() {
        val previous = machine.evaluate(
            url = URL,
            previous = MonitorSnapshot.empty(),
            dashboard = dashboard(
                sessions = listOf(
                    session("leaving", "managed", "turn-a", "inProgress"),
                    session("staying", "managed", "turn-b", "inProgress"),
                ),
            ),
            nowEpochSeconds = 100,
            forceFreshBaseline = true,
        ).snapshot

        val result = machine.evaluate(
            url = URL,
            previous = previous,
            dashboard = dashboard(
                sessions = listOf(
                    session("leaving", "ended", "turn-a", "completed"),
                    session("staying", "managed", "turn-b", "interrupted"),
                ),
            ),
            nowEpochSeconds = 110,
            forceFreshBaseline = false,
        )

        assertEquals(2, result.turnResults.size)
        assertEquals(setOf("leaving", "staying"), result.turnResults.map { it.sessionId }.toSet())
        assertTrue(result.snapshot.urlState(URL).seenTurnResults.containsKey("leaving:turn-a:completed"))
        assertFalse(result.snapshot.urlState(URL).managedTurnState.containsKey("leaving"))
        assertEquals(setOf("staying"), result.snapshot.urlState(URL).managedTurnState.keys)
    }

    @Test
    fun sessionDisappearingEntirelyDoesNotEmitFinalTurnResult() {
        val previous = machine.evaluate(
            url = URL,
            previous = MonitorSnapshot.empty(),
            dashboard = dashboard(sessions = listOf(session("gone", "managed", "t1", "inProgress"))),
            nowEpochSeconds = 100,
            forceFreshBaseline = true,
        ).snapshot

        val result = machine.evaluate(
            url = URL,
            previous = previous,
            dashboard = dashboard(sessions = emptyList()),
            nowEpochSeconds = 110,
            forceFreshBaseline = false,
        )

        assertTrue(result.turnResults.isEmpty())
        assertFalse(result.snapshot.urlState(URL).managedTurnState.containsKey("gone"))
    }

    @Test
    fun duplicatePollDoesNotRealertAndOldKeysArePruned() {
        val previous = MonitorSnapshot(
            version = 1,
            urls = mapOf(
                URL to UrlMonitorSnapshot(
                    initialized = true,
                    manuallyStopped = false,
                    lastUsedAt = 1,
                    lastSuccessAt = 1,
                    seenApprovals = mapOf("old-approval" to 1),
                    seenTurnResults = mapOf("old-session:old-turn:completed" to 1),
                    managedTurnState = mapOf("s1" to ManagedTurnState("t1", "completed")),
                    lastRunningManagedCount = 1,
                    lastPendingManualActionCount = 0,
                ),
            ),
        )

        val result = machine.evaluate(
            url = URL,
            previous = previous,
            dashboard = dashboard(sessions = listOf(session("s1", "managed", "t1", "completed"))),
            nowEpochSeconds = 8 * 24 * 60 * 60,
            forceFreshBaseline = false,
        )

        assertTrue(result.turnResults.isEmpty())
        assertFalse(result.snapshot.urlState(URL).seenApprovals.containsKey("old-approval"))
        assertFalse(result.snapshot.urlState(URL).seenTurnResults.containsKey("old-session:old-turn:completed"))
    }

    @Test
    fun staleUrlSnapshotsArePrunedAndHostPortComesFromUrl() {
        val staleUrl = "http://stale.example:9999"
        val previous = MonitorSnapshot(
            version = 1,
            urls = mapOf(
                staleUrl to MonitorSnapshot.emptyUrlState().copy(initialized = true, lastUsedAt = 1),
            ),
        )

        val result = machine.evaluate(
            url = URL,
            previous = previous,
            dashboard = dashboard(sessions = emptyList()),
            nowEpochSeconds = 31 * 24 * 60 * 60,
            forceFreshBaseline = false,
        )

        assertFalse(result.snapshot.urls.containsKey(staleUrl))
        assertEquals("100.91.5.116:4318", result.status.hostPort)
    }

    private fun dashboard(
        sessions: List<SessionSnapshot> = emptyList(),
        approvals: List<ApprovalSnapshot> = emptyList(),
    ) = DashboardSnapshot(agentConnected = true, sessions = sessions, approvals = approvals)

    private fun session(
        id: String,
        stage: String,
        turnId: String,
        turnStatus: String,
        pendingApprovals: Int = 0,
    ) = SessionSnapshot(
        id = id,
        displayName = id,
        lifecycleStage = stage,
        lastTurnId = turnId,
        lastTurnStatus = turnStatus,
        pendingApprovals = pendingApprovals,
    )

    private fun approval(id: String, threadId: String) = ApprovalSnapshot(
        id = id,
        threadId = threadId,
        summary = id,
        createdAtEpochSeconds = 1,
    )

    private companion object {
        const val URL = "http://100.91.5.116:4318"
    }
}
