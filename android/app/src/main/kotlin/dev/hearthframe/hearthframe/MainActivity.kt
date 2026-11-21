package dev.hearthframe.hearthframe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.ExifInterface
import android.media.MediaCodecList
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.util.Locale

class MainActivity : FlutterActivity() {
    companion object {
        /** True between onCreate and onDestroy, including backgrounded tasks. */
        @Volatile
        var isAlive = false
            private set

        /** True between onResume and onPause; used to skip redundant launches. */
        @Volatile
        var isForeground = false
            private set
    }

    private var keepScreenOnRequested = false
    private var screenWakeLock: PowerManager.WakeLock? = null

    private val stopReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == FrameAutomation.ACTION_STOP) {
                Log.i(FrameAutomation.TAG, "stop requested by automation")
                FrameAutomation.cancelLaunchNotification(this@MainActivity)
                finishAndRemoveTask()
            }
        }
    }

    private val powerReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_POWER_DISCONNECTED -> {
                    FrameAutomation.schedulePowerJobs(this@MainActivity)
                    val cfg = FrameAutomation.Config.load(this@MainActivity)
                    if (cfg.exitOnPowerLoss) {
                        Log.i(FrameAutomation.TAG, "charger unplugged: exit")
                        FrameAutomation.cancelLaunchNotification(this@MainActivity)
                        finishAndRemoveTask()
                    }
                }
                Intent.ACTION_POWER_CONNECTED -> {
                    FrameAutomation.schedulePowerJobs(this@MainActivity)
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 26) {
            findViewById<android.view.View>(FLUTTER_VIEW_ID)?.defaultFocusHighlightEnabled = false
        }
        isAlive = true
        // A frame is meant to stay visible. FLAG_KEEP_SCREEN_ON alone can be
        // dropped by some OEM power policies when the activity pauses, so a
        // native screen-bright wake lock backs it up while the app is
        // resumed. Dismiss a non-secure keyguard when the frame is on screen.
        window.addFlags(WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD)
        FrameAutomation.cancelLaunchNotification(this)
        val stopFilter = IntentFilter(FrameAutomation.ACTION_STOP)
        val powerFilter = IntentFilter().apply {
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(
                stopReceiver,
                stopFilter,
                Context.RECEIVER_NOT_EXPORTED,
            )
            registerReceiver(
                powerReceiver,
                powerFilter,
                Context.RECEIVER_EXPORTED,
            )
        } else {
            registerReceiver(stopReceiver, stopFilter)
            registerReceiver(powerReceiver, powerFilter)
        }
        // keep_adb: restore wireless debugging if the system switched it off.
        // Non-disruptive: only writes when the value is 0 (no daemon restart
        // while ADB is already up).
        AdbKeep.ensure(this)
    }

    override fun onResume() {
        super.onResume()
        isForeground = true
        applyScreenKeepOn()
    }

    override fun onPause() {
        isForeground = false
        releaseScreenKeepOn()
        super.onPause()
    }

    private fun applyScreenKeepOn() {
        if (!keepScreenOnRequested) return
        if (screenWakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            screenWakeLock = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK,
                "HearthFrame:frame",
            ).apply { setReferenceCounted(false) }
        }
        val lock = screenWakeLock
        if (lock != null && !lock.isHeld) lock.acquire()
    }

    private fun releaseScreenKeepOn() {
        val lock = screenWakeLock
        if (lock != null && lock.isHeld) lock.release()
    }

    private fun setKeepScreenOn(enabled: Boolean) {
        keepScreenOnRequested = enabled
        if (enabled) {
            applyScreenKeepOn()
        } else {
            releaseScreenKeepOn()
        }
    }

    override fun onDestroy() {
        isAlive = false
        isForeground = false
        keepScreenOnRequested = false
        releaseScreenKeepOn()
        try {
            screenWakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        screenWakeLock = null
        try {
            unregisterReceiver(stopReceiver)
        } catch (_: Exception) {
        }
        try {
            unregisterReceiver(powerReceiver)
        } catch (_: Exception) {
        }
        // Re-arm the cold plug-in job when the frame is closed while unplugged.
        FrameAutomation.schedulePowerJobs(this)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hearthframe/adb_keep"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensure" -> {
                    AdbKeep.ensure(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hearthframe/image"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "heicToJpeg" -> {
                    val src = call.argument<String>("src")
                    val dst = call.argument<String>("dst")
                    if (src == null || dst == null) {
                        result.error("args", "src and dst required", null)
                    } else {
                        HeicConvert.convert(src, dst) { path, err ->
                            if (path != null) result.success(path)
                            else result.error("convert", err, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(
            messenger,
            "hearthframe/metadata",
            StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue(),
        ).setMethodCallHandler { call, result ->
            if (call.method != "captureDate") {
                result.notImplemented()
            } else {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("args", "path required", null)
                } else {
                    result.success(readCaptureDate(path, call.argument<Boolean>("isVideo") == true))
                }
            }
        }
        // Only MIUI-derived builds need the portrait-attach workaround (see
        // ADR-003). ChromeOS/ARC and stock Android attach in landscape directly,
        // which avoids a visible portrait boot frame.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hearthframe/device"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "needsPortraitAttach" -> result.success(needsPortraitAttach())
                "supportsHevc" -> result.success(
                    MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { codec ->
                        !codec.isEncoder && codec.supportedTypes.any { it.equals("video/hevc", ignoreCase = true) }
                    }
                )
                "appVersion" -> {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                    result.success("${info.versionName} ($code)")
                }
                else -> result.notImplemented()
            }
        }
        // Automation settings are mirrored to native SharedPreferences so
        // boot/charging/alarms keep working while Flutter is not running.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hearthframe/screen"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepOn" -> {
                    setKeepScreenOn(call.argument<Boolean>("enabled") == true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hearthframe/automation"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    val values = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    result.success(FrameAutomation.configure(this, values))
                }
                "status" -> result.success(FrameAutomation.status(this))
                "requestNextPermission" ->
                    result.success(FrameAutomation.requestNextPermission(this))
                "openOemStartupSettings" ->
                    result.success(FrameAutomation.openOemStartupSettings(this))
                "openOemPermissionEditor" ->
                    result.success(FrameAutomation.openOemPermissionEditor(this))
                "start" -> {
                    FrameAutomation.launchFrame(this, "manual")
                    result.success(null)
                }
                "stop" -> {
                    FrameAutomation.stopFrame(this, "manual")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun readCaptureDate(path: String, video: Boolean): String? = try {
        if (video) {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(path)
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DATE)
            } finally {
                retriever.release()
            }
        } else {
            val exif = ExifInterface(path)
            listOf(ExifInterface.TAG_DATETIME_ORIGINAL, ExifInterface.TAG_DATETIME_DIGITIZED)
                .mapNotNull { exif.getAttribute(it) }
                .firstOrNull { it.isNotBlank() && !it.startsWith("0000") }
        }
    } catch (_: Exception) {
        null
    }

    private fun needsPortraitAttach(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase(Locale.ROOT)
        val brand = Build.BRAND.lowercase(Locale.ROOT)
        if (manufacturer == "xiaomi" || brand == "xiaomi" ||
            brand == "redmi" || brand == "poco"
        ) {
            return true
        }
        // Fallback for MIUI builds with an unexpected brand string.
        return !systemProperty("ro.miui.ui.version.name").isNullOrEmpty()
    }

    private fun systemProperty(name: String): String? = try {
        val clazz = Class.forName("android.os.SystemProperties")
        val getter = clazz.getMethod("get", String::class.java)
        (getter.invoke(null, name) as? String)?.takeIf { it.isNotEmpty() }
    } catch (_: Exception) {
        null
    }
}