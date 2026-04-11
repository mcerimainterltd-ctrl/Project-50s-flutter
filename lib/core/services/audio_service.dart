import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final audioServiceProvider = Provider<AudioService>((ref) => AudioService());

class AudioService {
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  final AudioPlayer _outgoingPlayer = AudioPlayer();
  final AudioPlayer _messagePlayer  = AudioPlayer();

  bool _ringing = false;

  // ── Incoming call ringtone (loops) ─────────────────────────
  Future<void> playRingtone() async {
    if (_ringing) return;
    _ringing = true;
    await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
    await _ringtonePlayer.setVolume(1.0);
    await _ringtonePlayer.play(AssetSource('audio/xamepage_call.mp3'));
  }

  Future<void> stopRingtone() async {
    _ringing = false;
    await _ringtonePlayer.stop();
  }

  // ── Outgoing call tone (loops) ─────────────────────────────
  Future<void> playOutgoing() async {
    await _outgoingPlayer.setReleaseMode(ReleaseMode.loop);
    await _outgoingPlayer.setVolume(0.8);
    await _outgoingPlayer.play(AssetSource('audio/xamepage_outgoing.mp3'));
  }

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
    await _ringtonePlayer.stop();
    await _outgoingPlayer.stop();
    await _messagePlayer.stop();
  }

  // ── Dispose ────────────────────────────────────────────────
  Future<void> dispose() async {
    await stopAll();
    await _ringtonePlayer.dispose();
    await _outgoingPlayer.dispose();
    await _messagePlayer.dispose();
  }
}
