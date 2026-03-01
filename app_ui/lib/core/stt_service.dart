import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// On-device speech-to-text using Apple's Speech framework (via the
/// `speech_to_text` package). Calls [onFinalTranscript] when the user
/// finishes an utterance, which AppState routes to [sendTextTurn].
class SttService {
  final SpeechToText _stt = SpeechToText();

  bool _initialised = false;

  /// True when the user wants continuous listening (toggled by the button).
  /// The underlying recognizer may start/stop between utterances, but this
  /// flag stays true so we know to auto-restart.
  bool isListening = false;

  /// The partial (in-progress) transcript shown in the UI.
  String partialTranscript = '';

  /// Guards against duplicate restart calls from both onResult and onStatus.
  bool _pendingRestart = false;

  /// True while TTS is speaking — suppresses auto-restart.
  bool _pausedForTts = false;
  bool get pausedForTts => _pausedForTts;

  /// Fired when an utterance is finalised (silence detected).
  void Function(String transcript)? onFinalTranscript;

  /// Fired on any state change so the UI can rebuild.
  void Function()? onStateChanged;

  // ── Lifecycle ───────────────────────────────────────────────────────────

  Future<bool> _ensureInit() async {
    if (_initialised) return true;
    _initialised = await _stt.initialize(
      onStatus: _onStatus,
      onError: (e) {
        debugPrint('🎤 STT error: ${e.errorMsg}');
        // On error, try to restart if the user still wants listening.
        _scheduleRestart();
      },
    );
    debugPrint('🎤 STT init: $_initialised');
    return _initialised;
  }

  /// Called by the user (via AppState) to toggle listening on.
  Future<void> startListening() async {
    if (!await _ensureInit()) return;
    isListening = true;
    await _beginSession();
  }

  /// Mark STT as wanting to listen but don't start the recognizer yet.
  /// Used at session start so STT waits for the initial TTS guidance to
  /// finish before opening the mic (avoids hearing its own TTS output).
  Future<void> startListeningDeferred() async {
    if (!await _ensureInit()) return;
    isListening = true;
    _pausedForTts = true;
    // #region agent log
    debugPrint('[DBG:STT_DEFERRED] armed, waiting for TTS to finish');
    // #endregion
  }

  /// Kick off a single recognition session. Can be called repeatedly
  /// between utterances without touching [isListening].
  Future<void> _beginSession() async {
    // #region agent log
    debugPrint('[DBG:STT_BEGIN] sttActive=${_stt.isListening} paused=$_pausedForTts');
    // #endregion
    if (_stt.isListening) return;

    partialTranscript = '';
    _pendingRestart = false;

    try {
      await _stt.listen(
        onResult: (result) {
          partialTranscript = result.recognizedWords;
          onStateChanged?.call();

          if (result.finalResult) {
            final text = result.recognizedWords.trim();
            debugPrint('🎤 Final: $text');
            partialTranscript = '';
            onStateChanged?.call();
            if (text.isNotEmpty) {
              onFinalTranscript?.call(text);
            }
            _scheduleRestart();
          }
        },
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 3),
        cancelOnError: false,
        partialResults: true,
      );
    } catch (e) {
      debugPrint('🎤 STT listen error: $e');
      _scheduleRestart();
    }

    onStateChanged?.call();
  }

  /// Schedule a restart after the recognizer stops, debounced so
  /// simultaneous calls from onResult + onStatus don't race.
  void _scheduleRestart() {
    // #region agent log
    debugPrint('[DBG:RESTART_REQ] pending=$_pendingRestart listening=$isListening paused=$_pausedForTts');
    // #endregion
    if (_pendingRestart || !isListening || _pausedForTts) return;
    _pendingRestart = true;
    Future.delayed(const Duration(milliseconds: 400), () {
      // #region agent log
      debugPrint('[DBG:RESTART_FIRE] listening=$isListening paused=$_pausedForTts sttActive=${_stt.isListening}');
      // #endregion
      _pendingRestart = false;
      if (isListening) {
        debugPrint('🎤 Auto-restarting listen session');
        _beginSession();
      }
    });
  }

  void _onStatus(String status) {
    debugPrint('🎤 STT status: $status');
    if (status == 'done' || status == 'notListening') {
      _scheduleRestart();
    }
  }

  /// Temporarily stop the recognition session while TTS is playing,
  /// but keep [isListening] true so we know to resume afterwards.
  Future<void> pauseForTts() async {
    // #region agent log
    debugPrint('[DBG:PAUSE_TTS] listening=$isListening sttActive=${_stt.isListening}');
    // #endregion
    if (!isListening) return;
    _pausedForTts = true;
    _pendingRestart = false;
    partialTranscript = '';
    await _stt.stop();
    onStateChanged?.call();
    debugPrint('🎤 Paused for TTS');
  }

  /// Restart listening after TTS finishes.
  Future<void> resumeAfterTts() async {
    _pausedForTts = false;
    // #region agent log
    debugPrint('[DBG:RESUME_TTS] listening=$isListening sttActive=${_stt.isListening}');
    // #endregion
    if (!isListening) return;
    debugPrint('🎤 Resuming after TTS');
    await _beginSession();
  }

  /// Called by the user (via AppState) to toggle listening off.
  Future<void> stopListening() async {
    isListening = false;
    _pendingRestart = false;
    _pausedForTts = false;
    partialTranscript = '';
    await _stt.stop();
    onStateChanged?.call();
    debugPrint('🎤 Listening stopped');
  }

  void dispose() {
    isListening = false;
    _pendingRestart = false;
    _pausedForTts = false;
    _stt.stop();
    _stt.cancel();
  }
}
