import os

app_path = 'lib/app.dart'
with open(app_path, 'r') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    # Remove any reference to the deleted file
    if 'webrtc_socket_service.dart' in line:
        continue
    # Ensure we are importing the actual socket service
    if "import 'package:xamepage/core/services/socket_service.dart';" not in new_lines:
        new_lines.append("import 'package:xamepage/core/services/socket_service.dart';\n")
    new_lines.append(line)

content = "".join(new_lines)
with open(app_path, 'w') as f:
    f.write(content)
