import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';

class UpdateService {
  static final _dio = Dio(BaseOptions(
    baseUrl:        AppConstants.serverUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      final res  = await _dio.get('/api/app/version');
      final data = res.data as Map<String, dynamic>;
      if (data['success'] != true) return;

      final serverBuild = (data['buildNumber'] as num?)?.toInt() ?? 0;
      final forceUpdate = data['forceUpdate'] as bool? ?? false;
      final downloadUrl = data['downloadUrl'] as String? ?? '';
      final changelog   = data['changelog']   as String? ?? 'Bug fixes and improvements.';
      final version     = data['version']     as String? ?? '';

      if (serverBuild <= AppConstants.appBuildNumber) return;
      if (!context.mounted) return;

      showDialog(
        context: context,
        barrierDismissible: !forceUpdate,
        builder: (_) => _UpdateDialog(
          version:     version,
          changelog:   changelog,
          downloadUrl: downloadUrl,
          forceUpdate: forceUpdate,
        ),
      );
    } catch (_) {}
  }
}

class _UpdateDialog extends StatelessWidget {
  final String version, changelog, downloadUrl;
  final bool   forceUpdate;
  const _UpdateDialog({
    required this.version,
    required this.changelog,
    required this.downloadUrl,
    required this.forceUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !forceUpdate,
      child: AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00B0A0).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.system_update_rounded,
              color: Color(0xFF00B0A0), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Update Available',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              if (version.isNotEmpty)
                Text('Version $version',
                  style: const TextStyle(color: Color(0xFF00B0A0), fontSize: 12)),
            ]),
          ),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(changelog,
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, height: 1.5)),
          ),
          if (forceUpdate) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 14),
                SizedBox(width: 6),
                Expanded(child: Text('This update is required to continue using XamePage.',
                  style: TextStyle(color: Color(0xFFEF4444), fontSize: 11))),
              ]),
            ),
          ],
        ]),
        actions: [
          if (!forceUpdate)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later', style: TextStyle(color: Color(0xFF6B7280))),
            ),
          ElevatedButton.icon(
            onPressed: () async {
              final uri = Uri.parse(downloadUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Download Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00B0A0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}
