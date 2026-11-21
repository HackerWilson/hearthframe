package dev.hearthframe.hearthframe

import android.Manifest
import android.app.Activity
import android.app.ActivityOptions
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import java.util.Calendar

/**
 * Frame automation: launch on boot / charging, exit when unplugged and a
 * daily start/stop schedule.
 *
 * Android 10+ blocks background activity starts. A photo frame has to come
 * up without the user touching the screen, so the launch path uses every
 * sanctioned option at once:
 *
 *  1. a high-importance notification with a full-screen intent (the path
 *     alarm-clock apps use),
 *  2. a one-shot AlarmManager activity PendingIntent delivered by the
 *     system, and
 *  3. a direct [Context.startActivity] which is allowed when the user grants
 *     "display over other apps" (a documented background-start exemption).
 *
 * Charging cannot be observed with a manifest receiver (ACTION_POWER_CONNECTED
 * is not an implicit-broadcast exception), so it is handled two ways:
 * a [JobScheduler] charging-constrained job for cold launches and a dynamic
 * receiver while the frame is running (used for exit-on-unplug).
 *
 * Scheduling itself lives here, in native code, because it must work while
 * Flutter is not running. Flutter mirrors its settings through the
 * `hearthframe/automation` channel.
 */
object FrameAutomation {
    const val TAG = "HearthFrameAuto"
    const val ACTION_START = "dev.hearthframe.hearthframe.AUTOSTART"
    const val ACTION_STOP = "dev.hearthframe.hearthframe.FRAME_STOP"
    const val ACTION_SCHEDULE_START = "dev.hearthframe.hearthframe.SCHEDULE_START"
    const val ACTION_SCHEDULE_END = "dev.hearthframe.hearthframe.SCHEDULE_END"

    private const val PREFS = "frame_automation"
    private const val CHANNEL_ID = "frame_automation"
    private const val NOTIFICATION_ID = 4100
    private const val JOB_POWER_ONESHOT = 4101
    private const val JOB_POWER_PERIODIC = 4102
    private const val ALARM_START = 4201
    private const val ALARM_END = 4202
    private const val LAUNCH_ALARM = 4301
    private const val PERMISSION_REQUEST = 4401

    data class Config(
        val launchOnBoot: Boolean,
        val launchOnPower: Boolean,
        val exitOnPowerLoss: Boolean,
        val activeHours: Boolean,
        val activeStart: Int,
        val activeEnd: Int,
        val schedule: Boolean,
        val scheduleStart: Int,
        val scheduleEnd: Int,
    ) {
        companion object {
            fun load(context: Context): Config {
                val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                return Config(
                    launchOnBoot = p.getBoolean("launch_on_boot", false),
                    launchOnPower = p.getBoolean("launch_on_power", false),
                    exitOnPowerLoss = p.getBoolean("exit_on_power_loss", false),
                    activeHours = p.getBoolean("active_hours", false),
                    activeStart = p.getInt("active_start", 7 * 60),
                    activeEnd = p.getInt("active_end", 23 * 60),
                    schedule = p.getBoolean("schedule", false),
                    scheduleStart = p.getInt("schedule_start", 7 * 60),
                    scheduleEnd = p.getInt("schedule_end", 23 * 60),
                )
            }
        }

        fun save(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean("launch_on_boot", launchOnBoot)
                .putBoolean("launch_on_power", launchOnPower)
                .putBoolean("exit_on_power_loss", exitOnPowerLoss)
                .putBoolean("active_hours", activeHours)
                .putInt("active_start", activeStart)
                .putInt("active_end", activeEnd)
                .putBoolean("schedule", schedule)
                .putInt("schedule_start", scheduleStart)
                .putInt("schedule_end", scheduleEnd)
                .apply()
        }
    }

    fun configure(context: Context, values: Map<*, *>): Map<String, Any> {
        val previous = Config.load(context)
        val cfg = Config(
            launchOnBoot = values["launchOnBoot"] as? Boolean ?: previous.launchOnBoot,
            launchOnPower = values["launchOnPower"] as? Boolean ?: previous.launchOnPower,
            exitOnPowerLoss = values["exitOnPowerLoss"] as? Boolean
                ?: previous.exitOnPowerLoss,
            activeHours = values["activeHours"] as? Boolean ?: previous.activeHours,
            activeStart = (values["activeStart"] as? Number)?.toInt()
                ?: previous.activeStart,
            activeEnd = (values["activeEnd"] as? Number)?.toInt()
                ?: previous.activeEnd,
            schedule = values["schedule"] as? Boolean ?: previous.schedule,
            scheduleStart = (values["scheduleStart"] as? Number)?.toInt()
                ?: previous.scheduleStart,
            scheduleEnd = (values["scheduleEnd"] as? Number)?.toInt()
                ?: previous.scheduleEnd,
        )
        cfg.save(context)
        createChannel(context)
        reschedule(context)
        schedulePowerJobs(context)
        Log.i(TAG, "configured $cfg charging=${isCharging(context)}")
        return status(context)
    }

    fun status(context: Context): Map<String, Any> {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        val notifications = if (Build.VERSION.SDK_INT >= 24) {
            nm.areNotificationsEnabled()
        } else {
            true
        }
        val overlay = if (Build.VERSION.SDK_INT >= 23) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
        val exact = if (Build.VERSION.SDK_INT >= 31) {
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
                .canScheduleExactAlarms()
        } else {
            true
        }
        val fullScreen = if (Build.VERSION.SDK_INT >= 34) {
            nm.canUseFullScreenIntent()
        } else {
            true
        }
        return mapOf(
            "notifications" to notifications,
            "overlay" to overlay,
            "exactAlarms" to exact,
            "fullScreen" to fullScreen,
            "miui" to isMiui(),
        )
    }

    /**
     * Opens the next missing special permission. Called repeatedly from the
     * settings sheet; each call advances one step after a system screen.
     * Returns the step that was opened ("notifications", "overlay", "exact",
     * "fullScreen") or "complete".
     */
    fun requestNextPermission(activity: Activity): String {
        if (Build.VERSION.SDK_INT >= 33 &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            activity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                PERMISSION_REQUEST,
            )
            return "notifications"
        }
        if (Build.VERSION.SDK_INT >= 23 && !Settings.canDrawOverlays(activity)) {
            openSettings(
                activity,
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${activity.packageName}"),
                ),
            )
            return "overlay"
        }
        if (Build.VERSION.SDK_INT >= 31) {
            val am = activity.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (!am.canScheduleExactAlarms()) {
                openSettings(
                    activity,
                    Intent(
                        Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                        Uri.parse("package:${activity.packageName}"),
                    ),
                )
                return "exact"
            }
        }
        if (Build.VERSION.SDK_INT >= 34) {
            val nm = activity.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            if (!nm.canUseFullScreenIntent()) {
                openSettings(
                    activity,
                    Intent(
                        Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                        Uri.parse("package:${activity.packageName}"),
                    ),
                )
                return "fullScreen"
            }
        }
        return "complete"
    }

    /** Opens MIUI/HyperOS autostart management. */
    fun openOemStartupSettings(activity: Activity): Boolean {
        val intent = Intent("miui.intent.action.OP_AUTO_START").apply {
            putExtra("extra_pkgname", activity.packageName)
            putExtra("PackageName", activity.packageName)
        }
        return openOemPage(activity, intent)
    }

    /**
     * Opens MIUI's per-app permission editor. The critical switch is
     * 其他权限 → 后台弹出界面 → 始终允许; without it MIUI aborts background
     * activity starts even with SYSTEM_ALERT_WINDOW granted.
     */
    fun openOemPermissionEditor(activity: Activity): Boolean {
        val intent = Intent("miui.intent.action.APP_PERM_EDITOR").apply {
            putExtra("extra_pkgname", activity.packageName)
            putExtra("PackageName", activity.packageName)
            setClassName(
                "com.miui.securitycenter",
                "com.miui.permcenter.permissions.PermissionsEditorActivity",
            )
        }
        return openOemPage(activity, intent)
    }

    private fun openOemPage(activity: Activity, intent: Intent): Boolean {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (activity.packageManager.resolveActivity(intent, 0) != null) {
            try {
                activity.startActivity(intent)
                return true
            } catch (e: Exception) {
                Log.w(TAG, "OEM settings failed: ${e.message}")
            }
        }
        openSettings(
            activity,
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${activity.packageName}"),
            ),
        )
        return false
    }

    fun isMiui(): Boolean =
        !systemProperty("ro.miui.ui.version.name").isNullOrEmpty()

    private fun systemProperty(name: String): String? = try {
        val clazz = Class.forName("android.os.SystemProperties")
        val getter = clazz.getMethod("get", String::class.java)
        (getter.invoke(null, name) as? String)?.takeIf { it.isNotEmpty() }
    } catch (_: Exception) {
        null
    }

    private fun openSettings(activity: Activity, intent: Intent) {
        try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "settings intent failed: ${e.message}")
        }
    }

    // ---- launch / stop -------------------------------------------------

    fun onBoot(context: Context) {
        createChannel(context)
        val cfg = Config.load(context)
        reschedule(context)
        schedulePowerJobs(context)
        val charging = isCharging(context)
        Log.i(TAG, "boot launchOnBoot=${cfg.launchOnBoot} " +
            "launchOnPower=${cfg.launchOnPower} charging=$charging")
        if (cfg.launchOnBoot &&
            withinActiveHours(cfg) &&
            withinSchedule(cfg)
        ) {
            launchFrame(context, "boot")
        } else if (cfg.launchOnPower &&
            charging &&
            withinActiveHours(cfg) &&
            withinSchedule(cfg)
        ) {
            launchFrame(context, "boot+charging")
        }
    }

    fun launchFrame(context: Context, reason: String) {
        Log.i(TAG, "launch frame reason=$reason alive=${MainActivity.isAlive} " +
            "foreground=${MainActivity.isForeground}")
        if (MainActivity.isAlive && MainActivity.isForeground) {
            Log.i(TAG, "already showing; launch skipped")
            return
        }
        val intent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_START
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
        }
        if (MainActivity.isAlive) {
            // Running but not visible: fall through to the notification/alarm
            // path so the user can still get back to the frame if the OEM
            // blocks a direct bring-up.
            postLaunchNotification(context, intent)
            scheduleLaunchAlarm(context, intent)
            try {
                context.startActivity(intent)
            } catch (e: Exception) {
                Log.w(TAG, "foreground bring-up blocked: ${e.message}")
            }
            return
        }
        postLaunchNotification(context, intent)
        // A direct startActivity from a receiver/job is blocked on Android
        // 10+ ("Abort background activity starts"), even with overlay
        // permission on MIUI. A PendingIntent delivered by AlarmManager is
        // sent by the system, which is an explicit BAL exemption, so route
        // the launch through a one-shot alarm.
        scheduleLaunchAlarm(context, intent)
        // Best-effort direct start for OEMs that permit it; harmless if the
        // system rejects it (it is logged by ActivityTaskManager).
        try {
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "direct start failed: ${e.message}")
        }
    }

    private fun scheduleLaunchAlarm(context: Context, intent: Intent) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
        // Android 15+ no longer delegates the creator's BAL privileges to a
        // PendingIntent by default. Opt in explicitly so the system sender
        // (AlarmManager) can hand the launch through.
        val options = if (Build.VERSION.SDK_INT >= 35) {
            ActivityOptions.makeBasic()
                .setPendingIntentCreatorBackgroundActivityStartMode(
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
                )
                .toBundle()
        } else {
            null
        }
        val pending = PendingIntent.getActivity(
            context,
            LAUNCH_ALARM,
            intent,
            flags,
            options,
        )
        val at = System.currentTimeMillis() + 800
        try {
            if (Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms()) {
                // Without exact alarms this would be delayed for minutes and
                // setAlarmClock would leave a visible alarm icon; the
                // full-screen notification remains the fallback.
                Log.w(TAG, "launch alarm skipped: exact alarm not allowed")
                return
            } else if (Build.VERSION.SDK_INT >= 23) {
                am.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    at,
                    pending,
                )
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, at, pending)
            }
            Log.i(TAG, "launch alarm armed +800ms")
        } catch (e: Exception) {
            Log.w(TAG, "launch alarm failed: ${e.message}")
        }
    }

    fun stopFrame(context: Context, reason: String) {
        Log.i(TAG, "stop frame reason=$reason alive=${MainActivity.isAlive}")
        cancelLaunchNotification(context)
        context.sendBroadcast(
            Intent(ACTION_STOP).setPackage(context.packageName),
        )
    }

    private fun postLaunchNotification(context: Context, intent: Intent) {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "notifications denied; relying on direct start")
            return
        }
        createChannel(context)
        if (Build.VERSION.SDK_INT >= 34) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            Log.i(TAG, "canUseFullScreenIntent=${manager.canUseFullScreenIntent()}")
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
        val pending = PendingIntent.getActivity(
            context,
            NOTIFICATION_ID,
            intent,
            flags,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("HearthFrame")
            .setContentText("Starting photo frame")
            .setContentIntent(pending)
            .setFullScreenIntent(pending, true)
            .setCategory(Notification.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setOngoing(false)
            .apply {
                if (Build.VERSION.SDK_INT >= 26) setTimeoutAfter(15000)
            }
            .build()
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            nm.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.w(TAG, "notify failed: ${e.message}")
        }
    }

    fun cancelLaunchNotification(context: Context) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            nm.cancel(NOTIFICATION_ID)
        } catch (_: Exception) {
        }
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Frame automation",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Start the frame at boot, on power or on schedule"
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(channel)
    }

    // ---- schedule ------------------------------------------------------

    fun reschedule(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val cfg = Config.load(context)
        cancelAlarm(context, am, ALARM_START, ACTION_SCHEDULE_START)
        cancelAlarm(context, am, ALARM_END, ACTION_SCHEDULE_END)
        if (!cfg.schedule) {
            Log.i(TAG, "schedule disabled")
            return
        }
        val now = Calendar.getInstance()
        setAlarm(
            am,
            nextOccurrence(cfg.scheduleStart, now),
            ALARM_START,
            ACTION_SCHEDULE_START,
            context,
        )
        setAlarm(
            am,
            nextOccurrence(cfg.scheduleEnd, now),
            ALARM_END,
            ACTION_SCHEDULE_END,
            context,
        )
        Log.i(TAG, "schedule armed start=${formatMinutes(cfg.scheduleStart)} " +
            "end=${formatMinutes(cfg.scheduleEnd)}")
    }

    private fun setAlarm(
        am: AlarmManager,
        at: Calendar,
        requestCode: Int,
        action: String,
        context: Context,
    ) {
        val pending = alarmPending(context, requestCode, action)
        try {
            if (Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms()) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at.timeInMillis, pending)
            } else if (Build.VERSION.SDK_INT >= 23) {
                am.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    at.timeInMillis,
                    pending,
                )
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, at.timeInMillis, pending)
            }
            Log.i(TAG, "alarm $action at ${at.time}")
        } catch (e: Exception) {
            Log.w(TAG, "alarm $action failed: ${e.message}")
        }
    }

    private fun cancelAlarm(
        context: Context,
        am: AlarmManager,
        requestCode: Int,
        action: String,
    ) {
        am.cancel(alarmPending(context, requestCode, action))
    }

    private fun alarmPending(
        context: Context,
        requestCode: Int,
        action: String,
    ): PendingIntent {
        val intent = Intent(context, AutomationReceiver::class.java)
            .setAction(action)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
        return PendingIntent.getBroadcast(context, requestCode, intent, flags)
    }

    private fun nextOccurrence(minuteOfDay: Int, now: Calendar): Calendar {
        val c = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, minuteOfDay / 60)
            set(Calendar.MINUTE, minuteOfDay % 60)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (!c.after(now)) c.add(Calendar.DAY_OF_YEAR, 1)
        return c
    }

    fun schedulePowerJobs(context: Context) {
        val cfg = Config.load(context)
        val js = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
        if (!cfg.launchOnPower) {
            js.cancel(JOB_POWER_ONESHOT)
            js.cancel(JOB_POWER_PERIODIC)
            Log.i(TAG, "charging job disabled")
            return
        }
        try {
            // Re-adding a charging-constrained periodic job while the device
            // is charging makes it run immediately. Keep the existing job
            // instead: it already has the constraint we need.
            val periodicExists = Build.VERSION.SDK_INT >= 24 &&
                js.getPendingJob(JOB_POWER_PERIODIC) != null
            if (!periodicExists) {
                // Safety net: if the process was killed while plugged in,
                // retry while charging. 15 min is the platform minimum.
                val periodic = JobInfo.Builder(
                    JOB_POWER_PERIODIC,
                    ComponentName(context, PowerJobService::class.java),
                )
                    .setRequiresCharging(true)
                    .setPersisted(true)
                    .setPeriodic(15 * 60 * 1000L)
                    .build()
                js.schedule(periodic)
            }
            val oneshotExists = Build.VERSION.SDK_INT >= 24 &&
                js.getPendingJob(JOB_POWER_ONESHOT) != null
            if (!isCharging(context) && !oneshotExists) {
                // Fires as soon as charging starts; avoids the up-to-15-minute
                // delay of the periodic safety net on a cold plug-in.
                val oneshot = JobInfo.Builder(
                    JOB_POWER_ONESHOT,
                    ComponentName(context, PowerJobService::class.java),
                )
                    .setRequiresCharging(true)
                    .setPersisted(true)
                    .build()
                js.schedule(oneshot)
            }
            Log.i(TAG, "charging jobs armed charging=${isCharging(context)}")
        } catch (e: Exception) {
            Log.w(TAG, "schedulePowerJobs failed: ${e.message}")
        }
    }

    // ---- helpers -------------------------------------------------------

    fun isCharging(context: Context): Boolean {
        return try {
            val battery = context.registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED),
            )
            val plugged = battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
            // FULL is also reported on an unplugged 100% battery, so the
            // plugged flag is the only reliable signal for "on power".
            plugged != 0
        } catch (_: Exception) {
            false
        }
    }

    fun withinActiveHours(cfg: Config): Boolean {
        if (!cfg.activeHours) return true
        return inWindow(cfg.activeStart, cfg.activeEnd)
    }

    /**
     * Whether the daily schedule is currently in its "on" window. A finished
     * schedule must also gate charging launches, otherwise the charging job
     * would immediately reopen the frame after the 23:00 stop.
     */
    fun withinSchedule(cfg: Config): Boolean {
        if (!cfg.schedule) return true
        return inWindow(cfg.scheduleStart, cfg.scheduleEnd)
    }

    private fun inWindow(start: Int, end: Int): Boolean {
        val now = Calendar.getInstance().let {
            it.get(Calendar.HOUR_OF_DAY) * 60 + it.get(Calendar.MINUTE)
        }
        return when {
            start == end -> true
            start < end -> now in start until end
            else -> now >= start || now < end
        }
    }

    fun formatMinutes(value: Int): String =
        "%02d:%02d".format(value / 60, value % 60)
}

/** Receives daily schedule alarms and time/package changes. */
class AutomationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            FrameAutomation.ACTION_SCHEDULE_START -> {
                FrameAutomation.launchFrame(context, "schedule")
                FrameAutomation.reschedule(context)
            }
            FrameAutomation.ACTION_SCHEDULE_END -> {
                FrameAutomation.stopFrame(context, "schedule")
                FrameAutomation.reschedule(context)
            }
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                FrameAutomation.reschedule(context)
                FrameAutomation.schedulePowerJobs(context)
            }
        }
    }
}

/**
 * Charging-constrained job. The one-shot job fires on a cold plug-in; the
 * periodic job recovers after the process was killed while plugged in.
 */
class PowerJobService : JobService() {
    override fun onStartJob(params: JobParameters?): Boolean {
        val cfg = FrameAutomation.Config.load(this)
        if (cfg.launchOnPower &&
            FrameAutomation.withinActiveHours(cfg) &&
            FrameAutomation.withinSchedule(cfg) &&
            !MainActivity.isAlive
        ) {
            FrameAutomation.launchFrame(this, "charging-job")
        }
        // Do NOT re-arm jobs here: cancelling and rescheduling a charging
        // periodic job while the device is charging makes it run again
        // immediately, which turns into a busy loop. The periodic job repeats
        // on its own; the one-shot is re-armed on unplug / app exit.
        jobFinished(params, false)
        return false
    }

    override fun onStopJob(params: JobParameters?): Boolean = false
}
