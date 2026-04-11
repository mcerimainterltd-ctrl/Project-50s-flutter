import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

// ── State ─────────────────────────────────────────────────────────────────────
enum VoiceRecordState { idle, recording, recorded, playing }

class VoiceState {
  final VoiceRecordState recordState;
  final String? recordedPath;
  final Duration recordDuration;
  final Duration playPosition;
  final Duration playDuration;
  final bool isSpeechListening;
  final bool isTtsPlaying;
  final double amplitude;

  const VoiceState({
    this.recordState    = VoiceRecordState.idle,
    this.recordedPath,
    this.recordDuration = Duration.zero,
    this.playPosition   = Duration.zero,
    this.playDuration   = Duration.zero,
    this.isSpeechListening = false,
    this.isTtsPlaying   = false,
    this.amplitude      = 0.0,
  });

  VoiceState copyWith({
    VoiceRecordState? recordState, String? recordedPath,
    Duration? recordDuration, Duration? playPosition,
    Duration? playDuration, bool? isSpeechListening,
    bool? isTtsPlaying, double? amplitude,
  }) => VoiceState(
    recordState:       recordState       ?? this.recordState,
    recordedPath:      recordedPath      ?? this.recordedPath,
    recordDuration:    recordDuration    ?? this.recordDuration,
    playPosition:      playPosition      ?? this.playPosition,
    playDuration:      playDuration      ?? this.playDuration,
    isSpeechListening: isSpeechListening ?? this.isSpeechListening,
    isTtsPlaying:      isTtsPlaying      ?? this.isTtsPlaying,
    amplitude:         amplitude         ?? this.amplitude,
  );
}

// ── Notifier ──────────────────────────────────────────────────────────────────
class VoiceNotifier extends StateNotifier<VoiceState> {
  final _recorder = AudioRecorder();
  final _player   = AudioPlayer();
  final _tts      = FlutterTts();
  final _stt      = SpeechToText();

  Timer? _recordTimer;
  Timer? _amplitudeTimer;
  int    _recordSeconds = 0;

  VoiceNotifier() : super(const VoiceState()) {
    _initTts();
    _initPlayer();
  }

  void _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _tts.setStartHandler(() => state = state.copyWith(isTtsPlaying: true));
    _tts.setCompletionHandler(() => state = state.copyWith(isTtsPlaying: false));
    _tts.setCancelHandler(() => state = state.copyWith(isTtsPlaying: false));
    _tts.setErrorHandler((_) => state = state.copyWith(isTtsPlaying: false));
  }

  void _initPlayer() {
    _player.positionStream.listen((pos) {
      state = state.copyWith(playPosition: pos);
    });
    _player.durationStream.listen((dur) {
      if (dur != null) state = state.copyWith(playDuration: dur);
    });
    _player.playerStateStream.listen((ps) {
      if (ps.processingState == ProcessingState.completed) {
        state = state.copyWith(
          recordState: VoiceRecordState.recorded,
          playPosition: Duration.zero,
        );
      }
    });
  }

  // ── Recording ──────────────────────────────────────────────────────────────
  Future<void> startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return;

    final dir  = await getTemporaryDirectory();
    final path = '${dir.path}/voicenote_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      RecordConfig(
        encoder:    AudioEncoder.aacLc,
        bitRate:    128000,
        sampleRate: 44100,
      ),
      path: path,
    );

    _recordSeconds = 0;
    state = state.copyWith(
      recordState:    VoiceRecordState.recording,
      recordDuration: Duration.zero,
      recordedPath:   null,
      amplitude:      0.0,
    );

    // Timer for duration display
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _recordSeconds++;
      state = state.copyWith(
          recordDuration: Duration(seconds: _recordSeconds));
    });

    // Amplitude for waveform animation
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      final amp = await _recorder.getAmplitude();
      final normalized = ((amp.current + 60) / 60).clamp(0.0, 1.0);
      state = state.copyWith(amplitude: normalized);
    });
  }

  Future<String?> stopRecording() async {
    _recordTimer?.cancel();
    _amplitudeTimer?.cancel();
    final path = await _recorder.stop();
    state = state.copyWith(
      recordState: path != null
          ? VoiceRecordState.recorded
          : VoiceRecordState.idle,
      recordedPath: path,
      amplitude:    0.0,
    );
    return path;
  }

  void cancelRecording() async {
    _recordTimer?.cancel();
    _amplitudeTimer?.cancel();
    await _recorder.cancel();
    state = const VoiceState();
  }

  // ── Playback ───────────────────────────────────────────────────────────────
  Future<void> playRecorded() async {
    if (state.recordedPath == null) return;
    await _player.setFilePath(state.recordedPath!);
    await _player.play();
    state = state.copyWith(recordState: VoiceRecordState.playing);
  }

  Future<void> playFromUrl(String url) async {
    await _player.setUrl(url);
    await _player.play();
    state = state.copyWith(recordState: VoiceRecordState.playing);
  }

  Future<void> pausePlay() async {
    await _player.pause();
    state = state.copyWith(recordState: VoiceRecordState.recorded);
  }

  Future<void> seekTo(Duration position) async {
    await _player.seek(position);
  }

  void reset() {
    _recordTimer?.cancel();
    _amplitudeTimer?.cancel();
    _player.stop();
    state = const VoiceState();
  }

  // ── Speech to Text ─────────────────────────────────────────────────────────
  Future<bool> initSpeech() async {
    return await _stt.initialize(
      onError: (_) => state = state.copyWith(isSpeechListening: false),
    );
  }

  Future<void> startListening(Function(String) onResult) async {
    final available = await initSpeech();
    if (!available) return;
    state = state.copyWith(isSpeechListening: true);
    await _stt.listen(
      onResult: (result) {
        onResult(result.recognizedWords);
        if (result.finalResult) {
          state = state.copyWith(isSpeechListening: false);
        }
      },
      listenFor:    const Duration(seconds: 30),
      pauseFor:     const Duration(seconds: 3),
      localeId:     'en_US',
      listenMode:   ListenMode.confirmation,
    );
  }

  Future<void> stopListening() async {
    await _stt.stop();
    state = state.copyWith(isSpeechListening: false);
  }

  // ── Text to Speech ─────────────────────────────────────────────────────────
  Future<void> speak(String text) async {
    if (state.isTtsPlaying) {
      await _tts.stop();
      return;
    }
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
    state = state.copyWith(isTtsPlaying: false);
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _amplitudeTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
    _tts.stop();
    _stt.stop();
    super.dispose();
  }
}

final voiceProvider = StateNotifierProvider<VoiceNotifier, VoiceState>(
  (_) => VoiceNotifier());
