import os

path = 'lib/features/calling/screens/call_screen.dart'
with open(path, 'r') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    # 1. Inject the listener into initState logic
    if 'super.initState();' in line:
        new_lines.append(line)
        new_lines.append("    ref.read(webRTCServiceProvider).callState.listen((s) => s == CallState.ended ? context.go('/contacts') : null);\n")
        continue
    
    # 2. Fix the End Call Button logic specifically
    if 'ref.read(webRTCServiceProvider).endCall()' in line:
        new_lines.append("                onPressed: () { ref.read(webRTCServiceProvider).endCall(); if(mounted) context.go('/contacts'); },\n")
        continue
        
    new_lines.append(line)

with open(path, 'w') as f:
    f.writelines(new_lines)
