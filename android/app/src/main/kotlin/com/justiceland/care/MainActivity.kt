package com.justiceland.care

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /// A tap on flutter_callkit_incoming's missed-call notification, not yet
    /// handed to Dart (see PushService: it opens the Missed requests tab).
    private var missedCallTap = false
    private var launchChannel: MethodChannel? = null

    /// A video call is on screen: leaving the app (back, home) shrinks it into
    /// a picture-in-picture window instead of closing it — see lib/core/pip.dart.
    private var inCall = false
    private var pipChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launchChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "justiceland/launch").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeMissedCallTap" -> {
                        result.success(missedCallTap)
                        missedCallTap = false
                    }
                    else -> result.notImplemented()
                }
            }
        }
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "justiceland/pip").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "enter" -> result.success(enterPip())
                    "setInCall" -> {
                        inCall = call.arguments == true
                        // Android 12+: pressing home while in a call goes to PiP
                        // by itself, with the system's smoother animation.
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            setPictureInPictureParams(pipParams(autoEnter = inCall))
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun pipParams(autoEnter: Boolean = false): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(Rational(9, 16))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) builder.setAutoEnterEnabled(autoEnter)
        return builder.build()
    }

    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            enterPictureInPictureMode(pipParams(autoEnter = inCall))
        } catch (e: IllegalStateException) {
            // PiP turned off for this app in system settings.
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Before Android 12 there is no auto-enter: do it on the home press.
        if (inCall && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            enterPip()
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("changed", isInPictureInPictureMode)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        noteLaunch(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (noteLaunch(intent)) {
            missedCallTap = false
            launchChannel?.invokeMethod("missedCallTapped", null)
        }
    }

    /// The missed-call notification opens the app with the call's data and no
    /// action; Accept and "Call back" open it with their own action.
    private fun noteLaunch(intent: Intent?): Boolean {
        val fromMissedCall = intent?.action == null && intent?.hasExtra(CALLKIT_CALL_DATA) == true
        if (fromMissedCall) missedCallTap = true
        return fromMissedCall
    }

    private companion object {
        /// FlutterCallkitIncomingPlugin.EXTRA_CALLKIT_CALL_DATA
        const val CALLKIT_CALL_DATA = "EXTRA_CALLKIT_CALL_DATA"
    }
}
