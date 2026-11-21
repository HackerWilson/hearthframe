import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'automation.dart';
import 'l10n.dart';
import 'media_cache.dart';
import 'settings.dart';
import 'theme.dart';

enum _SettingsCategory {
  slideshow,
  appearance,
  automation,
  system,
  storage,
  about,
}

/// Responsive category settings panel. Changes apply immediately to the frame.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.settings, this.onChanged});

  final FrameSettings settings;
  final ValueChanged<FrameSettings>? onChanged;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet>
    with WidgetsBindingObserver {
  FrameSettings get settings => widget.settings;
  ValueChanged<FrameSettings>? get onChanged => widget.onChanged;

  void _changed() => onChanged?.call(settings);

  int? _cacheBytes;
  bool _clearing = false;
  AutomationStatus? _automation;
  bool _permissionBusy = false;
  String? _appVersion;
  _SettingsCategory _category = _SettingsCategory.slideshow;
  final _contentScrollController = ScrollController(keepScrollOffset: false);

  Future<void> _loadAppVersion() async {
    var version = '—';
    try {
      final value = await const MethodChannel('hearthframe/device')
          .invokeMethod<String>('appVersion');
      if (value != null && value.trim().isNotEmpty) version = value.trim();
    } catch (_) {
      // Unsupported platforms and unavailable native metadata show a placeholder.
    }
    if (mounted) setState(() => _appVersion = version);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshCache();
    _refreshAutomation();
    _loadAppVersion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _contentScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from a system permission screen must refresh the summary.
    if (state == AppLifecycleState.resumed) _refreshAutomation();
  }

  Future<void> _refreshAutomation() async {
    if (!Platform.isAndroid) return;
    final status = await AutomationService.status();
    if (mounted) setState(() => _automation = status);
  }

  Future<void> _grantPermission() async {
    setState(() => _permissionBusy = true);
    final step = await AutomationService.requestNextPermission();
    debugPrint('HF automation permission step=$step');
    // Runtime dialogs return immediately; settings screens resume the app,
    // which also triggers a refresh via the lifecycle observer.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await _refreshAutomation();
    if (mounted) setState(() => _permissionBusy = false);
  }

  String _permissionSubtitle(AppStrings s) {
    final status = _automation;
    if (status == null) return s.loading;
    if (status.complete) return s.backgroundPermissionsAll;
    final missing = <String>[
      if (!status.notifications) s.permissionNotifications,
      if (!status.overlay) s.permissionOverlay,
      if (!status.exactAlarms) s.permissionExact,
      if (!status.fullScreen) s.permissionFullScreen,
    ];
    return '${status.grantedCount}/4 · ${missing.join(' · ')}';
  }

  Future<void> _openOemStartup() async {
    await AutomationService.openOemStartupSettings();
  }

  Future<void> _openOemPopup() async {
    await AutomationService.openOemPermissionEditor();
  }

  String _timeLabel(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  Future<void> _pickTime(
    int current,
    Future<void> Function(int minutes) apply,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    await apply(picked.hour * 60 + picked.minute);
    _changed();
  }

  Future<void> _refreshCache() async {
    final bytes = await mediaCacheBytes();
    if (mounted) setState(() => _cacheBytes = bytes);
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    await clearMediaCache();
    if (!mounted) return;
    await _refreshCache();
    if (mounted) setState(() => _clearing = false);
  }

  String _categoryLabel(_SettingsCategory category, AppStrings s) =>
      switch (category) {
        _SettingsCategory.slideshow => s.sectionSlideshow,
        _SettingsCategory.appearance => s.sectionAppearance,
        _SettingsCategory.automation => s.sectionAutomation,
        _SettingsCategory.system => s.sectionSystem,
        _SettingsCategory.storage => s.sectionStorage,
        _SettingsCategory.about => s.sectionAbout,
      };

  IconData _categoryIcon(_SettingsCategory category) => switch (category) {
        _SettingsCategory.slideshow => Icons.slideshow_rounded,
        _SettingsCategory.appearance => Icons.palette_outlined,
        _SettingsCategory.automation => Icons.schedule_rounded,
        _SettingsCategory.system => Icons.tune_rounded,
        _SettingsCategory.storage => Icons.storage_rounded,
        _SettingsCategory.about => Icons.info_outline_rounded,
      };

  void _selectCategory(_SettingsCategory category) {
    if (_category == category) return;
    if (_contentScrollController.hasClients) _contentScrollController.jumpTo(0);
    setState(() => _category = category);
  }

  Widget _categoryNavigation(AppStrings s, {required bool wide}) {
    final categories = _SettingsCategory.values.where(
      (category) =>
          category != _SettingsCategory.automation || Platform.isAndroid,
    );
    if (!wide) {
      return SingleChildScrollView(
        key: const ValueKey('settings-horizontal-categories'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            for (final category in categories)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: ValueKey('settings-category-${category.name}'),
                  avatar: Icon(_categoryIcon(category), size: 18),
                  label: Text(_categoryLabel(category, s)),
                  selected: _category == category,
                  showCheckmark: false,
                  onSelected: (_) => _selectCategory(category),
                ),
              ),
          ],
        ),
      );
    }
    return SizedBox(
      key: const ValueKey('settings-sidebar'),
      width: 208,
      child: ListView(
        primary: false,
        padding: const EdgeInsets.all(12),
        children: [
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                key: ValueKey('settings-category-${category.name}'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(_categoryIcon(category), size: 21),
                title: Text(_categoryLabel(category, s)),
                selected: _category == category,
                selectedColor: HearthPalette.primary,
                selectedTileColor: HearthPalette.card,
                onTap: () => _selectCategory(category),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.hasBoundedWidth
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width,
          height: constraints.hasBoundedHeight
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height,
          child: Material(
            color: HearthPalette.panel,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.settingsTitle,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('settings-close'),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: s.done,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 700;
                        final content = Scrollbar(
                          controller: _contentScrollController,
                          child: SingleChildScrollView(
                            key: const ValueKey('settings-content'),
                            controller: _contentScrollController,
                            padding: EdgeInsets.fromLTRB(
                              wide ? 28 : 20,
                              12,
                              wide ? 28 : 20,
                              24,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _SectionHeader(_categoryLabel(_category, s)),
                                const SizedBox(height: 12),
                                ..._categoryOptions(s),
                              ],
                            ),
                          ),
                        );
                        if (wide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _categoryNavigation(s, wide: true),
                              const VerticalDivider(width: 1),
                              Expanded(child: content),
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _categoryNavigation(s, wide: false),
                            const Divider(height: 1),
                            Expanded(child: content),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _categoryOptions(AppStrings s) => switch (_category) {
        _SettingsCategory.slideshow => _slideshowOptions(s),
        _SettingsCategory.appearance => _appearanceOptions(s),
        _SettingsCategory.automation => _automationOptions(s),
        _SettingsCategory.system => _systemOptions(s),
        _SettingsCategory.storage => [
            _CacheRow(
              title: s.mediaCache,
              subtitle: s.mediaCacheDesc,
              value:
                  _cacheBytes == null ? s.loading : formatBytes(_cacheBytes!),
              action: s.clearCache,
              busy: _clearing,
              onClear:
                  (_cacheBytes ?? 0) > 0 && !_clearing ? _clearCache : null,
            ),
          ],
        _SettingsCategory.about => [
            _InfoRow(label: s.version, value: _appVersion ?? s.loading),
            const _InfoRow(
                label: '', value: 'github.com/HackerWilson/hearthframe'),
          ],
      };

  List<Widget> _slideshowOptions(AppStrings s) => [
        _SliderRow(
          label: s.slideDuration,
          valueLabel: s.seconds(settings.intervalSeconds),
          value: settings.intervalSeconds.toDouble(),
          min: 3,
          max: 60,
          divisions: 57,
          showSlider:
              settings.intervalSeconds >= 3 && settings.intervalSeconds <= 60,
          onChanged: (v) async {
            await settings.setIntervalSeconds(v.round());
            _changed();
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final seconds in [10, 15, 30, 60, 300, 600])
              ChoiceChip(
                key: ValueKey('settings-duration-$seconds'),
                label: Text(s.seconds(seconds)),
                selected: settings.intervalSeconds == seconds,
                showCheckmark: false,
                onSelected: (_) async {
                  await settings.setIntervalSeconds(seconds);
                  _changed();
                },
              ),
          ],
        ),
        if (settings.intervalSeconds < 3 || settings.intervalSeconds > 60)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              s.durationSliderHint,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
        const SizedBox(height: 12),
        _Segmented(
          label: s.transitionStyle,
          value: settings.transitionStyle,
          options: {'fade': s.fade, 'slide': s.slideTransition, 'zoom': s.zoom},
          onChanged: (v) async {
            await settings.setTransitionStyle(v);
            _changed();
          },
        ),
        _SwitchRow(
          title: s.shuffle,
          value: settings.shuffle,
          onChanged: (v) async {
            await settings.setShuffle(v);
            _changed();
          },
        ),
        if (settings.shuffle)
          _SwitchRow(
            title: s.recentWeighted,
            subtitle: s.recentWeightedDesc,
            value: settings.recentWeighted,
            onChanged: (v) async {
              await settings.setRecentWeighted(v);
              _changed();
            },
          ),
        _SwitchRow(
          title: s.videoMuted,
          subtitle: s.videoMutedDesc,
          value: settings.videoMuted,
          onChanged: (v) async {
            await settings.setVideoMuted(v);
            _changed();
          },
        ),
      ];

  List<Widget> _appearanceOptions(AppStrings s) => [
        _SwitchRow(
          title: s.showMediaDate,
          subtitle: s.showMediaDateDesc,
          value: settings.showMediaDate,
          onChanged: (v) async {
            await settings.setShowMediaDate(v);
            _changed();
          },
        ),
        _SwitchRow(
          title: s.showClock,
          subtitle: s.showClockDesc,
          value: settings.showClock,
          onChanged: (v) async {
            await settings.setShowClock(v);
            _changed();
          },
        ),
        if (settings.showClock) ...[
          _Segmented(
            label: s.timeFormat,
            value: settings.clockFormat,
            options: {'auto': s.auto, '24': s.hour24, '12': s.hour12},
            onChanged: (v) async {
              await settings.setClockFormat(v);
              _changed();
            },
          ),
          _SwitchRow(
            title: s.clockBackground,
            subtitle: s.clockBackgroundDesc,
            value: settings.clockBackground,
            onChanged: (v) async {
              await settings.setClockBackground(v);
              _changed();
            },
          ),
          _SliderRow(
            label: s.clockSize,
            valueLabel: s.percent((settings.clockScale * 100).round()),
            value: settings.clockScale,
            min: 0.7,
            max: 1.4,
            divisions: 14,
            onChanged: (v) async {
              await settings.setClockScale(v);
              _changed();
            },
          ),
        ],
        _SwitchRow(
          title: s.fillScreen,
          subtitle: s.fillScreenDesc,
          value: settings.fillScreen,
          onChanged: (v) async {
            await settings.setFillScreen(v);
            _changed();
          },
        ),
        _SwitchRow(
          title: s.motion,
          subtitle: s.motionDesc,
          value: settings.motion,
          onChanged: (v) async {
            await settings.setMotion(v);
            _changed();
          },
        ),
        if (settings.motion)
          _SliderRow(
            label: s.motionSpeed,
            valueLabel: s.percent((settings.motionSpeed * 100).round()),
            value: settings.motionSpeed,
            min: 0.5,
            max: 1.5,
            divisions: 10,
            onChanged: (v) async {
              await settings.setMotionSpeed(v);
              _changed();
            },
          ),
      ];

  List<Widget> _automationOptions(AppStrings s) => [
        _SwitchRow(
          title: s.launchOnBoot,
          subtitle: s.launchOnBootDesc,
          value: settings.launchOnBoot,
          onChanged: (v) async {
            await settings.setLaunchOnBoot(v);
            _changed();
          },
        ),
        _SwitchRow(
          title: s.launchOnPower,
          subtitle: s.launchOnPowerDesc,
          value: settings.launchOnPower,
          onChanged: (v) async {
            await settings.setLaunchOnPower(v);
            _changed();
          },
        ),
        _SwitchRow(
          title: s.exitOnPowerLoss,
          subtitle: s.exitOnPowerLossDesc,
          value: settings.exitOnPowerLoss,
          onChanged: (v) async {
            await settings.setExitOnPowerLoss(v);
            _changed();
          },
        ),
        _SwitchRow(
          title: s.activeHours,
          subtitle: s.activeHoursDesc,
          value: settings.activeHours,
          onChanged: (v) async {
            await settings.setActiveHours(v);
            _changed();
          },
        ),
        if (settings.activeHours) ...[
          _TimeRow(
            label: s.startTime,
            value: _timeLabel(settings.activeStart),
            onTap: () =>
                _pickTime(settings.activeStart, settings.setActiveStart),
          ),
          _TimeRow(
            label: s.endTime,
            value: _timeLabel(settings.activeEnd),
            onTap: () => _pickTime(settings.activeEnd, settings.setActiveEnd),
          ),
        ],
        _SwitchRow(
          title: s.dailySchedule,
          subtitle: s.dailyScheduleDesc,
          value: settings.schedule,
          onChanged: (v) async {
            await settings.setSchedule(v);
            _changed();
          },
        ),
        if (settings.schedule) ...[
          _TimeRow(
            label: s.startTime,
            value: _timeLabel(settings.scheduleStart),
            onTap: () =>
                _pickTime(settings.scheduleStart, settings.setScheduleStart),
          ),
          _TimeRow(
            label: s.endTime,
            value: _timeLabel(settings.scheduleEnd),
            onTap: () =>
                _pickTime(settings.scheduleEnd, settings.setScheduleEnd),
          ),
        ],
        _ActionRow(
          title: s.backgroundPermissions,
          subtitle: _permissionSubtitle(s),
          action: s.grant,
          busy: _permissionBusy,
          onPressed: _automation?.complete == true || _permissionBusy
              ? null
              : _grantPermission,
        ),
        if (_automation?.miui == true) ...[
          _ActionRow(
            title: s.oemStartup,
            subtitle: s.oemStartupDesc,
            action: s.open,
            onPressed: _openOemStartup,
          ),
          _ActionRow(
            title: s.oemBackgroundPopup,
            subtitle: s.oemBackgroundPopupDesc,
            action: s.open,
            onPressed: _openOemPopup,
          ),
        ],
      ];

  List<Widget> _systemOptions(AppStrings s) => [
        _Segmented(
          label: s.language,
          value: settings.language,
          options: {
            'system': s.systemDefault,
            'en': s.english,
            'zh': s.chinese
          },
          onChanged: (v) async {
            await settings.setLanguage(v);
            _changed();
          },
        ),
        _SwitchRow(
          title: s.keepAwake,
          subtitle: s.keepAwakeDesc,
          value: settings.keepAwake,
          onChanged: (v) async {
            await settings.setKeepAwake(v);
            _changed();
          },
        ),
      ];
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w700,
          color: Colors.white.withValues(alpha: 0.42),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.showSlider = true,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final bool showSlider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.86),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                valueLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
        if (showSlider)
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
          ),
      ],
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = options.containsKey(value) ? value : options.keys.first;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in options.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: entry.key == selected,
                  showCheckmark: false,
                  onSelected: (_) => onChanged(entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          color: Colors.white.withValues(alpha: 0.88),
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _CacheRow extends StatelessWidget {
  const _CacheRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.action,
    required this.onClear,
    this.busy = false,
  });

  final String title;
  final String subtitle;
  final String value;
  final String action;
  final VoidCallback? onClear;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onClear,
            child: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(action),
          ),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.86),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.schedule_rounded,
              size: 16,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onPressed,
    this.busy = false,
  });

  final String title;
  final String subtitle;
  final String action;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onPressed,
            child: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(action),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (label.isNotEmpty) ...[
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Text(
              value,
              textAlign: label.isEmpty ? TextAlign.start : TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.38),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
