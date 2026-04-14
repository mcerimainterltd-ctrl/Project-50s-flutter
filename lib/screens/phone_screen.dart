// lib/screens/phone_screen.dart
// XamePage Phone â€” embedded in ContactsScreen tab 3  (Build 239+)
//
// Tabs: Recents | Contacts | Keypad
// Contacts: reads native device address book via contacts_service plugin.
// READ_CONTACTS permission already declared in AndroidManifest.xml.

import 'dart:convert';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

// â”€â”€ COLOURS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const _kTeal  = Color(0xFF00B0A0);
const _kBg    = Color(0xFF0D1520);
const _kCard  = Color(0xFF1A2332);
const _kMuted = Color(0xFFAAAAAA);

// â”€â”€ MODELS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _DevContact {
  final String name;
  final List<String> phones;
  final String? photo; // base64 avatar from contacts_service
  bool isOnXame;
  _DevContact({required this.name, required this.phones,
      this.photo, this.isOnXame = false});
  String get primary => phones.isNotEmpty ? phones.first : '';
  String get initials {
    final p = name.trim().split(' ');
    return p.length >= 2
        ? '${p[0][0]}${p[1][0]}'.toUpperCase()
        : name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class _CallRecord {
  final String callerId, recipientId, status;
  final String? startTime, type, callType;
  final int? duration;
  _CallRecord.fromJson(Map<String, dynamic> j)
      : callerId    = j['callerId']    ?? '',
        recipientId = j['recipientId'] ?? '',
        status      = j['status']      ?? '',
        startTime   = j['startTime'],
        type        = j['type'],
        callType    = j['callType'],
        duration    = (j['duration'] as num?)?.toInt();
}

class _Country {
  final String code, dial, flag, name;
  const _Country(this.code, this.dial, this.flag, this.name);
}

// â”€â”€ COUNTRY LIST â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

const _kCountries = [
  _Country('NG', '+234', 'ðŸ‡³ðŸ‡¬', 'Nigeria'),
  _Country('US', '+1',   'ðŸ‡ºðŸ‡¸', 'United States'),
  _Country('GB', '+44',  'ðŸ‡¬ðŸ‡§', 'United Kingdom'),
  _Country('GH', '+233', 'ðŸ‡¬ðŸ‡­', 'Ghana'),
  _Country('KE', '+254', 'ðŸ‡°ðŸ‡ª', 'Kenya'),
  _Country('ZA', '+27',  'ðŸ‡¿ðŸ‡¦', 'South Africa'),
  _Country('CM', '+237', 'ðŸ‡¨ðŸ‡²', 'Cameroon'),
  _Country('SN', '+221', 'ðŸ‡¸ðŸ‡³', 'Senegal'),
  _Country('CI', '+225', 'ðŸ‡¨ðŸ‡®', 'CÃ´te d\'Ivoire'),
  _Country('FR', '+33',  'ðŸ‡«ðŸ‡·', 'France'),
  _Country('DE', '+49',  'ðŸ‡©ðŸ‡ª', 'Germany'),
  _Country('CA', '+1',   'ðŸ‡¨ðŸ‡¦', 'Canada'),
  _Country('AU', '+61',  'ðŸ‡¦ðŸ‡º', 'Australia'),
  _Country('IN', '+91',  'ðŸ‡®ðŸ‡³', 'India'),
  _Country('AE', '+971', 'ðŸ‡¦ðŸ‡ª', 'UAE'),
  _Country('BR', '+55',  'ðŸ‡§ðŸ‡·', 'Brazil'),
  _Country('PH', '+63',  'ðŸ‡µðŸ‡­', 'Philippines'),
  _Country('ZM', '+260', 'ðŸ‡¿ðŸ‡²', 'Zambia'),
  _Country('UG', '+256', 'ðŸ‡ºðŸ‡¬', 'Uganda'),
  _Country('TZ', '+255', 'ðŸ‡¹ðŸ‡¿', 'Tanzania'),
  _Country('RW', '+250', 'ðŸ‡·ðŸ‡¼', 'Rwanda'),
  _Country('EG', '+20',  'ðŸ‡ªðŸ‡¬', 'Egypt'),
  _Country('SA', '+966', 'ðŸ‡¸ðŸ‡¦', 'Saudi Arabia'),
  _Country('JP', '+81',  'ðŸ‡¯ðŸ‡µ', 'Japan'),
  _Country('SG', '+65',  'ðŸ‡¸ðŸ‡¬', 'Singapore'),
  _Country('MY', '+60',  'ðŸ‡²ðŸ‡¾', 'Malaysia'),
  _Country('ZW', '+263', 'ðŸ‡¿ðŸ‡¼', 'Zimbabwe'),
];

// â”€â”€ SCREEN â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class PhoneScreen extends StatefulWidget {
  final String userId, serverUrl;
  const PhoneScreen({
    super.key,
    required this.userId,
    required this.serverUrl,
  });
  @override State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tab;

  // Credits
  double _credits = 0;
  String _creditsCurr = 'NGN';
  Map<String, dynamic> _rates = {};

  // Contacts
  List<_DevContact> _contacts = [];
  bool _contactsLoaded = false, _contactsLoading = false;
  String _q = '';

  // Keypad
  String _dial = '';
  _Country _country = _kCountries.first;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _loadCredits();
    _loadRates();
  }

  @override void dispose() { _tab.dispose(); super.dispose(); }

  // â”€â”€ API â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _loadCredits() async {
    try {
      final r = await http
          .get(Uri.parse(
              '${widget.serverUrl}/api/call-credits/${widget.userId}'))
          .timeout(const Duration(seconds: 6));
      final d = jsonDecode(r.body);
      if (d['success'] == true && mounted) setState(() {
        _credits     = (d['balance']  as num?)?.toDouble() ?? 0;
        _creditsCurr = d['currency'] ?? 'NGN';
      });
    } catch (_) {}
  }

  Future<void> _loadRates() async {
    try {
      final r = await http
          .get(Uri.parse('${widget.serverUrl}/api/call-credits/rates'))
          .timeout(const Duration(seconds: 6));
      final d = jsonDecode(r.body);
      if (d['success'] == true && mounted)
        setState(() => _rates = d['rates'] ?? {});
    } catch (_) {}
  }

  // â”€â”€ DEVICE CONTACTS via contacts_service â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _loadContacts() async {
    if (_contactsLoading) return;
    setState(() => _contactsLoading = true);

    // Runtime permission â€” READ_CONTACTS is already in AndroidManifest.xml
    final status = await Permission.contacts.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      if (mounted) {
        setState(() => _contactsLoading = false);
        _snack('Contacts permission denied');
        if (status.isPermanentlyDenied) openAppSettings();
      }
      return;
    }

    try {
      // contacts_service fetches full contact list with phones
      final raw = await FlutterContacts.getContacts(withProperties: true);

      // Flatten: one _DevContact per person, all numbers collected
      final Map<String, _DevContact> byName = {};
      for (final c in raw) {
        final name = c.displayName?.trim() ?? 'Unknown';
        if (name.isEmpty) continue;
        final phones = c.phones
            .map((p) => p.number.replaceAll(RegExp(r'\s'), ''))
            .where((p) => p.isNotEmpty)
            .toList();
        if (phones.isEmpty) continue;
        if (!byName.containsKey(name)) {
          byName[name] = _DevContact(name: name, phones: []);
        }
        byName[name]!.phones.addAll(phones);
      }

      final sorted = byName.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      // Cross-check which numbers are on XamePage
      final allPhones = sorted.expand((c) => c.phones).toList();
      if (allPhones.isNotEmpty) {
        try {
          final r = await http.post(
            Uri.parse('${widget.serverUrl}/api/phone/check-xamepage'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phones': allPhones}),
          ).timeout(const Duration(seconds: 8));
          final d = jsonDecode(r.body);
          if (d['success'] == true) {
            final reg = (d['registered'] as Map?) ?? {};
            for (final c in sorted) {
              c.isOnXame = c.phones.any((p) => reg.containsKey(p));
            }
          }
        } catch (_) {}
      }

      if (mounted) setState(() {
        _contacts       = sorted;
        _contactsLoaded = true;
        _contactsLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _contactsLoading = false);
        _snack('Could not load contacts: $e');
      }
    }
  }

  // â”€â”€ CALL HELPERS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _initiateCall(String number, String type, String callType) {
    if (type == 'xame') {
      // Delegate to the existing WebRTC call flow in the app
      // ContactsScreen already handles /call/:userId via context.go
      _snack('Opening XamePage callâ€¦');
    } else {
      _showPSTNConfirm(number);
    }
  }

  void _showPSTNConfirm(String number) {
    final rate = (_rates[_country.code] as Map?)?['rate'] ??
        (_rates['default'] as Map?)?['rate'] ?? 20;
    showModalBottomSheet(
      context: context, backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ðŸ“ž PSTN Call',
              style: TextStyle(color: Colors.white,
                  fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Calling $number',
              style: const TextStyle(color: _kMuted, fontSize: 14)),
          const SizedBox(height: 8),
          Text(
            'Rate: $_creditsCurr $rate/min  â€¢  '
            'Balance: $_creditsCurr ${_credits.toStringAsFixed(2)}',
            style: const TextStyle(color: _kMuted, fontSize: 13)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white)))),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kTeal,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                Navigator.pop(context);
                try {
                  _snack('ðŸ“ž Connectingâ€¦');
                  final r = await http.post(
                    Uri.parse('${widget.serverUrl}/api/pstn/call'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({'userId': widget.userId,
                        'to': number, 'countryCode': _country.code}),
                  ).timeout(const Duration(seconds: 20));
                  final d = jsonDecode(r.body);
                  if (d['success'] == true) {
                    setState(() => _credits = (_credits -
                        ((d['deducted'] as num?)?.toDouble() ?? 0))
                        .clamp(0, 999999));
                    _snack('ðŸ“ž Call connected');
                  } else { _snack(d['message'] ?? 'Call failed'); }
                } catch (_) { _snack('Call failed. Check connection.'); }
              },
              child: const Text('Call Now',
                  style: TextStyle(color: Colors.black,
                      fontWeight: FontWeight.w700, fontSize: 15)))),
          ]),
        ]),
      ),
    );
  }

  // â”€â”€ CONTACT OPTIONS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showContactOpts(_DevContact c) {
    showModalBottomSheet(
      context: context, backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.name, style: const TextStyle(color: Colors.white,
              fontSize: 17, fontWeight: FontWeight.w700)),
          Text(c.primary,
              style: const TextStyle(color: _kMuted, fontSize: 13)),
          const SizedBox(height: 20),
          if (c.isOnXame) ...[
            _optTile('ðŸ’¬', 'Voice Call via XamePage (Free)', _kTeal, () {
              Navigator.pop(context);
              _initiateCall(c.primary, 'xame', 'voice');
            }),
            const SizedBox(height: 10),
            _optTile('ðŸ“¹', 'Video Call via XamePage (Free)', _kTeal, () {
              Navigator.pop(context);
              _initiateCall(c.primary, 'xame', 'video');
            }),
            const SizedBox(height: 10),
          ],
          _optTile('ðŸ“ž', 'Call via Phone (Credits)', Colors.white, () {
            Navigator.pop(context); _showPSTNConfirm(c.primary);
          }),
          const SizedBox(height: 10),
          _optTile('âœ‰ï¸', 'Send SMS (Credits)', Colors.white, () {
            Navigator.pop(context); _showSms(c.primary);
          }),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Center(child: Text('Cancel',
                style: TextStyle(color: _kMuted, fontSize: 14)))),
        ]),
      ),
    );
  }

  Widget _optTile(String ico, String label, Color col, VoidCallback fn) =>
      GestureDetector(onTap: fn,
        child: Container(width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: col == _kTeal
                ? const Color(0x1A00B0A0)
                : const Color(0x12FFFFFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: col.withOpacity(0.2))),
          child: Text('$ico  $label',
              style: TextStyle(color: col,
                  fontSize: 14, fontWeight: FontWeight.w500))));

  // â”€â”€ SMS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showSms(String to) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('âœ‰ï¸ Send SMS',
                style: TextStyle(color: Colors.white,
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            RichText(text: TextSpan(
                style: const TextStyle(color: _kMuted, fontSize: 13),
                children: [
              const TextSpan(text: 'To: '),
              TextSpan(text: to, style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
              const TextSpan(text: '  â€¢  Cost: '),
              const TextSpan(text: '5 credits',
                  style: TextStyle(color: _kTeal)),
            ])),
            const SizedBox(height: 16),
            TextField(controller: ctrl, maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Type your messageâ€¦',
                hintStyle: const TextStyle(color: _kMuted),
                filled: true, fillColor: _kBg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white12)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white12)),
                contentPadding: const EdgeInsets.all(12))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white)))),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _kTeal,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  final msg = ctrl.text.trim();
                  if (msg.isEmpty) { _snack('Enter a message'); return; }
                  Navigator.pop(context);
                  try {
                    final r = await http.post(
                        Uri.parse('${widget.serverUrl}/api/pstn/sms'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({'userId': widget.userId,
                            'to': to, 'message': msg}))
                        .timeout(const Duration(seconds: 15));
                    final d = jsonDecode(r.body);
                    _snack(d['success'] == true
                        ? 'âœ… SMS sent!'
                        : (d['message'] ?? 'SMS failed'));
                  } catch (_) { _snack('SMS failed'); }
                },
                child: const Text('Send SMS',
                    style: TextStyle(color: Colors.black,
                        fontWeight: FontWeight.w700, fontSize: 15)))),
            ]),
          ]),
        ),
      ),
    );
  }

  // â”€â”€ TOP UP â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showTopup() {
    int? selAmt;
    final custCtrl = TextEditingController();
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx, ss) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ðŸ’° Top Up Call Credits',
              style: TextStyle(color: Colors.white,
                  fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 3, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.2, mainAxisSpacing: 10, crossAxisSpacing: 10,
            children: [100, 200, 500, 1000, 2000, 5000].map((a) =>
              GestureDetector(
                onTap: () => ss(() { selAmt = a; custCtrl.clear(); }),
                child: Container(alignment: Alignment.center,
                  decoration: BoxDecoration(color: _kBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: selAmt == a ? _kTeal : Colors.white12)),
                  child: Text('$_creditsCurr $a',
                      style: const TextStyle(color: Colors.white,
                          fontSize: 13, fontWeight: FontWeight.w600))))).toList()),
          const SizedBox(height: 12),
          TextField(controller: custCtrl, keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Custom amountâ€¦',
              hintStyle: const TextStyle(color: _kMuted),
              filled: true, fillColor: _kBg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white12)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white12)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12)),
            onChanged: (_) => ss(() => selAmt = null)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white)))),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kTeal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                final custom = int.tryParse(custCtrl.text);
                final amount = custom ?? selAmt;
                if (amount == null || amount <= 0) {
                  _snack('Select or enter an amount'); return;
                }
                Navigator.pop(ctx);
                try {
                  final r = await http.post(
                      Uri.parse(
                          '${widget.serverUrl}/api/call-credits/topup'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(
                          {'userId': widget.userId, 'amount': amount}))
                      .timeout(const Duration(seconds: 15));
                  final d = jsonDecode(r.body);
                  if (d['success'] == true) {
                    setState(() => _credits =
                        (d['balance'] as num?)?.toDouble() ?? _credits);
                    _snack('âœ… $_creditsCurr $amount added');
                  } else { _snack(d['message'] ?? 'Top up failed'); }
                } catch (_) { _snack('Top up failed'); }
              },
              child: const Text('Top Up',
                  style: TextStyle(color: Colors.black,
                      fontWeight: FontWeight.w700, fontSize: 15)))),
          ]),
        ]),
      )),
    );
  }

  // â”€â”€ RECHARGE TOKEN â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showRecharge() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ðŸŽŸï¸ Recharge Token',
                style: TextStyle(color: Colors.white,
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Format: XAME-XXXX-XXXX-XXXX',
                style: TextStyle(color: _kMuted, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(controller: ctrl,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white,
                  fontSize: 16, letterSpacing: 2),
              decoration: InputDecoration(
                hintText: 'XAME-XXXX-XXXX-XXXX',
                hintStyle: const TextStyle(color: _kMuted,
                    letterSpacing: 2, fontSize: 14),
                filled: true, fillColor: _kBg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white12)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white12)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white)))),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _kTeal,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  final tok = ctrl.text.trim().toUpperCase();
                  if (tok.isEmpty) { _snack('Enter a token'); return; }
                  Navigator.pop(context);
                  try {
                    final r = await http.post(
                        Uri.parse(
                            '${widget.serverUrl}/api/call-credits/recharge'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode(
                            {'userId': widget.userId, 'token': tok}))
                        .timeout(const Duration(seconds: 15));
                    final d = jsonDecode(r.body);
                    if (d['success'] == true) {
                      setState(() => _credits =
                          (d['balance'] as num?)?.toDouble() ?? _credits);
                      _snack('âœ… Credits added! '
                          'Balance: $_creditsCurr ${_credits.toStringAsFixed(2)}');
                    } else { _snack(d['message'] ?? 'Invalid token'); }
                  } catch (_) { _snack('Recharge failed'); }
                },
                child: const Text('Redeem',
                    style: TextStyle(color: Colors.black,
                        fontWeight: FontWeight.w700, fontSize: 15)))),
            ]),
          ]),
        ),
      ),
    );
  }

  // â”€â”€ COUNTRY PICKER â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _pickCountry() {
    showModalBottomSheet(
      context: context, backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.6,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text('ðŸŒ Select Country',
                  style: TextStyle(color: Colors.white,
                      fontSize: 17, fontWeight: FontWeight.w700))),
            ..._kCountries.map((c) => InkWell(
              onTap: () { setState(() => _country = c); Navigator.pop(context); },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: _country.code == c.code
                      ? const Color(0x1A00B0A0)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Text(c.flag, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(c.name,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14))),
                  Text(c.dial,
                      style: const TextStyle(
                          color: _kMuted, fontSize: 13)),
                ]),
              ),
            )),
          ],
        ),
      ),
    );
  }

  // â”€â”€ BUILD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) => Column(children: [
    // Credits bar
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: _kCard,
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          const Text('Call Credits',
              style: TextStyle(color: _kMuted, fontSize: 11)),
          Text('$_creditsCurr ${_credits.toStringAsFixed(2)}',
              style: const TextStyle(color: _kTeal,
                  fontSize: 18, fontWeight: FontWeight.w700)),
        ])),
        _cBtn('Top Up',   _kTeal, const Color(0x2600B0A0), _showTopup),
        const SizedBox(width: 8),
        _cBtn('Recharge', Colors.white, Colors.white10, _showRecharge),
      ]),
    ),

    // Sub-tabs
    Container(
      color: _kCard,
      child: TabBar(
        controller: _tab,
        indicatorColor: _kTeal,
        labelColor: _kTeal,
        unselectedLabelColor: _kMuted,
        labelStyle: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: 'ðŸ• Recents'),
          Tab(text: 'ðŸ‘¥ Contacts'),
          Tab(text: 'âŒ¨ï¸ Keypad'),
        ],
      ),
    ),

    // Content
    Expanded(child: TabBarView(controller: _tab, children: [

      // â”€â”€ RECENTS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      _RecentsTab(
          userId: widget.userId,
          serverUrl: widget.serverUrl,
          onCall: _initiateCall),

      // â”€â”€ CONTACTS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      _contactsLoaded
          ? _ContactsTab(
              contacts: _contacts, q: _q,
              onQChange: (v) => setState(() => _q = v),
              onTap: _showContactOpts)
          : Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              _contactsLoading
                  ? const CircularProgressIndicator(color: _kTeal)
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.contacts),
                      label: const Text('Load Contacts'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _kTeal,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
                          shape: const StadiumBorder()),
                      onPressed: _loadContacts),
              const SizedBox(height: 12),
              const Text('Requires contacts permission',
                  style: TextStyle(color: _kMuted, fontSize: 12)),
            ])),

      // â”€â”€ KEYPAD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      _KeypadTab(
        dial: _dial, country: _country,
        creditsCurr: _creditsCurr, credits: _credits, rates: _rates,
        onDigit:       (k) => setState(() => _dial += k),
        onBackspace:   ()  => setState(() {
          if (_dial.isNotEmpty) _dial = _dial.substring(0, _dial.length - 1);
        }),
        onPickCountry: _pickCountry,
        onCall: () {
          if (_dial.isEmpty) { _snack('Enter a number first'); return; }
          _showPSTNConfirm('${_country.dial}$_dial');
        },
        onSms: () {
          if (_dial.isEmpty) { _snack('Enter a number first'); return; }
          _showSms('${_country.dial}$_dial');
        },
      ),
    ])),
  ]);

  Widget _cBtn(String l, Color col, Color bg, VoidCallback fn) =>
      GestureDetector(onTap: fn,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: col.withOpacity(0.3))),
          child: Text(l, style: TextStyle(color: col,
              fontSize: 12, fontWeight: FontWeight.w600))));

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }
}

// â”€â”€ RECENTS TAB â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _RecentsTab extends StatefulWidget {
  final String userId, serverUrl;
  final void Function(String, String, String) onCall;
  const _RecentsTab({required this.userId, required this.serverUrl,
      required this.onCall});
  @override State<_RecentsTab> createState() => _RecentsTabState();
}

class _RecentsTabState extends State<_RecentsTab> {
  List<_CallRecord> _calls = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await http.get(Uri.parse(
              '${widget.serverUrl}/api/call-history/${widget.userId}'))
          .timeout(const Duration(seconds: 8));
      final d = jsonDecode(r.body);
      if (d['success'] == true && mounted) setState(() =>
          _calls = (d['calls'] as List)
              .map((c) => _CallRecord.fromJson(c)).toList());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(
        child: CircularProgressIndicator(color: _kTeal));
    if (_calls.isEmpty) return const Center(
        child: Text('No recent calls',
            style: TextStyle(color: _kMuted)));
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _calls.length,
      separatorBuilder: (_, __) =>
          const Divider(color: Colors.white10, height: 1),
      itemBuilder: (_, i) {
        final c        = _calls[i];
        final incoming = c.recipientId == widget.userId;
        final contact  = incoming ? c.callerId : c.recipientId;
        final pstn     = c.type == 'pstn';
        final missed   = c.status == 'missed' ||
            (incoming &&
                (c.duration == null || c.duration == 0) &&
                ['rejected', 'ended'].contains(c.status));
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF3E5163),
            child: Text(
              contact.substring(0, contact.length.clamp(0, 2))
                  .toUpperCase(),
              style: const TextStyle(color: Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w700))),
          title: Text(contact,
              style: TextStyle(
                  color: missed ? const Color(0xFFFF6464) : Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${missed ? 'ðŸ“µ' : incoming ? 'ðŸ“²' : 'ðŸ“¤'} '
            '${missed ? 'Missed' : incoming ? 'Incoming' : 'Outgoing'} '
            '${pstn ? 'ðŸ“ž' : 'ðŸ’¬'}'
            '${c.duration != null ? ' Â· ${c.duration! ~/ 60}m ${c.duration! % 60}s' : ''}'
            ' Â· ${_ago(c.startTime)}',
            style: const TextStyle(color: _kMuted, fontSize: 12)),
          trailing: TextButton(
            style: TextButton.styleFrom(
                backgroundColor: const Color(0x2600B0A0),
                foregroundColor: _kTeal,
                shape: const StadiumBorder(),
                side: const BorderSide(color: Color(0x4D00B0A0)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4)),
            onPressed: () => widget.onCall(
                contact, pstn ? 'pstn' : 'xame', c.callType ?? 'voice'),
            child: const Text('Call',
                style: TextStyle(fontSize: 12))),
        );
      },
    );
  }

  String _ago(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso); if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60)  return 'Just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)    return '${diff.inHours}h ago';
    if (diff.inDays < 7)      return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }
}

// â”€â”€ CONTACTS TAB â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ContactsTab extends StatelessWidget {
  final List<_DevContact> contacts;
  final String q;
  final void Function(String) onQChange;
  final void Function(_DevContact) onTap;
  const _ContactsTab({required this.contacts, required this.q,
      required this.onQChange, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fil = q.isEmpty
        ? contacts
        : contacts.where((c) =>
            c.name.toLowerCase().contains(q.toLowerCase()) ||
            c.phones.any((p) => p.contains(q))).toList();

    final Map<String, List<_DevContact>> grp = {};
    for (final c in fil) {
      grp.putIfAbsent(c.name[0].toUpperCase(), () => []).add(c);
    }
    final keys = grp.keys.toList()..sort();

    return Column(children: [
      Padding(padding: const EdgeInsets.all(12),
        child: TextField(
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'ðŸ” Search contactsâ€¦',
            hintStyle: const TextStyle(color: _kMuted, fontSize: 14),
            filled: true, fillColor: const Color(0x12FFFFFF),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: Colors.white12)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: Colors.white12)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10)),
          onChanged: onQChange)),
      Expanded(child: fil.isEmpty
        ? const Center(child: Text('No contacts found',
              style: TextStyle(color: _kMuted)))
        : ListView.builder(
            itemCount: keys.fold<int>(0, (s, k) => s + 1 + (grp[k]?.length ?? 0)),
            itemBuilder: (_, idx) {
              int cur = 0;
              for (final k in keys) {
                if (idx == cur) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    color: const Color(0x0D00B0A0),
                    child: Text(k, style: const TextStyle(
                        color: _kTeal, fontSize: 11,
                        fontWeight: FontWeight.w700)));
                }
                cur++;
                for (final c in grp[k]!) {
                  if (idx == cur) return InkWell(
                    onTap: () => onTap(c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(children: [
                        Stack(children: [
                          CircleAvatar(
                            radius: 21,
                            backgroundColor: const Color(0xFF3E5163),
                            child: Text(c.initials,
                                style: const TextStyle(color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700))),
                          if (c.isOnXame)
                            Positioned(bottom: -1, right: -1,
                              child: Container(
                                width: 16, height: 16,
                                decoration: BoxDecoration(
                                    color: _kTeal,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: _kBg, width: 2)),
                                child: const Center(child: Text('âœ“',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 8))))),
                        ]),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(c.name, style: const TextStyle(
                              color: Colors.white, fontSize: 14,
                              fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                          Row(children: [
                            Text(c.primary, style: const TextStyle(
                                color: _kMuted, fontSize: 12)),
                            if (c.isOnXame) ...[
                              const Text(' Â· ', style: TextStyle(
                                  color: _kMuted, fontSize: 12)),
                              const Text('On XamePage', style: TextStyle(
                                  color: _kTeal, fontSize: 12)),
                            ],
                          ]),
                        ])),
                      ]),
                    ));
                  cur++;
                }
              }
              return const SizedBox.shrink();
            })),
    ]);
  }
}

// â”€â”€ KEYPAD TAB â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _KeypadTab extends StatelessWidget {
  final String dial, creditsCurr;
  final double credits;
  final _Country country;
  final Map<String, dynamic> rates;
  final void Function(String) onDigit;
  final VoidCallback onBackspace, onPickCountry, onCall, onSms;

  const _KeypadTab({
    required this.dial, required this.country,
    required this.creditsCurr, required this.credits, required this.rates,
    required this.onDigit, required this.onBackspace,
    required this.onPickCountry, required this.onCall, required this.onSms,
  });

  @override
  Widget build(BuildContext context) {
    final rate = (rates[country.code] as Map?)?['rate'] ??
        (rates['default'] as Map?)?['rate'] ?? 20;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(children: [
        // Country selector
        GestureDetector(onTap: onPickCountry,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: const Color(0x12FFFFFF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min, children: [
              Text(country.flag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(country.name,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(width: 6),
              Text(country.dial,
                  style: const TextStyle(color: _kMuted, fontSize: 13)),
              const SizedBox(width: 4),
              const Text('â–¼',
                  style: TextStyle(color: _kMuted, fontSize: 10)),
            ]))),
        const SizedBox(height: 8),
        Text('Rate: $creditsCurr $rate/min',
            style: const TextStyle(color: _kMuted, fontSize: 12)),
        const SizedBox(height: 8),

        // Display
        SizedBox(height: 52, child: Center(child: dial.isEmpty
            ? const Text('Enter number',
                style: TextStyle(color: Color(0xFF444444),
                    fontSize: 28, letterSpacing: 4))
            : Text(dial, style: const TextStyle(
                color: Colors.white, fontSize: 28,
                fontWeight: FontWeight.w300, letterSpacing: 4)))),
        const SizedBox(height: 8),

        // Grid
        GridView.count(
          crossAxisCount: 3, shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.6,
          children: ['1','2','3','4','5','6','7','8','9','*','0','#']
              .map((k) => GestureDetector(onTap: () => onDigit(k),
                child: Container(alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: Color(0x12FFFFFF), shape: BoxShape.circle),
                  child: Text(k, style: const TextStyle(
                      color: Colors.white, fontSize: 22,
                      fontWeight: FontWeight.w500))))).toList()),
        const SizedBox(height: 8),

        // Backspace
        TextButton.icon(
          style: TextButton.styleFrom(
              backgroundColor: const Color(0x1AFF6464),
              foregroundColor: const Color(0xFFFF6464),
              shape: const StadiumBorder(),
              side: const BorderSide(color: Color(0x33FF6464)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 8)),
          onPressed: onBackspace,
          icon: const Icon(Icons.backspace_outlined, size: 16),
          label: const Text('âŒ«', style: TextStyle(fontSize: 16))),
        const SizedBox(height: 12),

        // Call / SMS row
        Row(children: [
          Expanded(child: OutlinedButton(
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white12),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: onSms,
            child: const Text('ðŸ’¬ SMS', style: TextStyle(fontSize: 13)))),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kTeal,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: onCall,
            child: const Text('ðŸ“ž Call',
                style: TextStyle(color: Colors.black,
                    fontSize: 15, fontWeight: FontWeight.w700)))),
        ]),
      ]),
    );
  }
}
