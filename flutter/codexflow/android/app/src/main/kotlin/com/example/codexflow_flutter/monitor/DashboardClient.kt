package com.example.codexflow_flutter.monitor

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.ParseException
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import kotlin.math.min

class DashboardClient {
    fun fetch(baseUrl: String): DashboardSnapshot {
        val url = URL(baseUrl.trimEnd('/') + "/api/v1/dashboard")
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = TIMEOUT_MS
            readTimeout = TIMEOUT_MS
            setRequestProperty("Accept", "application/json")
        }

        try {
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (status !in 200..299) {
                throw IllegalStateException("Dashboard request failed with status $status")
            }
            return parse(JSONObject(body))
        } finally {
            connection.disconnect()
        }
    }

    private fun parse(json: JSONObject): DashboardSnapshot {
        val sessions = json.optJSONArray("sessions")
        val approvals = json.optJSONArray("approvals")
        return DashboardSnapshot(
            agentConnected = json.optJSONObject("agent")?.optBoolean("connected", false) ?: false,
            sessions = List(sessions?.length() ?: 0) { index ->
                parseSession(sessions!!.optJSONObject(index) ?: JSONObject())
            },
            approvals = List(approvals?.length() ?: 0) { index ->
                parseApproval(approvals!!.optJSONObject(index) ?: JSONObject())
            },
        )
    }

    private fun parseSession(json: JSONObject): SessionSnapshot {
        val id = json.optString("id")
        return SessionSnapshot(
            id = id,
            displayName = sessionLabel(
                id = id,
                name = json.optString("name"),
                agentNickname = json.optString("agentNickname"),
                cwd = json.optString("cwd"),
                preview = json.optString("preview"),
            ),
            lifecycleStage = json.optString("lifecycleStage"),
            lastTurnId = json.optString("lastTurnId"),
            lastTurnStatus = json.optString("lastTurnStatus"),
            pendingApprovals = json.optInt("pendingApprovals", 0),
        )
    }

    private fun parseApproval(json: JSONObject): ApprovalSnapshot {
        return ApprovalSnapshot(
            id = json.optString("id"),
            threadId = json.optString("threadId"),
            summary = json.optString("summary"),
            createdAtEpochSeconds = parseEpochSeconds(json.opt("createdAt")),
        )
    }

    private fun sessionLabel(
        id: String,
        name: String,
        agentNickname: String,
        cwd: String,
        preview: String,
    ): String {
        val explicitName = name.trim()
        if (explicitName.isNotEmpty()) return explicitName
        val nickname = agentNickname.trim()
        if (nickname.isNotEmpty()) return nickname
        val directory = cwd.trim().replace('\\', '/').split('/').lastOrNull()?.trim().orEmpty()
        if (directory.isNotEmpty()) return directory
        val previewLine = preview.lineSequence()
            .map { it.trim() }
            .firstOrNull { it.isNotEmpty() }
            ?.replace(Regex("\\s+"), " ")
            .orEmpty()
        if (previewLine.isNotEmpty()) return truncateRunes(previewLine, 32)
        return "Session ${truncateRunes(id, 8)}"
    }

    private fun parseEpochSeconds(value: Any?): Long {
        return when (value) {
            is Number -> value.toLong()
            is String -> {
                val trimmed = value.trim()
                if (trimmed.isEmpty()) return 0
                trimmed.toLongOrNull() ?: parseIsoEpochSeconds(trimmed)
            }
            else -> 0
        }
    }

    private fun parseIsoEpochSeconds(value: String): Long {
        for (pattern in ISO_PATTERNS) {
            try {
                val format = SimpleDateFormat(pattern, Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }
                return (format.parse(value)?.time ?: 0L) / 1000L
            } catch (_: ParseException) {
                continue
            }
        }
        return 0
    }

    private fun truncateRunes(value: String, limit: Int): String {
        val codePoints = value.codePoints().toArray()
        if (codePoints.size <= limit) return value
        return String(codePoints, 0, min(limit, codePoints.size))
    }

    private companion object {
        const val TIMEOUT_MS = 15_000
        val ISO_PATTERNS = listOf(
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
        )
    }
}
