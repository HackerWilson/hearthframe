package dev.hearthframe.hearthframe

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // keep_adb: restore wireless debugging if the system switched it off.
        // Non-disruptive: only writes when the value is 0 (no daemon restart
        // while ADB is already up).
        AdbKeep.ensure(this)
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
    }
}