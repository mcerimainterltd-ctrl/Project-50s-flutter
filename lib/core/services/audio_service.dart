import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

final audioServiceProvider = Provider<AudioService>((ref) => AudioService());

class AudioService {
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  final AudioPlayer _outgoingPlayer = AudioPlayer();
  final AudioPlayer _messagePlayer  = AudioPlayer();

  bool _ringing = false;

  // ── Incoming call ringtone — handled by Android CallService (device ringtone)
  Future<void> playRingtone() async { /* bypassed — Android handles ringtone */ }

  Future<void> stopRingtone() async {
    _ringing = false;
    await _ringtonePlayer.stop();
  }

  // ── Outgoing call tone — handled by Android CallService (device ringtone)
  Future<void> playOutgoing() async { /* bypassed — Android handles ringtone */ }

  Future<void> stopOutgoing() async {
    await _outgoingPlayer.stop();
  }

  // ── Message notification (plays once) ──────────────────────
  Future<void> playMessage() async {
    await _messagePlayer.setReleaseMode(ReleaseMode.release);
    await _messagePlayer.setVolume(1.0);
    await _messagePlayer.play(AssetSource('audio/xamepage_message.mp3'));
  }

  // ── Stop all ───────────────────────────────────────────────
  Future<void> stopAll() async {
    _ringing = false;
    try { await _ringtonePlayer.stop(); } catch (_) {}
    try { await _outgoingPlayer.stop(); } catch (_) {}
    try { await _messagePlayer.stop(); } catch (_) {}
    // Release audio focus on older Android
    try { await _ringtonePlayer.release(); } catch (_) {}
    try { await _outgoingPlayer.release(); } catch (_) {}
  }

  // ── Dispose ────────────────────────────────────────────────
  Future<void> dispose() async {
    await stopAll();
    await _ringtonePlayer.dispose();
    await _outgoingPlayer.dispose();
    await _messagePlayer.dispose();
  }
}
