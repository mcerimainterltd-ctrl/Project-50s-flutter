import os

path = 'lib/core/services/webrtc_service.dart'
with open(path, 'r') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    new_lines.append(line)
    # Inject variables at the top of the class
    if 'class WebRTCService {' in line:
        new_lines.append("  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();\n")
        new_lines.append("  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();\n")
        new_lines.append("\n  // Call this in your constructor or main.dart\n")
        new_lines.append("  Future<void> initRenderers() async {\n")
        new_lines.append("    await _localRenderer.initialize();\n")
        new_lines.append("    await _remoteRenderer.initialize();\n  }\n")

with open(path, 'w') as f:
    f.writelines(new_lines)
