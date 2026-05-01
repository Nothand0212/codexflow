package com.example.codexflow_flutter.monitor

import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import androidx.core.app.NotificationManagerCompat

class CodexFlowMonitorService : Service() {
    private lateinit var notifications: CodexFlowNotifications
    private lateinit var snapshotStore: MonitorSnapshotStore
    private val dashboardClient = DashboardClient()
    private val stateMachine = MonitorStateMachine()
    private var workerThread: HandlerThread? = null
    private var workerHandler: Handler? = null
    @Volatile
    private var visible = false

    @Volatile
    private var running = false

    @Volatile
    private var runGeneration = 0L

    private var polling = false
    private var consecutiveFailures = 0
    private var lastUrl = ""
    private var lastStatus: MonitorStatus? = null
    private var immediatePollQueued = false
    private var scheduledPoll: Runnable? = null

    override fun onCreate() {
        super.onCreate()
        notifications = CodexFlowNotifications(this)
        notifications.ensureChannels()
        snapshotStore = MonitorSnapshotStore(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startAsForeground()
        when (intent?.action) {
            ACTION_STOP -> stopMonitor()
            ACTION_REFRESH_NOW -> startMonitorLoop()
            ACTION_SET_VISIBILITY -> {
                visible = intent.getBooleanExtra(EXTRA_VISIBLE, visible)
                startMonitorLoop()
            }
            ACTION_START, null -> startMonitorLoop()
            else -> startMonitorLoop()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        running = false
        runGeneration += 1
        markServiceRunning(this, false)
        workerHandler?.removeCallbacksAndMessages(null)
        workerThread?.quitSafely()
        workerHandler = null
        workerThread = null
        super.onDestroy()
    }

    private fun startAsForeground() {
        val status = lastStatus ?: startupStatusFromSnapshot()
        val notification = notifications.persistent(status)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                CodexFlowNotifications.ID_PERSISTENT,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(CodexFlowNotifications.ID_PERSISTENT, notification)
        }
    }

    private fun startupStatusFromSnapshot(): MonitorStatus? {
        val url = readBaseUrl()
        return MonitorStatusFactory.cached(
            url = url,
            snapshot = snapshotStore.load(),
            nowEpochSeconds = System.currentTimeMillis() / 1000L,
        )
    }

    private fun startMonitorLoop() {
        if (workerThread == null) {
            workerThread = HandlerThread("CodexFlowMonitor").also { it.start() }
            workerHandler = Handler(workerThread!!.looper)
        }
        markServiceRunning(this, true)
        if (running) {
            requestImmediatePoll(runGeneration)
            return
        }
        running = true
        runGeneration += 1
        requestImmediatePoll(runGeneration)
    }

    private fun pollOnce(generation: Long) {
        if (!isCurrentGeneration(generation) || polling) return
        polling = true
        val currentUrl = readBaseUrl()
        try {
            val dashboard = dashboardClient.fetch(currentUrl)
            val previous = snapshotStore.load()
            val forceFreshBaseline = currentUrl != lastUrl || !previous.urlState(currentUrl).initialized
            val decision = stateMachine.evaluate(
                url = currentUrl,
                previous = previous,
                dashboard = dashboard,
                nowEpochSeconds = System.currentTimeMillis() / 1000L,
                forceFreshBaseline = forceFreshBaseline,
            )
            if (!isCurrentGeneration(generation)) return
            snapshotStore.save(decision.snapshot)
            lastUrl = currentUrl
            lastStatus = decision.status
            consecutiveFailures = 0
            notifyPersistent(decision.status)
            if (decision.manualActions.isNotEmpty()) {
                notify(CodexFlowNotifications.ID_MANUAL, notifications.manualAction(decision.manualActions))
            }
            if (decision.turnResults.isNotEmpty()) {
                notify(CodexFlowNotifications.ID_TURN, notifications.turnResult(decision.turnResults))
            }
            scheduleNext(if (visible) SUCCESS_VISIBLE_MS else SUCCESS_BACKGROUND_MS, generation)
        } catch (_: Exception) {
            if (!isCurrentGeneration(generation)) return
            consecutiveFailures = (consecutiveFailures + 1).coerceAtMost(3)
            notifyPersistent(
                MonitorStatusFactory.offline(
                    url = currentUrl,
                    prior = lastStatus,
                    nowEpochSeconds = System.currentTimeMillis() / 1000L,
                ),
            )
            scheduleNext(failureBackoffMs(), generation)
        } finally {
            polling = false
        }
    }

    private fun stopMonitor() {
        running = false
        runGeneration += 1
        workerHandler?.removeCallbacksAndMessages(null)
        scheduledPoll = null
        immediatePollQueued = false
        markServiceRunning(this, false)
        val url = readBaseUrl()
        snapshotStore.markManuallyStopped(url)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun scheduleNext(delayMs: Long, generation: Long) {
        if (!isCurrentGeneration(generation)) return
        scheduledPoll?.let { workerHandler?.removeCallbacks(it) }
        val nextPoll = Runnable {
            scheduledPoll = null
            pollOnce(generation)
        }
        scheduledPoll = nextPoll
        workerHandler?.postDelayed(nextPoll, delayMs)
    }

    private fun requestImmediatePoll(generation: Long) {
        if (!isCurrentGeneration(generation) || immediatePollQueued) return
        scheduledPoll?.let { workerHandler?.removeCallbacks(it) }
        scheduledPoll = null
        immediatePollQueued = true
        workerHandler?.post {
            immediatePollQueued = false
            pollOnce(generation)
        }
    }

    private fun isCurrentGeneration(generation: Long): Boolean {
        return running && generation == runGeneration
    }

    private fun notifyPersistent(status: MonitorStatus) {
        notify(CodexFlowNotifications.ID_PERSISTENT, notifications.persistent(status))
    }

    private fun notify(id: Int, notification: android.app.Notification) {
        try {
            NotificationManagerCompat.from(this).notify(id, notification)
        } catch (_: SecurityException) {
            if (id == CodexFlowNotifications.ID_PERSISTENT) {
                try {
                    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    manager.notify(id, notification)
                } catch (_: SecurityException) {
                    // Android 13+ may reject notification updates until permission is granted.
                }
            }
        }
    }

    private fun failureBackoffMs(): Long {
        return when (consecutiveFailures) {
            0, 1 -> FAILURE_BACKOFF_1_MS
            2 -> FAILURE_BACKOFF_2_MS
            else -> FAILURE_BACKOFF_3_MS
        }
    }

    private fun readBaseUrl(): String {
        val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val packagePrefs = getSharedPreferences(packageName + "_preferences", Context.MODE_PRIVATE)
        return flutterPrefs.getString("flutter.$KEY_BASE_URL", null)
            ?: flutterPrefs.getString(KEY_BASE_URL, null)
            ?: packagePrefs.getString(KEY_BASE_URL, null)
            ?: DEFAULT_BASE_URL
    }

    companion object {
        const val ACTION_START = "com.example.codexflow_flutter.monitor.START"
        const val ACTION_STOP = "com.example.codexflow_flutter.monitor.STOP"
        const val ACTION_REFRESH_NOW = "com.example.codexflow_flutter.monitor.REFRESH_NOW"
        const val ACTION_SET_VISIBILITY = "com.example.codexflow_flutter.monitor.SET_VISIBILITY"
        const val EXTRA_VISIBLE = "visible"

        fun markServiceRunning(context: Context, running: Boolean): Boolean {
            return context.getSharedPreferences(RUNTIME_PREFERENCES_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_SERVICE_RUNNING, running)
                .commit()
        }

        fun isServiceMarkedRunning(context: Context): Boolean {
            return context.getSharedPreferences(RUNTIME_PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_SERVICE_RUNNING, false)
        }

        private const val RUNTIME_PREFERENCES_NAME = "codexflow_monitor_runtime"
        private const val KEY_SERVICE_RUNNING = "codexflow.monitor.serviceRunning"
        private const val KEY_BASE_URL = "codexflow.baseURL"
        private const val DEFAULT_BASE_URL = "http://127.0.0.1:4318"
        private const val SUCCESS_VISIBLE_MS = 10_000L
        private const val SUCCESS_BACKGROUND_MS = 30_000L
        private const val FAILURE_BACKOFF_1_MS = 30_000L
        private const val FAILURE_BACKOFF_2_MS = 60_000L
        private const val FAILURE_BACKOFF_3_MS = 120_000L
    }
}
