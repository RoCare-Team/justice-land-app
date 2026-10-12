package com.justiceland.care

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/// Keeps a live consultation call (flutter_webrtc) running when the user
/// leaves the app: a foreground service of type phoneCall + microphone
/// (+ camera for a video call), with an ongoing-call notification whose tap
/// brings the call screen back. Started and stopped from Dart
/// (lib/core/platform/ongoing_call.dart, via MainActivity `justiceland/call`).
class OngoingCallService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Consultation call"
        val video = intent?.getBooleanExtra(EXTRA_VIDEO, false) ?: false
        try {
            val notification = buildNotification(title, video)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, serviceTypes(video))
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // E.g. started while the app was already in the background — the
            // call still works while it is on screen, just not behind it.
            Log.e(TAG, "Could not start the ongoing-call service", e)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    /// Android 14 refuses the microphone / camera types unless that runtime
    /// permission is already granted, so only the granted ones are asked for.
    private fun serviceTypes(video: Boolean): Int {
        var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (granted(Manifest.permission.RECORD_AUDIO)) {
                types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
            if (video && granted(Manifest.permission.CAMERA)) {
                types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            }
        }
        return types
    }

    private fun granted(permission: String) =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun buildNotification(title: String, video: Boolean): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val text = if (video) "Video call in progress · Tap to return" else "Audio call in progress · Tap to return"
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            if (manager?.getNotificationChannel(CHANNEL_ID) == null) {
                manager?.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Ongoing calls", NotificationManager.IMPORTANCE_LOW)
                )
            }
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_accept)
            .setContentIntent(open)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_CALL)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    companion object {
        private const val TAG = "OngoingCallService"
        private const val CHANNEL_ID = "ongoing_call"
        private const val NOTIFICATION_ID = 7301
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_VIDEO = "video"

        fun start(context: Context, title: String?, video: Boolean): Boolean {
            val intent = Intent(context, OngoingCallService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_VIDEO, video)
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (e: Exception) {
                Log.e(TAG, "Could not start the ongoing-call service", e)
                false
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, OngoingCallService::class.java))
        }
    }
}
