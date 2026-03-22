import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_controller.dart';
import 'app/app_settings.dart';
import 'app/app_state.dart';
import 'app/platform_bridge.dart';
import 'app/settings_widgets.dart';
import 'app/app_theme.dart';
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
      title: 'Voice Input',
      theme: buildAppTheme(),
      home: const SettingsPage(),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WindowListener, TrayListener {
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

  final _controller = AppController(
    platformBridge: PlatformBridge(),
    transcriber: SonioxTranscriber(),
  );
  final _tokenEndpointController = TextEditingController();
  final _websocketEndpointController = TextEditingController();
  final _targetLanguageController = TextEditingController();
  final _sourceLanguageController = TextEditingController();

  bool _isQuitting = false;

  AppSettings get _settings => _controller.settings;
  AppViewState get _viewState => _controller.state;

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
    unawaited(_controller.disposeAsync());
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _initTray();
    await _controller.preloadSettings();
    _syncControllersFromSettings();
    await _configureWindow();
    await _controller.bootstrap();
  }

  void _syncControllersFromSettings() {
    _tokenEndpointController.text = _settings.tokenEndpoint;
    _websocketEndpointController.text = _settings.websocketEndpoint;
    _targetLanguageController.text = _settings.targetLanguage;
    _sourceLanguageController.text = _settings.sourceLanguageHint;
  }

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
    await _controller.disposeAsync();
    await windowManager.destroy();
  }

  Future<void> _resetWsWithCurrentConfig() async {
    await _controller.reconnect();
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _viewState.isReady
                ? _buildContent(context)
                : _buildLoading(context),
          ),
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
            _viewState.statusMessage,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: AppColors.mutedInk),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      key: const ValueKey('content'),
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFFBF5), Color(0xFFF3EEE5)],
                  ),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 40,
                      offset: Offset(0, 20),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 760;
                      final intro = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'VOICE INPUT',
                            style: theme.textTheme.bodySmall?.copyWith(
                              letterSpacing: 2.2,
                              color: AppColors.mutedInk,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Speak faster.\nStay in flow.',
                            style: theme.textTheme.displayLarge,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'A warm, quiet desktop utility for dropping voice straight into the app you are already using.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: AppColors.mutedInk,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              KeycapBadge(label: '${_settings.originalHotkey} Original'),
                              KeycapBadge(
                                label:
                                    '${_settings.translationHotkey} Translate',
                              ),
                              const KeycapBadge(label: 'Tray Ready'),
                            ],
                          ),
                        ],
                      );
                      final utilityCard = Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.58),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'How it should feel',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: AppColors.mutedInk,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _buildUtilityPoint(
                              context,
                              title: 'Hold, talk, release',
                              detail:
                                  'No mode switcher, no floating mic UI, no paste dance.',
                            ),
                            const SizedBox(height: 14),
                            _buildUtilityPoint(
                              context,
                              title: 'Tray-first',
                              detail:
                                  'The window is a settings surface. The product lives in the background.',
                            ),
                            const SizedBox(height: 14),
                            _buildUtilityPoint(
                              context,
                              title: 'Translation stays core',
                              detail:
                                  'Useful for bilingual prompting and fast text entry, but still under one simple promise.',
                            ),
                          ],
                        ),
                      );
                      if (!wide) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            intro,
                            const SizedBox(height: 20),
                            utilityCard,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: intro),
                          const SizedBox(width: 20),
                          Expanded(flex: 5, child: utilityCard),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 22),
              StatusBanner(
                title: _viewState.statusTitle,
                detail: _viewState.statusDetail,
                tone: _viewState.statusTone,
              ),
              if (!_viewState.onboardingDismissed) ...[
                const SizedBox(height: 16),
                InfoCard(
                  title: 'Start here',
                  body:
                      'Focus any text field, hold a shortcut, speak, then release the key. The app keeps running in the tray when you close this window.',
                  primaryLabel: 'Got it',
                  onPrimaryPressed: () async {
                    await _controller.dismissOnboarding();
                  },
                ),
              ],
              if (_viewState.phase == AppPhase.needsAttention) ...[
                const SizedBox(height: 16),
                InfoCard(
                  title: 'Voice input needs repair',
                  body:
                      'If speech is not working, try reconnecting first. You can open Advanced for diagnostics if the problem continues.',
                  primaryLabel: 'Reconnect now',
                  onPrimaryPressed: _viewState.isBusy || _controller.isRecording
                      ? null
                      : () async {
                          await _resetWsWithCurrentConfig();
                        },
                  secondaryLabel: _viewState.advancedModeEnabled
                      ? null
                      : 'Open Advanced',
                  onSecondaryPressed: _viewState.advancedModeEnabled
                      ? null
                      : () async {
                          await _controller.setAdvancedModeEnabled(true);
                        },
                  tone: AppStatusTone.warning,
                ),
              ],
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 860;
                  final shortcutsCard = SectionCard(
                    title: 'Shortcuts',
                    subtitle: 'Choose the keys you hold while speaking.',
                    child: Row(
                      children: [
                        Expanded(
                          child: HotkeyDropdown(
                            label: 'Original',
                            value: _settings.originalHotkey,
                            choices: _hotkeyChoices,
                            onChanged: (value) async {
                              if (value == null ||
                                  value == _settings.translationHotkey) {
                                return;
                              }
                              await _controller.updateSettings(
                                _settings.copyWith(originalHotkey: value),
                              );
                              await _controller.applyHotkeys();
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: HotkeyDropdown(
                            label: 'Translation',
                            value: _settings.translationHotkey,
                            choices: _hotkeyChoices,
                            onChanged: (value) async {
                              if (value == null ||
                                  value == _settings.originalHotkey) {
                                return;
                              }
                              await _controller.updateSettings(
                                _settings.copyWith(translationHotkey: value),
                              );
                              await _controller.applyHotkeys();
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                  final languageCard = SectionCard(
                    title: 'Voice & Language',
                    subtitle:
                        'Original types what you said. Translate types the translated result.',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SettingField(
                                label: 'Spoken language hint',
                                example: 'Examples: vi or vi,en',
                                controller: _sourceLanguageController,
                                onSubmitted: (value) async {
                                  await _controller.updateSettings(
                                    _settings.copyWith(
                                      sourceLanguageHint: value.trim(),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: SettingField(
                                label: 'Translate output language',
                                controller: _targetLanguageController,
                                onSubmitted: (value) async {
                                  await _controller.updateSettings(
                                    _settings.copyWith(
                                      targetLanguage: value.trim(),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.panelMuted,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            'Use ${_settings.originalHotkey} for Original and ${_settings.translationHotkey} for Translate.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.mutedInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  final generalCard = SectionCard(
                    title: 'General',
                    subtitle: 'Keep the app quiet and ready in the background.',
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _settings.launchToTray,
                          title: const Text('Open in the tray on startup'),
                          subtitle: const Text(
                            'Hide the window at startup and keep the app available from the tray icon.',
                          ),
                          onChanged: (value) async {
                            await _controller.updateSettings(
                              _settings.copyWith(launchToTray: value),
                            );
                            if (value && Platform.isWindows) {
                              await _hideWindow();
                            } else {
                              await _showWindow();
                            }
                          },
                        ),
                        const Divider(),
                        const ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Closing the window keeps the app running'),
                          subtitle: Text(
                            'Use the tray icon to open settings again or quit the app.',
                          ),
                        ),
                      ],
                    ),
                  );
                  final typingCard = SectionCard(
                    title: 'Typing',
                    subtitle:
                        'This release types directly into the currently focused app.',
                    child: Column(
                      children: [
                        const ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Direct typing'),
                          subtitle: Text(
                            'Your transcript is typed into the app you are using. Clipboard history is not used.',
                          ),
                        ),
                        const Divider(),
                        const ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Best for short and medium text'),
                          subtitle: Text(
                            'The first release is optimized for prompts, chat, notes, and repeated text entry.',
                          ),
                        ),
                      ],
                    ),
                  );

                  if (!wide) {
                    return Column(
                      children: [
                        shortcutsCard,
                        const SizedBox(height: 16),
                        languageCard,
                        const SizedBox(height: 16),
                        generalCard,
                        const SizedBox(height: 16),
                        typingCard,
                      ],
                    );
                  }

                  return Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: shortcutsCard),
                          const SizedBox(width: 16),
                          Expanded(child: languageCard),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: generalCard),
                          const SizedBox(width: 16),
                          Expanded(child: typingCard),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              AdvancedSection(
                expanded: _viewState.advancedModeEnabled,
                onChanged: (value) async {
                  await _controller.setAdvancedModeEnabled(value);
                },
                child: Column(
                  children: [
                    SectionCard(
                      title: 'Health',
                      subtitle:
                          'Use this only when voice input needs attention.',
                      child: Column(
                        children: [
                          ReadOnlyField(
                            label: 'Connection',
                            value: _viewState.wsStateLabel,
                          ),
                          const SizedBox(height: 16),
                          ReadOnlyField(
                            label: 'Sample rate',
                            value: '${_settings.sampleRate}',
                          ),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.tonalIcon(
                              onPressed:
                                  _viewState.isBusy || _controller.isRecording
                                  ? null
                                  : _resetWsWithCurrentConfig,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Reconnect voice service'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SectionCard(
                      title: 'Backend',
                      subtitle:
                          'Technical configuration for debugging and support.',
                      child: Column(
                        children: [
                          SettingField(
                            label: 'Token endpoint',
                            controller: _tokenEndpointController,
                            onSubmitted: (value) async {
                              await _controller.updateSettings(
                                _settings.copyWith(tokenEndpoint: value.trim()),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          SettingField(
                            label: 'WebSocket endpoint',
                            controller: _websocketEndpointController,
                            onSubmitted: (value) async {
                              await _controller.updateSettings(
                                _settings.copyWith(
                                  websocketEndpoint: value.trim(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SectionCard(
                      title: 'Session transcript',
                      subtitle:
                          'Live accumulated text for the current hold-to-talk session.',
                      child: Column(
                        children: [
                          TranscriptBox(
                            label: 'Original accumulated',
                            value: _composeSessionDisplay(
                              accumulated:
                                  _viewState.sessionOriginalAccumulated,
                              provisional:
                                  _viewState.sessionOriginalProvisional,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TranscriptBox(
                            label: 'Translation accumulated',
                            value: _composeSessionDisplay(
                              accumulated:
                                  _viewState.sessionTranslationAccumulated,
                              provisional:
                                  _viewState.sessionTranslationProvisional,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SectionCard(
                      title: 'Last transcript',
                      subtitle: 'Useful when checking the last successful run.',
                      child: Column(
                        children: [
                          TranscriptBox(
                            label: 'Original',
                            value: _viewState.lastOriginal,
                          ),
                          const SizedBox(height: 16),
                          TranscriptBox(
                            label: 'Translation',
                            value: _viewState.lastTranslation,
                          ),
                        ],
                      ),
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

  Widget _buildUtilityPoint(
    BuildContext context, {
    required String title,
    required String detail,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 5),
          decoration: const BoxDecoration(
            color: AppColors.brass,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.mutedInk,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
