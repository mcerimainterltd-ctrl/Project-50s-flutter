import os

path = 'lib/features/calling/screens/call_screen.dart'
with open(path, 'r') as f:
    content = f.read()

# Modify the _startTimer function to check the current state before incrementing
old_timer_fn = '''  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _seconds++);
    });
  }'''

new_timer_fn = '''  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final state = ref.read(webRTCServiceProvider).callStateStreamValue;
      if (mounted && state == CallState.active) {
        setState(() => _seconds++);
      }
    });
  }'''

content = content.replace(old_timer_fn, new_timer_fn)

# Also ensure _startTimer is called in initState again to allow the guard to work
if '// Timer waits for active state' in content:
    content = content.replace('// Timer waits for active state', '_startTimer();')

with open(path, 'w') as f:
    f.write(content)
