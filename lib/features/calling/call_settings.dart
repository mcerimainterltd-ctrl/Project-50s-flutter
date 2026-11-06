import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:xamepage/core/config/constants.dart';
import 'package:xamepage/core/theme/app_theme.dart';

// ── Model ─────────────────────────────────────────────────────────────────────
class BlockedEntry {
  final String xameId, name, reason;
  final int blockedAt;
  const BlockedEntry({required this.xameId, required this.name,
      required this.reason, required this.blockedAt});

  Map<String, dynamic> toJson() =>
      {'number': xameId, 'name': name, 'reason': reason, 'blockedAt': blockedAt};

  factory BlockedEntry.fromJson(Map<String, dynamic> j) => BlockedEntry(
    xameId:    j['number']    as String,
    name:      j['name']      as String? ?? '',
    reason:    j['reason']    as String? ?? '',
    blockedAt: j['blockedAt'] as int?    ?? 0,
  );
}

// ── Service ───────────────────────────────────────────────────────────────────
class CallBlockingService {
  static const _key = 'xame:blockedNumbers';

  // BLOCK_SERVER_LIST_V1: the block list now lives on the server
  Future<Map<String, String>> _headers() async {
    final token = await const FlutterSecureStorage().read(key: AppConstants.keySessionToken);
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<BlockedEntry>> getBlockedList() async {
    try {
      final r = await http.get(
        Uri.parse('${AppConstants.serverUrl}/api/blocked-contacts'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 15));
      final d = jsonDecode(r.body);
      if (d['success'] == true) {
        return (d['blocked'] as List).map((e) => BlockedEntry(
          xameId: (e['xameId'] ?? '').toString(),
          name: (e['name'] ?? '').toString(),
          reason: '', blockedAt: 0)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _save(List<BlockedEntry> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<bool> isBlocked(String xameId) async {
    final list = await getBlockedList();
    return list.any((e) => e.xameId == xameId);
  }

  Future<bool> block(String xameId, {String name = '', String reason = ''}) async {
    try {
      final r = await http.post(
        Uri.parse('${AppConstants.serverUrl}/api/block-contact'),
        headers: await _headers(),
        body: jsonEncode({'contactId': xameId}),
      ).timeout(const Duration(seconds: 15));
      return jsonDecode(r.body)['success'] == true;
    } catch (_) { return false; }
  }

  Future<void> unblock(String xameId) async {
    try {
      await http.post(
        Uri.parse('${AppConstants.serverUrl}/api/unblock-contact'),
        headers: await _headers(),
        body: jsonEncode({'contactId': xameId}),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {}
  }
}

// ── Blocked Numbers Sheet ─────────────────────────────────────────────────────
class BlockedNumbersDialog extends StatefulWidget {
  final List<Map<String, dynamic>> contacts;
  const BlockedNumbersDialog({super.key, required this.contacts});

  static Future<void> show(BuildContext context,
      {required List<Map<String, dynamic>> contacts}) =>
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => BlockedNumbersDialog(contacts: contacts),
      );

  @override
  State<BlockedNumbersDialog> createState() => _BlockedNumbersDialogState();
}

class _BlockedNumbersDialogState extends State<BlockedNumbersDialog> {
  final _svc      = CallBlockingService();
  final _inputCtrl = TextEditingController();
  List<BlockedEntry> _blocked = [];

  @override
  void initState() { super.initState(); _reload(); }

  @override
  void dispose() { _inputCtrl.dispose(); super.dispose(); }

  Future<void> _reload() async {
    final list = await _svc.getBlockedList();
    if (mounted) setState(() => _blocked = list);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: context.xSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Handle + header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(children: [
              Center(child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: context.xMuted.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2)),
              )),
              Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: context.xDanger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.block_outlined,
                      color: context.xDanger, size: 18),
                ),
                SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Blocked Numbers',
                      style: TextStyle(color: context.xText, fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  Text('These people cannot message or call you',
                      style: TextStyle(color: context.xMuted, fontSize: 12)),
                ]),
              ]),
              SizedBox(height: 16),
              // Input row
              Row(children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.xCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.xMuted.withValues(alpha: 0.1)),
                    ),
                    child: TextField(
                      controller: _inputCtrl,
                      style: TextStyle(color: context.xText, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Enter Xame-ID to block',
                        hintStyle: TextStyle(color: context.xMuted.withValues(alpha: 0.3)),
                        prefixIcon: Icon(Icons.person_outline,
                            color: context.xMuted.withValues(alpha: 0.3), size: 18),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                GestureDetector(
                  onTap: () async {
                    final val = _inputCtrl.text.trim();
                    if (val.isEmpty) return;
                    final contact = widget.contacts.firstWhere(
                        (c) => c['id'] == val, orElse: () => {});
                    final name = contact['name'] as String? ?? '';
                    final ok = await _svc.block(val, name: name);
                    if (ok) { _inputCtrl.clear(); _reload(); }
                    else if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Could not block $val. Check the Xame-ID and try again.'),
                        backgroundColor: context.xCard,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ));
                    }
                  },
                  child: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: context.xDanger,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.block, color: context.xText, size: 18),
                  ),
                ),
              ]),
              SizedBox(height: 8),
            ]),
          ),
          // List
          Expanded(
            child: _blocked.isEmpty
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.check_circle_outline,
                        color: context.xMuted.withValues(alpha: 0.25), size: 48),
                    SizedBox(height: 12),
                    Text('No blocked numbers',
                        style: TextStyle(color: context.xMuted, fontSize: 14)),
                  ])
                : ListView.separated(
                    controller: ctrl,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    itemCount: _blocked.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final e = _blocked[i];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: context.xCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: context.xMuted.withValues(alpha: 0.1)),
                        ),
                        child: Row(children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: context.xDanger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.person_off_outlined,
                                color: context.xDanger, size: 18),
                          ),
                          SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.name.isNotEmpty ? e.name : e.xameId,
                                  style: TextStyle(color: context.xText,
                                      fontSize: 14, fontWeight: FontWeight.w600)),
                              if (e.name.isNotEmpty)
                                Text(e.xameId, style: TextStyle(
                                    color: context.xMuted, fontSize: 12)),
                            ],
                          )),
                          GestureDetector(
                            onTap: () async {
                              await _svc.unblock(e.xameId);
                              _reload();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: context.xText.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: context.xMuted.withValues(alpha: 0.1)),
                              ),
                              child: Text('Unblock',
                                  style: TextStyle(color: context.xText.withValues(alpha: 0.6),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ]),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
