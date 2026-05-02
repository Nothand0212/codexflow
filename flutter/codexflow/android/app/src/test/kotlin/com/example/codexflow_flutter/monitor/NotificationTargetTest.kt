package com.example.codexflow_flutter.monitor

import org.junit.Assert.assertEquals
import org.junit.Test

class NotificationTargetTest {
    @Test
    fun approvalRouteEncodesDartParseContractFields() {
        val target = NotificationTarget.approval("req-1", "s1")

        assertEquals(
            "{\"target\":\"approvals\",\"approvalId\":\"req-1\",\"sessionId\":\"s1\",\"turnId\":\"\",\"status\":\"\"}",
            target.encode(),
        )
        assertEquals(CodexFlowNotifications.ID_MANUAL, target.requestCode())
    }

    @Test
    fun sessionRouteEncodesDartParseContractFields() {
        val target = NotificationTarget.session("s1", "t1", "completed")

        assertEquals(
            "{\"target\":\"sessionDetail\",\"approvalId\":\"\",\"sessionId\":\"s1\",\"turnId\":\"t1\",\"status\":\"completed\"}",
            target.encode(),
        )
        assertEquals(CodexFlowNotifications.ID_TURN, target.requestCode())
    }

    @Test
    fun dashboardRouteUsesPersistentStatusRequestCode() {
        val target = NotificationTarget.dashboard()

        assertEquals(
            "{\"target\":\"dashboard\",\"approvalId\":\"\",\"sessionId\":\"\",\"turnId\":\"\",\"status\":\"\"}",
            target.encode(),
        )
        assertEquals(CodexFlowNotifications.ID_PERSISTENT, target.requestCode())
    }

    @Test
    fun routeEncodingEscapesJsonStringValues() {
        val target = NotificationTarget.session("s\"1", "t\\1", "done\nnow")

        assertEquals(
            "{\"target\":\"sessionDetail\",\"approvalId\":\"\",\"sessionId\":\"s\\\"1\",\"turnId\":\"t\\\\1\",\"status\":\"done\\nnow\"}",
            target.encode(),
        )
    }
}
