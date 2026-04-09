import os

path = 'lib/core/services/webrtc_service.dart'
with open(path, 'r') as f:
    content = f.read()

# Fix 1: Ensure getUserMedia and addTrack happen COMPLETELY before signaling
# We move the track addition into a guaranteed sequence
old_setup = """  Future<void> _setup(bool v) async {
    _pc = await createPeerConnection({'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]});
    _pc!.onIceCandidate = (c) => _socket.emitIceCandidate(currentRemoteUserId!, {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    _pc!.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        _remoteRenderer.srcObject = e.streams[0];
        _remoteStreamController.add(e.streams[0]);
      }
    };
    localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': v});
    _localRenderer.srcObject = localStream;
    localStream!.getTracks().forEach((t) => _pc!.addTrack(t, localStream!));
  }"""

new_setup = """  Future<void> _setup(bool v) async {
    _pc = await createPeerConnection({
      'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}],
      'sdpSemantics': 'unified-plan'
    });
    
    _pc!.onIceCandidate = (c) => _socket.emitIceCandidate(currentRemoteUserId!, {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    
    _pc!.onTrack = (e) {
      if (e.streams.isNotEmpty && _remoteRenderer.srcObject == null) {
        _remoteRenderer.srcObject = e.streams[0];
        _remoteStreamController.add(e.streams[0]);
      }
    };

    // We MUST await the hardware before moving to the next step in joinCall/startCall
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true, 
      'video': v ? {'facingMode': 'user'} : false
    });
    
    _localRenderer.srcObject = localStream;
    for (var track in localStream!.getTracks()) {
      await _pc!.addTrack(track, localStream!);
    }
  }"""

content = content.replace(old_setup, new_setup)

with open(path, 'w') as f:
    f.write(content)
