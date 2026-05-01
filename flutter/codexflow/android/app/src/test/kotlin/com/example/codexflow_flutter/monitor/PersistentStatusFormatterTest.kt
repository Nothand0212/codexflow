package com.example.codexflow_flutter.monitor

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.TimeZone

class PersistentStatusFormatterTest {
    @Test
    fun startingStatusShowsActionableLoadingContent() {
        val content = PersistentStatusFormatter.format(null)

        assertEquals("CodexFlow starting", content.title)
        assertEquals("Connecting to agent · Tap to open", content.text)
        assertTrue(content.expandedText.contains("Host: loading saved address"))
        assertTrue(content.expandedText.contains("Tap to open dashboard"))
    }

    @Test
    fun onlineStatusIncludesHostCountsRunningLabelsAndLastCheck() {
        withUtcTimeZone {
            val content = PersistentStatusFormatter.format(
                MonitorStatus(
                    online = true,
                    runningManagedCount = 3,
                    runningTurnCount = 2,
                    pendingManualActionCount = 1,
                    hostPort = "100.91.5.116:4318",
                    runningSessionLabels = listOf("codexflow_ws", "phad_slam"),
                    lastCheckedEpochSeconds = 100,
                    lastSuccessEpochSeconds = 100,
                ),
            )

            assertEquals("● CodexFlow online", content.title)
            assertEquals("🌐 100.91.5.116:4318 · 🗂 3 · ▶ 2 · ⚠ 1", content.text)
            assertTrue(content.expandedText.contains("Agent: online"))
            assertTrue(content.expandedText.contains("Host: 100.91.5.116:4318"))
            assertTrue(content.expandedText.contains("Managed sessions: 3"))
            assertTrue(content.expandedText.contains("Running turns: 2"))
            assertTrue(content.expandedText.contains("Pending manual actions: 1"))
            assertTrue(content.expandedText.contains("Running sessions: codexflow_ws, phad_slam"))
            assertTrue(content.expandedText.contains("Last checked: 00:01:40"))
            assertEquals(100_000L, content.notificationTimeMillis)
        }
    }

    @Test
    fun offlineStatusIncludesLastOnlineWhenKnown() {
        withUtcTimeZone {
            val content = PersistentStatusFormatter.format(
                MonitorStatus(
                    online = false,
                    runningManagedCount = 1,
                    runningTurnCount = 1,
                    pendingManualActionCount = 0,
                    hostPort = "100.91.5.116:4318",
                    runningSessionLabels = listOf("codexflow_ws"),
                    lastCheckedEpochSeconds = 200,
                    lastSuccessEpochSeconds = 100,
                ),
            )

            assertEquals("○ CodexFlow offline", content.title)
            assertTrue(content.expandedText.contains("Last checked: 00:03:20"))
            assertTrue(content.expandedText.contains("Last online: 00:01:40"))
        }
    }

    private fun withUtcTimeZone(block: () -> Unit) {
        val original = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
            block()
        } finally {
            TimeZone.setDefault(original)
        }
    }
}
