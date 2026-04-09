import os

path = 'lib/app.dart'
with open(path, 'r') as f:
    content = f.read()

# Re-inject the socket connection logic safely
if 'ref.read(socketServiceProvider).connect' not in content:
    target = 'final user = ref.watch(currentUserProvider);'
    replacement = target + '\n    if (user != null) {\n      Future.microtask(() => ref.read(socketServiceProvider).connect(user.xameId));\n    }'
    content = content.replace(target, replacement)

with open(path, 'w') as f:
    f.write(content)
