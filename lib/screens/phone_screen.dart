import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class PhoneScreen extends StatefulWidget {
  final String serverUrl;
  final String userId;
  final Function(dynamic, String, String) onCall;

  const PhoneScreen({
    super.key,
    required this.serverUrl,
    required this.userId,
    required this.onCall,
  });

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  double _credits = 0;
  String _creditsCurr = 'NGN';
  Map<String, dynamic> _rates = {};
  List<Contact> _contacts = [];
  bool _contactsLoaded = false;
  String _q = '';
  String _dial = '';
  _Country _country = _kCountries.first;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _loadCredits();
    _loadRates();
    _fetchContacts();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _fetchContacts() async {
    if (await Permission.contacts.request().isGranted) {
      final cts = await FlutterContacts.getContacts(withProperties: true, withPhoto: true);
      if (mounted) setState(() { _contacts = cts; _contactsLoaded = true; });
    }
  }

  Future<void> _loadCredits() async {
    try {
      final r = await http.get(Uri.parse('${widget.serverUrl}/api/call-credits/${widget.userId}'));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        if (mounted) setState(() { _credits = d['credits'].toDouble(); _creditsCurr = d['currency']; });
      }
    } catch (_) {}
  }

  Future<void> _loadRates() async {
    try {
      final r = await http.get(Uri.parse('${widget.serverUrl}/api/call-rates'));
      if (r.statusCode == 200) {
        if (mounted) setState(() { _rates = jsonDecode(r.body); });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, 
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // If we are on Contacts or Keypad, go back to Recents (Tab 0)
        if (_tab.index > 0) {
          _tab.animateTo(0);
        } else {
          // If we are already on Recents, actually close the screen
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Phone', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: TabBar(
            controller: _tab,
            tabs: const [Tab(text: 'Recents'), Tab(text: 'Contacts'), Tab(text: 'Keypad')],
          ),
        ),
        body: TabBarView(
          controller: _tab,
          children: [
            const Center(child: Text("Recent Calls")),
            _buildContacts(),
            Center(child: Text("Dialpad: $_dial")),
          ],
        ),
      ),
    );
  }

  Widget _buildContacts() {
    if (!_contactsLoaded) return const Center(child: CircularProgressIndicator());
    final filtered = _contacts.where((c) => c.displayName.toLowerCase().contains(_q.toLowerCase())).toList();
    if (filtered.isEmpty) return const Center(child: Text("No contacts found"));
    
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final c = filtered[i];
        return ListTile(
          leading: (c.photo != null) 
            ? CircleAvatar(backgroundImage: MemoryImage(c.photo!)) 
            : CircleAvatar(child: Text(c.displayName.isNotEmpty ? c.displayName[0] : '?')),
          title: Text(c.displayName),
          onTap: () => widget.onCall(c, 'xame', 'voice'),
        );
      },
    );
  }
}

class _Country {
  final String code, dialCode, flag, name;
  const _Country(this.code, this.dialCode, this.flag, this.name);
}

const List<_Country> _kCountries = [
  _Country('NG','+234','🇳🇬','Nigeria'),
  _Country('GH','+233','🇬🇭','Ghana'),
  _Country('CI','+225','🇨🇮','Côte d\'Ivoire'),
  _Country('US','+1','🇺🇸','USA'),
];
