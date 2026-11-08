package dev.hearthframe.hearthframe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.util.Log

/**
 * keep_adb: some OEM builds (e.g. HyperOS) switch wireless debugging off
 * across reboots or standby. When WRITE_SECURE_SETTINGS has been granted
 * once via `adb shell pm grant`, HearthFrame writes the setting back so
 * wireless ADB stays available — a common pattern on Android TV devices.
 * Without the grant this is a silent no-op.
 */
object AdbKeep {
    private const val TAG = "HearthFrameAdbKeep"
    // Hidden Settings.Global key (not in the public SDK).
    private const val ADB_WIFI_ENABLED = "adb_wifi_enabled"

    private fun hasGrant(context: Context): Boolean =
        context.checkSelfPermission(android.Manifest.permission.WRITE_SECURE_SETTINGS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED

    /** Called from the running frame UI: only write when the system turned it off. */
    fun ensure(context: Context) {
        if (!hasGrant(context)) return
        try {
            val resolver = context.contentResolver
            if (Settings.Global.getInt(resolver, ADB_WIFI_ENABLED, 0) != 1) {
                Settings.Global.putInt(resolver, ADB_WIFI_ENABLED, 1)
                Log.i(TAG, "adb_wifi_enabled restored to 1")
            }
            if (Settings.Global.getInt(resolver, Settings.Global.ADB_ENABLED, 0) != 1) {
                Settings.Global.putInt(resolver, Settings.Global.ADB_ENABLED, 1)
            }
        } catch (e: Exception) {
            Log.w(TAG, "ensure failed: ${e.message}")
        }
    }

    /**
     * Called at boot / app start: force a 0->1 transition so the platform
     * restarts the wireless-debugging daemon even if the stored value was
     * already 1 but the daemon did not come up.
     */
    fun force(context: Context) {
        if (!hasGrant(context)) return
        try {
            val resolver = context.contentResolver
            Settings.Global.putInt(resolver, ADB_WIFI_ENABLED, 0)
            Settings.Global.putInt(resolver, ADB_WIFI_ENABLED, 1)
            Settings.Global.putInt(resolver, Settings.Global.ADB_ENABLED, 1)
            Settings.Global.putInt(resolver, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 1)
            Log.i(TAG, "wireless debugging re-enabled at startup")
        } catch (e: Exception) {
            Log.w(TAG, "force failed: ${e.message}")
        }
    }
}

/** Restores wireless ADB after the device boots (needs autostart allowed on MIUI/HyperOS). */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            AdbKeep.force(context)
        }
    }
}