import os

path = 'lib/core/services/webrtc_service.dart'
with open(path, 'r') as f:
    content = f.read()

# Fix A: Add the Listener for the 'Remote' End Call
# This ensures that when the OTHER person hangs up, your screen closes too.
if '_socket.callEnded.listen' not in content:
    listener_code = '''
    _socket.callEnded.listen((data) {
      _handleRemoteHangup();
    });
    '''
    content = content.replace('WebRTCService(this._socket) {', f'WebRTCService(this._socket) {{ {listener_code}')

# Fix B: Add the Helper methods for cleaning up
if 'void _handleRemoteHangup()' not in content:
    cleanup_methods = '''
  void _handleRemoteHangup() {
    _callState = CallState.ended;
    _callStateController.add(CallState.ended);
    _cleanup();
  }

  void _cleanup() {
    localStream?.getTracks().forEach((t) => t.stop());
    localStream?.dispose();
    localStream = null;
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _pc?.close();
    _pc = null;
    _remoteDescriptionSet = false;
  }
'''
    # Insert before the last closing brace
    content = content.rstrip().rstrip('}') + cleanup_methods + '\n}'

# Fix C: Ensure endCall uses the shared cleanup
content = content.replace(
    'void endCall() {',
    'void endCall() {\n    _socket.emitCallEnded(currentRemoteUserId ?? "");\n    _cleanup();'
)

with open(path, 'w') as f:
    f.write(content)
