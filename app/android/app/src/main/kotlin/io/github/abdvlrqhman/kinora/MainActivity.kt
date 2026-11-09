package io.github.abdvlrqhman.kinora

import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var pipAllowed = false
    private var pipAspect = Rational(16, 9)
    private var pipChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // DLNA discovery (SSDP) needs multicast, which Android filters
        // unless a MulticastLock is held.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kinora/net")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquireMulticast" -> {
                        if (multicastLock == null) {
                            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                            multicastLock = wifi.createMulticastLock("kinora-dlna").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        }
                        result.success(true)
                    }
                    "releaseMulticast" -> {
                        multicastLock?.release()
                        multicastLock = null
                        result.success(true)
                    }
                    // Real liquid glass needs Impeller on Vulkan; Flutter falls
                    // back to OpenGL ES without Vulkan 1.1 (and on emulators),
                    // where the glass renderer can stall frames.
                    "vulkanRendering" -> result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                            packageManager.hasSystemFeature(
                                PackageManager.FEATURE_VULKAN_HARDWARE_VERSION, 0x401000
                            ) && !isEmulator()
                    )
                    else -> result.notImplemented()
                }
            }
        // Picture-in-picture while a video plays.
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kinora/pip").also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAllowed" -> {
                        pipAllowed = call.argument<Boolean>("allowed") ?: false
                        val w = call.argument<Int>("width") ?: 16
                        val h = call.argument<Int>("height") ?: 9
                        // Android accepts ratios between 1:2.39 and 2.39:1.
                        val r = (w.toDouble() / h.coerceAtLeast(1)).coerceIn(0.42, 2.39)
                        pipAspect = Rational((r * 1000).toInt(), 1000)
                        setPictureInPictureParams(pipParams())
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun isEmulator(): Boolean =
        Build.HARDWARE in setOf("goldfish", "ranchu") ||
            Build.FINGERPRINT.startsWith("generic") ||
            Build.PRODUCT.contains("sdk")

    private fun pipParams(): PictureInPictureParams {
        val b = PictureInPictureParams.Builder().setAspectRatio(pipAspect)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            b.setAutoEnterEnabled(pipAllowed).setSeamlessResizeEnabled(true)
        }
        return b.build()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Android 12+ enters automatically (setAutoEnterEnabled); older needs this.
        if (pipAllowed && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            enterPictureInPictureMode(pipParams())
        }
    }

    override fun onPictureInPictureModeChanged(inPip: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(inPip, newConfig)
        pipChannel?.invokeMethod("changed", inPip)
    }

    override fun onDestroy() {
        multicastLock?.release()
        multicastLock = null
        super.onDestroy()
    }
}
