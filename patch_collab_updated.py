import sys

# 1. Add collabUpdated stream to socket service
with open('lib/core/services/socket_service.dart', 'r') as f:
    sock = f.read()

old_s1 = """  final _collabAcceptedCtrl  = StreamController<Map<String,dynamic>>.broadcast();"""
new_s1 = """  final _collabAcceptedCtrl  = StreamController<Map<String,dynamic>>.broadcast();
  final _collabUpdatedCtrl   = StreamController<Map<String,dynamic>>.broadcast();"""

old_s2 = """  Stream<Map<String,dynamic>>       get collabAccepted  => _collabAcceptedCtrl.stream;"""
new_s2 = """  Stream<Map<String,dynamic>>       get collabAccepted  => _collabAcceptedCtrl.stream;
  Stream<Map<String,dynamic>>       get collabUpdated   => _collabUpdatedCtrl.stream;"""

old_s3 = """      if (d != null) _collabAcceptedCtrl.add(Map<String,dynamic>.from(d as Map));"""
new_s3 = """      if (d != null) _collabAcceptedCtrl.add(Map<String,dynamic>.from(d as Map));
    });
    socket.on('collab_updated', (d) {
      if (d != null) _collabUpdatedCtrl.add(Map<String,dynamic>.from(d as Map));"""

for label, old, new in [("ctrl decl", old_s1, new_s1), ("stream getter", old_s2, new_s2), ("socket.on", old_s3, new_s3)]:
    c = sock.count(old)
    if c != 1:
        print(f"ERROR socket_service {label}: expected 1, found {c}. Aborting.")
        import sys; sys.exit(1)
for label, old, new in [("ctrl decl", old_s1, new_s1), ("stream getter", old_s2, new_s2), ("socket.on", old_s3, new_s3)]:
    sock = sock.replace(old, new)
with open('lib/core/services/socket_service.dart', 'w') as f:
    f.write(sock)
print("socket_service patched.")

# 2. Add collabUpdated + collabAccepted refresh listeners in Discovery screen
with open('lib/features/discovery/screens/xame_discover_screen.dart', 'r') as f:
    disc = f.read()

old_d = "      // Collab listeners handled globally in app.dart"
new_d = """      // Collab listeners handled globally in app.dart
      // Feed refresh on collab events — both parties see split-screen immediately
      ref.read(socketServiceProvider).collabUpdated.listen((data) {
        if (!mounted) return;
        _loadData(refresh: true);
      });
      ref.read(socketServiceProvider).collabAccepted.listen((data) {
        if (!mounted) return;
        _loadData(refresh: true);
      });"""

c = disc.count(old_d)
if c != 1:
    print(f"ERROR discover {old_d!r}: expected 1, found {c}. Aborting.")
    import sys; sys.exit(1)
disc = disc.replace(old_d, new_d)
with open('lib/features/discovery/screens/xame_discover_screen.dart', 'w') as f:
    f.write(disc)
print("xame_discover_screen patched.")
