import 'package:flutter/services.dart';

class PlatformBridge {
  PlatformBridge();

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
