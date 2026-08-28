import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';

class PublicWebProfileScreen extends ConsumerWidget {
  const PublicWebProfileScreen({super.key});

  static const String _baseUrl = 'https://app.xamepage.com/u/';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Public Web Profile')),
        body: const Center(
          child: Text('Please sign in to access your public profile.'),
        ),
      );
    }

    final profileUrl = '$_baseUrl${user.xameId}';
    final displayName = user.displayName.isNotEmpty
        ? user.displayName
        : user.firstName;

    return Scaffold(
      backgroundColor: context.xBg,
      appBar: AppBar(
        backgroundColor: context.xBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.xText),
          tooltip: 'Back',
          onPressed: () => context.go('/contacts'),
        ),
        title: const Text(
          'Public Web Profile',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: _ProfileAvatar(
                  imageUrl: user.profilePic,
                  name: displayName,
                ),
              ),
              const SizedBox(height: 16),

              Text(
                displayName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.xText,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                '@${user.xameId}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.xMuted,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 30),

              Text(
                'Your Public Web Profile',
                style: TextStyle(
                  color: context.xText,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Share this link with anyone. They can view your XamePage profile from a web browser without installing the app.',
                style: TextStyle(
                  color: context.xMuted,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 18),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.xSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: context.xMuted.withOpacity(.18),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        profileUrl,
                        style: TextStyle(
                          color: context.xText,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.link_rounded,
                      color: context.xMuted,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: profileUrl),
                    );

                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Public profile link copied'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy Profile Link'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.xPrimary,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Share.share(
                      profileUrl,
                      subject: '$displayName on XamePage',
                    );
                  },
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Share Profile'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.xText,
                    side: BorderSide(
                      color: context.xMuted.withOpacity(.25),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                height: 52,
                child: TextButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse(profileUrl);
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Preview Public Profile'),
                  style: TextButton.styleFrom(
                    foregroundColor: context.xPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 26),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.xSurface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.public_rounded,
                      color: context.xPrimary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Visitors can use your public profile to message you, call you, or send money through XamePay.',
                        style: TextStyle(
                          color: context.xMuted,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;

  const _ProfileAvatar({
    required this.imageUrl,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl?.isNotEmpty == true;

    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: context.xPrimary,
          width: 3,
        ),
      ),
      child: ClipOval(
        child: hasImage
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(context),
              )
            : _placeholder(context),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: context.xSurface,
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          color: context.xPrimary,
          fontSize: 36,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
