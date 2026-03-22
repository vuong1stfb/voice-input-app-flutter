/*  */import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../soniox_transcriber.dart';
import 'app_settings.dart';
import 'app_state.dart';
import 'platform_bridge.dart';

class AppController extends ChangeNotifier {
  AppController({
    required PlatformBridge platformBridge,
    required SonioxTranscriber transcriber,
  }) : _platformBridge = platformBridge,
       _transcriber = transcriber;

  static const originalHotkeyKey = 'original_hotkey';
  static const translationHotkeyKey = 'translation_hotkey';
  static const pasteViaClipboardKey = 'paste_via_clipboard';
  static const launchToTrayKey = 'launch_to_tray';
  static const advancedModeEnabledKey = 'advanced_mode_enabled';
  static const onboardingDismissedKey = 'onboarding_dismissed';
  static const tokenEndpointKey = 'token_endpoint';
  static const websocketEndpointKey = 'websocket_endpoint';
  static const targetLanguageKey = 'target_language';
  static const sourceLanguageHintKey = 'source_language_hint';
  static const sampleRateKey = 'sample_rate';

  final PlatformBridge _platformBridge;
  final SonioxTranscriber _transcriber;

  SharedPreferences? _prefs;
  AppSettings _settings = AppSettings.defaults;
  AppViewState _state = AppViewState.initial();
  TranscriptMode? _pressedMode;
  bool _pendingRelease = false;

  AppSettings get settings => _settings;
  AppViewState get state => _state;
  bool get isRecording => _transcriber.isRecording;
  TranscriptMode? get activeMode => _transcriber.activeMode;

  Future<void> preloadSettings() async {
    _prefs ??= await SharedPreferences.getInstance();
    _loadSettings();
    _setState(
      _state.copyWith(
        advancedModeEnabled: _settings.advancedModeEnabled,
        onboardingDismissed: _settings.onboardingDismissed,
      ),
    );
  }

  SonioxSettings get _sonioxSettings => SonioxSettings(
    tokenEndpoint: _settings.tokenEndpoint,
    websocketEndpoint: _settings.websocketEndpoint,
    targetLanguage: _settings.targetLanguage,
    sourceLanguageHint: _settings.sourceLanguageHint,
    sampleRate: _settings.sampleRate,
  );

  Future<void> bootstrap() async {
    await preloadSettings();

    await _platformBridge.initialize();
    _platformBridge.onHotkeyEvent = onHotkeyEvent;

    _transcriber.onTranscriptProgress =
        ({
          required String originalAccumulated,
          required String translationAccumulated,
          required String originalProvisional,
          required String translationProvisional,
        }) {
          _setState(
            _state.copyWith(
              sessionOriginalAccumulated: originalAccumulated,
              sessionTranslationAccumulated: translationAccumulated,
              sessionOriginalProvisional: originalProvisional,
              sessionTranslationProvisional: translationProvisional,
            ),
          );
        };
    _transcriber.onWsStateChanged = (wsState) {
      _setState(_state.copyWith(wsStateLabel: _formatWsState(wsState)));
    };

    await _appendLog('dart:bootstrap:initialized');
    await applyHotkeys();
    await warmUpSession();

    _setState(
      _state.copyWith(
        isReady: true,
        phase: AppPhase.ready,
        wsStateLabel: _formatWsState(_transcriber.wsState),
        statusMessage:
            'Ready. Hold ${_settings.originalHotkey} for original or ${_settings.translationHotkey} for translation, then release to transcribe.',
        clearLastError: true,
      ),
    );
    await _appendLog('dart:bootstrap:ready');
  }

  Future<void> disposeAsync() async {
    await _transcriber.dispose();
    super.dispose();
  }

  Future<void> updateSettings(AppSettings nextSettings) async {
    _settings = nextSettings;
    _setState(
      _state.copyWith(
        advancedModeEnabled: nextSettings.advancedModeEnabled,
        onboardingDismissed: nextSettings.onboardingDismissed,
      ),
    );
    await _saveSettings(nextSettings);
  }

  Future<void> setAdvancedModeEnabled(bool enabled) async {
    await updateSettings(_settings.copyWith(advancedModeEnabled: enabled));
  }

  Future<void> dismissOnboarding() async {
    await updateSettings(_settings.copyWith(onboardingDismissed: true));
  }

  Future<void> applyHotkeys() async {
    try {
      await _platformBridge.configureHotkeys(
        originalHotkey: _settings.originalHotkey,
        translationHotkey: _settings.translationHotkey,
      );
      await setStatus(
        'Hotkeys active: ${_settings.originalHotkey} / ${_settings.translationHotkey}',
      );
    } on PlatformException catch (error) {
      await _fail(
        error.message ?? 'Failed to register global hotkeys on Windows.',
      );
    }
  }

  Future<void> warmUpSession() async {
    try {
      await _transcriber.warmUp(settings: _sonioxSettings, onStatus: setStatus);
      await _appendLog('dart:warmup:ok');
    } catch (error) {
      await _appendLog('dart:warmup:error:$error');
      await _fail('Warm-up failed: $error');
    }
  }

  Future<void> reconnect() async {
    if (_state.isBusy || _transcriber.isRecording) {
      return;
    }

    _setState(
      _state.copyWith(
        isBusy: true,
        phase: AppPhase.recovering,
        clearLastError: true,
      ),
    );
    try {
      await setStatus('Resetting Soniox WebSocket with current config...');
      await _transcriber.resetConnection(
        settings: _sonioxSettings,
        onStatus: setStatus,
      );
      _setState(
        _state.copyWith(
          isBusy: false,
          phase: AppPhase.ready,
          statusMessage: 'Soniox WebSocket reset completed.',
          clearLastError: true,
        ),
      );
    } catch (error) {
      await _fail('Failed to reset Soniox WebSocket: $error');
    }
  }

  Future<void> onHotkeyEvent(String kind, String action) async {
    await _appendLog('dart:event:$kind:$action');
    final mode = kind == 'translation'
        ? TranscriptMode.translation
        : TranscriptMode.original;

    if (_state.isBusy) {
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
      await startRecording(mode);
      return;
    }

    if (action == 'up' &&
        _transcriber.isRecording &&
        _pressedMode == mode &&
        _transcriber.activeMode == mode) {
      await stopRecording();
      _pressedMode = null;
    } else if (action == 'up') {
      await _appendLog('dart:event:up_ignored_state_mismatch');
    }
  }

  Future<void> startRecording(TranscriptMode mode) async {
    await _appendLog('dart:start:${mode.name}');
    _setState(
      _state.copyWith(
        isBusy: true,
        phase: AppPhase.listening,
        activeInputMode: _toActiveInputMode(mode),
        clearLastError: true,
      ),
    );
    try {
      await _transcriber.start(
        mode: mode,
        settings: _sonioxSettings,
        onStatus: setStatus,
      );
      await setStatus(
        'Recording ${mode == TranscriptMode.translation ? 'translation' : 'original'} audio. Release the hotkey to finalize.',
      );
      await _appendLog('dart:start:ok:${mode.name}');
    } catch (error) {
      await _appendLog('dart:start:error:$error');
      await _fail('Failed to start recording: $error');
      return;
    } finally {
      if (_state.phase != AppPhase.needsAttention) {
        _setState(_state.copyWith(isBusy: false));
      }
    }

    if (_pendingRelease &&
        _transcriber.isRecording &&
        _transcriber.activeMode == mode) {
      await _appendLog('dart:start:consuming_pending_release:${mode.name}');
      _pendingRelease = false;
      await stopRecording();
    }
  }

  Future<void> stopRecording() async {
    await _appendLog('dart:stop:begin');
    _setState(
      _state.copyWith(
        isBusy: true,
        phase: AppPhase.finalizing,
        clearLastError: true,
      ),
    );
    try {
      final result = await _transcriber.stop(onStatus: setStatus);
      if (result == null || result.text.trim().isEmpty) {
        await _appendLog('dart:stop:no_result');
        await _fail('No transcript returned from Soniox.');
        return;
      }

      _setState(
        _state.copyWith(
          phase: AppPhase.typing,
          lastOriginal: result.originalText,
          lastTranslation: result.translationText,
        ),
      );

      await _appendLog(
        'dart:stop:result:mode=${result.mode.name}:text=${result.text}',
      );
      await _platformBridge.pasteText(result.text, useClipboard: false);
      _setState(
        _state.copyWith(
          phase: AppPhase.ready,
          statusMessage:
              'Typed ${result.mode == TranscriptMode.translation ? 'translation' : 'original'} transcript directly.',
          clearLastError: true,
        ),
      );
    } catch (error) {
      await _appendLog('dart:stop:error:$error');
      await _fail('Failed to finalize transcript: $error');
      return;
    } finally {
      _pressedMode = null;
      _pendingRelease = false;
      if (_state.phase != AppPhase.needsAttention) {
        _setState(
          _state.copyWith(isBusy: false, activeInputMode: ActiveInputMode.none),
        );
      }
    }
  }

  Future<void> setStatus(String status) async {
    await _appendLog('dart:status:$status');
    _setState(_state.copyWith(statusMessage: status));
  }

  Future<void> _fail(String message) async {
    _setState(
      _state.copyWith(
        isBusy: false,
        phase: AppPhase.needsAttention,
        activeInputMode: ActiveInputMode.none,
        statusMessage: message,
        lastError: message,
      ),
    );
  }

  void _loadSettings() {
    final prefs = _prefs;
    if (prefs == null) {
      return;
    }

    _settings = AppSettings(
      originalHotkey:
          prefs.getString(originalHotkeyKey) ??
          AppSettings.defaults.originalHotkey,
      translationHotkey:
          prefs.getString(translationHotkeyKey) ??
          AppSettings.defaults.translationHotkey,
      pasteViaClipboard:
          prefs.getBool(pasteViaClipboardKey) ??
          AppSettings.defaults.pasteViaClipboard,
      launchToTray:
          prefs.getBool(launchToTrayKey) ?? AppSettings.defaults.launchToTray,
      advancedModeEnabled:
          prefs.getBool(advancedModeEnabledKey) ??
          AppSettings.defaults.advancedModeEnabled,
      onboardingDismissed:
          prefs.getBool(onboardingDismissedKey) ??
          AppSettings.defaults.onboardingDismissed,
      tokenEndpoint:
          prefs.getString(tokenEndpointKey) ??
          AppSettings.defaults.tokenEndpoint,
      websocketEndpoint:
          prefs.getString(websocketEndpointKey) ??
          AppSettings.defaults.websocketEndpoint,
      targetLanguage:
          prefs.getString(targetLanguageKey) ??
          AppSettings.defaults.targetLanguage,
      sourceLanguageHint:
          prefs.getString(sourceLanguageHintKey) ??
          AppSettings.defaults.sourceLanguageHint,
      sampleRate:
          prefs.getInt(sampleRateKey) ?? AppSettings.defaults.sampleRate,
    );
  }

  Future<void> _saveSettings(AppSettings settings) async {
    final prefs = _prefs;
    if (prefs == null) {
      return;
    }
    await prefs.setString(originalHotkeyKey, settings.originalHotkey);
    await prefs.setString(translationHotkeyKey, settings.translationHotkey);
    await prefs.setBool(pasteViaClipboardKey, settings.pasteViaClipboard);
    await prefs.setBool(launchToTrayKey, settings.launchToTray);
    await prefs.setBool(advancedModeEnabledKey, settings.advancedModeEnabled);
    await prefs.setBool(onboardingDismissedKey, settings.onboardingDismissed);
    await prefs.setString(tokenEndpointKey, settings.tokenEndpoint);
    await prefs.setString(websocketEndpointKey, settings.websocketEndpoint);
    await prefs.setString(targetLanguageKey, settings.targetLanguage);
    await prefs.setString(sourceLanguageHintKey, settings.sourceLanguageHint);
    await prefs.setInt(sampleRateKey, settings.sampleRate);
  }

  Future<void> _appendLog(String message) async {
    final file = File('C:/dev/input_app_flutter/flutter_app.log');
    await file.writeAsString('$message\n', mode: FileMode.append, flush: true);
  }

  void _setState(AppViewState nextState) {
    _state = _withStatusPresentation(nextState);
    notifyListeners();
  }

  AppViewState _withStatusPresentation(AppViewState nextState) {
    final statusTitle = switch (nextState.phase) {
      AppPhase.booting => 'Starting up',
      AppPhase.ready => 'Ready to type',
      AppPhase.listening =>
        nextState.activeInputMode == ActiveInputMode.translate
            ? 'Listening for translation'
            : 'Listening',
      AppPhase.finalizing => 'Turning speech into text',
      AppPhase.typing => 'Typing into your app',
      AppPhase.recovering => 'Trying to recover',
      AppPhase.needsAttention => 'Needs attention',
    };

    final statusTone = switch (nextState.phase) {
      AppPhase.needsAttention => AppStatusTone.warning,
      AppPhase.listening ||
      AppPhase.finalizing ||
      AppPhase.typing ||
      AppPhase.recovering => AppStatusTone.active,
      AppPhase.booting || AppPhase.ready => AppStatusTone.calm,
    };

    final fallbackDetail =
        'Hold ${_settings.originalHotkey} for Original or ${_settings.translationHotkey} for Translate.';

    return nextState.copyWith(
      statusTitle: statusTitle,
      statusDetail: nextState.statusMessage.isEmpty
          ? fallbackDetail
          : nextState.statusMessage,
      statusTone: statusTone,
      advancedModeEnabled: _settings.advancedModeEnabled,
      onboardingDismissed: _settings.onboardingDismissed,
    );
  }

  ActiveInputMode _toActiveInputMode(TranscriptMode mode) {
    return mode == TranscriptMode.translation
        ? ActiveInputMode.translate
        : ActiveInputMode.original;
  }

  String _formatWsState(SonioxWsState state) {
    switch (state) {
      case SonioxWsState.disconnected:
        return 'Disconnected';
      case SonioxWsState.connecting:
        return 'Connecting';
      case SonioxWsState.ready:
        return 'Ready';
      case SonioxWsState.reconnecting:
        return 'Reconnecting';
    }
  }
}
