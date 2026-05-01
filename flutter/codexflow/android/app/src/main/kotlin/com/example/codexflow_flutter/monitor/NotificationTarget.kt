package com.example.codexflow_flutter.monitor

import org.json.JSONObject

data class NotificationTarget(
    val target: String,
    val approvalId: String = "",
    val sessionId: String = "",
    val turnId: String = "",
    val status: String = "",
) {
    fun encode(): String {
        return JSONObject()
            .put("target", target)
            .put("approvalId", approvalId)
            .put("sessionId", sessionId)
            .put("turnId", turnId)
            .put("status", status)
            .toString()
    }

    fun requestCode(): Int {
        return when (target) {
            "approvals" -> CodexFlowNotifications.ID_MANUAL
            "sessionDetail" -> CodexFlowNotifications.ID_TURN
            else -> CodexFlowNotifications.ID_PERSISTENT
        }
    }

    companion object {
        fun dashboard() = NotificationTarget(target = "dashboard")

        fun approvals() = NotificationTarget(target = "approvals")

        fun approval(approvalId: String, sessionId: String) = NotificationTarget(
            target = "approvals",
            approvalId = approvalId,
            sessionId = sessionId,
        )

        fun session(sessionId: String, turnId: String, status: String) = NotificationTarget(
            target = "sessionDetail",
            sessionId = sessionId,
            turnId = turnId,
            status = status,
        )
    }
}
