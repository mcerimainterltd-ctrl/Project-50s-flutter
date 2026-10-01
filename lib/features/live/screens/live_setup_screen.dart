import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/live_provider.dart';
import 'live_broadcast_screen.dart';

class LiveSetupScreen extends ConsumerStatefulWidget {
  const LiveSetupScreen({super.key});

  @override
  ConsumerState<LiveSetupScreen> createState() => _LiveSetupScreenState();
}

class _LiveSetupScreenState extends ConsumerState<LiveSetupScreen> {
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();

  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(liveProvider.notifier).loadGoLiveAccess();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _startLive() async {
    final title = _titleController.text.trim();
    final category = _categoryController.text.trim();

    if (title.isEmpty || category.isEmpty) {
      _showMessage('Please enter a live title and category.');
      return;
    }

    final microphone = await Permission.microphone.request();

    if (!microphone.isGranted) {
      _showMessage('Microphone permission is required to go live.');
      return;
    }

    if (!mounted) return;

    setState(() => _starting = true);

    final result = await ref.read(liveProvider.notifier).startLive(
          title: title,
          category: category,
        );

    if (!mounted) return;

    setState(() => _starting = false);

    if (result == null) {
      final error = ref.read(liveProvider).error;
      _showMessage(
        error?.replaceFirst('StateError: ', '') ??
            'Unable to start XameLive.',
      );
      return;
    }

    context.push(
      '/live/broadcast',
      extra: result,
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.xBg,
      appBar: AppBar(
        backgroundColor: context.xBg,
        foregroundColor: context.xText,
        elevation: 0,
        title: const Text('Go Live'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _goLiveAccessCard(context),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.xSurface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.videocam_rounded,
                    color: context.xPrimary,
                    size: 42,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Start XameLive',
                    style: TextStyle(
                      color: context.xText,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Share your live video with people on XamePage.',
                    style: TextStyle(
                      color: context.xMuted,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _field(
                    context,
                    controller: _titleController,
                    label: 'Live title',
                    hint: 'What are you talking about?',
                    icon: Icons.title_rounded,
                  ),
                  const SizedBox(height: 16),
                  _field(
                    context,
                    controller: _categoryController,
                    label: 'Category',
                    hint: 'e.g. Music, News, Chat',
                    icon: Icons.category_rounded,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _starting ? null : _startLive,
                      icon: _starting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.live_tv_rounded),
                      label: Text(
                        _starting ? 'Starting…' : 'Start Live',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _goLiveAccessCard(BuildContext context) {
    final liveState = ref.watch(liveProvider);
    final entitlement = liveState.entitlement;

    if (liveState.entitlementLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.xSurface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Checking Go Live access...'),
          ],
        ),
      );
    }

    if (entitlement == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.xSurface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.card_giftcard_rounded,
              color: context.xPrimary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Go Live Access Not Active',
                    style: TextStyle(
                      color: context.xText,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your Go Live eligibility will be checked when you start.',
                    style: TextStyle(
                      color: context.xMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final expiry = entitlement.expiresAt;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.xSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            entitlement.trial
                ? Icons.card_giftcard_rounded
                : Icons.verified_rounded,
            color: context.xPrimary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entitlement.trial
                      ? 'Go Live Trial Active'
                      : 'Go Live Access Active',
                  style: TextStyle(
                    color: context.xText,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                if (expiry != null)
                  Text(
                    'Expires ${expiry.toLocal()}',
                    style: TextStyle(
                      color: context.xMuted,
                      fontSize: 13,
                    ),
                  ),
                if (!entitlement.trial &&
                    entitlement.remainingMinutes > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${entitlement.remainingMinutes} minutes remaining',
                    style: TextStyle(
                      color: context.xMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      enabled: !_starting,
      style: TextStyle(color: context.xText),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: context.xBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
