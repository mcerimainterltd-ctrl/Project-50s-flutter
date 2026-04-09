import os

path = 'lib/core/services/webrtc_service.dart'
with open(path, 'r') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    new_lines.append(line)
    if '_socket.incomingCall.listen((data) {' in line:
        new_lines.append('      if (data.callerId == _socket.currentUserId) return; // Ignore self\n')

with open(path, 'w') as f:
    f.writelines(new_lines)
