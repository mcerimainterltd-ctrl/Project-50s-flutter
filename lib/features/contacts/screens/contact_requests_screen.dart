import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/contacts_provider.dart';

class ContactRequestsScreen extends ConsumerStatefulWidget {
  const ContactRequestsScreen({super.key});
  @override
  ConsumerState<ContactRequestsScreen> createState() => _ContactRequestsScreenState();
}

class _ContactRequestsScreenState extends ConsumerState<ContactRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  StreamSubscription? _sub;
  final _dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));

  @override
  void initState() {
    super.initState();
    _fetchRequests();
    _sub = ref.read(socketServiceProvider).contactRequest.listen((data) {
      if (mounted) setState(() => _requests = [data, ..._requests]);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _fetchRequests() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      final res = await _dio.get('/api/contact-requests/${user.xameId}');
      final data = res.data as Map<String, dynamic>;
      if (data['success'] == true) {
        setState(() {
          _requests = List<Map<String, dynamic>>.from(data['requests']);
          _loading  = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _accept(String fromId) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      final res = await _dio.post('/api/accept-contact-request',
          data: {'userId': user.xameId, 'fromId': fromId});
      final data = res.data as Map<String, dynamic>;
      if (data['success'] == true) {
        setState(() => _requests.removeWhere((r) => r['fromId'] == fromId));
        // Add to contacts provider
        final c = data['contact'] as Map<String, dynamic>?;
        if (c != null) {
          ref.read(contactsProvider.notifier).addContact(user.xameId, fromId);
        }
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Contact added successfully'),
          backgroundColor: XameColors.accent));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not accept request'),
        backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _decline(String fromId) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      await _dio.post('/api/decline-contact-request',
          data: {'userId': user.xameId, 'fromId': fromId});
      setState(() => _requests.removeWhere((r) => r['fromId'] == fromId));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.xBg,
      appBar: AppBar(
        backgroundColor: context.xBg,
        title: Text('Contact Requests',
            style: TextStyle(color: context.xText,
                fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.xText, size: 18),
          onPressed: () => Navigator.pop(context)),
        actions: [
          if (_requests.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.xAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12)),
                child: Text('${_requests.length}',
                  style: TextStyle(color: context.xAccent,
                      fontWeight: FontWeight.w700, fontSize: 13))))),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: context.xAccent))
          : _requests.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.person_add_outlined,
                      color: context.xMuted, size: 48),
                  const SizedBox(height: 16),
                  Text('No pending requests',
                      style: TextStyle(color: context.xMuted, fontSize: 16)),
                ]))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _requests.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final r = _requests[i];
                    final name = r['fromName'] as String? ?? r['fromId'] as String;
                    final pic  = r['fromPic']  as String?;
                    final initials = name.trim().split(' ').take(2)
                        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.xCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.xMuted.withOpacity(0.1))),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: context.xSurface,
                          backgroundImage: (pic != null && pic.isNotEmpty)
                              ? CachedNetworkImageProvider(pic) : null,
                          child: (pic == null || pic.isEmpty)
                              ? Text(initials, style: TextStyle(
                                  color: context.xAccent,
                                  fontWeight: FontWeight.w700)) : null),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: TextStyle(
                                color: context.xText, fontSize: 15,
                                fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text('Wants to add you on XamePage',
                                style: TextStyle(
                                    color: context.xMuted, fontSize: 12)),
                          ])),
                        const SizedBox(width: 8),
                        Column(children: [
                          GestureDetector(
                            onTap: () => _accept(r['fromId'] as String),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: context.xAccent,
                                borderRadius: BorderRadius.circular(10)),
                              child: const Text('Accept',
                                  style: TextStyle(color: Colors.black,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12)))),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => _decline(r['fromId'] as String),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: context.xMuted.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: context.xMuted.withOpacity(0.2))),
                              child: Text('Decline',
                                  style: TextStyle(color: context.xMuted,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12)))),
                        ]),
                      ]),
                    );
                  }),
    );
  }
}
