package com.example.codexflow_flutter

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.example.codexflow_flutter.monitor.CodexFlowMonitorService
import com.example.codexflow_flutter.monitor.CodexFlowNotifications
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingNotificationRoute: String? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        captureNotificationRoute(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_MONITOR)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startMonitor" -> {
                    startMonitor()
                    result.success(null)
                }
                "stopMonitor" -> {
                    stopMonitor()
                    result.success(null)
                }
                "setAppVisible" -> {
                    setAppVisible(call.argument<Boolean>("visible") ?: false)
                    result.success(null)
                }
                "agentUrlChanged" -> {
                    if (CodexFlowMonitorService.isServiceMarkedRunning(this)) {
                        startMonitor()
                    }
                    result.success(null)
                }
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "getMonitorStatus" -> result.success(monitorStatus())
                "takeInitialNotificationRoute" -> {
                    val route = pendingNotificationRoute
                    pendingNotificationRoute = null
                    result.success(route)
                }
                else -> result.notImplemented()
            }
        }
        pendingNotificationRoute?.let { route ->
            channel?.invokeMethod("notificationRoute", route)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureNotificationRoute(intent)
    }

    private fun startMonitor() {
        CodexFlowMonitorService.markServiceRunning(this, true)
        val intent = Intent(this, CodexFlowMonitorService::class.java)
            .setAction(CodexFlowMonitorService.ACTION_START)
        ContextCompat.startForegroundService(this, intent)
    }

    private fun stopMonitor() {
        val intent = Intent(this, CodexFlowMonitorService::class.java)
            .setAction(CodexFlowMonitorService.ACTION_STOP)
        ContextCompat.startForegroundService(this, intent)
        CodexFlowMonitorService.markServiceRunning(this, false)
    }

    private fun setAppVisible(visible: Boolean) {
        if (!CodexFlowMonitorService.isServiceMarkedRunning(this)) return
        val intent = Intent(this, CodexFlowMonitorService::class.java)
            .setAction(CodexFlowMonitorService.ACTION_SET_VISIBILITY)
            .putExtra(CodexFlowMonitorService.EXTRA_VISIBLE, visible)
        ContextCompat.startForegroundService(this, intent)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (hasNotificationPermission()) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.success(false)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATION_PERMISSION,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_NOTIFICATION_PERMISSION) {
            return
        }
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    private fun monitorStatus(): Map<String, Any> {
        return mapOf(
            "supported" to true,
            "running" to CodexFlowMonitorService.isServiceMarkedRunning(this),
            "notificationPermissionGranted" to hasNotificationPermission(),
            "versionName" to packageVersionName(),
            "buildNumber" to packageVersionCode(),
        )
    }

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun packageVersionName(): String {
        return packageManager.getPackageInfo(packageName, 0).versionName ?: ""
    }

    private fun packageVersionCode(): Long {
        val info = packageManager.getPackageInfo(packageName, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
    }

    private fun captureNotificationRoute(intent: Intent?) {
        if (intent?.action != CodexFlowNotifications.ACTION_NOTIFICATION_ROUTE) {
            return
        }
        val route = intent.getStringExtra(CodexFlowNotifications.EXTRA_NOTIFICATION_TARGET)
        if (route.isNullOrEmpty()) {
            return
        }
        if (channel == null) {
            pendingNotificationRoute = route
        } else {
            channel?.invokeMethod("notificationRoute", route)
        }
    }

    companion object {
        private const val CHANNEL_MONITOR = "codexflow/monitor"
        private const val REQUEST_NOTIFICATION_PERMISSION = 5101
    }
}
