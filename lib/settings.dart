import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-tunable frame settings, persisted with shared_preferences.
/// Only the "core + useful" set is kept, by design. Credentials live only in
/// on-device preferences; nothing is hard-coded into the source tree.
class FrameSettings extends ChangeNotifier {
  FrameSettings(this._prefs);

  final SharedPreferences _prefs;

  static const _kInterval = 'interval_seconds';
  static const _kTransition = 'transition_ms';
  static const _kShuffle = 'shuffle';
  static const _kClock = 'show_clock';
  static const _kMediaDate = 'show_media_date';
  static const _kAwake = 'keep_awake';
  static const _kFill = 'fill_screen';
  static const _kMotion = 'motion_effect';
  static const _kFolder = 'source_folder';
  static const _kSourceType = 'source_type';
  static const _kSetupMode = 'setup_mode';
  static const _kDavUrl = 'webdav_url';
  static const _kDavUser = 'webdav_user';
  static const _kDavPass = 'webdav_pass';
  static const _kDavPath = 'webdav_path';
  static const _kSmbHost = 'smb_host';
  static const _kSmbDomain = 'smb_domain';
  static const _kSmbUser = 'smb_user';
  static const _kSmbPass = 'smb_pass';
  static const _kSmbPath = 'smb_path';
  static const _kLanguage = 'language';
  static const _kClockFormat = 'clock_format';
  static const _kTransitionStyle = 'transition_style';
  static const _kSeenHint = 'seen_hint';
  static const _kLaunchOnBoot = 'auto_launch_boot';
  static const _kLaunchOnPower = 'auto_launch_power';
  static const _kExitOnPowerLoss = 'auto_exit_power';
  static const _kActiveHours = 'auto_active_hours';
  static const _kActiveStart = 'auto_active_start';
  static const _kActiveEnd = 'auto_active_end';
  static const _kSchedule = 'auto_schedule';
  static const _kScheduleStart = 'auto_schedule_start';
  static const _kScheduleEnd = 'auto_schedule_end';
  static const _kVideoMuted = 'video_muted';
  static const _kRecentWeighted = 'recent_weighted';
  static const _kClockBackground = 'clock_background';
  static const _kClockScale = 'clock_scale';
  static const _kMotionSpeed = 'motion_speed';

  /// Seconds each slide is shown.
  int get intervalSeconds => _prefs.getInt(_kInterval) ?? 30;

  /// Cross-fade duration in milliseconds.
  int get transitionMs => _prefs.getInt(_kTransition) ?? 600;

  bool get shuffle => _prefs.getBool(_kShuffle) ?? true;
  bool get showClock => _prefs.getBool(_kClock) ?? true;
  bool get showMediaDate => _prefs.getBool(_kMediaDate) ?? true;
  bool get keepAwake => _prefs.getBool(_kAwake) ?? true;

  /// True: photos crop to fill the screen (frame style). False: the whole
  /// photo is shown over a blurred backdrop.
  bool get fillScreen => _prefs.getBool(_kFill) ?? true;

  /// Slow Ken Burns zoom/pan on still photos (frame-style motion).
  bool get motion => _prefs.getBool(_kMotion) ?? true;

  /// Local source folder (empty = not configured).
  String get sourceFolder => _prefs.getString(_kFolder) ?? '';

  /// One of: 'local', 'webdav', 'smb'.
  String get sourceType => _prefs.getString(_kSourceType) ?? 'local';

  /// When true the setup screen is shown even if a source is configured.
  bool get setupMode => _prefs.getBool(_kSetupMode) ?? false;

  String get webdavUrl => _prefs.getString(_kDavUrl) ?? '';
  String get webdavUser => _prefs.getString(_kDavUser) ?? '';
  String get webdavPass => _prefs.getString(_kDavPass) ?? '';
  String get webdavPath => _prefs.getString(_kDavPath) ?? '';

  String get smbHost => _prefs.getString(_kSmbHost) ?? '';
  String get smbDomain => _prefs.getString(_kSmbDomain) ?? '';
  String get smbUser => _prefs.getString(_kSmbUser) ?? '';
  String get smbPass => _prefs.getString(_kSmbPass) ?? '';
  String get smbPath => _prefs.getString(_kSmbPath) ?? '';

  /// 'system', 'en' or 'zh'.
  String get language => _prefs.getString(_kLanguage) ?? 'system';

  /// 'auto', '24' or '12'.
  String get clockFormat => _prefs.getString(_kClockFormat) ?? 'auto';

  /// 'fade', 'slide' or 'zoom'.
  String get transitionStyle => _prefs.getString(_kTransitionStyle) ?? 'fade';

  /// True once the first-run gesture hint has been shown.
  bool get seenHint => _prefs.getBool(_kSeenHint) ?? false;

  // ---- Automation (Android; native layer does the actual scheduling) ----

  bool get launchOnBoot => _prefs.getBool(_kLaunchOnBoot) ?? false;
  bool get launchOnPower => _prefs.getBool(_kLaunchOnPower) ?? false;
  bool get exitOnPowerLoss => _prefs.getBool(_kExitOnPowerLoss) ?? false;

  /// Restrict power/boot auto-starts to the active-hours window.
  bool get activeHours => _prefs.getBool(_kActiveHours) ?? false;

  /// Minutes after midnight.
  int get activeStart => _prefs.getInt(_kActiveStart) ?? 7 * 60;
  int get activeEnd => _prefs.getInt(_kActiveEnd) ?? 23 * 60;

  /// Daily start/stop schedule (independent of the active-hours gate).
  bool get schedule => _prefs.getBool(_kSchedule) ?? false;
  int get scheduleStart => _prefs.getInt(_kScheduleStart) ?? 7 * 60;
  int get scheduleEnd => _prefs.getInt(_kScheduleEnd) ?? 23 * 60;

  bool get hasAutomation =>
      launchOnBoot || launchOnPower || exitOnPowerLoss || schedule;

  /// Videos play muted by default, matching the frame use case.
  bool get videoMuted => _prefs.getBool(_kVideoMuted) ?? true;

  /// Bias the shuffle toward recently modified media.
  bool get recentWeighted => _prefs.getBool(_kRecentWeighted) ?? true;

  bool get clockBackground => _prefs.getBool(_kClockBackground) ?? false;

  /// Clock size multiplier.
  double get clockScale => _prefs.getDouble(_kClockScale) ?? 1.0;

  /// Ken Burns speed multiplier.
  double get motionSpeed => _prefs.getDouble(_kMotionSpeed) ?? 1.0;

  /// Whether the active source has enough configuration to run.
  bool get isConfigured {
    switch (sourceType) {
      case 'webdav':
        return webdavUrl.isNotEmpty && webdavPath.isNotEmpty;
      case 'smb':
        return smbHost.isNotEmpty && smbPath.isNotEmpty;
      default:
        return sourceFolder.isNotEmpty;
    }
  }

  Future<void> setIntervalSeconds(int v) => _set(_kInterval, v);
  Future<void> setTransitionMs(int v) => _set(_kTransition, v);
  Future<void> setShuffle(bool v) => _set(_kShuffle, v);
  Future<void> setShowClock(bool v) => _set(_kClock, v);
  Future<void> setShowMediaDate(bool v) => _set(_kMediaDate, v);
  Future<void> setKeepAwake(bool v) => _set(_kAwake, v);
  Future<void> setFillScreen(bool v) => _set(_kFill, v);
  Future<void> setMotion(bool v) => _set(_kMotion, v);
  Future<void> setSourceFolder(String v) => _set(_kFolder, v);
  Future<void> setSourceType(String v) => _set(_kSourceType, v);
  Future<void> setSetupMode(bool v) => _set(_kSetupMode, v);
  Future<void> setWebdavUrl(String v) => _set(_kDavUrl, v);
  Future<void> setWebdavUser(String v) => _set(_kDavUser, v);
  Future<void> setWebdavPass(String v) => _set(_kDavPass, v);
  Future<void> setWebdavPath(String v) => _set(_kDavPath, v);
  Future<void> setSmbHost(String v) => _set(_kSmbHost, v);
  Future<void> setSmbDomain(String v) => _set(_kSmbDomain, v);
  Future<void> setSmbUser(String v) => _set(_kSmbUser, v);
  Future<void> setSmbPass(String v) => _set(_kSmbPass, v);
  Future<void> setSmbPath(String v) => _set(_kSmbPath, v);
  Future<void> setLanguage(String v) => _set(_kLanguage, v);
  Future<void> setClockFormat(String v) => _set(_kClockFormat, v);
  Future<void> setTransitionStyle(String v) => _set(_kTransitionStyle, v);
  Future<void> setSeenHint(bool v) => _set(_kSeenHint, v);
  Future<void> setLaunchOnBoot(bool v) => _set(_kLaunchOnBoot, v);
  Future<void> setLaunchOnPower(bool v) => _set(_kLaunchOnPower, v);
  Future<void> setExitOnPowerLoss(bool v) => _set(_kExitOnPowerLoss, v);
  Future<void> setActiveHours(bool v) => _set(_kActiveHours, v);
  Future<void> setActiveStart(int v) => _set(_kActiveStart, v);
  Future<void> setActiveEnd(int v) => _set(_kActiveEnd, v);
  Future<void> setSchedule(bool v) => _set(_kSchedule, v);
  Future<void> setScheduleStart(int v) => _set(_kScheduleStart, v);
  Future<void> setScheduleEnd(int v) => _set(_kScheduleEnd, v);
  Future<void> setVideoMuted(bool v) => _set(_kVideoMuted, v);
  Future<void> setRecentWeighted(bool v) => _set(_kRecentWeighted, v);
  Future<void> setClockBackground(bool v) => _set(_kClockBackground, v);
  Future<void> setClockScale(double v) => _set(_kClockScale, v);
  Future<void> setMotionSpeed(double v) => _set(_kMotionSpeed, v);

  /// Values mirrored to the native automation layer. Native code must be able
  /// to act without Flutter running (boot, charging, alarms), so this is
  /// pushed to its own SharedPreferences file on every change.
  Map<String, Object> get automationConfig => {
        'launchOnBoot': launchOnBoot,
        'launchOnPower': launchOnPower,
        'exitOnPowerLoss': exitOnPowerLoss,
        'activeHours': activeHours,
        'activeStart': activeStart,
        'activeEnd': activeEnd,
        'schedule': schedule,
        'scheduleStart': scheduleStart,
        'scheduleEnd': scheduleEnd,
      };

  Future<void> _set(String key, Object v) async {
    if (v is int) await _prefs.setInt(key, v);
    if (v is bool) await _prefs.setBool(key, v);
    if (v is double) await _prefs.setDouble(key, v);
    if (v is String) await _prefs.setString(key, v);
    notifyListeners();
  }

  static Future<FrameSettings> load() async =>
      FrameSettings(await SharedPreferences.getInstance());
}
