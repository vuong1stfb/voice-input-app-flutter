class AppSettings {
  const AppSettings({
    required this.originalHotkey,
    required this.translationHotkey,
    required this.pasteViaClipboard,
    required this.launchToTray,
    required this.advancedModeEnabled,
    required this.onboardingDismissed,
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
  final bool advancedModeEnabled;
  final bool onboardingDismissed;
  final String tokenEndpoint;
  final String websocketEndpoint;
  final String targetLanguage;
  final String sourceLanguageHint;
  final int sampleRate;

  AppSettings copyWith({
    String? originalHotkey,
    String? translationHotkey,
    bool? pasteViaClipboard,
    bool? launchToTray,
    bool? advancedModeEnabled,
    bool? onboardingDismissed,
    String? tokenEndpoint,
    String? websocketEndpoint,
    String? targetLanguage,
    String? sourceLanguageHint,
    int? sampleRate,
  }) {
    return AppSettings(
      originalHotkey: originalHotkey ?? this.originalHotkey,
      translationHotkey: translationHotkey ?? this.translationHotkey,
      pasteViaClipboard: pasteViaClipboard ?? this.pasteViaClipboard,
      launchToTray: launchToTray ?? this.launchToTray,
      advancedModeEnabled: advancedModeEnabled ?? this.advancedModeEnabled,
      onboardingDismissed: onboardingDismissed ?? this.onboardingDismissed,
      tokenEndpoint: tokenEndpoint ?? this.tokenEndpoint,
      websocketEndpoint: websocketEndpoint ?? this.websocketEndpoint,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      sourceLanguageHint: sourceLanguageHint ?? this.sourceLanguageHint,
      sampleRate: sampleRate ?? this.sampleRate,
    );
  }

  static const defaults = AppSettings(
    originalHotkey: 'F9',
    translationHotkey: 'F10',
    pasteViaClipboard: false,
    launchToTray: true,
    advancedModeEnabled: false,
    onboardingDismissed: false,
    tokenEndpoint:
        'https://soniox-proxy-ud00.onrender.com/api/soniox/speech-to-text',
    websocketEndpoint: 'wss://stt-rt.soniox.com/transcribe-websocket',
    targetLanguage: 'en',
    sourceLanguageHint: 'vi',
    sampleRate: 48000,
  );
}
