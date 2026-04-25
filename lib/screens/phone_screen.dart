// lib/screens/phone_screen.dart
// XamePage Phone — Tabs: Recents | Contacts | Keypad
// Real country flags, live credits from API, native device contacts

import 'dart:convert';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';

// ── Colours ───────────────────────────────────────────────────────────────────
const _kGreen = Color(0xFF00FF88);
const _kBg    = Color(0xFF0A0A0F);
const _kCard  = const Color(0xFF141420);
const _kMuted = Color(0xFF8B949E);
const _kDanger= Color(0xFFE53935);

// ── Models ────────────────────────────────────────────────────────────────────
class _DevContact {
  final String name;
  final List<String> phones;
  bool isOnXame;
  _DevContact({required this.name, required this.phones, this.isOnXame = false});
  String get primary => phones.isNotEmpty ? phones.first : '';
  String get initials {
    final p = name.trim().split(' ').where((s) => s.isNotEmpty).toList();
    if (p.length >= 2) return '${p[0][0]}${p[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class _CallRecord {
  final String callerId, recipientId, status;
  final String? startTime, callType;
  final int? duration;
  _CallRecord.fromJson(Map<String, dynamic> j)
      : callerId    = j['callerId']    ?? '',
        recipientId = j['recipientId'] ?? '',
        status      = j['status']      ?? '',
        startTime   = j['startTime'],
        callType    = j['callType'],
        duration    = (j['duration'] as num?)?.toInt();
}

class _Country {
  final String code, dial, flag, name;
  const _Country({
    required this.code,
    required this.dial,
    required this.flag,
    required this.name,
  });
}

// ── Real country flags using Unicode Regional Indicator pairs ─────────────────
String _flag(String code) {
  if (code.length != 2) return '🌐';
  final base = 0x1F1E6 - 0x41;
  return String.fromCharCode(base + code.codeUnitAt(0)) +
         String.fromCharCode(base + code.codeUnitAt(1));
}

// ── Country data ──────────────────────────────────────────────────────────────
final _kCountries = [
  _Country(code:'NG', dial:'+234', flag:_flag('NG'), name:'Nigeria'),
  _Country(code:'US', dial:'+1',   flag:_flag('US'), name:'United States'),
  _Country(code:'GB', dial:'+44',  flag:_flag('GB'), name:'United Kingdom'),
  _Country(code:'GH', dial:'+233', flag:_flag('GH'), name:'Ghana'),
  _Country(code:'KE', dial:'+254', flag:_flag('KE'), name:'Kenya'),
  _Country(code:'ZA', dial:'+27',  flag:_flag('ZA'), name:'South Africa'),
  _Country(code:'CM', dial:'+237', flag:_flag('CM'), name:'Cameroon'),
  _Country(code:'SN', dial:'+221', flag:_flag('SN'), name:'Senegal'),
  _Country(code:'CI', dial:'+225', flag:_flag('CI'), name:'Côte d\'Ivoire'),
  _Country(code:'FR', dial:'+33',  flag:_flag('FR'), name:'France'),
  _Country(code:'DE', dial:'+49',  flag:_flag('DE'), name:'Germany'),
  _Country(code:'CA', dial:'+1',   flag:_flag('CA'), name:'Canada'),
  _Country(code:'AU', dial:'+61',  flag:_flag('AU'), name:'Australia'),
  _Country(code:'IN', dial:'+91',  flag:_flag('IN'), name:'India'),
  _Country(code:'AE', dial:'+971', flag:_flag('AE'), name:'UAE'),
  _Country(code:'BR', dial:'+55',  flag:_flag('BR'), name:'Brazil'),
  _Country(code:'PH', dial:'+63',  flag:_flag('PH'), name:'Philippines'),
  _Country(code:'ZM', dial:'+260', flag:_flag('ZM'), name:'Zambia'),
  _Country(code:'UG', dial:'+256', flag:_flag('UG'), name:'Uganda'),
  _Country(code:'TZ', dial:'+255', flag:_flag('TZ'), name:'Tanzania'),
  _Country(code:'RW', dial:'+250', flag:_flag('RW'), name:'Rwanda'),
  _Country(code:'EG', dial:'+20',  flag:_flag('EG'), name:'Egypt'),
  _Country(code:'SA', dial:'+966', flag:_flag('SA'), name:'Saudi Arabia'),
  _Country(code:'JP', dial:'+81',  flag:_flag('JP'), name:'Japan'),
  _Country(code:'SG', dial:'+65',  flag:_flag('SG'), name:'Singapore'),
  _Country(code:'MY', dial:'+60',  flag:_flag('MY'), name:'Malaysia'),
  _Country(code:'ZW', dial:'+263', flag:_flag('ZW'), name:'Zimbabwe'),
  _Country(code:'ET', dial:'+251', flag:_flag('ET'), name:'Ethiopia'),
  _Country(code:'MX', dial:'+52',  flag:_flag('MX'), name:'Mexico'),
  _Country(code:'TR', dial:'+90',  flag:_flag('TR'), name:'Turkey'),
  _Country(code:'PK', dial:'+92',  flag:_flag('PK'), name:'Pakistan'),
  _Country(code:'ID', dial:'+62',  flag:_flag('ID'), name:'Indonesia'),
  _Country(code:'QA', dial:'+974', flag:_flag('QA'), name:'Qatar'),
  _Country(code:'KW', dial:'+965', flag:_flag('KW'), name:'Kuwait'),
  _Country(code:'IT', dial:'+39',  flag:_flag('IT'), name:'Italy'),
  _Country(code:'ES', dial:'+34',  flag:_flag('ES'), name:'Spain'),
  _Country(code:'NL', dial:'+31',  flag:_flag('NL'), name:'Netherlands'),
  _Country(code:'SE', dial:'+46',  flag:_flag('SE'), name:'Sweden'),
  _Country(code:'NO', dial:'+47',  flag:_flag('NO'), name:'Norway'),
  _Country(code:'CH', dial:'+41',  flag:_flag('CH'), name:'Switzerland'),
];

// ── Screen ────────────────────────────────────────────────────────────────────
// Lightweight XamePage contact model (avoids circular import from contacts_provider)
class XameContact {
  final String id, name;
  final String? profilePic;
  const XameContact({required this.id, required this.name, this.profilePic});
}

class PhoneScreen extends StatefulWidget {
  final String userId, serverUrl;
  const PhoneScreen({super.key, required this.userId, required this.serverUrl});
  @override State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  // Credits
  double _credits     = 0;
  String _creditsCurr = 'NGN';
  Map<String, dynamic> _rates = {};

  // Recents
  List<_CallRecord> _recents = [];
  bool _recentsLoading = false;

  // Contacts
  List<_DevContact> _contacts      = [];
  bool _contactsLoaded   = false;
  bool _contactsLoading  = false;
  String _q = '';

  // Keypad
  String   _dial    = '';
  _Country _country = _kCountries.first;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (_tab.index == 0 && _recents.isEmpty) _loadRecents();
        if (_tab.index == 1 && !_contactsLoaded) _loadContacts();
      });
    _loadCredits();
    _loadRates();
    _loadRecents();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  // ── API ─────────────────────────────────────────────────────────────────────

  Future<void> _loadCredits() async {
    try {
      final r = await http.get(Uri.parse(
          '${widget.serverUrl}/api/call-credits/${widget.userId}'))
          .timeout(const Duration(seconds: 8));
      final d = jsonDecode(r.body);
      if (d['success'] == true && mounted) setState(() {
        _credits     = (d['balance']  as num?)?.toDouble() ?? 0;
        _creditsCurr = d['currency'] ?? 'NGN';
      });
    } catch (_) {}
  }

  Future<void> _loadRates() async {
    try {
      final r = await http.get(Uri.parse(
          '${widget.serverUrl}/api/call-credits/rates'))
          .timeout(const Duration(seconds: 8));
      final d = jsonDecode(r.body);
      if (d['success'] == true && mounted)
        setState(() => _rates = d['rates'] ?? {});
    } catch (_) {}
  }

  Future<void> _loadRecents() async {
    if (_recentsLoading) return;
    setState(() => _recentsLoading = true);
    try {
      final r = await http.get(Uri.parse(
          '${widget.serverUrl}/api/call-history/${widget.userId}'))
          .timeout(const Duration(seconds: 8));
      final d = jsonDecode(r.body);
      if (d['success'] == true && mounted) {
        setState(() {
          _recents = (d['calls'] as List? ?? [])
            .map((c) => _CallRecord.fromJson(
                Map<String, dynamic>.from(c)))
            .toList();
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _recentsLoading = false);
  }

  Future<void> _loadContacts() async {
    if (_contactsLoading) return;
    setState(() => _contactsLoading = true);
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
      final raw = await FlutterContacts.getContacts(withProperties: true);
      final Map<String, _DevContact> byName = {};
      for (final c in raw) {
        final name = c.displayName.trim();
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
      if (mounted) setState(() {
        _contacts       = sorted;
        _contactsLoaded = true;
        _contactsLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _contactsLoading = false);
      _snack('Failed to load contacts');
    }
  }

  // ── Native call via tel: URI ─────────────────────────────────────────────────
  // ── PSTN call via Twilio ──────────────────────────────────────────────────
  // Shows a confirmation sheet with rate and balance before calling.
  // Server handles Twilio call creation, credit deduction, and call logging.
  // ── PSTN call via Twilio ──────────────────────────────────────────────────
  // Shows a confirmation sheet with rate and balance before calling.
  // Server handles Twilio call creation, credit deduction, and call logging.
  Future<void> _callNumber(String number) async {
    if (number.isEmpty) { _snack('No number entered'); return; }
    final full = number.startsWith('+')
        ? number : '${_country.dial}$number';

    // Get rate for this country from already-loaded _rates map
    final rateData = _rates[_country.code] ?? _rates['default'];
    final rate     = (rateData is Map ? rateData['rate'] : rateData) ?? 20;

    // Show confirmation sheet before calling
    if (!mounted) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('📞 Confirm Call',
              style: TextStyle(color: Colors.white,
                  fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          // Number row
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _kBg,
                borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Text(_country.flag,
                  style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Text(full,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 18, fontWeight: FontWeight.w700,
                      letterSpacing: 1))),
            ]),
          ),
          const SizedBox(height: 12),
          // Rate and balance
          Row(children: [
            Expanded(child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: _kBg,
                  borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Rate / min',
                    style: TextStyle(color: _kMuted, fontSize: 11)),
                const SizedBox(height: 4),
                Text('$_creditsCurr $rate',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ]),
            )),
            const SizedBox(width: 10),
            Expanded(child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: _kBg,
                  borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Your Balance',
                    style: TextStyle(color: _kMuted, fontSize: 11)),
                const SizedBox(height: 4),
                Text('$_creditsCurr ${_credits.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: _credits >= rate
                            ? const Color(0xFF00FF88)
                            : const Color(0xFFE53935),
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ]),
            )),
          ]),
          if (_credits < rate) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0x1AE53935),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0x33E53935))),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    color: const Color(0xFFE53935), size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'Insufficient credits. Top up to continue.',
                  style: const TextStyle(
                      color: const Color(0xFFE53935), fontSize: 12))),
              ]),
            ),
          ],
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white)))),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _credits >= rate
                      ? const Color(0xFF00FF88)
                      : Colors.grey,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: _credits >= rate
                  ? () => Navigator.pop(_, true)
                  : null,
              child: const Text('Call Now',
                  style: TextStyle(fontWeight: FontWeight.w700,
                      fontSize: 15)))),
          ]),
        ]),
      ),
    );

    if (confirmed != true) return;

    // Initiate call via server → Twilio
    _snack('📞 Connecting…');
    try {
      final r = await http.post(
        Uri.parse('${widget.serverUrl}/api/pstn/call'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId':      widget.userId,
          'to':          full,
          'countryCode': _country.code,
        }),
      ).timeout(const Duration(seconds: 20));

      final d = jsonDecode(r.body);
      if (d['success'] == true) {
        // Deduct from local balance to reflect server deduction
        setState(() {
          _credits = (_credits -
              ((d['deducted'] as num?)?.toDouble() ?? rate))
              .clamp(0, double.infinity);
        });
        _snack('📞 Call connected');
      } else {
        _snack('❌ ${d['message'] ?? 'Call failed'}');
      }
    } catch (_) {
      _snack('❌ Call failed — check connection');
    }
  }

  
  Future<void> _smsNumber(String number) async {
    if (number.isEmpty) { _snack('No number entered'); return; }
    final full = number.startsWith('+')
        ? number : '${_country.dial}$number';
    final uri = Uri.parse('sms:$full');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _snack('Cannot open SMS');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _kCard,
      duration: const Duration(seconds: 2)));
  }

  void _showTopUpSheet() {
    showModalBottomSheet(
      context:            context,
      backgroundColor:    _kCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _TopUpSheet(
        userId:      widget.userId,
        serverUrl:   widget.serverUrl,
        currency:    _creditsCurr,
        onSuccess:   (newBalance) {
          setState(() => _credits = newBalance);
          Navigator.pop(context);
          _snack('Recharge successful! Balance: $_creditsCurr ${newBalance.toStringAsFixed(2)}');
        },
      ),
    );
  }

  void _pickCountry() {
    showModalBottomSheet(
      context:         context,
      backgroundColor: _kCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CountryPicker(
        countries: _kCountries,
        selected:  _country,
        onSelect:  (c) {
          setState(() => _country = c);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Column(children: [
        // ── Credits bar ──────────────────────────────────────────
        _CreditsBar(
          credits:  _credits,
          currency: _creditsCurr,
          onTopUp:  () => _showTopUpSheet(),
        ),
        // ── Tab bar ──────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF21262D)))),
          child: TabBar(
            controller:           _tab,
            indicatorColor:       _kGreen,
            indicatorWeight:      2,
            labelColor:           _kGreen,
            unselectedLabelColor: _kMuted,
            labelStyle: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600),
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'Recents'),
              Tab(text: 'Contacts'),
              Tab(text: 'Keypad'),
            ],
          ),
        ),
        // ── Tab views ────────────────────────────────────────────
        Expanded(child: TabBarView(
          controller: _tab,
          children: [
            // Recents
            _RecentsTab(
              records:  _recents,
              loading:  _recentsLoading,
              userId:   widget.userId,
              onCall:   (n) => _callNumber(n),
              onRefresh: _loadRecents,
            ),
            // Contacts
            _ContactsTab(
              contacts: _contacts,
              loading:  _contactsLoading,
              loaded:   _contactsLoaded,
              q:        _q,
              onQChange:(v) => setState(() => _q = v),
              onLoad:   _loadContacts,
              onCall:   (c) => _callNumber(c.primary),
              onSms:    (c) => _smsNumber(c.primary),
            ),
            // Keypad
            _KeypadTab(
              dial:        _dial,
              country:     _country,
              creditsCurr: _creditsCurr,
              credits:     _credits,
              rates:       _rates,
              onDigit:     (d) => setState(() => _dial += d),
              onBackspace: () => setState(() {
                if (_dial.isNotEmpty)
                  _dial = _dial.substring(0, _dial.length - 1);
              }),
              onPickCountry: _pickCountry,
              onCall: () => _callNumber(_dial),
              onSms:  () => _smsNumber(_dial),
            ),
          ],
        )),
      ]),
    );
  }
}

// ── Credits bar ───────────────────────────────────────────────────────────────
class _CreditsBar extends StatelessWidget {
  final double credits;
  final String currency;
  final VoidCallback onTopUp;
  const _CreditsBar({required this.credits, required this.currency,
      required this.onTopUp});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: const BoxDecoration(
      color: const Color(0xFF141420),
      border: Border(bottom: BorderSide(color: Color(0xFF21262D)))),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:        _kGreen.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(color: _kGreen.withOpacity(0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.phone_in_talk_rounded,
              color: _kGreen, size: 14),
          const SizedBox(width: 6),
          Text('$currency ${credits.toStringAsFixed(2)}',
            style: const TextStyle(color: _kGreen,
                fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          const Text('credits',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
      ),
      const Spacer(),
      GestureDetector(
        onTap: onTopUp,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color:        Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border:       Border.all(color: Colors.white12)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_rounded, color: Colors.white70, size: 14),
            SizedBox(width: 4),
            Text('Top Up', style: TextStyle(
                color: Colors.white70, fontSize: 12,
                fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    ]),
  );
}

// ── Recents tab ───────────────────────────────────────────────────────────────
class _RecentsTab extends StatelessWidget {
  final List<_CallRecord> records;
  final bool     loading;
  final String   userId;
  final void Function(String) onCall;
  final VoidCallback onRefresh;

  const _RecentsTab({
    required this.records, required this.loading,
    required this.userId,  required this.onCall,
    required this.onRefresh});

  String _fmt(String? iso) {
    if (iso == null) return '';
    final dt   = DateTime.tryParse(iso);
    if (dt == null) return '';
    final now  = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24)  return '${diff.inHours}h ago';
    if (diff.inDays    < 7)   return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _dur(int? s) {
    if (s == null || s == 0) return '';
    if (s < 60) return '${s}s';
    return '${s ~/ 60}m ${s % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator(
        color: _kGreen, strokeWidth: 1.5));
    if (records.isEmpty) return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 72, height: 72,
          decoration: BoxDecoration(shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.04)),
          child: const Icon(Icons.call_outlined,
              color: Colors.white24, size: 32)),
        const SizedBox(height: 16),
        const Text('No recent calls',
          style: TextStyle(color: Colors.white38, fontSize: 15)),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onRefresh,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12)),
            child: const Text('Refresh',
              style: TextStyle(color: Colors.white54, fontSize: 13)))),
      ]),
    );

    return RefreshIndicator(
      color: _kGreen,
      backgroundColor: _kCard,
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: records.length,
        itemBuilder: (_, i) {
          final r        = records[i];
          final isOut    = r.callerId == userId;
          final isMissed = r.status == 'missed' && !isOut;
          final peer     = isOut ? r.recipientId : r.callerId;
          final isVideo  = r.callType == 'video';

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 4),
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isMissed
                  ? _kDanger.withOpacity(0.1)
                  : _kGreen.withOpacity(0.08)),
              child: Icon(
                isOut
                  ? Icons.call_made_rounded
                  : isMissed
                    ? Icons.call_missed_rounded
                    : Icons.call_received_rounded,
                color: isMissed ? _kDanger : _kGreen,
                size: 20)),
            title: Text(peer, style: TextStyle(
                color: isMissed ? _kDanger : Colors.white,
                fontSize: 14, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
            subtitle: Row(children: [
              Icon(isVideo ? Icons.videocam_outlined : Icons.call_outlined,
                  color: _kMuted, size: 12),
              const SizedBox(width: 4),
              Text(
                [
                  isOut ? 'Outgoing' : isMissed ? 'Missed' : 'Incoming',
                  if (r.duration != null && r.duration! > 0)
                    _dur(r.duration),
                  _fmt(r.startTime),
                ].where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(color: _kMuted, fontSize: 12)),
            ]),
            trailing: GestureDetector(
              onTap: () => onCall(peer),
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kGreen.withOpacity(0.1),
                  border: Border.all(
                      color: _kGreen.withOpacity(0.3))),
                child: const Icon(Icons.call_rounded,
                    color: _kGreen, size: 18)),
            ),
          );
        },
      ),
    );
  }
}

// ── Contacts tab ──────────────────────────────────────────────────────────────
class _ContactsTab extends StatelessWidget {
  final List<_DevContact>  contacts;
  final List<XameContact>  xameContacts;
  final bool      loading, loaded;
  final String    q;
  final void Function(String)      onQChange;
  final VoidCallback               onLoad;
  final void Function(_DevContact) onCall;
  final void Function(_DevContact) onSms;

  const _ContactsTab({
    required this.contacts,  required this.loading,
    required this.loaded,    required this.q,
    required this.onQChange, required this.onLoad,
    required this.onCall,    required this.onSms,
    this.xameContacts = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (!loaded && !loading) return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 72, height: 72,
          decoration: BoxDecoration(shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.04)),
          child: const Icon(Icons.contacts_outlined,
              color: Colors.white24, size: 32)),
        const SizedBox(height: 16),
        const Text('Tap to load contacts',
          style: TextStyle(color: Colors.white38, fontSize: 15)),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onLoad,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [
                const Color(0xFF00FF88), const Color(0xFF00FF88)]),
              borderRadius: BorderRadius.circular(20)),
            child: const Text('Load Contacts',
              style: TextStyle(color: Colors.black,
                  fontSize: 14, fontWeight: FontWeight.w700)))),
      ]),
    );

    if (loading) return const Center(child: CircularProgressIndicator(
        color: _kGreen, strokeWidth: 1.5));

    final fil = contacts.where((c) =>
      q.isEmpty ||
      c.name.toLowerCase().contains(q.toLowerCase()) ||
      c.phones.any((p) => p.contains(q))
    ).toList();

    // Group by first letter
    final Map<String, List<_DevContact>> grp = {};
    for (final c in fil) {
      final k = c.name.isNotEmpty
        ? c.name[0].toUpperCase() : '#';
      grp.putIfAbsent(k, () => []).add(c);
    }
    final keys = grp.keys.toList()..sort();

    return Column(children: [
      // XamePage contacts
      if (xameContacts.isNotEmpty)
        _XameContactsSection(xameContacts: xameContacts),

      // Search bar
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          onChanged: onQChange,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText:  'Search contacts...',
            hintStyle: const TextStyle(color: Colors.white30),
            prefixIcon: const Icon(Icons.search,
                color: Colors.white30, size: 18),
            filled:    true,
            fillColor: _kCard,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: _kGreen, width: 1)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10)),
        ),
      ),

      // Count
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Text('${fil.length} contact${fil.length != 1 ? "s" : ""}',
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const Spacer(),
          if (fil.any((c) => c.isOnXame))
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color:        _kGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border:       Border.all(
                    color: _kGreen.withOpacity(0.3))),
              child: Text(
                '${fil.where((c) => c.isOnXame).length} on XamePage',
                style: const TextStyle(
                    color: _kGreen, fontSize: 11,
                    fontWeight: FontWeight.w600))),
        ]),
      ),
      const SizedBox(height: 4),

      // List
      Expanded(child: fil.isEmpty
        ? const Center(child: Text('No contacts found',
            style: TextStyle(color: Colors.white38)))
        : ListView.builder(
            itemCount: keys.fold<int>(
                0, (s, k) => s + 1 + (grp[k]?.length ?? 0)),
            itemBuilder: (_, idx) {
              int cur = 0;
              for (final k in keys) {
                if (idx == cur) return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 5),
                  color: const Color(0x08FFFFFF),
                  child: Text(k, style: const TextStyle(
                      color: _kGreen, fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)));
                cur++;
                for (final c in grp[k]!) {
                  if (idx == cur) return _ContactTile(
                    contact: c,
                    onCall:  () => onCall(c),
                    onSms:   () => onSms(c));
                  cur++;
                }
              }
              return const SizedBox.shrink();
            })),
    ]);
  }
}

// ── Contact tile ──────────────────────────────────────────────────────────────
class _ContactTile extends StatelessWidget {
  final _DevContact contact;
  final VoidCallback onCall, onSms;
  const _ContactTile({
    required this.contact,
    required this.onCall,
    required this.onSms});

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(
        horizontal: 16, vertical: 4),
    leading: Stack(clipBehavior: Clip.none, children: [
      CircleAvatar(
        radius:          21,
        backgroundColor: const Color(0xFF1E3A2F),
        child: Text(contact.initials,
          style: const TextStyle(color: _kGreen,
              fontSize: 14, fontWeight: FontWeight.w700))),
      if (contact.isOnXame)
        Positioned(bottom: -2, right: -2,
          child: Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              color:  _kGreen,
              shape:  BoxShape.circle,
              border: Border.all(color: _kBg, width: 2)),
            child: const Icon(Icons.check,
                color: Colors.black, size: 9))),
    ]),
    title: Text(contact.name,
      style: const TextStyle(color: Colors.white,
          fontSize: 14, fontWeight: FontWeight.w600),
      overflow: TextOverflow.ellipsis),
    subtitle: Row(children: [
      Flexible(child: Text(contact.primary,
        style: const TextStyle(color: _kMuted, fontSize: 12),
        overflow: TextOverflow.ellipsis)),
      if (contact.isOnXame) ...[
        const Text(' · ', style: TextStyle(color: _kMuted)),
        const Text('XamePage',
          style: TextStyle(color: _kGreen, fontSize: 12,
              fontWeight: FontWeight.w500)),
      ],
    ]),
    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
      // SMS
      GestureDetector(
        onTap: onSms,
        child: Container(
          width: 36, height: 36,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.05),
            border: Border.all(color: Colors.white12)),
          child: const Icon(Icons.message_outlined,
              color: Colors.white54, size: 16))),
      // Call
      GestureDetector(
        onTap: onCall,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kGreen.withOpacity(0.1),
            border: Border.all(
                color: _kGreen.withOpacity(0.3))),
          child: const Icon(Icons.call_rounded,
              color: _kGreen, size: 16))),
    ]),
  );
}

// ── Keypad tab ────────────────────────────────────────────────────────────────

class _XameContactsSection extends StatelessWidget {
  final List<XameContact> xameContacts;
  const _XameContactsSection({required this.xameContacts});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0x1A00FF88),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0x3300FF88))),
            child: const Text('XamePage',
                style: TextStyle(color: const Color(0xFF00FF88),
                    fontSize: 11, fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          Text(
            '${xameContacts.length} contact${xameContacts.length == 1 ? "" : "s"}',
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
      ),
      SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: xameContacts.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (ctx, i) {
            final c = xameContacts[i];
            return SizedBox(width: 68,
              child: Column(children: [
                Stack(children: [
                  CircleAvatar(radius: 26,
                    backgroundColor: const Color(0xFF1A2332),
                    backgroundImage: c.profilePic != null
                        ? NetworkImage(c.profilePic!) : null,
                    child: c.profilePic == null
                        ? Text(
                            c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white,
                                fontSize: 18, fontWeight: FontWeight.w700))
                        : null),
                  Positioned(bottom: 0, right: 0,
                    child: Container(width: 13, height: 13,
                      decoration: BoxDecoration(
                          color: const Color(0xFF00FF88),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFF0D1520), width: 2)))),
                ]),
                const SizedBox(height: 4),
                Text(c.name,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 10, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis, maxLines: 1,
                    textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  GestureDetector(
                    onTap: () => ctx.go(
                        '/call/${c.id}?video=false&incoming=false'),
                    child: Container(width: 28, height: 28,
                      decoration: BoxDecoration(
                          color: const Color(0x1A00FF88),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0x3300FF88))),
                      child: const Icon(Icons.call_rounded,
                          color: const Color(0xFF00FF88), size: 14))),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => ctx.go(
                        '/call/${c.id}?video=true&incoming=false'),
                    child: Container(width: 28, height: 28,
                      decoration: BoxDecoration(
                          color: const Color(0x1A9C27B0),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0x339C27B0))),
                      child: const Icon(Icons.videocam_rounded,
                          color: Color(0xFF9C27B0), size: 14))),
                ]),
              ]),
            );
          },
        ),
      ),
      const Divider(color: Colors.white12, height: 1),
    ]);
  }
}

class _KeypadTab extends StatelessWidget {
  final String   dial, creditsCurr;
  final double   credits;
  final _Country country;
  final Map<String, dynamic> rates;
  final void Function(String) onDigit;
  final VoidCallback onBackspace, onPickCountry, onCall, onSms;

  const _KeypadTab({
    required this.dial,         required this.country,
    required this.creditsCurr,  required this.credits,
    required this.rates,        required this.onDigit,
    required this.onBackspace,  required this.onPickCountry,
    required this.onCall,       required this.onSms,
  });

  @override
  Widget build(BuildContext context) {
    final rateData = (rates[country.code] as Map?) ??
        (rates['default'] as Map?);
    final rate = rateData?['rate'] ?? '—';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(children: [
        // Country selector
        GestureDetector(
          onTap: onPickCountry,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color:        Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(14),
              border:       Border.all(color: Colors.white12)),
            child: Row(children: [
              Text(country.flag,
                  style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(country.name,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('${country.dial}  ·  $creditsCurr $rate/min',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
                ],
              )),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.white38, size: 20),
            ]),
          ),
        ),
        const SizedBox(height: 16),

        // Number display
        SizedBox(height: 60, child: Center(
          child: dial.isEmpty
            ? const Text('Enter number',
                style: TextStyle(color: Color(0xFF3D4450),
                    fontSize: 26, letterSpacing: 6))
            : Text(dial, style: const TextStyle(
                color: Colors.white, fontSize: 28,
                fontWeight: FontWeight.w300, letterSpacing: 5),
                textAlign: TextAlign.center))),

        // Keys grid — fixed height, works on all screen sizes
        GridView.count(
          crossAxisCount:  3,
          shrinkWrap:      true,
          physics:         const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.8,
          children: [
            ...['1','2','3','4','5','6','7','8','9'].map(
              (k) => _DialKey(label: k, sub: _kSub[k] ?? '', onTap: () => onDigit(k))),
            _DialKey(label: '*',  sub: '', onTap: () => onDigit('*')),
            _DialKey(label: '0',  sub: '+', onTap: () => onDigit('0')),
            _DialKey(label: '#',  sub: '', onTap: () => onDigit('#')),
          ],
        ),

        // Backspace
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: onBackspace,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: const Icon(Icons.backspace_outlined,
                  color: Colors.white38, size: 22))),
        ),
        const SizedBox(height: 4),

        // Call + SMS row
        Row(children: [
          // SMS
          GestureDetector(
            onTap: onSms,
            child: Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
                border: Border.all(color: Colors.white12)),
              child: const Icon(Icons.message_outlined,
                  color: Colors.white54, size: 22))),
          const SizedBox(width: 16),
          // Call
          Expanded(child: GestureDetector(
            onTap: onCall,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(colors: [
                  const Color(0xFF00FF88), const Color(0xFF00FF88),
                ])),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.call_rounded,
                      color: Colors.black, size: 22),
                  SizedBox(width: 8),
                  Text('Call',
                    style: TextStyle(color: Colors.black,
                        fontSize: 16, fontWeight: FontWeight.w800)),
                ]),
            ),
          )),

        ]),
        const SizedBox(height: 8),
      ]),
    );
  }

  static const _kSub = {
    '2':'ABC','3':'DEF','4':'GHI','5':'JKL',
    '6':'MNO','7':'PQRS','8':'TUV','9':'WXYZ',
  };
}

// ── Dial key ──────────────────────────────────────────────────────────────────
class _DialKey extends StatefulWidget {
  final String label, sub;
  final VoidCallback onTap;
  const _DialKey({required this.label, required this.sub,
      required this.onTap});
  @override
  State<_DialKey> createState() => _DialKeyState();
}

class _DialKeyState extends State<_DialKey>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 80));
    _scale = Tween(begin: 1.0, end: 0.9).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown:   (_) { HapticFeedback.lightImpact(); _ctrl.forward(); },
    onTapUp:     (_) { _ctrl.reverse(); widget.onTap(); },
    onTapCancel: ()  => _ctrl.reverse(),
    child: ScaleTransition(
      scale: _scale,
      child: Container(
        alignment:  Alignment.center,
        decoration: BoxDecoration(
          color:        Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: Colors.white.withOpacity(0.06))),
        child: Column(mainAxisAlignment: MainAxisAlignment.center,
          children: [
          Text(widget.label, style: const TextStyle(
              color: Colors.white, fontSize: 24,
              fontWeight: FontWeight.w300)),
          if (widget.sub.isNotEmpty)
            Text(widget.sub, style: const TextStyle(
                color: Colors.white38, fontSize: 8,
                letterSpacing: 1.5, fontWeight: FontWeight.w600)),
        ]),
      ),
    ),
  );
}

// ── Country picker ────────────────────────────────────────────────────────────
class _CountryPicker extends StatefulWidget {
  final List<_Country> countries;
  final _Country       selected;
  final void Function(_Country) onSelect;
  const _CountryPicker({required this.countries, required this.selected,
      required this.onSelect});
  @override
  State<_CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<_CountryPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final fil = widget.countries.where((c) =>
      _q.isEmpty ||
      c.name.toLowerCase().contains(_q.toLowerCase()) ||
      c.dial.contains(_q)
    ).toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(children: [
        const SizedBox(height: 12),
        Container(width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.white24,
              borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        const Text('Select Country', style: TextStyle(
            color: Colors.white, fontSize: 17,
            fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            autofocus: true,
            decoration: InputDecoration(
              hintText:  'Search country or code...',
              hintStyle: const TextStyle(color: Colors.white30),
              prefixIcon: const Icon(Icons.search,
                  color: Colors.white30, size: 18),
              filled:    true,
              fillColor: const Color(0xFF0A0A0F),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: _kGreen, width: 1)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10))),
        ),
        const SizedBox(height: 8),
        Expanded(child: ListView.builder(
          itemCount: fil.length,
          itemBuilder: (_, i) {
            final c          = fil[i];
            final isSelected = c.code == widget.selected.code;
            return ListTile(
              onTap: () => widget.onSelect(c),
              leading: Text(c.flag,
                  style: const TextStyle(fontSize: 24)),
              title: Text(c.name, style: TextStyle(
                  color: isSelected ? _kGreen : Colors.white,
                  fontSize: 14,
                  fontWeight: isSelected
                    ? FontWeight.w700 : FontWeight.normal)),
              trailing: Text(c.dial, style: TextStyle(
                  color: isSelected ? _kGreen : _kMuted,
                  fontSize: 13)),
              selected:      isSelected,
              selectedTileColor: _kGreen.withOpacity(0.05),
            );
          },
        )),
      ]),
    );
  }
}

// ── Top Up / Recharge Sheet ───────────────────────────────────────────────────
class _TopUpSheet extends StatefulWidget {
  final String   userId, serverUrl, currency;
  final void Function(double) onSuccess;
  const _TopUpSheet({
    required this.userId,   required this.serverUrl,
    required this.currency, required this.onSuccess});
  @override
  State<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends State<_TopUpSheet> {
  final _tokenCtrl  = TextEditingController();
  final _amountCtrl  = TextEditingController();
  bool   _loading  = false;
  String? _error;
  int    _tab      = 0; // 0 = token, 1 = wallet

  @override
  void dispose() { _tokenCtrl.dispose(); _amountCtrl.dispose(); super.dispose(); }

  Future<double> _fetchWalletBalance() async {
    try {
      final r = await http.get(Uri.parse(
          '${widget.serverUrl}/api/wallet/me?userId=${widget.userId}'))
          .timeout(const Duration(seconds: 6));
      final d = jsonDecode(r.body);
      if (d['success'] == true) {
        return (d['balance'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {}
    return 0.0;
  }

  Future<void> _transferFromWallet() async {
    final amt = double.tryParse(_amountCtrl.text.trim());
    if (amt == null || amt <= 0) {
      setState(() => _error = 'Enter a valid amount'); return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final r = await http.post(
        Uri.parse('${widget.serverUrl}/api/call-credits/topup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': widget.userId, 'amount': amt}),
      ).timeout(const Duration(seconds: 10));
      final d = jsonDecode(r.body);
      if (d['success'] == true) {
        widget.onSuccess((d['balance'] as num).toDouble());
      } else {
        setState(() => _error = d['message'] ?? 'Transfer failed');
      }
    } catch (_) {
      setState(() => _error = 'Network error. Try again.');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _redeemToken() async {
    final token = _tokenCtrl.text.trim().toUpperCase();
    if (token.isEmpty) {
      setState(() => _error = 'Enter a recharge token'); return;
    }
    // Validate format: XAME-XXXX-XXXX-XXXX
    final valid = RegExp(
      r'^XAME-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$').hasMatch(token);
    if (!valid) {
      setState(() => _error = 'Invalid format. Use: XAME-XXXX-XXXX-XXXX');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final r = await http.post(
        Uri.parse('${widget.serverUrl}/api/call-credits/recharge'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': widget.userId, 'token': token}),
      ).timeout(const Duration(seconds: 10));
      final d = jsonDecode(r.body);
      if (d['success'] == true) {
        widget.onSuccess((d['balance'] as num).toDouble());
      } else {
        setState(() => _error = d['message'] ?? 'Redemption failed');
      }
    } catch (_) {
      setState(() => _error = 'Network error. Try again.');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 20, 20,
        MediaQuery.of(context).viewInsets.bottom + 24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // Handle
      Container(width: 36, height: 4,
        decoration: BoxDecoration(color: Colors.white24,
            borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 20),

      // Title
      const Text('Top Up Credits',
        style: TextStyle(color: Colors.white, fontSize: 18,
            fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text('Add call credits to your account',
        style: const TextStyle(color: Colors.white38, fontSize: 13)),
      const SizedBox(height: 20),

      // Tab selector
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color:        Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          _TabBtn(label: '🎟 Recharge Token', selected: _tab == 0,
              onTap: () => setState(() => _tab = 0)),
          _TabBtn(label: '💳 From Wallet',    selected: _tab == 1,
              onTap: () => setState(() => _tab = 1)),
        ]),
      ),
      const SizedBox(height: 20),

      if (_tab == 0) ...[
        // Token input
        Container(
          decoration: BoxDecoration(
            color:        const Color(0xFF0A0A0F),
            borderRadius: BorderRadius.circular(14),
            border:       Border.all(color: Colors.white12)),
          child: TextField(
            controller:    _tokenCtrl,
            style: const TextStyle(
              color:       Colors.white,
              fontSize:    18,
              fontWeight:  FontWeight.w700,
              letterSpacing: 2),
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            onChanged: (v) {
              // Auto-format as XAME-XXXX-XXXX-XXXX
              final raw = v.replaceAll('-', '').toUpperCase();
              String fmt = '';
              for (int i = 0; i < raw.length && i < 16; i++) {
                if (i == 4 || i == 8 || i == 12) fmt += '-';
                fmt += raw[i];
              }
              if (fmt != v) {
                _tokenCtrl.value = TextEditingValue(
                  text:      fmt,
                  selection: TextSelection.collapsed(offset: fmt.length));
              }
            },
            decoration: InputDecoration(
              hintText:  'XAME-XXXX-XXXX-XXXX',
              hintStyle: const TextStyle(
                color:       Color(0xFF3D4450),
                fontSize:    18,
                letterSpacing: 2),
              border:    InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 16)),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter your XamePage recharge token\nAvailable from authorized resellers',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white24, fontSize: 12, height: 1.5)),
      ] else ...[
        // Wallet balance display
        FutureBuilder<double>(
          future: _fetchWalletBalance(),
          builder: (_, snap) {
            final bal = snap.data ?? 0.0;
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:        _kGreen.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
                border:       Border.all(color: _kGreen.withOpacity(0.2))),
              child: Row(children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    color: _kGreen, size: 28),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  const Text('XamePay Wallet',
                    style: TextStyle(color: Colors.white,
                        fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('${widget.currency} ${bal.toStringAsFixed(2)} available',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12)),
                ]),
              ]),
            );
          },
        ),
        const SizedBox(height: 12),
        // Amount input
        Container(
          decoration: BoxDecoration(
            color:        const Color(0xFF0A0A0F),
            borderRadius: BorderRadius.circular(14),
            border:       Border.all(color: Colors.white12)),
          child: TextField(
            controller:   _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white,
                fontSize: 22, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText:  '0.00',
              hintStyle: const TextStyle(color: Color(0xFF3D4450),
                  fontSize: 22),
              prefixText: '${widget.currency} ',
              prefixStyle: const TextStyle(color: _kGreen,
                  fontSize: 16, fontWeight: FontWeight.w600),
              border:    InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14)),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Amount will be deducted from your XamePay wallet',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white24, fontSize: 11)),
      ],

      if (_error != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color:        _kDanger.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border:       Border.all(color: _kDanger.withOpacity(0.3))),
          child: Row(children: [
            const Icon(Icons.error_outline, color: _kDanger, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(_error!,
              style: const TextStyle(color: _kDanger, fontSize: 13))),
          ]),
        ),
      ],

      const SizedBox(height: 20),

      // Action button
      SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton(
          onPressed: _loading ? null
            : _tab == 0 ? _redeemToken
            : _transferFromWallet,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kGreen,
            foregroundColor: Colors.black,
            disabledBackgroundColor: _kGreen.withOpacity(0.3),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0),
          child: _loading
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: Colors.black, strokeWidth: 2))
            : Text(
                _tab == 0 ? 'Redeem Token' : 'Transfer to Credits',
                style: const TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w800)),
        ),
      ),
    ]),
  );
}

class _TabBtn extends StatelessWidget {
  final String label;
  final bool   selected;
  final VoidCallback onTap;
  const _TabBtn({required this.label, required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color:        selected ? _kGreen.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border:       selected
            ? Border.all(color: _kGreen.withOpacity(0.4))
            : Border.all(color: Colors.transparent)),
        child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color:      selected ? _kGreen : Colors.white38,
            fontSize:   12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
      ),
    ),
  );
}
