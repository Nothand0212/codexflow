package com.example.codexflow_flutter.monitor

data class NotificationTarget(
    val target: String,
    val approvalId: String = "",
    val sessionId: String = "",
    val turnId: String = "",
    val status: String = "",
) {
    fun encode(): String {
        return buildString {
            append("{")
            appendJsonField("target", target)
            append(",")
            appendJsonField("approvalId", approvalId)
            append(",")
            appendJsonField("sessionId", sessionId)
            append(",")
            appendJsonField("turnId", turnId)
            append(",")
            appendJsonField("status", status)
            append("}")
        }
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

private fun StringBuilder.appendJsonField(name: String, value: String) {
    append("\"")
    append(escapeJsonString(name))
    append("\":\"")
    append(escapeJsonString(value))
    append("\"")
}

private fun escapeJsonString(value: String): String {
    return buildString {
        for (character in value) {
            when (character) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\b' -> append("\\b")
                '\u000C' -> append("\\f")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> {
                    if (character.code < 0x20) {
                        append("\\u")
                        append(character.code.toString(16).padStart(4, '0'))
                    } else {
                        append(character)
                    }
                }
            }
        }
    }
}
