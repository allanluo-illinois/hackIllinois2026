import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Lightweight wrapper around flutter_tts for reading agent text aloud.
///
/// Queues messages so each utterance finishes before the next begins.
/// Only the most recent pending message is kept (stale ones are dropped).
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool isSpeaking = false;

  /// The text currently being spoken (or last spoken).
  String currentText = '';

  /// Called whenever [isSpeaking] or [currentText] changes.
  void Function()? onStateChanged;

  /// The next message to speak after the current one finishes.
  /// Null means nothing is queued; setting a new value replaces the old one.
  String? _pending;
  DateTime? _speakStartedAt;

  TtsService() {
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.55);
    _tts.setPitch(1.0);
    _tts.setVolume(1.0);

    _tts.setStartHandler(() {
      debugPrint('🔊 TTS started');
      isSpeaking = true;
      _speakStartedAt = DateTime.now();
      onStateChanged?.call();
    });
    _tts.setCompletionHandler(() {
      debugPrint('🔊 TTS completed');
      isSpeaking = false;
      onStateChanged?.call();
      _playNext();
    });
    _tts.setCancelHandler(() {
      debugPrint('🔊 TTS cancelled');
      isSpeaking = false;
      onStateChanged?.call();
    });
    _tts.setErrorHandler((msg) {
      debugPrint('🔊 TTS error: $msg');
      isSpeaking = false;
      onStateChanged?.call();
      _playNext();
    });

    _tts.setSharedInstance(true);
    _tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playAndRecord,
      [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
      ],
    );

    _selectBestVoice();
  }

  /// Ranked preference of clear, professional-sounding iOS voices.
  static const _preferredVoices = [
    'Reed',     // clearest male iOS voice
    'Daniel',   // clear British male
    'Samantha', // fallback female
  ];

  Future<void> _selectBestVoice() async {
    try {
      final voices = await _tts.getVoices as List<dynamic>?;
      if (voices == null) return;

      final enVoices = voices
          .cast<Map<dynamic, dynamic>>()
          .where((v) => (v['locale'] as String? ?? '').startsWith('en'))
          .toList();

      final names = enVoices.map((v) => v['name'] as String).toSet();

      for (final preferred in _preferredVoices) {
        if (names.contains(preferred)) {
          final match = enVoices.firstWhere((v) => v['name'] == preferred);
          await _tts.setVoice({
            'name': preferred,
            'locale': match['locale'] as String,
          });
          debugPrint('🔊 TTS voice: $preferred');
          return;
        }
      }
    } catch (e) {
      debugPrint('🔊 TTS voice selection failed: $e');
    }
  }

  /// Queue [text] to be spoken. If nothing is currently playing, speaks
  /// immediately. Otherwise replaces any pending message so only the
  /// latest queued text is played after the current utterance finishes.
  Future<void> speak(String? text) async {
    if (text == null || text.trim().isEmpty) return;

    // Recover from stuck isSpeaking (no completion callback for >10s).
    if (isSpeaking && _speakStartedAt != null) {
      final elapsed = DateTime.now().difference(_speakStartedAt!);
      if (elapsed.inSeconds > 10) {
        debugPrint('🔊 TTS stuck — resetting');
        isSpeaking = false;
        await _tts.stop();
      }
    }

    if (isSpeaking) {
      // #region agent log
      debugPrint('[DBG:TTS_QUEUE] queuing (already speaking), pending="${text.length > 40 ? text.substring(0, 40) : text}"');
      // #endregion
      _pending = text;
      return;
    }
    currentText = text;
    _speakStartedAt = DateTime.now();
    debugPrint('🔊 TTS speak: "${text.substring(0, text.length.clamp(0, 50))}"');
    onStateChanged?.call();
    await _tts.speak(text);
  }

  void _playNext() {
    final next = _pending;
    _pending = null;
    if (next != null && next.trim().isNotEmpty) {
      currentText = next;
      onStateChanged?.call();
      _tts.speak(next);
    }
  }

  /// Immediately stop speech and clear the queue.
  Future<void> stop() async {
    _pending = null;
    currentText = '';
    await _tts.stop();
    isSpeaking = false;
    onStateChanged?.call();
  }

  Future<void> dispose() async {
    _pending = null;
    await _tts.stop();
  }
}
