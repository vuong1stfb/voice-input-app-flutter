enum AppPhase {
  booting,
  ready,
  listening,
  finalizing,
  typing,
  recovering,
  needsAttention,
}

enum ActiveInputMode { none, original, translate }

enum AppStatusTone { calm, active, warning }

class AppViewState {
  const AppViewState({
    required this.isReady,
    required this.isBusy,
    required this.phase,
    required this.activeInputMode,
    required this.statusMessage,
    required this.statusTitle,
    required this.statusDetail,
    required this.statusTone,
    required this.advancedModeEnabled,
    required this.onboardingDismissed,
    required this.wsStateLabel,
    required this.lastOriginal,
    required this.lastTranslation,
    required this.sessionOriginalAccumulated,
    required this.sessionTranslationAccumulated,
    required this.sessionOriginalProvisional,
    required this.sessionTranslationProvisional,
    required this.lastError,
  });

  final bool isReady;
  final bool isBusy;
  final AppPhase phase;
  final ActiveInputMode activeInputMode;
  final String statusMessage;
  final String statusTitle;
  final String statusDetail;
  final AppStatusTone statusTone;
  final bool advancedModeEnabled;
  final bool onboardingDismissed;
  final String wsStateLabel;
  final String lastOriginal;
  final String lastTranslation;
  final String sessionOriginalAccumulated;
  final String sessionTranslationAccumulated;
  final String sessionOriginalProvisional;
  final String sessionTranslationProvisional;
  final String? lastError;

  factory AppViewState.initial() {
    return const AppViewState(
      isReady: false,
      isBusy: false,
      phase: AppPhase.booting,
      activeInputMode: ActiveInputMode.none,
      statusMessage: 'Booting Windows shell...',
      statusTitle: 'Starting up',
      statusDetail: 'Booting Windows shell...',
      statusTone: AppStatusTone.calm,
      advancedModeEnabled: false,
      onboardingDismissed: false,
      wsStateLabel: 'Disconnected',
      lastOriginal: '',
      lastTranslation: '',
      sessionOriginalAccumulated: '',
      sessionTranslationAccumulated: '',
      sessionOriginalProvisional: '',
      sessionTranslationProvisional: '',
      lastError: null,
    );
  }

  AppViewState copyWith({
    bool? isReady,
    bool? isBusy,
    AppPhase? phase,
    ActiveInputMode? activeInputMode,
    String? statusMessage,
    String? statusTitle,
    String? statusDetail,
    AppStatusTone? statusTone,
    bool? advancedModeEnabled,
    bool? onboardingDismissed,
    String? wsStateLabel,
    String? lastOriginal,
    String? lastTranslation,
    String? sessionOriginalAccumulated,
    String? sessionTranslationAccumulated,
    String? sessionOriginalProvisional,
    String? sessionTranslationProvisional,
    String? lastError,
    bool clearLastError = false,
  }) {
    return AppViewState(
      isReady: isReady ?? this.isReady,
      isBusy: isBusy ?? this.isBusy,
      phase: phase ?? this.phase,
      activeInputMode: activeInputMode ?? this.activeInputMode,
      statusMessage: statusMessage ?? this.statusMessage,
      statusTitle: statusTitle ?? this.statusTitle,
      statusDetail: statusDetail ?? this.statusDetail,
      statusTone: statusTone ?? this.statusTone,
      advancedModeEnabled: advancedModeEnabled ?? this.advancedModeEnabled,
      onboardingDismissed: onboardingDismissed ?? this.onboardingDismissed,
      wsStateLabel: wsStateLabel ?? this.wsStateLabel,
      lastOriginal: lastOriginal ?? this.lastOriginal,
      lastTranslation: lastTranslation ?? this.lastTranslation,
      sessionOriginalAccumulated:
          sessionOriginalAccumulated ?? this.sessionOriginalAccumulated,
      sessionTranslationAccumulated:
          sessionTranslationAccumulated ?? this.sessionTranslationAccumulated,
      sessionOriginalProvisional:
          sessionOriginalProvisional ?? this.sessionOriginalProvisional,
      sessionTranslationProvisional:
          sessionTranslationProvisional ?? this.sessionTranslationProvisional,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }
}
