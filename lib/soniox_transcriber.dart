import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';

enum TranscriptMode { original, translation }

enum SonioxWsState { disconnected, connecting, ready, reconnecting }

class SonioxSettings {
  const SonioxSettings({
    required this.tokenEndpoint,
    required this.websocketEndpoint,
    required this.targetLanguage,
    required this.sourceLanguageHint,
    required this.sampleRate,
  });

  final String tokenEndpoint;
  final String websocketEndpoint;
  final String targetLanguage;
  final String sourceLanguageHint;
  final int sampleRate;
}

class TranscriptResult {
  const TranscriptResult({
    required this.mode,
    required this.text,
    required this.originalText,
    required this.translationText,
  });

  final TranscriptMode mode;
  final String text;
  final String originalText;
  final String translationText;
}

class SonioxTranscriber {
  SonioxTranscriber();

  static const int _channels = 1;
  static const int _timesliceMs = 500;
  static const int _finalizeSilenceMs = 200;
  static const Duration _transportPingInterval = Duration(seconds: 20);
  static const Duration _segmentFinalTimeout = Duration(seconds: 5);

  final AudioRecorder _recorder = AudioRecorder();
  final String _origin = 'https://soniox.com';
  final File _logFile = File('C:/dev/input_app_flutter/soniox_debug.log');

  StreamSubscription<Uint8List>? _audioSubscription;
  WebSocket? _websocket;
  Completer<TranscriptResult?>? _resultCompleter;
  Timer? _keepAliveTimer;
  Timer? _reconnectTimer;
  final BytesBuilder _pcmBuffer = BytesBuilder(copy: false);

  TranscriptMode? _activeMode;
  SonioxSettings? _preparedSettings;
  int _activeSampleRate = 48000;
  int? _streamSampleRate;
  int _chunkBytesTarget = 0;
  int _audioBytesSent = 0;
  bool _hasSentAudio = false;
  bool _captureAudio = false;
  bool _commitRequested = false;
  bool _segmentActive = false;
  final Map<String, String> _pendingSegmentTexts = {
    'original': '',
    'translation': '',
  };
  final Map<String, String> _pendingProvisionalTexts = {
    'original': '',
    'translation': '',
  };
  bool _finalMarkerSeen = false;
  bool _isStopping = false;
  bool _isPreparing = false;
  bool _isDisposed = false;
  bool _closingSocket = false;
  bool _recorderReady = false;
  SonioxSettings? _lastRequestedSettings;
  SonioxWsState _wsState = SonioxWsState.disconnected;
  void Function({
    required String originalAccumulated,
    required String translationAccumulated,
    required String originalProvisional,
    required String translationProvisional,
  })? onTranscriptProgress;
  void Function(SonioxWsState state)? onWsStateChanged;

  bool get isRecording => _activeMode != null;
  TranscriptMode? get activeMode => _activeMode;
  bool get isPreparing => _isPreparing;
  SonioxWsState get wsState => _wsState;

  Future<void> _appendLog(String message) async {
    await _logFile.writeAsString('$message\n', mode: FileMode.append, flush: true);
  }

  Future<void> warmUp({
    required SonioxSettings settings,
    required Future<void> Function(String status) onStatus,
  }) async {
    _lastRequestedSettings = settings;
    await _ensureRecorderReady(onStatus);
    await _ensureLiveInputStream(settings, onStatus);
    await _ensurePreparedSession(
      settings: settings,
      onStatus: onStatus,
    );
  }

  Future<void> start({
    required TranscriptMode mode,
    required SonioxSettings settings,
    required Future<void> Function(String status) onStatus,
  }) async {
    if (isRecording) {
      throw StateError('A recording session is already active.');
    }

    _lastRequestedSettings = settings;
    await _ensureRecorderReady(onStatus);
    await _ensureLiveInputStream(settings, onStatus);
    await _ensurePreparedSession(
      settings: settings,
      onStatus: onStatus,
    );

    _resetSession(mode, settings.sampleRate);
    _resultCompleter = Completer<TranscriptResult?>();
    _stopKeepAlive();
    await _appendLog('soniox:start:mode=${mode.name}:sampleRate=${settings.sampleRate}');
    _notifyTranscriptProgress();
    _captureAudio = true;

    await onStatus(
      'Recording... hold ${mode == TranscriptMode.original ? 'Original' : 'Translation'} and release to finalize.',
    );
  }

  Future<TranscriptResult?> stop({
    required Future<void> Function(String status) onStatus,
  }) async {
    if (!isRecording || _isStopping) {
      return null;
    }

    _isStopping = true;
    _captureAudio = false;
    await onStatus('Stopping microphone...');
    await _flushPcmBuffer();

    TranscriptResult? result;
    if (_hasSentAudio) {
      await onStatus('Finalizing transcript...');
      await _commitSegment();
      result = await _waitForSegmentText();
    } else {
      await _appendLog('soniox:stop:skip_finalize_no_audio');
    }

    _finishStopState();
    await _appendLog(
      result == null
          ? 'soniox:stop:no_result'
          : 'soniox:stop:result:mode=${result.mode.name}:original=${result.originalText}:translation=${result.translationText}:selected=${result.text}',
    );
    return result;
  }

  Future<void> dispose() async {
    _isDisposed = true;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    _stopKeepAlive();
    _stopReconnect();
    await _recorder.dispose();
    await _closeSocket();
  }

  Future<void> resetConnection({
    required SonioxSettings settings,
    required Future<void> Function(String status) onStatus,
  }) async {
    _lastRequestedSettings = settings;
    await _appendLog('soniox:manual_reset_requested');
    await _closeSocket();
    await warmUp(settings: settings, onStatus: onStatus);
  }

  void _handleSocketMessage(dynamic raw) {
    final decoded = jsonDecode(raw as String);
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    if (isRecording && !_hasSentAudio) {
      unawaited(_appendLog('soniox:ignore_pre_audio_payload'));
      return;
    }

    if (decoded['error_code'] != null) {
      unawaited(
        _appendLog(
          'soniox:error_payload:code=${decoded['error_code']}:message=${decoded['error_message'] ?? decoded['message'] ?? decoded.toString()}',
        ),
      );
      final code = decoded['error_code'];
      final selectedChannel = _selectedChannel;
      if (code == 408 &&
          _commitRequested &&
          _pendingSegmentTexts[selectedChannel]!.trim().isEmpty &&
          _pendingProvisionalTexts[selectedChannel]!.trim().isNotEmpty) {
        _pendingSegmentTexts[selectedChannel] =
            _pendingProvisionalTexts[selectedChannel]!.trim();
      }
      _segmentActive = false;
      _completeIfPending(_buildBestEffortResult());
      _notifyTranscriptProgress();
      return;
    }

    final tokens = decoded['tokens'];
    if (tokens is! List) {
      return;
    }

    final finalTexts = {'original': '', 'translation': ''};
    final provisionalTexts = {'original': '', 'translation': ''};
    var hasEnd = false;
    var hasFin = false;
    var tokenCount = 0;

    for (final token in tokens) {
      if (token is! Map) {
        continue;
      }
      tokenCount += 1;

      final tokenText = _tokenText(token);
      final isFinal = _tokenIsFinal(token);
      final channel = _tokenChannel(token);

      if (tokenText == '<end>' ||
          token['is_end'] == true ||
          token['end'] == true) {
        hasEnd = true;
        continue;
      }
      if (tokenText == '<fin>') {
        hasFin = true;
        continue;
      }

      if (channel == 'translation') {
        if (isFinal) {
          finalTexts['translation'] = '${finalTexts['translation']}$tokenText';
        } else {
          provisionalTexts['translation'] =
              '${provisionalTexts['translation']}$tokenText';
        }
        continue;
      }

      if (isFinal) {
        finalTexts['original'] = '${finalTexts['original']}$tokenText';
      } else {
        provisionalTexts['original'] = '${provisionalTexts['original']}$tokenText';
      }
    }

    if (finalTexts['original']!.isNotEmpty) {
      _pendingSegmentTexts['original'] =
          '${_pendingSegmentTexts['original']}${finalTexts['original']}';
      _pendingProvisionalTexts['original'] = '';
    }
    if (provisionalTexts['original']!.isNotEmpty) {
      _pendingProvisionalTexts['original'] = provisionalTexts['original']!;
    }
    if (finalTexts['translation']!.isNotEmpty) {
      _pendingSegmentTexts['translation'] =
          '${_pendingSegmentTexts['translation']}${finalTexts['translation']}';
      _pendingProvisionalTexts['translation'] = '';
    }
    if (provisionalTexts['translation']!.isNotEmpty) {
      _pendingProvisionalTexts['translation'] = provisionalTexts['translation']!;
    }

    if (hasEnd ||
        hasFin ||
        finalTexts['original']!.trim().isNotEmpty ||
        provisionalTexts['original']!.trim().isNotEmpty ||
        finalTexts['translation']!.trim().isNotEmpty ||
        provisionalTexts['translation']!.trim().isNotEmpty ||
        tokenCount > 0) {
      unawaited(
        _appendLog(
          'soniox:payload_summary:tokens=$tokenCount:has_end=$hasEnd:has_fin=$hasFin:final_original_len=${finalTexts['original']!.trim().length}:provisional_original_len=${provisionalTexts['original']!.trim().length}:final_translation_len=${finalTexts['translation']!.trim().length}:provisional_translation_len=${provisionalTexts['translation']!.trim().length}',
        ),
      );
    }

    if (hasEnd || hasFin) {
      _finalMarkerSeen = true;
      final selectedChannel = _selectedChannel;
      if (_pendingSegmentTexts[selectedChannel]!.trim().isEmpty &&
          _pendingProvisionalTexts[selectedChannel]!.trim().isNotEmpty) {
        _pendingSegmentTexts[selectedChannel] =
            _pendingProvisionalTexts[selectedChannel]!.trim();
      }
      if (_commitRequested && _pendingSegmentTexts[selectedChannel]!.trim().isNotEmpty) {
        _segmentActive = false;
        _commitRequested = false;
        unawaited(
          _appendLog(
            'soniox:marker:${hasFin ? '<fin>' : '<end>'}:original=${_pendingSegmentTexts['original']}:translation=${_pendingSegmentTexts['translation']}:provisional=${_pendingProvisionalTexts[selectedChannel]}',
          ),
        );
        _completeIfPending(_buildBestEffortResult());
      }
    }
    _notifyTranscriptProgress();
  }

  Future<void> _ensureRecorderReady(
    Future<void> Function(String status) onStatus,
  ) async {
    if (_recorderReady) {
      return;
    }

    await onStatus('Checking microphone permission...');
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission was denied.');
    }

    await onStatus('Checking PCM encoder support...');
    if (!await _recorder.isEncoderSupported(AudioEncoder.pcm16bits)) {
      throw StateError('PCM16 stream is not supported on this machine.');
    }

    _recorderReady = true;
  }

  Future<void> _ensurePreparedSession({
    required SonioxSettings settings,
    required Future<void> Function(String status) onStatus,
  }) async {
    _lastRequestedSettings = settings;
    if (_websocket != null &&
        _preparedSettings?.tokenEndpoint == settings.tokenEndpoint &&
        _preparedSettings?.websocketEndpoint == settings.websocketEndpoint &&
        _preparedSettings?.targetLanguage == settings.targetLanguage &&
        _preparedSettings?.sourceLanguageHint == settings.sourceLanguageHint &&
        _preparedSettings?.sampleRate == settings.sampleRate) {
      return;
    }

    _isPreparing = true;
    _setWsState(SonioxWsState.connecting);
    _stopReconnect();
    await _closeSocket();

    await onStatus('Fetching Soniox token...');
    final token = await _fetchToken(settings.tokenEndpoint);

    await onStatus('Connecting to Soniox...');
    final socket = await WebSocket.connect(settings.websocketEndpoint);
    socket.pingInterval = _transportPingInterval;
    _websocket = socket;
    _preparedSettings = settings;

    socket.listen(
      _handleSocketMessage,
      onError: (Object error, StackTrace stackTrace) {
        unawaited(_appendLog('soniox:socket_error:$error'));
        _handleSocketTerminalState();
        _completeIfPending(_buildBestEffortResult());
      },
      onDone: () {
        unawaited(_appendLog('soniox:socket_done'));
        _handleSocketTerminalState();
        if (_resultCompleter != null &&
            !_resultCompleter!.isCompleted &&
            !_finalMarkerSeen) {
          _completeIfPending(_buildBestEffortResult());
        }
      },
      cancelOnError: true,
    );

    final languageHints = settings.sourceLanguageHint
        .split(',')
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty && value != 'auto')
        .toSet()
        .toList();

    final configMessage = {
      'api_key': token,
      'audio_format': 's16le',
      'sample_rate': settings.sampleRate,
      'num_channels': _channels,
      'model': 'stt-rt-v4',
      if (languageHints.isNotEmpty) 'language_hints': languageHints,
      'enable_speaker_diarization': true,
      'enable_language_identification': true,
      'enable_endpoint_detection': true,
      'max_endpoint_delay_ms': 500,
      'translation': {
        'type': 'one_way',
        'target_language': settings.targetLanguage,
        'source_languages': ['*'],
      },
    };

    socket.add(
      jsonEncode(configMessage),
    );
    unawaited(
      _appendLog(
        'soniox:prepared:source_hint=${settings.sourceLanguageHint}:target=${settings.targetLanguage}:sampleRate=${settings.sampleRate}:translation_enabled=true:transport_ping_sec=${_transportPingInterval.inSeconds}',
      ),
    );

    _isPreparing = false;
    _startKeepAlive();
    _setWsState(SonioxWsState.ready);
    await onStatus('Soniox session ready.');
  }

  Future<void> _ensureLiveInputStream(
    SonioxSettings settings,
    Future<void> Function(String status) onStatus,
  ) async {
    if (_audioSubscription != null && _streamSampleRate == settings.sampleRate) {
      return;
    }

    await _audioSubscription?.cancel();
    _audioSubscription = null;
    _captureAudio = false;

    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }

    await onStatus('Opening microphone stream...');
    final audioStream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: settings.sampleRate,
        numChannels: _channels,
      ),
    );
    _streamSampleRate = settings.sampleRate;
    _audioSubscription = audioStream.listen((bytes) {
      if (!_captureAudio || !isRecording || _isStopping) {
        return;
      }
      _handleAudioChunk(bytes);
    });
    await _appendLog('soniox:input_stream_ready:sampleRate=${settings.sampleRate}');
  }

  Future<String> _fetchToken(String endpoint) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      request.headers.set('origin', _origin);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Token endpoint failed with HTTP ${response.statusCode}.',
        );
      }

      final contentType = response.headers.contentType?.mimeType ?? '';
      final payload = contentType.contains('application/json')
          ? jsonDecode(body)
          : body;
      final token = _extractTokenDeep(payload);
      if (token == null || token.isEmpty) {
        throw StateError('Token response did not contain a valid api key.');
      }
      return token;
    } finally {
      client.close(force: true);
    }
  }

  String? _extractTokenDeep(Object? payload) {
    if (payload == null) {
      return null;
    }
    if (payload is String) {
      final trimmed = payload.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (payload is! Map) {
      return null;
    }

    final map = payload.cast<Object?, Object?>();
    const candidates = ['token', 'apiKey', 'api_key', 'x-api-key', 'key'];
    for (final candidate in candidates) {
      final value = map[candidate];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    for (final value in map.values) {
      final nested = _extractTokenDeep(value);
      if (nested != null) {
        return nested;
      }
    }
    return null;
  }

  String _tokenText(Map token) {
    const fields = [
      'text',
      'token',
      'value',
      'original_text',
      'translated_text',
    ];
    for (final field in fields) {
      final value = token[field];
      if (value is String) {
        return value;
      }
    }
    return '';
  }

  bool _tokenIsFinal(Map token) {
    for (final field in ['is_final', 'isFinal', 'final']) {
      final value = token[field];
      if (value is bool) {
        return value;
      }
    }
    return false;
  }

  String _tokenChannel(Map token) {
    final raw =
        token['translation_status'] ?? token['channel'] ?? token['type'];
    return raw == 'translation' ? 'translation' : 'original';
  }

  Uint8List _buildTailSilence() {
    final sampleCount = (_activeSampleRate * _finalizeSilenceMs / 1000).round();
    return Uint8List(sampleCount * 2);
  }

  TranscriptResult? _buildBestEffortResult() {
    final mode = _activeMode;
    if (mode == null) {
      return null;
    }

    final original = _pickFullerText(
      _pendingSegmentTexts['original']!,
      _pendingProvisionalTexts['original']!,
    );
    final translation = _pickFullerText(
      _pendingSegmentTexts['translation']!,
      _pendingProvisionalTexts['translation']!,
    );
    final selected = mode == TranscriptMode.translation
        ? (translation.isNotEmpty ? translation : original)
        : original;

    if (selected.isEmpty) {
      return null;
    }

    return TranscriptResult(
      mode: mode,
      text: selected,
      originalText: original,
      translationText: translation,
    );
  }

  void _resetSession(TranscriptMode mode, int sampleRate) {
    _activeMode = mode;
    _activeSampleRate = sampleRate;
    _chunkBytesTarget = ((sampleRate * _channels * 2 * _timesliceMs) / 1000)
        .round()
        .clamp(2, 1 << 30);
    _audioBytesSent = 0;
    _hasSentAudio = false;
    _commitRequested = false;
    _segmentActive = true;
    _captureAudio = false;
    _pendingSegmentTexts['original'] = '';
    _pendingSegmentTexts['translation'] = '';
    _pendingProvisionalTexts['original'] = '';
    _pendingProvisionalTexts['translation'] = '';
    _pcmBuffer.clear();
    _finalMarkerSeen = false;
    _isStopping = false;
  }

  void _notifyTranscriptProgress() {
    final callback = onTranscriptProgress;
    if (callback == null) {
      return;
    }
    callback(
      originalAccumulated: _pendingSegmentTexts['original']!.trim(),
      translationAccumulated: _pendingSegmentTexts['translation']!.trim(),
      originalProvisional: _pendingProvisionalTexts['original']!.trim(),
      translationProvisional: _pendingProvisionalTexts['translation']!.trim(),
    );
  }

  String get _selectedChannel =>
      _activeMode == TranscriptMode.translation ? 'translation' : 'original';

  String _pickFullerText(String primary, String fallback) {
    final primaryTrimmed = primary.trim();
    final fallbackTrimmed = fallback.trim();
    if (primaryTrimmed.isEmpty) {
      return fallbackTrimmed;
    }
    if (fallbackTrimmed.isEmpty) {
      return primaryTrimmed;
    }
    if (fallbackTrimmed.contains(primaryTrimmed) &&
        fallbackTrimmed.length >= primaryTrimmed.length) {
      return fallbackTrimmed;
    }
    if (primaryTrimmed.contains(fallbackTrimmed) &&
        primaryTrimmed.length >= fallbackTrimmed.length) {
      return primaryTrimmed;
    }
    return fallbackTrimmed.length > primaryTrimmed.length
        ? fallbackTrimmed
        : primaryTrimmed;
  }

  void _handleAudioChunk(Uint8List bytes) {
    if (_websocket == null || bytes.isEmpty) {
      return;
    }
    _pcmBuffer.add(bytes);
    while (_pcmBuffer.length >= _chunkBytesTarget) {
      final data = _pcmBuffer.takeBytes();
      final chunk = Uint8List.sublistView(data, 0, _chunkBytesTarget);
      final remainder = data.length > _chunkBytesTarget
          ? Uint8List.sublistView(data, _chunkBytesTarget)
          : Uint8List(0);
      _sendAudioChunk(chunk);
      if (remainder.isNotEmpty) {
        _pcmBuffer.add(remainder);
      }
    }
  }

  Future<void> _flushPcmBuffer() async {
    if (_pcmBuffer.isEmpty) {
      return;
    }
    final remainder = _pcmBuffer.takeBytes();
    await _appendLog('soniox:flush_last_chunk:bytes=${remainder.length}');
    _sendAudioChunk(remainder);
  }

  void _sendAudioChunk(Uint8List bytes) {
    if (_websocket == null || bytes.isEmpty) {
      return;
    }
    _websocket!.add(bytes);
    _audioBytesSent += bytes.length;
    _hasSentAudio = true;
  }

  Future<void> _commitSegment() async {
    if (_websocket == null) {
      return;
    }
    _commitRequested = true;
    _finalMarkerSeen = false;
    _websocket!.add(_buildTailSilence());
    _websocket!.add(jsonEncode({'type': 'finalize'}));
    await _appendLog(
      'soniox:finalize_sent:audio_bytes=$_audioBytesSent:tail_silence_ms=$_finalizeSilenceMs',
    );
  }

  Future<TranscriptResult?> _waitForSegmentText() async {
    try {
      return await _resultCompleter?.future.timeout(
        _segmentFinalTimeout,
        onTimeout: () {
          final fallback = _buildBestEffortResult();
          return fallback;
        },
      );
    } finally {
      _pendingSegmentTexts['original'] = '';
      _pendingSegmentTexts['translation'] = '';
      _pendingProvisionalTexts['original'] = '';
      _pendingProvisionalTexts['translation'] = '';
      _commitRequested = false;
      _segmentActive = false;
      _notifyTranscriptProgress();
    }
  }

  void _finishStopState() {
    _activeMode = null;
    _resultCompleter = null;
    _isStopping = false;
    _captureAudio = false;
    _startKeepAlive();
  }

  void _completeIfPending(TranscriptResult? result) {
    final completer = _resultCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  void _startKeepAlive() {
    _stopKeepAlive();
    if (_websocket == null || isRecording) {
      return;
    }
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_websocket != null && !isRecording && !_segmentActive && !_commitRequested) {
        _websocket!.add(jsonEncode({'type': 'keepalive'}));
        unawaited(_appendLog('soniox:keepalive_sent'));
      }
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  void _setWsState(SonioxWsState state) {
    if (_wsState == state) {
      return;
    }
    _wsState = state;
    onWsStateChanged?.call(state);
  }

  void _scheduleReconnect() {
    if (_isDisposed || _reconnectTimer != null || _isPreparing) {
      return;
    }
    final settings = _lastRequestedSettings;
    if (settings == null) {
      return;
    }
    _setWsState(SonioxWsState.reconnecting);
    _reconnectTimer = Timer(const Duration(seconds: 2), () async {
      _reconnectTimer = null;
      if (_isDisposed || _websocket != null) {
        return;
      }
      try {
        await _appendLog('soniox:reconnect_attempt');
        await _ensurePreparedSession(
          settings: settings,
          onStatus: (_) async {},
        );
      } catch (error) {
        await _appendLog('soniox:reconnect_failed:$error');
        _setWsState(SonioxWsState.disconnected);
        _scheduleReconnect();
      }
    });
  }

  void _stopReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _handleSocketTerminalState() {
    if (_closingSocket) {
      return;
    }
    _stopKeepAlive();
    _websocket = null;
    _preparedSettings = null;
    _isPreparing = false;
    _setWsState(SonioxWsState.disconnected);
    _scheduleReconnect();
  }

  Future<void> _closeSocket() async {
    _stopKeepAlive();
    _stopReconnect();
    final socket = _websocket;
    _websocket = null;
    _preparedSettings = null;
    _isPreparing = false;
    _setWsState(SonioxWsState.disconnected);
    if (socket == null) {
      return;
    }
    _closingSocket = true;
    try {
      await socket.close();
    } finally {
      _closingSocket = false;
    }
  }
}
