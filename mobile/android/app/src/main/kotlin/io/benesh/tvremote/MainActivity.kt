package io.benesh.tvremote

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Picture-in-picture for the channel player.
 *
 * The whole activity is what shrinks into the floating window, so Flutter is
 * told when it happens and draws nothing but the picture while it lasts.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** On while a video is playing: leaving the app shrinks it instead of stopping it. */
    private var autoEnter = false
    private var aspect = Rational(16, 9)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.benesh.tvremote/pip")
            .apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "isSupported" -> result.success(supported())
                        "enter" -> {
                            readAspect(call)
                            result.success(enter())
                        }
                        "setAutoEnter" -> {
                            autoEnter = call.argument<Boolean>("enabled") ?: false
                            readAspect(call)
                            applyParams()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
    }

    private fun supported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun readAspect(call: MethodCall) {
        val width = call.argument<Int>("width") ?: return
        val height = call.argument<Int>("height") ?: return
        if (width <= 0 || height <= 0) return
        // Android rejects anything outside 1:2.39..2.39:1 with an exception, so
        // an unusual stream size is clamped rather than allowed to crash.
        val ratio = width.toDouble() / height
        aspect = when {
            ratio > 2.39 -> Rational(239, 100)
            ratio < 1 / 2.39 -> Rational(100, 239)
            else -> Rational(width, height)
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun params(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(aspect)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnter)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun applyParams() {
        if (!supported()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) setPictureInPictureParams(params())
    }

    private fun enter(): Boolean {
        if (!supported()) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            enterPictureInPictureMode(params())
        } catch (_: IllegalStateException) {
            false
        }
    }

    // Android 12 and later enter on their own through setAutoEnterEnabled;
    // before that, the user leaving is the only signal there is.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoEnter && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enter()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("changed", isInPictureInPictureMode)
    }
}
