package com.example.codexflow_flutter.monitor

import android.content.Context
import org.json.JSONObject

class MonitorSnapshotStore(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun load(): MonitorSnapshot {
        val raw = preferences.getString(KEY_SNAPSHOT, null) ?: return MonitorSnapshot.empty()
        return runCatching {
            val json = JSONObject(raw)
            if (json.optInt("version", -1) != VERSION) return MonitorSnapshot.empty()
            val urlsJson = json.optJSONObject("urls") ?: return MonitorSnapshot.empty()
            val urls = mutableMapOf<String, UrlMonitorSnapshot>()
            val keys = urlsJson.keys()
            while (keys.hasNext()) {
                val url = keys.next()
                urls[url] = parseUrlState(urlsJson.optJSONObject(url) ?: JSONObject())
            }
            MonitorSnapshot(version = VERSION, urls = urls)
        }.getOrDefault(MonitorSnapshot.empty())
    }

    fun save(snapshot: MonitorSnapshot): Boolean {
        return preferences.edit().putString(KEY_SNAPSHOT, encode(snapshot).toString()).commit()
    }

    fun markManuallyStopped(url: String): Boolean {
        val now = System.currentTimeMillis() / 1000L
        val snapshot = load()
        val state = snapshot.urlState(url)
        val next = state.copy(
            initialized = true,
            manuallyStopped = true,
            lastUsedAt = now,
        )
        return save(snapshot.copy(urls = snapshot.urls + (url to next)))
    }

    private fun parseUrlState(json: JSONObject): UrlMonitorSnapshot {
        val counts = json.optJSONObject("counts")
        return UrlMonitorSnapshot(
            initialized = json.optBoolean("initialized", false),
            manuallyStopped = json.optBoolean("manuallyStopped", false),
            lastUsedAt = json.optLong("lastUsedAt", 0),
            lastSuccessAt = json.optLong("lastSuccessAt", 0),
            seenApprovals = parseStringLongMap(json.optJSONObject("seenApprovals")),
            seenTurnResults = parseStringLongMap(json.optJSONObject("seenTurnResults")),
            managedTurnState = parseManagedTurnState(json.optJSONObject("managedTurnState")),
            lastRunningManagedCount = counts?.optInt("lastRunningManagedCount") ?: json.optInt("lastRunningManagedCount", 0),
            lastPendingManualActionCount = counts?.optInt("lastPendingManualActionCount") ?: json.optInt("lastPendingManualActionCount", 0),
        )
    }

    private fun encode(snapshot: MonitorSnapshot): JSONObject {
        val urls = JSONObject()
        snapshot.urls.forEach { (url, state) ->
            urls.put(url, encodeUrlState(state))
        }
        return JSONObject()
            .put("version", VERSION)
            .put("urls", urls)
    }

    private fun encodeUrlState(state: UrlMonitorSnapshot): JSONObject {
        val managedTurnState = JSONObject()
        state.managedTurnState.forEach { (sessionId, turnState) ->
            managedTurnState.put(
                sessionId,
                JSONObject()
                    .put("lastTurnId", turnState.lastTurnId)
                    .put("lastTurnStatus", turnState.lastTurnStatus),
            )
        }
        return JSONObject()
            .put("initialized", state.initialized)
            .put("manuallyStopped", state.manuallyStopped)
            .put("lastUsedAt", state.lastUsedAt)
            .put("lastSuccessAt", state.lastSuccessAt)
            .put("seenApprovals", encodeStringLongMap(state.seenApprovals))
            .put("seenTurnResults", encodeStringLongMap(state.seenTurnResults))
            .put("managedTurnState", managedTurnState)
            .put(
                "counts",
                JSONObject()
                    .put("lastRunningManagedCount", state.lastRunningManagedCount)
                    .put("lastPendingManualActionCount", state.lastPendingManualActionCount),
            )
    }

    private fun parseStringLongMap(json: JSONObject?): Map<String, Long> {
        if (json == null) return emptyMap()
        val result = mutableMapOf<String, Long>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            result[key] = json.optLong(key, 0)
        }
        return result
    }

    private fun parseManagedTurnState(json: JSONObject?): Map<String, ManagedTurnState> {
        if (json == null) return emptyMap()
        val result = mutableMapOf<String, ManagedTurnState>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val sessionId = keys.next()
            val state = json.optJSONObject(sessionId) ?: JSONObject()
            result[sessionId] = ManagedTurnState(
                lastTurnId = state.optString("lastTurnId"),
                lastTurnStatus = state.optString("lastTurnStatus"),
            )
        }
        return result
    }

    private fun encodeStringLongMap(values: Map<String, Long>): JSONObject {
        val json = JSONObject()
        values.forEach { (key, value) -> json.put(key, value) }
        return json
    }

    companion object {
        private const val VERSION = 1
        private const val PREFERENCES_NAME = "codexflow_monitor"
        private const val KEY_SNAPSHOT = "codexflow.monitor.snapshot.v1"
    }
}
