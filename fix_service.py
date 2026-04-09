import os

path = 'lib/core/services/webrtc_service.dart'
with open(path, 'r') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    new_lines.append(line)
    # Inject the public getters right after the class declaration
    if 'class WebRTCService {' in line:
        new_lines.append("  RTCVideoRenderer get localRenderer => _localRenderer;\n")
        new_lines.append("  RTCVideoRenderer get remoteRenderer => _remoteRenderer;\n")

with open(path, 'w') as f:
    f.writelines(new_lines)
