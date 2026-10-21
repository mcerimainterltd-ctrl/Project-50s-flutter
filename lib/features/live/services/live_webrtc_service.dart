
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

void _logXameLiveSdpDiagnostics(
  String flow,
  http.Response response,
  String answerSdp,
) {
  final lines = answerSdp.split(RegExp(r'\r?\n'));
  debugPrint(
    '[XAMELIVE] $flow response: status=${response.statusCode}, '
    'contentType=${response.headers['content-type'] ?? 'missing'}, '
    'bytes=${answerSdp.length}, '
    'v0=${lines.any((line) => line.trim() == 'v=0')}, '
    'origin=${lines.any((line) => line.startsWith('o='))}, '
    'media=${lines.where((line) => line.startsWith('m=')).length}, '
    'attributes=${lines.where((line) => line.startsWith('a=')).length}',
  );
}

void _validateXameLiveSdpAnswer(String flow, String answerSdp) {
  if (answerSdp.isEmpty) {
    throw StateError('$flow returned an empty SDP answer.');
  }

  final lines = answerSdp
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .toList();

  final hasVersion = lines.any((line) => line == 'v=0');
  final hasOrigin = lines.any((line) => line.startsWith('o='));
  final hasSessionName = lines.any((line) => line.startsWith('s='));
  final hasTiming = lines.any((line) => line.startsWith('t='));
  final mediaCount = lines.where((line) => line.startsWith('m=')).length;

  if (!hasVersion ||
      !hasOrigin ||
      !hasSessionName ||
      !hasTiming ||
      mediaCount == 0) {
    throw StateError(
      '$flow returned an invalid SDP answer '
      '(version=$hasVersion, origin=$hasOrigin, '
      'sessionName=$hasSessionName, timing=$hasTiming, '
      'mediaSections=$mediaCount).',
    );
  }
}

class LiveWebRTCService {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  RTCVideoRenderer? _remoteRenderer;

  String? _sessionUrl;
  bool _closed = false;

  MediaStream? get localStream => _localStream;
  RTCVideoRenderer? get remoteRenderer => _remoteRenderer;
  bool get isClosed => _closed;

  Future<void> startBroadcast({
    required String publishUrl,
    required RTCVideoRenderer localRenderer,
    bool video = true,
    bool audio = true,
  }) async {
    await dispose();

    _closed = false;

    final pc = await _createPeerConnection();
    _pc = pc;

    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': audio,
        'video': video
            ? {
                'facingMode': 'user',
                'width': 640,
                'height': 480,
              }
            : false,
      });

      _localStream = stream;
      localRenderer.srcObject = stream;

      for (final track in stream.getTracks()) {
        await pc.addTransceiver(
          track: track,
          init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendOnly,
          ),
        );
      }

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _waitForIceGatheringComplete(pc);

      final localDescription = await pc.getLocalDescription();
      final sdp = localDescription?.sdp ?? offer.sdp;
      if (sdp == null || sdp.isEmpty) {
        throw StateError('WebRTC broadcaster SDP offer is empty.');
      }

      final response = await http.post(
        Uri.parse(publishUrl),
        headers: const {
          'Content-Type': 'application/sdp',
        },
        body: sdp,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'WHIP negotiation failed (${response.statusCode}): '
          '${response.body}',
        );
      }

      final answerSdp = '${response.body.trim().split(RegExp(r'\r?\n')).join('\r\n')}\r\n';
      _logXameLiveSdpDiagnostics(
        'WHIP',
        response,
        answerSdp,
      );
      _validateXameLiveSdpAnswer('WHIP', answerSdp);

      await pc.setRemoteDescription(
        RTCSessionDescription(answerSdp, 'answer'),
      );

      _sessionUrl = _resolveSessionUrl(
        response.headers['location'],
        publishUrl,
      );

      debugPrint('[XAMELIVE] broadcaster WebRTC connected');
      debugPrint('[XAMELIVE] WHIP session: $_sessionUrl');
    } catch (_) {
      await dispose();
      rethrow;
    }
  }

  Future<void> startViewer({
    required String playbackUrl,
    required RTCVideoRenderer renderer,
  }) async {
    await dispose();

    _closed = false;
    _remoteRenderer = renderer;

    final pc = await _createPeerConnection();
    _pc = pc;

    try {
      final remoteStream = await createLocalMediaStream(
        'xame_live_remote_${DateTime.now().millisecondsSinceEpoch}',
      );

      _remoteStream = remoteStream;
      renderer.srcObject = remoteStream;

      pc.onTrack = (event) {
        final track = event.track;

        if (!remoteStream.getTracks().contains(track)) {
          remoteStream.addTrack(track);
        }

        track.enabled = true;

        debugPrint(
          '[XAMELIVE] viewer track received: ${track.kind}',
        );
      };

      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.RecvOnly,
        ),
      );

      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.RecvOnly,
        ),
      );

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _waitForIceGatheringComplete(pc);

      final localDescription = await pc.getLocalDescription();
      final sdp = localDescription?.sdp ?? offer.sdp;
      if (sdp == null || sdp.isEmpty) {
        throw StateError('WebRTC viewer SDP offer is empty.');
      }

      final response = await http.post(
        Uri.parse(playbackUrl),
        headers: const {
          'Content-Type': 'application/sdp',
        },
        body: sdp,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'WHEP negotiation failed (${response.statusCode}): '
          '${response.body}',
        );
      }

      final answerSdp = '${response.body.trim().split(RegExp(r'\r?\n')).join('\r\n')}\r\n';
      _logXameLiveSdpDiagnostics(
        'WHEP',
        response,
        answerSdp,
      );
      _validateXameLiveSdpAnswer('WHEP', answerSdp);

      await pc.setRemoteDescription(
        RTCSessionDescription(answerSdp, 'answer'),
      );

      _sessionUrl = _resolveSessionUrl(
        response.headers['location'],
        playbackUrl,
      );

      debugPrint('[XAMELIVE] viewer WebRTC connected');
      debugPrint('[XAMELIVE] WHEP session: $_sessionUrl');
    } catch (_) {
      await dispose();
      rethrow;
    }
  }

  Future<void> _waitForIceGatheringComplete(
    RTCPeerConnection pc, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (pc.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }

    final completer = Completer<void>();
    late Timer timer;

    pc.onIceGatheringState = (state) {
      debugPrint('[XAMELIVE] ICE gathering state: $state');

      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !completer.isCompleted) {
        timer.cancel();
        completer.complete();
      }
    };

    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        debugPrint('[XAMELIVE] ICE gathering timeout; continuing with current SDP');
        completer.complete();
      }
    });

    await completer.future;
  }

  Future<RTCPeerConnection> _createPeerConnection() async {
    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
        {'urls': 'stun:stun3.l.google.com:19302'},
        {
          'urls': 'turn:openrelay.metered.ca:80',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
        {
          'urls': 'turn:openrelay.metered.ca:443',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
      ],
      'sdpSemantics': 'unified-plan',
    });

    pc.onIceConnectionState = (state) {
      debugPrint('[XAMELIVE] ICE state: $state');
    };

    pc.onConnectionState = (state) {
      debugPrint('[XAMELIVE] connection state: $state');
    };

    return pc;
  }

  String? _resolveSessionUrl(
    String? location,
    String endpoint,
  ) {
    if (location == null || location.trim().isEmpty) {
      return null;
    }

    final value = location.trim();

    try {
      return Uri.parse(value).isAbsolute
          ? value
          : Uri.parse(endpoint).resolve(value).toString();
    } catch (_) {
      return value;
    }
  }

  Future<void> _disposeStreamSafely(
    MediaStream stream,
    String label,
  ) async {
    try {
      for (final track in stream.getTracks()) {
        try {
          track.stop();
        } catch (e) {
          debugPrint('[XAMELIVE] $label track stop failed: $e');
        }
      }
    } catch (e) {
      debugPrint('[XAMELIVE] $label track enumeration failed: $e');
    }

    try {
      await stream.dispose();
    } catch (e) {
      debugPrint('[XAMELIVE] $label stream disposal failed: $e');
    }
  }

  Future<void> dispose() async {
    _closed = true;

    final sessionUrl = _sessionUrl;
    _sessionUrl = null;

    if (sessionUrl != null && sessionUrl.isNotEmpty) {
      try {
        final response = await http.delete(Uri.parse(sessionUrl));

        debugPrint(
          '[XAMELIVE] WebRTC session DELETE: ${response.statusCode}',
        );
      } catch (e) {
        debugPrint(
          '[XAMELIVE] WebRTC session DELETE failed: $e',
        );
      }
    }

    final stream = _localStream;
    _localStream = null;

    if (stream != null) {
      await _disposeStreamSafely(stream, 'Local');
    }

    final remoteStream = _remoteStream;
    _remoteStream = null;

    if (remoteStream != null) {
      await _disposeStreamSafely(remoteStream, 'Remote');
    }

    final remoteRenderer = _remoteRenderer;
    _remoteRenderer = null;

    if (remoteRenderer != null) {
      try {
        remoteRenderer.srcObject = null;
      } catch (e) {
        debugPrint('[XAMELIVE] Remote renderer cleanup failed: $e');
      }
    }

    final pc = _pc;
    _pc = null;

    if (pc != null) {
      try {
        await pc.close();
      } catch (e) {
        debugPrint('[XAMELIVE] Peer connection close failed: $e');
      }
    }
  }
}
