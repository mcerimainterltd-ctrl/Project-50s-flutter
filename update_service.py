import os

path = 'lib/core/services/webrtc_service.dart'
with open(path, 'r') as f:
    content = f.read()

# Adding the missing rejection signal
if 'void rejectCall()' not in content:
    replacement = """
  void rejectCall() {
    _socket.emitCallRejected(currentRemoteUserId ?? "", "declined");
    _callStateController.add(CallState.ended);
    _incomingCallController.add(false);
  }

  void endCall() {"""
    content = content.replace('void endCall() {', replacement)

with open(path, 'w') as f:
    f.write(content)
