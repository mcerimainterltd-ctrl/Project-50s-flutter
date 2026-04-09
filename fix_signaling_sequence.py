import os

path = 'lib/core/services/webrtc_service.dart'
with open(path, 'r') as f:
    content = f.read()

# Fix joinCall: We MUST await _setup fully before creating the answer
old_join = '''  Future<void> joinCall(bool isVideo) async {
    if (_pendingOffer == null) return;
    await _setup(isVideo);
    await _pc!.setRemoteDescription(RTCSessionDescription(_pendingOffer['sdp'], _pendingOffer['type']));
    _remoteDescriptionSet = true;
    var answer = await _pc!.createAnswer();'''

new_join = '''  Future<void> joinCall(bool isVideo) async {
    if (_pendingOffer == null) return;
    // 1. Setup hardware and WAIT for tracks to be added
    await _setup(isVideo); 
    
    // 2. Set remote info
    await _pc!.setRemoteDescription(RTCSessionDescription(_pendingOffer['sdp'], _pendingOffer['type']));
    _remoteDescriptionSet = true;
    
    // 3. Create Answer (Now it will include the tracks we added in _setup)
    var answer = await _pc!.createAnswer();'''

content = content.replace(old_join, new_join)

# Fix startCall: Same logic, ensure hardware is ready before creating offer
old_start = '''  Future<void> startCall(String userId, bool isVideo) async {
    currentRemoteUserId = userId;
    _callState = CallState.outgoing; _callStateController.add(CallState.outgoing);
    await _setup(isVideo);
    var offer = await _pc!.createOffer();'''

new_start = '''  Future<void> startCall(String userId, bool isVideo) async {
    currentRemoteUserId = userId;
    _callState = CallState.outgoing; _callStateController.add(CallState.outgoing);
    // 1. Setup hardware first
    await _setup(isVideo);
    
    // 2. Create Offer (This now contains the media info)
    var offer = await _pc!.createOffer();'''

content = content.replace(old_start, new_start)

with open(path, 'w') as f:
    f.write(content)
