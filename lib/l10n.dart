import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Language options exposed in the UI.
enum AppLanguage { system, english, chinese }

AppLanguage parseAppLanguage(String? value) => switch (value) {
      'en' => AppLanguage.english,
      'zh' => AppLanguage.chinese,
      _ => AppLanguage.system,
    };

String appLanguageValue(AppLanguage language) => switch (language) {
      AppLanguage.system => 'system',
      AppLanguage.english => 'en',
      AppLanguage.chinese => 'zh',
    };

/// Lightweight localization for HearthFrame.
///
/// English is the template; Chinese lives next to it so translators can see
/// both languages in one place. Date and time formatting is delegated to the
/// Material localizations, which are locale-aware and follow the system
/// 12/24-hour preference.
class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;

  bool get isZh => locale.languageCode == 'zh';

  String _s(String en, String zh) => isZh ? zh : en;

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings)!;

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  // Brand and setup hero
  String get appName => 'HearthFrame';
  String get tagline =>
      _s('Turn this device into a family photo frame.', '把这台设备变成家庭相框。');
  String get heroTitle =>
      _s('Your family photos,\nalways on.', '家人的照片，\n一直亮着。');
  String get heroBody => _s(
        'A quiet, always-on frame for the photos and short videos you already have. No account, no cloud, no distractions.',
        '把现有的照片和短视频安静地轮播出来。不需要账号，不依赖云服务，也没有多余打扰。',
      );
  String get featurePhotos => _s('Photos and videos', '照片和视频');
  String get featurePhotosBody =>
      _s('One slideshow for stills and short clips.', '照片和短视频在同一个轮播里。');
  String get featureStorage => _s('Your own storage', '用你自己的存储');
  String get featureStorageBody => _s(
        'Local folders, WebDAV or SMB — nothing leaves your network.',
        '本地文件夹、WebDAV 或 SMB，数据不出你的网络。',
      );
  String get featureAlwaysOn => _s('Made to stay on', '为长期显示而做');
  String get featureAlwaysOnBody => _s(
        'Instant restarts, cached media and a calm clock.',
        '快速启动、本地缓存，还有安静的时钟。',
      );

  // Setup form
  String get connectTitle => _s('Connect a photo source', '连接照片来源');
  String get connectBody => _s(
        'Choose where your photos live. You can switch sources at any time.',
        '选择照片所在的位置，之后随时可以更换。',
      );
  String get photoSource => _s('Photo source', '照片来源');
  String get localFolder => _s('Local folder', '本地文件夹');
  String get localFolderDesc => _s('On this device', '平板本机');
  String get webdav => 'WebDAV';
  String get webdavDesc => _s('Synology, Nextcloud…', '群晖、Nextcloud…');
  String get smb => 'SMB / CIFS';
  String get smbDesc => _s('NAS shares', '局域网 NAS');
  String get folderPath => _s('Folder path', '文件夹路径');
  String get allFilesGranted => _s('All-files access granted', '已获得所有文件访问权限');
  String get allFilesNeeded => _s('Needs all-files access', '需要所有文件访问权限');
  String get grant => _s('Grant', '授权');
  String get serverUrl => _s('Server URL', '服务器地址');
  String get username => _s('Username', '用户名');
  String get password => _s('Password', '密码');
  String get showPassword => _s('Show password', '显示密码');
  String get hidePassword => _s('Hide password', '隐藏密码');
  String get host => _s('Host', '主机');
  String get domainOptional => _s('Domain (optional)', '域（可选）');
  String get sharePath => _s('Share path', '共享路径');
  String get setupNote => _s(
        'Photos and short videos play full screen. Network sources are cached on this device as they play.',
        '照片和短视频全屏播放；网络来源会在播放时缓存到本机。',
      );
  String get startFrame => _s('Start photo frame', '开始播放');
  String get starting => _s('Starting…', '正在启动…');
  String get back => _s('Back', '返回');
  String get backToFrame => _s('Back to frame', '返回相框');
  String get language => _s('Language', '语言');
  String get systemDefault => _s('System', '跟随系统');
  String get english => 'English';
  String get chinese => '简体中文';

  // Field hints
  String get hintLocalPath => '/storage/emulated/0/Pictures';
  String get hintServerUrl => 'https://nas.local:5006';
  String get hintFolderPath => '/photo/family';
  String get hintUsername => _s('username', '用户名');
  String get hintPassword => _s('password', '密码');
  String get hintHost => '192.168.1.20';
  String get hintDomain => 'WORKGROUP';
  String get hintSharePath => '/photo/family';

  // Validation and errors
  String get errFolder => _s('Enter a folder path.', '请输入文件夹路径。');
  String get errPermission => _s(
        'All-files access is required to read this folder.',
        '需要所有文件访问权限才能读取这个文件夹。',
      );
  String get errWebdav => _s(
        'WebDAV needs a server URL and a folder path.',
        'WebDAV 需要服务器地址和文件夹路径。',
      );
  String get errSmb => _s(
        'SMB needs a host and a share path (e.g. /photo/family).',
        'SMB 需要主机和共享路径（例如 /photo/family）。',
      );
  String get noMedia =>
      _s('No photos or videos found in this source.', '这个来源里没有找到照片或视频。');
  String get couldNotLoad => _s('Could not load this source.', '无法加载这个来源。');
  String get retry => _s('Retry', '重试');
  String get changeSource => _s('Change source', '更换来源');
  String get loading => _s('Loading…', '正在加载…');

  // Slideshow controls
  String get previous => _s('Previous', '上一张');
  String get pause => _s('Pause', '暂停');
  String get play => _s('Play', '播放');
  String get next => _s('Next', '下一张');
  String get refresh => _s('Refresh', '刷新');
  String get settings => _s('Settings', '设置');
  String get mediaDetails => _s('Media details', '媒体详情');
  String get loadingMedia => _s('Loading media', '正在加载媒体');
  String get skipMedia => _s('Skip', '跳过');
  String get mediaOrderUpdated => _s('Playback order updated', '播放顺序已更新');
  String get photo => _s('Photo', '照片');
  String get video => _s('Video', '视频');
  String get videoProgress => _s('Video progress', '视频进度');
  String get videoUnavailable =>
      _s('This video cannot be played on this device.', '此设备无法播放该视频');

  // Read-only media details
  String get originalFilename => _s('Original filename', '原文件名');
  String get mediaDate => _s('Date', '日期');
  String get mediaType => _s('Media type', '媒体类型');
  String get sourceType => _s('Source type', '来源类型');
  String get originalFilePath => _s('Local / original path', '本地 / 原始文件路径');
  String get fileSize => _s('File size', '文件大小');
  String get unknown => _s('Unknown', '未知');
  String get mediaDateSources => _s(
        'Date uses capture metadata when available, then the filename or folder, then the source file’s modified date.',
        '日期优先采用拍摄元数据，其次为文件名或目录日期，最后为源文件修改日期。',
      );
  String mediaBytes(int bytes) => _s('$bytes B', '$bytes 字节');
  String get gestureHint =>
      _s('Swipe to browse · Tap for controls', '左右滑动切换 · 点击显示控制');

  // Settings sheet
  String get settingsTitle => _s('Settings', '设置');
  String get sectionSlideshow => _s('Slideshow', '轮播');
  String get slideDuration => _s('Slide duration', '停留时长');
  String get durationSliderHint => _s(
        'Choose a preset of 60 s or less to use the 3–60 s slider.',
        '选择不超过 60 秒的快捷时长，即可使用 3–60 秒滑杆。',
      );
  String get transition => _s('Transition', '转场');
  String get transitionStyle => _s('Style', '样式');
  String get fade => _s('Fade', '淡化');
  String get slideTransition => _s('Slide', '滑动');
  String get zoom => _s('Zoom', '缩放');
  String get shuffle => _s('Shuffle', '随机播放');
  String get sectionAppearance => _s('Appearance', '外观');
  String get showMediaDate => _s('Show photo/video date', '显示照片/视频日期');
  String get showMediaDateDesc => _s(
        'Watermark text at the bottom left, no background plate: capture date, then filename/folder date, then the source file’s modified date.',
        '左下角水印文字（无背景板）：优先拍摄日期，其次文件名/目录日期，最后源文件修改日期。',
      );
  String get showClock => _s('Show clock', '显示时钟');
  String get showClockDesc => _s('Time and date in the corner.', '在角落显示时间和日期。');
  String get timeFormat => _s('Time format', '时间格式');
  String get auto => _s('Auto', '跟随系统');
  String get hour24 => _s('24-hour', '24 小时');
  String get hour12 => _s('12-hour', '12 小时');
  String get fillScreen => _s('Fill screen', '铺满屏幕');
  String get fillScreenDesc => _s(
        'Crop photos to the edges. Off shows the whole photo over a blurred backdrop.',
        '裁剪照片铺满屏幕；关闭后完整显示照片，并加模糊背景。',
      );
  String get motion => _s('Motion effect', '动态效果');
  String get motionDesc =>
      _s('Slow Ken Burns zoom and pan on photos.', '照片缓慢缩放平移（Ken Burns）。');
  String get motionSpeed => _s('Motion speed', '动态速度');
  String get videoMuted => _s('Mute videos', '视频静音');
  String get videoMutedDesc => _s('Play videos without sound.', '播放视频时不发出声音。');
  String get recentWeighted => _s('Favor recent media', '偏向近期内容');
  String get recentWeightedDesc => _s(
        'When shuffling, newer photos and videos appear more often.',
        '随机播放时较新的照片和视频出现得更频繁。',
      );
  String get clockBackground => _s('Clock backdrop', '时钟背景板');
  String get clockBackgroundDesc =>
      _s('A soft translucent panel behind the time.', '在时间后面加一层柔和半透明背景。');
  String get clockSize => _s('Clock size', '时钟大小');
  String percent(int value) => '$value%';
  String get sectionAutomation => _s('Automation', '自动化');
  String get launchOnBoot => _s('Launch at startup', '开机自动启动');
  String get launchOnBootDesc =>
      _s('Open the frame when the device finishes booting.', '设备开机完成后自动打开相框。');
  String get launchOnPower => _s('Launch when charging', '接通电源自动启动');
  String get launchOnPowerDesc =>
      _s('Open the frame when power is connected.', '连接电源时自动打开相框。');
  String get exitOnPowerLoss => _s('Exit when unplugged', '断开电源自动退出');
  String get exitOnPowerLossDesc =>
      _s('Close the frame when the charger is removed.', '拔掉电源时关闭相框。');
  String get activeHours => _s('Active hours', '使用时段');
  String get activeHoursDesc =>
      _s('Only auto-start within this window.', '仅在该时段内自动启动。');
  String get dailySchedule => _s('Daily schedule', '每日定时');
  String get dailyScheduleDesc => _s(
        'Start and stop the frame automatically every day.',
        '每天自动开始播放并在结束时退出。',
      );
  String get startTime => _s('Start', '开始');
  String get endTime => _s('End', '结束');
  String get backgroundPermissions => _s('Background permissions', '后台运行权限');
  String get backgroundPermissionsAll => _s('All granted', '已全部授予');
  String get backgroundPermissionsHint => _s(
        'MIUI/HyperOS may also require Autostart and background pop-up permission in system settings.',
        'MIUI/HyperOS 可能还需要在系统设置中允许「自启动」和「后台弹出界面」。',
      );
  String get permissionNotifications => _s('Notifications', '通知');
  String get permissionOverlay => _s('Display over other apps', '显示在其他应用上层');
  String get permissionExact => _s('Exact alarms', '精确闹钟');
  String get permissionFullScreen => _s('Full-screen notifications', '全屏通知');
  String get oemStartup => _s('System autostart', '系统自启动');
  String get oemStartupDesc => _s(
        'MIUI/HyperOS: allow HearthFrame to start automatically.',
        'MIUI/HyperOS：允许 HearthFrame 自启动。',
      );
  String get oemBackgroundPopup => _s('Background pop-up', '后台弹出界面');
  String get oemBackgroundPopupDesc => _s(
        'Other permissions → Background pop-up → Always allow. Required for the frame to come back on screen.',
        '进入「其他权限 → 后台弹出界面」并选择「始终允许」，否则相框无法从后台回到前台。',
      );
  String get open => _s('Open', '打开');
  String get sectionSystem => _s('System', '系统');
  String get keepAwake => _s('Keep screen on', '保持屏幕常亮');
  String get keepAwakeDesc =>
      _s('Prevents the display from sleeping in frame mode.', '相框模式下阻止屏幕休眠。');
  String get sectionStorage => _s('Storage', '存储');
  String get mediaCache => _s('Media cache', '媒体缓存');
  String get mediaCacheDesc => _s(
        'Downloaded media for instant replay. The oldest files are removed automatically to stay under 1.5 GB.',
        '已下载的媒体用于快速重播；超过 1.5 GB 时自动删除最旧的文件。',
      );
  String get clearCache => _s('Clear', '清空');
  String get sectionAbout => _s('About', '关于');
  String get version => _s('Version', '版本');
  String get projectPage => _s('Project page', '项目主页');
  String get done => _s('Done', '完成');

  String seconds(int value) => _s('$value s', '$value 秒');
  String milliseconds(int value) => _s('$value ms', '$value 毫秒');
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'zh';

  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture<AppStrings>(AppStrings(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppStrings> old) => false;
}
