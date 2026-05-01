package com.example.codexflow_flutter.monitor

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MonitorStatusFactoryTest {
    @Test
    fun cachedReturnsNullWhenNoInitializedSnapshotExists() {
        val status = MonitorStatusFactory.cached(
            url = URL,
            snapshot = MonitorSnapshot.empty(),
            nowEpochSeconds = 200,
        )

        assertNull(status)
    }

    @Test
    fun cachedUsesPersistedCountsAndTurnStateInsteadOfStartingPlaceholder() {
        val snapshot = MonitorSnapshot(
            version = 1,
            urls = mapOf(
                URL to UrlMonitorSnapshot(
                    initialized = true,
                    manuallyStopped = false,
                    lastUsedAt = 100,
                    lastSuccessAt = 90,
                    seenApprovals = emptyMap(),
                    seenTurnResults = emptyMap(),
                    managedTurnState = mapOf(
                        "running" to ManagedTurnState("t1", "inProgress"),
                        "completed" to ManagedTurnState("t2", "completed"),
                    ),
                    lastRunningManagedCount = 2,
                    lastPendingManualActionCount = 1,
                ),
            ),
        )

        val status = MonitorStatusFactory.cached(
            url = URL,
            snapshot = snapshot,
            nowEpochSeconds = 200,
        )

        requireNotNull(status)
        assertEquals(false, status.online)
        assertEquals("100.91.5.116:4318", status.hostPort)
        assertEquals(2, status.runningManagedCount)
        assertEquals(1, status.runningTurnCount)
        assertEquals(1, status.pendingManualActionCount)
        assertEquals(200L, status.lastCheckedEpochSeconds)
        assertEquals(90L, status.lastSuccessEpochSeconds)
    }

    @Test
    fun offlinePreservesPriorCountsAndLastSuccess() {
        val status = MonitorStatusFactory.offline(
            url = URL,
            prior = MonitorStatus(
                online = true,
                runningManagedCount = 3,
                runningTurnCount = 2,
                pendingManualActionCount = 1,
                hostPort = "old",
                runningSessionLabels = listOf("codexflow_ws"),
                lastCheckedEpochSeconds = 100,
                lastSuccessEpochSeconds = 95,
            ),
            nowEpochSeconds = 200,
        )

        assertEquals(false, status.online)
        assertEquals("100.91.5.116:4318", status.hostPort)
        assertEquals(3, status.runningManagedCount)
        assertEquals(2, status.runningTurnCount)
        assertEquals(1, status.pendingManualActionCount)
        assertEquals(listOf("codexflow_ws"), status.runningSessionLabels)
        assertEquals(200L, status.lastCheckedEpochSeconds)
        assertEquals(95L, status.lastSuccessEpochSeconds)
    }

    private companion object {
        const val URL = "http://100.91.5.116:4318"
    }
}
