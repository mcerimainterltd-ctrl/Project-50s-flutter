import re

path = 'lib/features/calling/screens/incoming_call_screen.dart'
with open(path, 'r') as f:
    content = f.read()

# Ensure UI import exists
if 'import "dart:ui";' not in content:
    content = 'import "dart:ui";\n' + content

new_ui = '''
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final webrtc = ref.watch(webRTCServiceProvider);
    final userId = webrtc.currentRemoteUserId ?? "Unknown User";
    final isVideo = webrtc.isIncomingVideo;
    const String? profileUrl = null; 

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(color: Color(0xFF0D1117)),
            child: profileUrl != null 
                ? Image.network(profileUrl, fit: BoxFit.cover, height: double.infinity, width: double.infinity)
                : Container(color: const Color(0xFF161B22)),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(color: Colors.black.withOpacity(0.5)),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 800),
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.scale(scale: 0.8 + (0.2 * value), child: child),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white10, width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 70,
                      backgroundColor: Colors.blueGrey.shade800,
                      child: profileUrl == null 
                        ? Text(userId.isNotEmpty ? userId[0].toUpperCase() : "?", 
                            style: const TextStyle(fontSize: 48, color: Colors.white, fontWeight: FontWeight.bold))
                        : null,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Text(userId, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 8),
                Text("INCOMING ${isVideo ? 'VIDEO' : 'VOICE'} CALL",
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const Spacer(flex: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildModernButton(
                        icon: Icons.close, label: "Decline", color: Colors.redAccent,
                        onTap: () { webrtc.rejectCall(); context.pop(); },
                      ),
                      _buildModernButton(
                        icon: isVideo ? Icons.videocam : Icons.call, label: "Accept", color: Colors.greenAccent.shade400,
                        onTap: () {
                          webrtc.joinCall(isVideo);
                          context.push('/call/$userId?video=$isVideo&incoming=true');
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 75, width: 75,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.5), width: 1.5),
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
'''

pattern = r'  @override\n  Widget build\(BuildContext context, WidgetRef ref\) \{.*?\}\n\}'
updated_content = re.sub(pattern, new_ui, content, flags=re.DOTALL)

with open(path, 'w') as f:
    f.write(updated_content)
