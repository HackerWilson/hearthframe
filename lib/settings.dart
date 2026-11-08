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

  /// Seconds each slide is shown.
  int get intervalSeconds => _prefs.getInt(_kInterval) ?? 8;

  /// Cross-fade duration in milliseconds.
  int get transitionMs => _prefs.getInt(_kTransition) ?? 600;

  bool get shuffle => _prefs.getBool(_kShuffle) ?? true;
  bool get showClock => _prefs.getBool(_kClock) ?? true;
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

  Future<void> _set(String key, Object v) async {
    if (v is int) await _prefs.setInt(key, v);
    if (v is bool) await _prefs.setBool(key, v);
    if (v is String) await _prefs.setString(key, v);
    notifyListeners();
  }

  static Future<FrameSettings> load() async =>
      FrameSettings(await SharedPreferences.getInstance());
}
