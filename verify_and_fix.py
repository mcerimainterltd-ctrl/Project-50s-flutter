import os

path = 'lib/core/services/webrtc_service.dart'
with open(path, 'r') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    new_lines.append(line)
    # Bridge 1: Link Local Camera to Renderer
    if 'localStream = await navigator.mediaDevices.getUserMedia(constraints);' in line:
        if '_localRenderer.srcObject = localStream;' not in "".join(lines):
            new_lines.append('    _localRenderer.srcObject = localStream;\n')
            new_lines.append('    _localRenderer.muted = false;\n')
    
    # Bridge 2: Link Remote Stream to Renderer & Audio
    if '_pc!.onAddStream = (stream) {' in line:
        if '_remoteRenderer.srcObject = stream;' not in "".join(lines):
            new_lines.append('      _remoteRenderer.srcObject = stream;\n')
            new_lines.append('      print("STREAM ATTACHED TO RENDERER");\n')

with open(path, 'w') as f:
    f.writelines(new_lines)
