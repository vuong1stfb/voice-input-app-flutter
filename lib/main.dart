import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'soniox_transcriber.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  runApp(const InputAppDesktop());
}

class InputAppDesktop extends StatelessWidget {
  const InputAppDesktop({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Input App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF135D66),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F1EA),
        useMaterial3: true,
      ),
      home: const SettingsPage(),
    );
  }
}

class _AppSettings {
  const _AppSettings({
    required this.originalHotkey,
    required this.translationHotkey,
    required this.pasteViaClipboard,
    required this.launchToTray,
    required this.tokenEndpoint,
    required this.websocketEndpoint,
    required this.targetLanguage,
    required this.sourceLanguageHint,
    required this.sampleRate,
  });

  final String originalHotkey;
  final String translationHotkey;
  final bool pasteViaClipboard;
  final bool launchToTray;
  final String tokenEndpoint;
  final String websocketEndpoint;
  final String targetLanguage;
  final String sourceLanguageHint;
  final int sampleRate;

  _AppSettings copyWith({
    String? originalHotkey,
    String? translationHotkey,
    bool? pasteViaClipboard,
    bool? launchToTray,
    String? tokenEndpoint,
    String? websocketEndpoint,
    String? targetLanguage,
    String? sourceLanguageHint,
    int? sampleRate,
  }) {
    return _AppSettings(
      originalHotkey: originalHotkey ?? this.originalHotkey,
      translationHotkey: translationHotkey ?? this.translationHotkey,
      pasteViaClipboard: pasteViaClipboard ?? this.pasteViaClipboard,
      launchToTray: launchToTray ?? this.launchToTray,
      tokenEndpoint: tokenEndpoint ?? this.tokenEndpoint,
      websocketEndpoint: websocketEndpoint ?? this.websocketEndpoint,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      sourceLanguageHint: sourceLanguageHint ?? this.sourceLanguageHint,
      sampleRate: sampleRate ?? this.sampleRate,
    );
  }

  static const defaults = _AppSettings(
    originalHotkey: 'F9',
    translationHotkey: 'F10',
    pasteViaClipboard: false,
    launchToTray: true,
    tokenEndpoint:
        'https://soniox-proxy-ud00.onrender.com/api/soniox/speech-to-text',
    websocketEndpoint: 'wss://stt-rt.soniox.com/transcribe-websocket',
    targetLanguage: 'en',
    sourceLanguageHint: 'vi',
    sampleRate: 48000,
  );
}

class _PlatformBridge {
  _PlatformBridge();

  static const _channel = MethodChannel('input_app/platform');

  Future<void> Function(String kind, String action)? onHotkeyEvent;

  Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onHotkeyEvent') {
        return;
      }
      final payload = Map<String, dynamic>.from(call.arguments as Map);
      final kind = payload['kind'] as String?;
      final action = payload['action'] as String?;
      if (kind != null && action != null && onHotkeyEvent != null) {
        await onHotkeyEvent!(kind, action);
      }
    });
  }

  Future<void> configureHotkeys({
    required String originalHotkey,
    required String translationHotkey,
  }) async {
    await _channel.invokeMethod<void>('configureHotkeys', {
      'original': originalHotkey,
      'translation': translationHotkey,
    });
  }

  Future<void> pasteText(String text, {required bool useClipboard}) async {
    await _channel.invokeMethod<void>('typeText', text);
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WindowListener, TrayListener {
  static const _originalHotkeyKey = 'original_hotkey';
  static const _translationHotkeyKey = 'translation_hotkey';
  static const _pasteViaClipboardKey = 'paste_via_clipboard';
  static const _launchToTrayKey = 'launch_to_tray';
  static const _tokenEndpointKey = 'token_endpoint';
  static const _websocketEndpointKey = 'websocket_endpoint';
  static const _targetLanguageKey = 'target_language';
  static const _sourceLanguageHintKey = 'source_language_hint';
  static const _sampleRateKey = 'sample_rate';
  static const _hotkeyChoices = <String>[
    'F1',
    'F2',
    'F3',
    'F4',
    'F5',
    'F6',
    'F7',
    'F8',
    'F9',
    'F10',
    'F11',
    'F12',
    'Space',
    'Enter',
    'Tab',
  ];

  final _platformBridge = _PlatformBridge();
  final _transcriber = SonioxTranscriber();
  final _tokenEndpointController = TextEditingController();
  final _websocketEndpointController = TextEditingController();
  final _targetLanguageController = TextEditingController();
  final _sourceLanguageController = TextEditingController();

  late final SharedPreferences _prefs;
  _AppSettings _settings = _AppSettings.defaults;
  bool _isReady = false;
  bool _isQuitting = false;
  bool _isBusy = false;
  TranscriptMode? _pressedMode;
  bool _pendingRelease = false;
  String _status = 'Booting Windows shell...';
  String _lastOriginal = '';
  String _lastTranslation = '';
  String _sessionOriginalAccumulated = '';
  String _sessionTranslationAccumulated = '';
  String _sessionOriginalProvisional = '';
  String _sessionTranslationProvisional = '';

  Future<void> _appendLog(String message) async {
    final file = File('C:/dev/input_app_flutter/flutter_app.log');
    await file.writeAsString('$message\n', mode: FileMode.append, flush: true);
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _tokenEndpointController.dispose();
    _websocketEndpointController.dispose();
    _targetLanguageController.dispose();
    _sourceLanguageController.dispose();
    unawaited(_transcriber.dispose());
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _prefs = await SharedPreferences.getInstance();
    _loadSettings();
    _tokenEndpointController.text = _settings.tokenEndpoint;
    _websocketEndpointController.text = _settings.websocketEndpoint;
    _targetLanguageController.text = _settings.targetLanguage;
    _sourceLanguageController.text = _settings.sourceLanguageHint;

    await _platformBridge.initialize();
    _platformBridge.onHotkeyEvent = _handleHotkeyEvent;
    _transcriber.onTranscriptProgress = ({
      required String originalAccumulated,
      required String translationAccumulated,
      required String originalProvisional,
      required String translationProvisional,
    }) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sessionOriginalAccumulated = originalAccumulated;
        _sessionTranslationAccumulated = translationAccumulated;
        _sessionOriginalProvisional = originalProvisional;
        _sessionTranslationProvisional = translationProvisional;
      });
    };
    await _appendLog('dart:bootstrap:initialized');

    await _initTray();
    await _configureWindow();
    await _applyHotkeys();
    await _warmUpSession();

    if (!mounted) {
      return;
    }
    setState(() {
      _isReady = true;
      _status =
          'Ready. Hold ${_settings.originalHotkey} for original or ${_settings.translationHotkey} for translation, then release to transcribe.';
    });
    await _appendLog('dart:bootstrap:ready');
  }

  void _loadSettings() {
    _settings = _AppSettings(
      originalHotkey:
          _prefs.getString(_originalHotkeyKey) ??
          _AppSettings.defaults.originalHotkey,
      translationHotkey:
          _prefs.getString(_translationHotkeyKey) ??
          _AppSettings.defaults.translationHotkey,
      pasteViaClipboard:
          _prefs.getBool(_pasteViaClipboardKey) ??
          _AppSettings.defaults.pasteViaClipboard,
      launchToTray:
          _prefs.getBool(_launchToTrayKey) ??
          _AppSettings.defaults.launchToTray,
      tokenEndpoint:
          _prefs.getString(_tokenEndpointKey) ??
          _AppSettings.defaults.tokenEndpoint,
      websocketEndpoint:
          _prefs.getString(_websocketEndpointKey) ??
          _AppSettings.defaults.websocketEndpoint,
      targetLanguage:
          _prefs.getString(_targetLanguageKey) ??
          _AppSettings.defaults.targetLanguage,
      sourceLanguageHint:
          _prefs.getString(_sourceLanguageHintKey) ??
          _AppSettings.defaults.sourceLanguageHint,
      sampleRate:
          _prefs.getInt(_sampleRateKey) ?? _AppSettings.defaults.sampleRate,
    );
  }

  Future<void> _saveSettings(_AppSettings settings) async {
    await _prefs.setString(_originalHotkeyKey, settings.originalHotkey);
    await _prefs.setString(_translationHotkeyKey, settings.translationHotkey);
    await _prefs.setBool(_pasteViaClipboardKey, settings.pasteViaClipboard);
    await _prefs.setBool(_launchToTrayKey, settings.launchToTray);
    await _prefs.setString(_tokenEndpointKey, settings.tokenEndpoint);
    await _prefs.setString(_websocketEndpointKey, settings.websocketEndpoint);
    await _prefs.setString(_targetLanguageKey, settings.targetLanguage);
    await _prefs.setString(
      _sourceLanguageHintKey,
      settings.sourceLanguageHint,
    );
    await _prefs.setInt(_sampleRateKey, settings.sampleRate);
  }

  Future<void> _updateSettings(_AppSettings nextSettings) async {
    setState(() {
      _settings = nextSettings;
    });
    await _saveSettings(nextSettings);
  }

  SonioxSettings get _sonioxSettings => SonioxSettings(
    tokenEndpoint: _settings.tokenEndpoint,
    websocketEndpoint: _settings.websocketEndpoint,
    targetLanguage: _settings.targetLanguage,
    sourceLanguageHint: _settings.sourceLanguageHint,
    sampleRate: _settings.sampleRate,
  );

  Future<void> _initTray() async {
    if (!Platform.isWindows) {
      return;
    }

    await trayManager.setIcon(_resolveTrayIconPath());
    await trayManager.setToolTip('Input App');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Open Settings'),
          MenuItem(key: 'hide', label: 'Hide'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
        ],
      ),
    );
  }

  Future<void> _configureWindow() async {
    final ready = Completer<void>();
    const options = WindowOptions(
      size: Size(980, 820),
      center: true,
      title: 'Input App',
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
    );

    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setPreventClose(true);
      if (_settings.launchToTray && Platform.isWindows) {
        await _hideWindow();
      } else {
        await _showWindow();
      }
      ready.complete();
    });

    await ready.future;
  }

  String _resolveTrayIconPath() {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final bundled = File(
      '${exeDir.path}${Platform.pathSeparator}data${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}assets${Platform.pathSeparator}app_icon.ico',
    );
    if (bundled.existsSync()) {
      return bundled.path;
    }

    return '${Directory.current.path}${Platform.pathSeparator}assets${Platform.pathSeparator}app_icon.ico';
  }

  Future<void> _showWindow() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _hideWindow() async {
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  Future<void> _exitApp() async {
    _isQuitting = true;
    if (Platform.isWindows) {
      await trayManager.destroy();
    }
    await _transcriber.dispose();
    await windowManager.destroy();
  }

  Future<void> _setStatus(String status) async {
    if (!mounted) {
      return;
    }
    await _appendLog('dart:status:$status');
    setState(() {
      _status = status;
    });
  }

  Future<void> _applyHotkeys() async {
    try {
      await _platformBridge.configureHotkeys(
        originalHotkey: _settings.originalHotkey,
        translationHotkey: _settings.translationHotkey,
      );
      await _setStatus(
        'Hotkeys active: ${_settings.originalHotkey} / ${_settings.translationHotkey}',
      );
    } on PlatformException catch (error) {
      await _setStatus(
        error.message ?? 'Failed to register global hotkeys on Windows.',
      );
    }
  }

  Future<void> _warmUpSession() async {
    try {
      await _transcriber.warmUp(
        settings: _sonioxSettings,
        onStatus: _setStatus,
      );
      await _appendLog('dart:warmup:ok');
    } catch (error) {
      await _appendLog('dart:warmup:error:$error');
      await _setStatus('Warm-up failed: $error');
    }
  }

  Future<void> _handleHotkeyEvent(String kind, String action) async {
    await _appendLog('dart:event:$kind:$action');
    final mode = kind == 'translation'
        ? TranscriptMode.translation
        : TranscriptMode.original;

    if (_isBusy) {
      if (action == 'up' && _pressedMode == mode) {
        _pendingRelease = true;
        await _appendLog('dart:event:queued_release_while_busy');
      } else {
        await _appendLog('dart:event:ignored_busy');
      }
      return;
    }

    if (action == 'down') {
      if (_transcriber.isRecording) {
        await _appendLog('dart:event:ignored_already_recording');
        return;
      }
      _pressedMode = mode;
      _pendingRelease = false;
      await _startRecording(mode);
      return;
    }

    if (action == 'up' &&
        _transcriber.isRecording &&
        _pressedMode == mode &&
        _transcriber.activeMode == mode) {
      await _stopRecording();
      _pressedMode = null;
    } else if (action == 'up') {
      await _appendLog('dart:event:up_ignored_state_mismatch');
    }
  }

  Future<void> _startRecording(TranscriptMode mode) async {
    await _appendLog('dart:start:${mode.name}');
    _isBusy = true;
    try {
      await _transcriber.start(
        mode: mode,
        settings: _sonioxSettings,
        onStatus: _setStatus,
      );
      await _setStatus(
        'Recording ${mode == TranscriptMode.translation ? 'translation' : 'original'} audio. Release the hotkey to finalize.',
      );
      await _appendLog('dart:start:ok:${mode.name}');
    } catch (error) {
      await _appendLog('dart:start:error:$error');
      await _setStatus('Failed to start recording: $error');
    } finally {
      _isBusy = false;
      if (mounted) {
        setState(() {});
      }
    }

    if (_pendingRelease &&
        _transcriber.isRecording &&
        _transcriber.activeMode == mode) {
      await _appendLog('dart:start:consuming_pending_release:${mode.name}');
      _pendingRelease = false;
      await _stopRecording();
    }
  }

  Future<void> _stopRecording() async {
    await _appendLog('dart:stop:begin');
    _isBusy = true;
    try {
      final result = await _transcriber.stop(onStatus: _setStatus);
      if (result == null || result.text.trim().isEmpty) {
        await _appendLog('dart:stop:no_result');
        await _setStatus('No transcript returned from Soniox.');
        return;
      }

      _lastOriginal = result.originalText;
      _lastTranslation = result.translationText;
      await _appendLog(
        'dart:stop:result:mode=${result.mode.name}:text=${result.text}',
      );
      await _platformBridge.pasteText(
        result.text,
        useClipboard: false,
      );
      await _setStatus(
        'Typed ${result.mode == TranscriptMode.translation ? 'translation' : 'original'} transcript directly.',
      );
    } catch (error) {
      await _appendLog('dart:stop:error:$error');
      await _setStatus('Failed to finalize transcript: $error');
    } finally {
      _isBusy = false;
      _pressedMode = null;
      _pendingRelease = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _toggleManual(TranscriptMode mode) async {
    if (_transcriber.isRecording) {
      await _stopRecording();
      return;
    }
    await _startRecording(mode);
  }

  @override
  Future<void> onWindowClose() async {
    if (_isQuitting) {
      return;
    }
    if (Platform.isWindows) {
      await _hideWindow();
      return;
    }
    await _exitApp();
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayIconRightMouseUp() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(_showWindow());
        break;
      case 'hide':
        unawaited(_hideWindow());
        break;
      case 'quit':
        unawaited(_exitApp());
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _isReady ? _buildContent(context) : _buildLoading(context),
        ),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return Center(
      key: const ValueKey('loading'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            _status,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final isRecording = _transcriber.isRecording;
    final activeMode = _transcriber.activeMode;
    return SingleChildScrollView(
      key: const ValueKey('content'),
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Input App',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F2C2F),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Windows-first voice input shell with native tray, single-instance protection, global hotkeys, Soniox streaming, and text injection into the focused app.',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF355C5E),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F2EE),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFBED3C7)),
                ),
                child: Text(
                  _status,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF204E4B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _StatCard(
                    title: 'Recording',
                    value: isRecording
                        ? (activeMode == TranscriptMode.translation
                              ? 'Translation live'
                              : 'Original live')
                        : 'Idle',
                    note: 'Hold to record, release to finalize.',
                  ),
                  _StatCard(
                    title: 'Injection',
                    value: 'Direct typing',
                    note: 'Text is typed directly into the currently focused app.',
                  ),
                  _StatCard(
                    title: 'Audio',
                    value: '${_settings.sampleRate} Hz PCM16',
                    note: 'Windows mic stream routed into Soniox WS.',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SectionCard(
                title: 'Hotkeys',
                subtitle:
                    'The native Windows runner listens for key down and key up so the app behaves like classic push-to-talk.',
                child: Row(
                  children: [
                    Expanded(
                      child: _HotkeyDropdown(
                        label: 'Original',
                        value: _settings.originalHotkey,
                        choices: _hotkeyChoices,
                        onChanged: (value) async {
                          if (value == null ||
                              value == _settings.translationHotkey) {
                            return;
                          }
                          await _updateSettings(
                            _settings.copyWith(originalHotkey: value),
                          );
                          await _applyHotkeys();
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _HotkeyDropdown(
                        label: 'Translation',
                        value: _settings.translationHotkey,
                        choices: _hotkeyChoices,
                        onChanged: (value) async {
                          if (value == null ||
                              value == _settings.originalHotkey) {
                            return;
                          }
                          await _updateSettings(
                            _settings.copyWith(translationHotkey: value),
                          );
                          await _applyHotkeys();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Soniox',
                subtitle:
                    'These settings are persisted immediately and used on the next recording session.',
                child: Column(
                  children: [
                    _SettingField(
                      label: 'Token endpoint',
                      controller: _tokenEndpointController,
                      onSubmitted: (value) async {
                        await _updateSettings(
                          _settings.copyWith(tokenEndpoint: value.trim()),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _SettingField(
                      label: 'WebSocket endpoint',
                      controller: _websocketEndpointController,
                      onSubmitted: (value) async {
                        await _updateSettings(
                          _settings.copyWith(websocketEndpoint: value.trim()),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _SettingField(
                            label: 'Source language hints',
                            example: 'Examples: vi or vi,en',
                            controller: _sourceLanguageController,
                            onSubmitted: (value) async {
                              await _updateSettings(
                                _settings.copyWith(
                                  sourceLanguageHint: value.trim(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _SettingField(
                            label: 'Target language',
                            controller: _targetLanguageController,
                            onSubmitted: (value) async {
                              await _updateSettings(
                                _settings.copyWith(
                                  targetLanguage: value.trim(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _ReadOnlyField(
                            label: 'Sample rate',
                            value: '${_settings.sampleRate}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Manual controls',
                subtitle:
                    'These buttons mimic the same start/stop lifecycle as the hold-to-talk hotkeys.',
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _isBusy
                            ? null
                            : () => _toggleManual(TranscriptMode.original),
                        child: Text(
                          isRecording && activeMode == TranscriptMode.original
                              ? 'Finalize Original'
                              : 'Start Original',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: _isBusy
                            ? null
                            : () => _toggleManual(TranscriptMode.translation),
                        child: Text(
                          isRecording &&
                                  activeMode == TranscriptMode.translation
                              ? 'Finalize Translation'
                              : 'Start Translation',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Behavior',
                subtitle:
                    'This build avoids clipboard usage so transcripts do not enter clipboard history.',
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Direct typing only'),
                      subtitle: const Text(
                        'The app now sends text directly with native typing and does not use the clipboard.',
                      ),
                    ),
                    const Divider(),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _settings.launchToTray,
                      title: const Text('Launch directly to tray on Windows'),
                      subtitle: const Text(
                        'Hide the settings window at startup and keep only the tray icon visible.',
                      ),
                      onChanged: (value) async {
                        await _updateSettings(
                          _settings.copyWith(launchToTray: value),
                        );
                        if (value && Platform.isWindows) {
                          await _hideWindow();
                        } else {
                          await _showWindow();
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Session transcript',
                subtitle:
                    'Live accumulated text for the current hold-to-talk session. Provisional tails are shown until Soniox finalizes them.',
                child: Column(
                  children: [
                    _TranscriptBox(
                      label: 'Original accumulated',
                      value: _composeSessionDisplay(
                        accumulated: _sessionOriginalAccumulated,
                        provisional: _sessionOriginalProvisional,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _TranscriptBox(
                      label: 'Translation accumulated',
                      value: _composeSessionDisplay(
                        accumulated: _sessionTranslationAccumulated,
                        provisional: _sessionTranslationProvisional,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Last transcript',
                subtitle:
                    'Useful for debugging the STT layer separately from paste behavior.',
                child: Column(
                  children: [
                    _TranscriptBox(label: 'Original', value: _lastOriginal),
                    const SizedBox(height: 16),
                    _TranscriptBox(
                      label: 'Translation',
                      value: _lastTranslation,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _composeSessionDisplay({
    required String accumulated,
    required String provisional,
  }) {
    final finalText = accumulated.trim();
    final provisionalText = provisional.trim();
    if (finalText.isEmpty) {
      return provisionalText;
    }
    if (provisionalText.isEmpty) {
      return finalText;
    }
    return '$finalText\n\n[provisional] $provisionalText';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.note,
  });

  final String title;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF52796F),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF112D32),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            note,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF506568)),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFD8E2DC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF12343B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF5C7778)),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _HotkeyDropdown extends StatelessWidget {
  const _HotkeyDropdown({
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> choices;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: value,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF7FAF8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
          items: choices
              .map(
                (choice) => DropdownMenuItem<String>(
                  value: choice,
                  child: Text(choice),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SettingField extends StatelessWidget {
  const _SettingField({
    required this.label,
    required this.controller,
    required this.onSubmitted,
    this.example,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final String? example;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (example != null) ...[
          const SizedBox(height: 4),
          Text(
            example!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF5C7672)),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          onSubmitted: onSubmitted,
          onChanged: onSubmitted,
          decoration: InputDecoration(
            hintText: example == null ? null : 'vi,en',
            filled: true,
            fillColor: const Color(0xFFF7FAF8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: const Color(0xFFF7FAF8),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(value),
        ),
      ],
    );
  }
}

class _TranscriptBox extends StatelessWidget {
  const _TranscriptBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF7FAF8),
            borderRadius: BorderRadius.circular(18),
          ),
          child: SelectableText(value.isEmpty ? 'No transcript yet.' : value),
        ),
      ],
    );
  }
}
