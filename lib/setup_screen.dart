import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'l10n.dart';
import 'settings.dart';
import 'theme.dart';

/// Onboarding screen: a calm two-column layout on tablets, stacked on phones.
/// Source cards make the three connection types obvious at a glance.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.settings});

  final FrameSettings settings;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  FrameSettings get settings => widget.settings;

  late String _type;
  late final TextEditingController _localPath;
  late final TextEditingController _davUrl;
  late final TextEditingController _davUser;
  late final TextEditingController _davPass;
  late final TextEditingController _davPath;
  late final TextEditingController _smbHost;
  late final TextEditingController _smbDomain;
  late final TextEditingController _smbUser;
  late final TextEditingController _smbPass;
  late final TextEditingController _smbPath;

  bool _granted = false;
  bool _busy = false;
  bool _obscureDav = true;
  bool _obscureSmb = true;
  String? _errorKey;

  @override
  void initState() {
    super.initState();
    _type = settings.sourceType;
    _localPath = TextEditingController(
      text: settings.sourceFolder.isNotEmpty
          ? settings.sourceFolder
          : '/storage/emulated/0/Pictures',
    );
    _davUrl = TextEditingController(text: settings.webdavUrl);
    _davUser = TextEditingController(text: settings.webdavUser);
    _davPass = TextEditingController(text: settings.webdavPass);
    _davPath = TextEditingController(text: settings.webdavPath);
    _smbHost = TextEditingController(text: settings.smbHost);
    _smbDomain = TextEditingController(text: settings.smbDomain);
    _smbUser = TextEditingController(text: settings.smbUser);
    _smbPass = TextEditingController(text: settings.smbPass);
    _smbPath = TextEditingController(text: settings.smbPath);
    _refreshPerm();
  }

  @override
  void dispose() {
    for (final controller in [
      _localPath,
      _davUrl,
      _davUser,
      _davPass,
      _davPath,
      _smbHost,
      _smbDomain,
      _smbUser,
      _smbPass,
      _smbPath,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshPerm() async {
    if (!Platform.isAndroid) {
      setState(() => _granted = true);
      return;
    }
    final status = await Permission.manageExternalStorage.status;
    if (mounted) setState(() => _granted = status.isGranted);
  }

  Future<void> _requestPerm() async {
    final status = await Permission.manageExternalStorage.request();
    if (mounted) setState(() => _granted = status.isGranted);
  }

  String? _errorText(AppStrings s) => switch (_errorKey) {
        'folder' => s.errFolder,
        'permission' => s.errPermission,
        'webdav' => s.errWebdav,
        'smb' => s.errSmb,
        _ => null,
      };

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    if (_type == 'local') {
      if (_localPath.text.trim().isEmpty) {
        setState(() {
          _busy = false;
          _errorKey = 'folder';
        });
        return;
      }
      if (Platform.isAndroid && !_granted) {
        final status = await Permission.manageExternalStorage.request();
        _granted = status.isGranted;
        if (!mounted) return;
        if (!_granted) {
          setState(() {
            _busy = false;
            _errorKey = 'permission';
          });
          return;
        }
      }
    } else if (_type == 'webdav') {
      if (_davUrl.text.trim().isEmpty || _davPath.text.trim().isEmpty) {
        setState(() {
          _busy = false;
          _errorKey = 'webdav';
        });
        return;
      }
    } else {
      if (_smbHost.text.trim().isEmpty || _smbPath.text.trim().isEmpty) {
        setState(() {
          _busy = false;
          _errorKey = 'smb';
        });
        return;
      }
    }

    await settings.setSourceType(_type);
    await settings.setSourceFolder(_localPath.text.trim());
    await settings.setWebdavUrl(_davUrl.text.trim());
    await settings.setWebdavUser(_davUser.text.trim());
    await settings.setWebdavPass(_davPass.text);
    await settings.setWebdavPath(_davPath.text.trim());
    await settings.setSmbHost(_smbHost.text.trim());
    await settings.setSmbDomain(_smbDomain.text.trim());
    await settings.setSmbUser(_smbUser.text.trim());
    await settings.setSmbPass(_smbPass.text);
    await settings.setSmbPath(_smbPath.text.trim());
    await settings.setSetupMode(false);
    // The app root rebuilds into the slideshow.
  }

  String _languageLabel(AppStrings s) => switch (settings.language) {
        'en' => s.english,
        'zh' => s.chinese,
        _ => s.systemDefault,
      };

  /// Only an already-configured frame can be left without saving.
  bool get _canCancel => settings.isConfigured;

  void _cancel() => settings.setSetupMode(false);

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return PopScope(
      canPop: !_canCancel,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(
                child: ColoredBox(color: HearthPalette.background)),
            Positioned(
              top: -180,
              left: -120,
              child: _Glow(
                size: 520,
                color: HearthPalette.primary.withValues(alpha: 0.10),
              ),
            ),
            Positioned(
              bottom: -220,
              right: -160,
              child: _Glow(
                size: 600,
                color: HearthPalette.accent.withValues(alpha: 0.06),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  return SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 48 : 20,
                      vertical: 24,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _topBar(s),
                            const SizedBox(height: 30),
                            if (wide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                      flex: 5, child: _hero(s, wide: true)),
                                  const SizedBox(width: 48),
                                  Expanded(
                                      flex: 6, child: _form(s, wide: true)),
                                ],
                              )
                            else ...[
                              _hero(s, wide: false),
                              const SizedBox(height: 26),
                              _form(s, wide: false),
                            ],
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(AppStrings s) {
    return Row(
      children: [
        if (_canCancel) ...[
          IconButton(
            onPressed: _busy ? null : _cancel,
            tooltip: s.back,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: Colors.white.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 4),
        ],
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: HearthPalette.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: HearthPalette.primary.withValues(alpha: 0.30),
            ),
          ),
          child: const Icon(
            Icons.photo_library_outlined,
            color: HearthPalette.primary,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          s.appName,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: Colors.white.withValues(alpha: 0.92),
          ),
        ),
        const Spacer(),
        PopupMenuButton<String>(
          tooltip: s.language,
          initialValue: settings.language,
          onSelected: settings.setLanguage,
          itemBuilder: (context) => [
            PopupMenuItem(value: 'system', child: Text(s.systemDefault)),
            PopupMenuItem(value: 'en', child: Text(s.english)),
            PopupMenuItem(value: 'zh', child: Text(s.chinese)),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.language_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Text(
                  _languageLabel(s),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _hero(AppStrings s, {required bool wide}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          s.heroTitle,
          style: TextStyle(
            fontSize: wide ? 46 : 34,
            height: 1.12,
            fontWeight: FontWeight.w300,
            letterSpacing: -0.6,
            color: Colors.white.withValues(alpha: 0.96),
          ),
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            s.heroBody,
            style: TextStyle(
              fontSize: wide ? 15 : 14,
              height: 1.6,
              color: Colors.white.withValues(alpha: 0.64),
            ),
          ),
        ),
        const SizedBox(height: 28),
        _Feature(
          icon: Icons.photo_library_outlined,
          title: s.featurePhotos,
          body: s.featurePhotosBody,
        ),
        const SizedBox(height: 16),
        _Feature(
          icon: Icons.cloud_outlined,
          title: s.featureStorage,
          body: s.featureStorageBody,
        ),
        const SizedBox(height: 16),
        _Feature(
          icon: Icons.nightlight_outlined,
          title: s.featureAlwaysOn,
          body: s.featureAlwaysOnBody,
        ),
      ],
    );
  }

  Widget _form(AppStrings s, {required bool wide}) {
    return Container(
      padding: EdgeInsets.all(wide ? 28 : 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 44,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            s.connectTitle,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            s.connectBody,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 22),
          _sourceCard(s, 'local', Icons.folder_outlined, s.localFolder,
              s.localFolderDesc),
          const SizedBox(height: 10),
          _sourceCard(
              s, 'webdav', Icons.cloud_outlined, s.webdav, s.webdavDesc),
          const SizedBox(height: 10),
          _sourceCard(s, 'smb', Icons.storage_outlined, s.smb, s.smbDesc),
          const SizedBox(height: 20),
          ..._fields(s),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: Colors.white.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.setupNote,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.42),
                  ),
                ),
              ),
            ],
          ),
          if (_errorText(s) != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFB3261E).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFF2B8B5).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: Color(0xFFF2B8B5),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorText(s)!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Color(0xFFF2B8B5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _start,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(_busy ? s.starting : s.startFrame),
          ),
          if (_canCancel) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: _busy ? null : _cancel,
              child: Text(s.backToFrame),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sourceCard(
    AppStrings s,
    String value,
    IconData icon,
    String title,
    String description,
  ) {
    final selected = _type == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _type = value;
        _errorKey = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? HearthPalette.primary.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? HearthPalette.primary.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.10),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? HearthPalette.primary.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                icon,
                size: 20,
                color: selected
                    ? HearthPalette.primary
                    : Colors.white.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withValues(
                        alpha: selected ? 0.55 : 0.38,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle_rounded,
                size: 20,
                color: HearthPalette.primary.withValues(alpha: 0.9),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _fields(AppStrings s) {
    if (_type == 'local') {
      return [
        if (Platform.isAndroid) ...[
          _permissionRow(s),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _localPath,
          decoration:
              _dec(s.folderPath, s.hintLocalPath, Icons.folder_outlined),
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _start(),
        ),
      ];
    }
    if (_type == 'webdav') {
      return [
        TextField(
          controller: _davUrl,
          decoration: _dec(s.serverUrl, s.hintServerUrl, Icons.link_rounded),
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _davUser,
          decoration:
              _dec(s.username, s.hintUsername, Icons.person_outline_rounded),
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _davPass,
          decoration: _dec(
            s.password,
            s.hintPassword,
            Icons.key_rounded,
            suffix: _passwordSuffix(s, dav: true),
          ),
          obscureText: _obscureDav,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _davPath,
          decoration:
              _dec(s.folderPath, s.hintFolderPath, Icons.folder_outlined),
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _start(),
        ),
      ];
    }
    return [
      TextField(
        controller: _smbHost,
        decoration: _dec(s.host, s.hintHost, Icons.dns_outlined),
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _smbUser,
        decoration:
            _dec(s.username, s.hintUsername, Icons.person_outline_rounded),
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _smbPass,
        decoration: _dec(
          s.password,
          s.hintPassword,
          Icons.key_rounded,
          suffix: _passwordSuffix(s, dav: false),
        ),
        obscureText: _obscureSmb,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _smbDomain,
        decoration: _dec(s.domainOptional, s.hintDomain, Icons.badge_outlined),
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _smbPath,
        decoration:
            _dec(s.sharePath, s.hintSharePath, Icons.folder_shared_outlined),
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _start(),
      ),
    ];
  }

  Widget _permissionRow(AppStrings s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _granted
            ? HearthPalette.primary.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _granted
              ? HearthPalette.primary.withValues(alpha: 0.30)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _granted ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 18,
            color: _granted
                ? HearthPalette.primary
                : Colors.white.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _granted ? s.allFilesGranted : s.allFilesNeeded,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ),
          if (!_granted)
            TextButton(onPressed: _requestPerm, child: Text(s.grant)),
        ],
      ),
    );
  }

  Widget _passwordSuffix(AppStrings s, {required bool dav}) {
    final obscure = dav ? _obscureDav : _obscureSmb;
    return IconButton(
      tooltip: obscure ? s.showPassword : s.hidePassword,
      onPressed: () => setState(() {
        if (dav) {
          _obscureDav = !_obscureDav;
        } else {
          _obscureSmb = !_obscureSmb;
        }
      }),
      icon: Icon(
        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 20,
      ),
    );
  }

  InputDecoration _dec(
    String label,
    String hint,
    IconData icon, {
    Widget? suffix,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.035),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: HearthPalette.primary.withValues(alpha: 0.9),
          width: 1.3,
        ),
      ),
      labelStyle: TextStyle(
        fontSize: 13,
        color: Colors.white.withValues(alpha: 0.55),
      ),
      hintStyle: TextStyle(
        fontSize: 13,
        color: Colors.white.withValues(alpha: 0.28),
      ),
      prefixIconColor: Colors.white.withValues(alpha: 0.45),
      suffixIconColor: Colors.white.withValues(alpha: 0.45),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: HearthPalette.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: HearthPalette.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.88),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, Colors.transparent]),
        ),
      ),
    );
  }
}
