package com.example.codexflow_flutter.monitor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import com.example.codexflow_flutter.MainActivity
import com.example.codexflow_flutter.R

class CodexFlowNotifications(private val context: Context) {
    fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .build()

        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_MANUAL, "Manual action", NotificationManager.IMPORTANCE_HIGH).apply {
                enableVibration(true)
                setSound(Settings.System.DEFAULT_NOTIFICATION_URI, attributes)
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_TURN, "Turn result", NotificationManager.IMPORTANCE_DEFAULT).apply {
                enableVibration(true)
                setSound(Settings.System.DEFAULT_NOTIFICATION_URI, attributes)
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_STATUS, "CodexFlow status", NotificationManager.IMPORTANCE_LOW).apply {
                enableVibration(false)
                setSound(null, null)
            },
        )
    }

    fun persistent(status: MonitorStatus?): Notification {
        val content = PersistentStatusFormatter.format(status)
        val builder = NotificationCompat.Builder(context, CHANNEL_STATUS)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(content.title)
            .setContentText(content.text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(content.expandedText))
            .setSubText(content.subText)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(routeIntent(NotificationTarget.dashboard()))
            .addAction(
                R.drawable.ic_dashboard_24,
                "Dashboard",
                routeIntent(NotificationTarget.dashboard()),
            )
            .addAction(
                R.drawable.ic_approvals_24,
                "Approvals",
                routeIntent(NotificationTarget.approvals()),
            )
            .addAction(
                R.drawable.ic_refresh_24,
                "Refresh",
                serviceIntent(CodexFlowMonitorService.ACTION_REFRESH_NOW, REQUEST_REFRESH),
            )
        content.notificationTimeMillis?.let { timestamp ->
            builder.setShowWhen(true).setWhen(timestamp)
        }
        return builder.build()
    }

    fun manualAction(events: List<ManualActionEvent>): Notification {
        val target = if (events.size == 1) {
            val event = events.single()
            NotificationTarget.approval(event.approvalId, event.sessionId)
        } else {
            NotificationTarget.approvals()
        }
        val text = if (events.size == 1) {
            "${events.single().sessionLabel} has a pending approval"
        } else {
            "${events.size} pending approvals need review"
        }
        return NotificationCompat.Builder(context, CHANNEL_MANUAL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("CodexFlow needs your action")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setOnlyAlertOnce(false)
            .setAutoCancel(true)
            .setContentIntent(routeIntent(target))
            .build()
    }

    fun turnResult(events: List<TurnResultEvent>): Notification {
        val sameSession = events.map { it.sessionId }.toSet().size == 1
        val target = if (events.size == 1 || sameSession) {
            val first = events.first()
            NotificationTarget.session(first.sessionId, first.turnId, first.status)
        } else {
            NotificationTarget.dashboard()
        }
        val title = when {
            events.size > 1 -> "CodexFlow tasks updated"
            events.single().status == "interrupted" -> "CodexFlow task interrupted"
            else -> "CodexFlow task completed"
        }
        val text = if (events.size == 1) {
            val event = events.single()
            if (event.status == "interrupted") {
                "${event.sessionLabel} was interrupted"
            } else {
                "${event.sessionLabel} finished a turn"
            }
        } else {
            val completed = events.count { it.status == "completed" }
            val interrupted = events.count { it.status == "interrupted" }
            listOfNotNull(
                if (completed > 0) "$completed completed" else null,
                if (interrupted > 0) "$interrupted interrupted" else null,
            ).joinToString(", ")
        }
        return NotificationCompat.Builder(context, CHANNEL_TURN)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setOnlyAlertOnce(false)
            .setAutoCancel(true)
            .setContentIntent(routeIntent(target))
            .build()
    }

    private fun routeIntent(target: NotificationTarget): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(ACTION_NOTIFICATION_ROUTE)
            .putExtra(EXTRA_NOTIFICATION_TARGET, target.encode())
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            context,
            target.requestCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun serviceIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, CodexFlowMonitorService::class.java)
            .setAction(action)
        return PendingIntent.getService(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        const val CHANNEL_MANUAL = "manual_action"
        const val CHANNEL_TURN = "turn_result"
        const val CHANNEL_STATUS = "persistent_status"
        const val ID_PERSISTENT = 1000
        const val ID_MANUAL = 2000
        const val ID_TURN = 3000
        private const val REQUEST_REFRESH = 1001
        const val ACTION_NOTIFICATION_ROUTE = "com.example.codexflow_flutter.NOTIFICATION_ROUTE"
        const val EXTRA_NOTIFICATION_TARGET = "codexflow.notificationTarget"
    }
}
