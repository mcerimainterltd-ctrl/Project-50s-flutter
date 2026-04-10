import os

path = 'lib/features/calling/screens/call_screen.dart'
with open(path, 'r') as f:
    content = f.read()

# Step A: Remove the blind start from initState
content = content.replace('_startTimer();', '// Timer waits for active state')

# Step B: Inject the conditional start into the service listener
# This looks for the transition to CallState.active
old_listener = '''      service.callState.listen((s) {
        if (s == CallState.ended && mounted) context.go('/contacts');
      });'''

new_listener = '''      service.callState.listen((s) {
        if (s == CallState.active && _timer == null) {
          _startTimer();
        }
        if (s == CallState.ended && mounted) {
          context.go('/contacts');
        }
      });'''

content = content.replace(old_listener, new_listener)

with open(path, 'w') as f:
    f.write(content)
