import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Blocked entry model ───────────────────────────────────────────────────────
class BlockedEntry {
  final String xameId;
  final String name;
  final String reason;
  final int blockedAt;

  const BlockedEntry({
    required this.xameId,
    required this.name,
    required this.reason,
    required this.blockedAt,
  });

  Map<String, dynamic> toJson() => {
    'number': xameId,
    'name': name,
    'reason': reason,
    'blockedAt': blockedAt,
  };

  factory BlockedEntry.fromJson(Map<String, dynamic> j) => BlockedEntry(
    xameId:    j['number'] as String,
    name:      j['name']   as String? ?? '',
    reason:    j['reason'] as String? ?? '',
    blockedAt: j['blockedAt'] as int? ?? 0,
  );
}

// ── Service ───────────────────────────────────────────────────────────────────
class CallBlockingService {
  static const _key = 'xame:blockedNumbers';

  Future<List<BlockedEntry>> getBlockedList() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => BlockedEntry.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) { return []; }
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
    final list = await getBlockedList();
    if (list.any((e) => e.xameId == xameId)) return false;
    list.add(BlockedEntry(
      xameId: xameId,
      name: name,
      reason: reason,
      blockedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await _save(list);
    return true;
  }

  Future<void> unblock(String xameId) async {
    final list = await getBlockedList();
    list.removeWhere((e) => e.xameId == xameId);
    await _save(list);
  }
}

// ── Blocked Numbers Dialog ────────────────────────────────────────────────────
class BlockedNumbersDialog extends StatefulWidget {
  final List<Map<String, dynamic>> contacts;

  const BlockedNumbersDialog({super.key, required this.contacts});

  static Future<void> show(BuildContext context,
      {required List<Map<String, dynamic>> contacts}) {
    return showDialog(
      context: context,
      builder: (_) => BlockedNumbersDialog(contacts: contacts),
    );
  }

  @override
  State<BlockedNumbersDialog> createState() => _BlockedNumbersDialogState();
}

class _BlockedNumbersDialogState extends State<BlockedNumbersDialog> {
  final _svc = CallBlockingService();
  List<BlockedEntry> _blocked = [];
  final _inputCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await _svc.getBlockedList();
    if (mounted) setState(() => _blocked = list);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('🚫 Blocked Numbers'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_blocked.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No blocked numbers',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _blocked.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = _blocked[i];
                    return ListTile(
                      dense: true,
                      title: Text(e.name.isNotEmpty ? e.name : e.xameId,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: e.name.isNotEmpty ? Text(e.xameId) : null,
                      trailing: TextButton(
                        onPressed: () async {
                          await _svc.unblock(e.xameId);
                          _reload();
                        },
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.red),
                        child: const Text('Unblock'),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Enter Xame-ID to block',
                      isDense: true,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final val = _inputCtrl.text.trim();
                    if (val.isEmpty) return;
                    final contact = widget.contacts.firstWhere(
                      (c) => c['id'] == val,
                      orElse: () => {},
                    );
                    final name = contact['name'] as String? ?? '';
                    final success = await _svc.block(val, name: name);
                    if (success) {
                      _inputCtrl.clear();
                      _reload();
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$val is already blocked')),
                        );
                      }
                    }
                  },
                  child: const Text('Block'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
