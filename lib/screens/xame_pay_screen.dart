// lib/screens/xame_pay_screen.dart
// XamePay — go_router-aware wallet for XamePage 2.1  (Build 264+)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── COLOURS ───────────────────────────────────────────────────────────────────
const _kTeal  = Color(0xFF00B0A0);
const _kBg    = Color(0xFF0D1520);
const _kCard  = Color(0xFF111E2E);
const _kMuted = Color(0xFF7A9BB5);

// ── MODELS ────────────────────────────────────────────────────────────────────

class WalletTx {
  final String id, label, icon, type, status, ts;
  final double amount;
  WalletTx.fromJson(Map<String, dynamic> j)
      : id     = j['id']?.toString() ?? '${DateTime.now().millisecondsSinceEpoch}',
        label  = j['label']  ?? '',
        icon   = j['icon']   ?? '💳',
        type   = j['type']   ?? 'debit',
        status = j['status'] ?? 'Completed',
        ts     = j['ts']     ?? DateTime.now().toIso8601String(),
        amount = (j['amount'] as num?)?.toDouble() ?? 0;
}

class BankItem {
  final String name, code;
  BankItem(this.name, this.code);
  BankItem.fromJson(Map<String, dynamic> j)
      : name = j['name'] ?? '', code = j['code'] ?? '';
}

// ── NETWORK ITEM ──────────────────────────────────────────────────────────────
// color: brand hex string e.g. 'FFCC00'
// initials: 1–3 chars shown inside the circle
class NetItem {
  final String id, label, color, initials;
  const NetItem(this.id, this.label, this.color, this.initials);
}

// ── NETWORK ICON WIDGET ───────────────────────────────────────────────────────
// Replaces colored-circle emoji with a real branded circle + carrier initials.
class _NetIcon extends StatelessWidget {
  final NetItem net;
  final bool selected;
  const _NetIcon(this.net, {this.selected = false});

  @override
  Widget build(BuildContext context) {
    final bg = Color(int.parse('FF${net.color}', radix: 16));
    // Perceived brightness — use black text on light backgrounds
    final lum = (0.299 * ((bg.red) / 255) +
                 0.587 * ((bg.green) / 255) +
                 0.114 * ((bg.blue) / 255));
    final fg = lum > 0.55 ? Colors.black : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: selected ? _kTeal : Colors.white12, width: 2)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(net.initials,
              style: TextStyle(color: fg,
                  fontSize: net.initials.length > 2 ? 9 : 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
        ),
        const SizedBox(height: 4),
        Text(net.label,
            style: const TextStyle(color: Colors.white,
                fontSize: 10, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1),
      ]),
    );
  }
}

// ── REGION INFO ───────────────────────────────────────────────────────────────
// flag: real country flag emoji
// networks: list of NetItem (brand color + initials, no colored circles)
// Bank names always come from Flutterwave API — never hardcoded here.
class RegionInfo {
  final String currency, country, countryCode, symbol, flag;
  final List<NetItem> networks;
  const RegionInfo(this.currency, this.country, this.countryCode,
      this.symbol, this.flag, this.networks);
}

const _kRegions = <RegionInfo>[
  RegionInfo('NGN','Nigeria','NG','₦','🇳🇬', [
    NetItem('MTN-NG',      'MTN',      'FFCC00', 'MTN'),
    NetItem('AIRTEL-NG',   'Airtel',   'FF0000', 'AIR'),
    NetItem('GLO-NG',      'Glo',      '009A44', 'GLO'),
    NetItem('9MOBILE-NG',  '9mobile',  '006F51', '9MB'),
  ]),
  RegionInfo('GHS','Ghana','GH','GH₵','🇬🇭', [
    NetItem('MTN-GH',        'MTN',      'FFCC00', 'MTN'),
    NetItem('VODAFONE-GH',   'Vodafone', 'E60000', 'VOD'),
    NetItem('AIRTELTIGO-GH', 'AirtelTigo','FF0000','AT'),
  ]),
  RegionInfo('KES','Kenya','KE','KSh','🇰🇪', [
    NetItem('SAFARICOM-KE', 'Safaricom','4CAF50', 'SAF'),
    NetItem('AIRTEL-KE',    'Airtel',   'FF0000', 'AIR'),
    NetItem('TELKOM-KE',    'Telkom',   '0070C0', 'TEL'),
  ]),
  RegionInfo('ZAR','South Africa','ZA','R','🇿🇦', [
    NetItem('VODACOM-ZA', 'Vodacom', 'E60000', 'VOD'),
    NetItem('MTN-ZA',     'MTN',     'FFCC00', 'MTN'),
    NetItem('CELL-ZA',    'Cell C',  '333333', 'CEL'),
    NetItem('TELKOM-ZA',  'Telkom',  '0070C0', 'TEL'),
  ]),
  RegionInfo('USD','United States','US','\$','🇺🇸', [
    NetItem('ATT-US',     'AT&T',    '00A8E0', 'AT&T'),
    NetItem('TMOBILE-US', 'T-Mobile','E20074', 'T-Mo'),
    NetItem('VERIZON-US', 'Verizon', 'CD040B', 'VZN'),
    NetItem('CRICKET-US', 'Cricket', '4CAF50', 'CRK'),
  ]),
  RegionInfo('GBP','United Kingdom','GB','£','🇬🇧', [
    NetItem('EE-UK',        'EE',      '007A3D', 'EE'),
    NetItem('O2-UK',        'O2',      '0019A5', 'O2'),
    NetItem('VODAFONE-UK',  'Vodafone','E60000', 'VOD'),
    NetItem('THREE-UK',     'Three',   '333333', '3'),
  ]),
  RegionInfo('EUR','Europe','DE','€','🇪🇺', [
    NetItem('VODAFONE-EU', 'Vodafone', 'E60000', 'VOD'),
    NetItem('ORANGE-EU',   'Orange',   'FF7900', 'ORA'),
    NetItem('TMOBILE-EU',  'T-Mobile', 'E20074', 'T-Mo'),
    NetItem('O2-EU',       'O2',       '0019A5', 'O2'),
  ]),
  RegionInfo('INR','India','IN','₹','🇮🇳', [
    NetItem('JIO-IN',    'Jio',   '0033A0', 'JIO'),
    NetItem('AIRTEL-IN', 'Airtel','FF0000', 'AIR'),
    NetItem('VI-IN',     'Vi',    '6B2D8B', 'Vi'),
    NetItem('BSNL-IN',   'BSNL',  'F58220', 'BSN'),
  ]),
  RegionInfo('AED','UAE','AE','د.إ','🇦🇪', [
    NetItem('ETISALAT-AE', 'e&',  '00A850', 'e&'),
    NetItem('DU-AE',       'du',  '7B2D8B', 'du'),
  ]),
  RegionInfo('CAD','Canada','CA','CA\$','🇨🇦', [
    NetItem('ROGERS-CA',  'Rogers',  'E4003B', 'ROG'),
    NetItem('BELL-CA',    'Bell',    '0055A5', 'BELL'),
    NetItem('TELUS-CA',   'Telus',   '4B286D', 'TEL'),
    NetItem('FREEDOM-CA', 'Freedom', '6DB33F', 'FRE'),
  ]),
  RegionInfo('AUD','Australia','AU','A\$','🇦🇺', [
    NetItem('TELSTRA-AU',  'Telstra',  '0073CF', 'TEL'),
    NetItem('OPTUS-AU',    'Optus',    'FFCC00', 'OPT'),
    NetItem('VODAFONE-AU', 'Vodafone', 'E60000', 'VOD'),
    NetItem('TPG-AU',      'TPG',      '333333', 'TPG'),
  ]),
  RegionInfo('JPY','Japan','JP','¥','🇯🇵', [
    NetItem('DOCOMO-JP',   'Docomo',  'D70035', 'DCM'),
    NetItem('SOFTBANK-JP', 'SoftBank','333333', 'SBK'),
    NetItem('AU-JP',       'au',      'F07800', 'au'),
    NetItem('RAKUTEN-JP',  'Rakuten', 'BF0000', 'RAK'),
  ]),
  RegionInfo('SGD','Singapore','SG','S\$','🇸🇬', [
    NetItem('SINGTEL-SG',  'Singtel', 'D71920', 'SIN'),
    NetItem('STARHUB-SG',  'StarHub', '0066CC', 'STH'),
    NetItem('M1-SG',       'M1',      '003B8E', 'M1'),
    NetItem('TPG-SG',      'TPG',     '6B2D8B', 'TPG'),
  ]),
  RegionInfo('EGP','Egypt','EG','E£','🇪🇬', [
    NetItem('ORANGE-EG',   'Orange',  'FF7900', 'ORA'),
    NetItem('VODAFONE-EG', 'Vodafone','E60000', 'VOD'),
    NetItem('ETISALAT-EG', 'Etisalat','00A850', 'ETS'),
    NetItem('WE-EG',       'WE',      '0033A0', 'WE'),
  ]),
  RegionInfo('SAR','Saudi Arabia','SA','ر.س','🇸🇦', [
    NetItem('STC-SA',    'STC',    '6B2D8B', 'STC'),
    NetItem('MOBILY-SA', 'Mobily', '009A44', 'MOB'),
    NetItem('ZAIN-SA',   'Zain',   '0033A0', 'ZAI'),
  ]),
  RegionInfo('TRY','Turkey','TR','₺','🇹🇷', [
    NetItem('TURKCELL-TR',    'Turkcell',  '0099D6', 'TCL'),
    NetItem('VODAFONE-TR',    'Vodafone',  'E60000', 'VOD'),
    NetItem('TURKTELEKOM-TR', 'Turk Tel.', 'F58220', 'TTK'),
  ]),
  RegionInfo('MXN','Mexico','MX','MX\$','🇲🇽', [
    NetItem('TELCEL-MX',   'Telcel',  '0033A0', 'TCL'),
    NetItem('MOVISTAR-MX', 'Movistar','019DF4', 'MOV'),
    NetItem('ATT-MX',      'AT&T',    '00A8E0', 'AT&T'),
  ]),
  RegionInfo('IDR','Indonesia','ID','Rp','🇮🇩', [
    NetItem('TELKOMSEL-ID', 'Telkomsel','FF0000', 'TSL'),
    NetItem('INDOSAT-ID',   'Indosat',  'FFCC00', 'IOH'),
    NetItem('XL-ID',        'XL Axiata','0033A0', 'XL'),
  ]),
  RegionInfo('PHP','Philippines','PH','₱','🇵🇭', [
    NetItem('GLOBE-PH', 'Globe', '0033A0', 'GLB'),
    NetItem('SMART-PH', 'Smart', '009A44', 'SMT'),
    NetItem('DITO-PH',  'DITO',  'F58220', 'DITO'),
  ]),
  RegionInfo('MYR','Malaysia','MY','RM','🇲🇾', [
    NetItem('MAXIS-MY',   'Maxis',   '009BDE', 'MAX'),
    NetItem('CELCOM-MY',  'Celcom',  'FFCC00', 'CEL'),
    NetItem('DIGI-MY',    'Digi',    'FFCC00', 'DIGI'),
    NetItem('UMOBILE-MY', 'U Mobile','009A44', 'UMB'),
  ]),
  RegionInfo('BRL','Brazil','BR','R\$','🇧🇷', [
    NetItem('VIVO-BR',  'Vivo',  '6B2D8B', 'VVO'),
    NetItem('CLARO-BR', 'Claro', 'E4003B', 'CLR'),
    NetItem('TIM-BR',   'TIM',   '0033A0', 'TIM'),
  ]),
  RegionInfo('ZMW','Zambia','ZM','ZK','🇿🇲', [
    NetItem('MTN-ZM',    'MTN',    'FFCC00', 'MTN'),
    NetItem('AIRTEL-ZM', 'Airtel', 'FF0000', 'AIR'),
    NetItem('ZAMTEL-ZM', 'Zamtel', '009A44', 'ZTL'),
  ]),
  RegionInfo('UGX','Uganda','UG','USh','🇺🇬', [
    NetItem('MTN-UG',      'MTN',      'FFCC00', 'MTN'),
    NetItem('AIRTEL-UG',   'Airtel',   'FF0000', 'AIR'),
    NetItem('AFRICELL-UG', 'Africell', '0033A0', 'AFC'),
  ]),
  RegionInfo('TZS','Tanzania','TZ','TSh','🇹🇿', [
    NetItem('VODACOM-TZ', 'Vodacom', 'E60000', 'VOD'),
    NetItem('AIRTEL-TZ',  'Airtel',  'FF0000', 'AIR'),
    NetItem('TIGO-TZ',    'Tigo',    '0066CC', 'TGO'),
  ]),
  RegionInfo('RWF','Rwanda','RW','Fr','🇷🇼', [
    NetItem('MTN-RW',    'MTN',    'FFCC00', 'MTN'),
    NetItem('AIRTEL-RW', 'Airtel', 'FF0000', 'AIR'),
  ]),
  RegionInfo('XOF','West Africa','SN','CFA','🌍', [
    NetItem('ORANGE-WA', 'Orange', 'FF7900', 'ORA'),
    NetItem('MTN-WA',    'MTN',    'FFCC00', 'MTN'),
    NetItem('MOOV-WA',   'Moov',   '0033A0', 'MOV'),
  ]),
  RegionInfo('CMR','Cameroon','CM','FCFA','🇨🇲', [
    NetItem('MTN-CM',    'MTN',    'FFCC00', 'MTN'),
    NetItem('ORANGE-CM', 'Orange', 'FF7900', 'ORA'),
  ]),
  RegionInfo('QAR','Qatar','QA','QR','🇶🇦', [
    NetItem('OOREDOO-QA',   'Ooredoo', 'E4003B', 'OOR'),
    NetItem('VODAFONE-QA',  'Vodafone','E60000', 'VOD'),
  ]),
  RegionInfo('VND','Vietnam','VN','₫','🇻🇳', [
    NetItem('VIETTEL-VN',   'Viettel',  'E4003B', 'VTL'),
    NetItem('VINAPHONE-VN', 'Vinaphone','0033A0', 'VNP'),
    NetItem('MOBIFONE-VN',  'Mobifone', '009A44', 'MBF'),
  ]),
  RegionInfo('THB','Thailand','TH','฿','🇹🇭', [
    NetItem('AIS-TH',  'AIS',       '1DA462', 'AIS'),
    NetItem('DTAC-TH', 'DTAC',      '0066CC', 'DTC'),
    NetItem('TRUE-TH', 'True Move', 'E4003B', 'TRU'),
  ]),
  RegionInfo('PKR','Pakistan','PK','Rs','🇵🇰', [
    NetItem('JAZZ-PK',    'Jazz',    'F58220', 'JZZ'),
    NetItem('TELENOR-PK', 'Telenor', '0033A0', 'TNR'),
    NetItem('ZONG-PK',    'Zong',    'E4003B', 'ZNG'),
    NetItem('UFONE-PK',   'Ufone',   '6B2D8B', 'UFN'),
  ]),
  RegionInfo('MAD','Morocco','MA','MAD','🇲🇦', [
    NetItem('MAROCTELECOM-MA', 'Maroc Tel.','009A44', 'IAM'),
    NetItem('ORANGE-MA',       'Orange',    'FF7900', 'ORA'),
    NetItem('INWI-MA',         'Inwi',      '0033A0', 'INW'),
  ]),
  RegionInfo('ETB','Ethiopia','ET','Br','🇪🇹', [
    NetItem('ETHIOTELECOM-ET', 'Ethio Tel.','009A44', 'ETT'),
    NetItem('SAFARICOM-ET',    'Safaricom', '4CAF50', 'SAF'),
  ]),
  RegionInfo('ZWL','Zimbabwe','ZW','Z\$','🇿🇼', [
    NetItem('ECONET-ZW',  'Econet',  '0033A0', 'ECO'),
    NetItem('NETONE-ZW',  'NetOne',  '009A44', 'NET'),
    NetItem('TELECEL-ZW', 'Telecel', 'E4003B', 'TCL'),
  ]),
  RegionInfo('COP','Colombia','CO','COL\$','🇨🇴', [
    NetItem('CLARO-CO',    'Claro',    'E4003B', 'CLR'),
    NetItem('MOVISTAR-CO', 'Movistar', '019DF4', 'MOV'),
    NetItem('TIGO-CO',     'Tigo',     '0033A0', 'TGO'),
  ]),
  RegionInfo('ARS','Argentina','AR','AR\$','🇦🇷', [
    NetItem('CLARO-AR',    'Claro',    'E4003B', 'CLR'),
    NetItem('PERSONAL-AR', 'Personal', '0033A0', 'PRS'),
    NetItem('MOVISTAR-AR', 'Movistar', '019DF4', 'MOV'),
  ]),
];

// currency → Flutterwave country code
const _kCurrToCC = {
  'NGN':'NG','GHS':'GH','KES':'KE','ZAR':'ZA','TZS':'TZ','UGX':'UG',
  'ZMW':'ZM','RWF':'RW','ETB':'ET','USD':'US','GBP':'GB','EUR':'DE',
  'INR':'IN','CAD':'CA','AUD':'AU','MXN':'MX','BRL':'BR','PHP':'PH',
  'MYR':'MY','IDR':'ID','EGP':'EG','MAD':'MA','XOF':'SN','CMR':'CM',
  'QAR':'QA','VND':'VN','THB':'TH','PKR':'PK','AED':'AE','SAR':'SA',
  'TRY':'TR','JPY':'JP','SGD':'SG','ZWL':'ZW','COP':'CO','ARS':'AR',
};

RegionInfo _region(String c) =>
    _kRegions.firstWhere((r) => r.currency == c,
        orElse: () => _kRegions.first);

// ── CURRENCY CONVERTER (open.er-api.com — free, no key) ─────────────────────

class _FxService {
  static Map<String, double> _r = {};
  static String _base = '';
  static DateTime? _ts;

  static Future<void> load(String base) async {
    if (_base == base && _ts != null &&
        DateTime.now().difference(_ts!).inMinutes < 60) return;
    try {
      final res = await http
          .get(Uri.parse('https://open.er-api.com/v6/latest/$base'))
          .timeout(const Duration(seconds: 8));
      final d = jsonDecode(res.body);
      if (d['result'] == 'success') {
        _r    = Map<String, double>.from((d['rates'] as Map)
            .map((k, v) => MapEntry('$k', (v as num).toDouble())));
        _base = base;
        _ts   = DateTime.now();
      }
    } catch (_) {}
  }

  static double? convert(double amount, String from, String to) {
    if (from == to) return amount;
    if (_base.isEmpty) return null;
    final inBase = from == _base ? amount : amount / (_r[from] ?? 1);
    if (to == _base) return inBase;
    final t = _r[to];
    return t == null ? null : inBase * t;
  }

  static double? rate(String from, String to) {
    if (from == to) return 1;
    if (_base.isEmpty) return null;
    final f = _r[from], t = _r[to];
    return (f == null || t == null) ? null : t / f;
  }
}

// ── SCREEN ────────────────────────────────────────────────────────────────────

class XamePayScreen extends StatefulWidget {
  final String userId, serverUrl;
  final VoidCallback? onBack; // router.dart passes: () => context.go('/contacts')
  const XamePayScreen({
    super.key,
    required this.userId,
    required this.serverUrl,
    this.onBack,
  });
  @override State<XamePayScreen> createState() => _XamePayScreenState();
}

class _XamePayScreenState extends State<XamePayScreen>
    with SingleTickerProviderStateMixin {

  String _currency = 'NGN', _dispCurrency = 'NGN';
  double _balance  = 0;
  bool   _loading  = true;
  List<WalletTx> _txs = [];
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _loadPrefs().then((_) => _init());
  }

  @override void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _currency     = p.getString('wallet:currency')     ?? 'NGN';
      _dispCurrency = p.getString('wallet:dispCurrency') ?? _currency;
    });
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('wallet:currency',     _currency);
    await p.setString('wallet:dispCurrency', _dispCurrency);
  }

  Future<void> _init() async {
    try {
      final r = await http
          .get(Uri.parse('${widget.serverUrl}/api/wallet/pubkey'))
          .timeout(const Duration(seconds: 6));
      final d = jsonDecode(r.body);
      final p = await SharedPreferences.getInstance();
      if (d['currency'] != null && p.getString('wallet:currency') == null)
        _currency = d['currency'];
    } catch (_) {}
    await _loadWallet();
    await _FxService.load(_currency);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadWallet() async {
    try {
      final r = await http
          .get(Uri.parse(
              '${widget.serverUrl}/api/wallet/me?userId=${widget.userId}'))
          .timeout(const Duration(seconds: 8));
      final d = jsonDecode(r.body);
      if (d['success'] == true) setState(() {
        _balance = (d['balance'] as num?)?.toDouble() ?? 0;
        _txs = (d['transactions'] as List? ?? [])
            .map((t) => WalletTx.fromJson(t)).toList();
      });
    } catch (_) {}
  }

  void _goBack() { if (widget.onBack != null) widget.onBack!(); }

  RegionInfo get _ri => _region(_currency);
  String _fmt(double n) => '${_ri.symbol}${_fmtN(n)}';

  static String _fmtN(double n) {
    final s = n.toStringAsFixed(2);
    final parts = s.split('.');
    final buf = StringBuffer();
    int c = 0;
    for (int i = parts[0].length - 1; i >= 0; i--) {
      if (c > 0 && c % 3 == 0) buf.write(',');
      buf.write(parts[0][i]);
      c++;
    }
    return '${buf.toString().split('').reversed.join()}.${parts[1]}';
  }

  String _convLine() {
    if (_dispCurrency == _currency) return '';
    final v = _FxService.convert(_balance, _currency, _dispCurrency);
    if (v == null) return '';
    return '≈ ${_region(_dispCurrency).symbol}${_fmtN(v)} $_dispCurrency';
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (_) => _goBack(),
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: _kCard,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
            onPressed: _goBack,
          ),
          title: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_ri.flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            const Text('XamePay',
                style: TextStyle(color: Colors.white,
                    fontSize: 17, fontWeight: FontWeight.w700)),
          ]),
          centerTitle: true,
          actions: [
            IconButton(
                icon: const Icon(Icons.tune, color: _kTeal),
                onPressed: _showSettings),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _kTeal))
            : Column(children: [
                _balanceCard(),
                _tabBar(),
                Expanded(child: TabBarView(
                  controller: _tab,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _AirtimeTab(
                        region: _ri, balance: _balance,
                        serverUrl: widget.serverUrl, userId: widget.userId,
                        fmt: _fmt, onSuccess: _loadWallet, snack: _snack),
                    _DataTab(
                        region: _ri, balance: _balance,
                        serverUrl: widget.serverUrl, userId: widget.userId,
                        fmt: _fmt, onSuccess: _loadWallet, snack: _snack),
                    _BillsTab(
                        region: _ri, balance: _balance,
                        serverUrl: widget.serverUrl, userId: widget.userId,
                        currency: _currency, fmt: _fmt,
                        onSuccess: _loadWallet, snack: _snack),
                    _SendTab(
                        region: _ri, balance: _balance,
                        serverUrl: widget.serverUrl, userId: widget.userId,
                        currency: _currency, fmt: _fmt,
                        onSuccess: _loadWallet, snack: _snack),
                    _HistoryTab(txs: _txs, fmt: _fmt),
                  ],
                )),
              ]),
      ),
    );
  }

  // ── BALANCE CARD ──────────────────────────────────────────────────────────

  Widget _balanceCard() {
    final conv = _convLine();
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF00B0A0), Color(0xFF008A7D)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Wallet Balance',
            style: TextStyle(color: Color(0xCCFFFFFF),
                fontSize: 12, letterSpacing: 1)),
        const SizedBox(height: 8),
        Text(_fmt(_balance),
            style: const TextStyle(color: Colors.white,
                fontSize: 32, fontWeight: FontWeight.w800)),
        if (conv.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4),
              child: Text(conv, style: const TextStyle(
                  color: Color(0xB3FFFFFF), fontSize: 13))),
        Text('XamePay • $_currency',
            style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12)),
        const SizedBox(height: 20),
        Row(children: [
          _cBtn('+ Add Money', () => _showAddMoney()),
          const SizedBox(width: 8),
          _cBtn('↗ Send',     () => _tab.animateTo(3)),
          const SizedBox(width: 8),
          _cBtn('📊 History', () => _tab.animateTo(4)),
        ]),
      ]),
    );
  }

  Widget _cBtn(String l, VoidCallback f) => Expanded(
    child: GestureDetector(onTap: f,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x33FFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x4DFFFFFF)),
        ),
        child: Text(l, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white,
                fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    ),
  );

  // ── TAB BAR ───────────────────────────────────────────────────────────────

  Widget _tabBar() => Container(
    color: _kCard,
    child: TabBar(
      controller: _tab,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorColor: _kTeal,
      labelColor: _kTeal,
      unselectedLabelColor: _kMuted,
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      tabs: const [
        Tab(text: '📱 Airtime'),
        Tab(text: '📶 Data'),
        Tab(text: '🧾 Bills'),
        Tab(text: '💸 Send'),
        Tab(text: '📊 History'),
      ],
    ),
  );

  // ── ADD MONEY SHEET ───────────────────────────────────────────────────────

  void _showAddMoney() {
    final methods = [
      ['💳', 'Debit / Credit Card',  'Instant • Visa, Mastercard, Verve'],
      ['🏦', 'Bank Transfer',         'Instant • Virtual account'],
      ['📟', 'USSD',                  'No internet needed'],
      ['📥', 'Receive from Contact',  'From another XamePage user'],
    ];
    showModalBottomSheet(
      context: context, backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.55,
        builder: (_, sc) => ListView(
          controller: sc, padding: const EdgeInsets.all(24),
          children: [
            const Text('💳 Add Money',
                style: TextStyle(color: Colors.white,
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            ...methods.map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: _kCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12)),
                  child: Row(children: [
                    Text(m[0], style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 16),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(m[1], style: const TextStyle(color: Colors.white,
                          fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(m[2], style: const TextStyle(
                          color: _kMuted, fontSize: 12)),
                    ])),
                    const Icon(Icons.chevron_right, color: _kMuted),
                  ]),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  // ── SETTINGS ──────────────────────────────────────────────────────────────

  void _showSettings() {
    String tc = _currency, td = _dispCurrency;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) =>
        DraggableScrollableSheet(expand: false, initialChildSize: 0.75,
          builder: (_, sc) => ListView(
            controller: sc, padding: const EdgeInsets.all(24),
            children: [
              Row(children: [
                const Expanded(child: Text('⚙️ Wallet Settings',
                    style: TextStyle(color: Colors.white,
                        fontSize: 17, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(ctx)),
              ]),
              const SizedBox(height: 16),
              _sLabel('🌍 Region & Currency'),
              const SizedBox(height: 8),
              // Region picker — shows flag + country + currency code
              DropdownButtonFormField<String>(
                value: tc, isExpanded: true, dropdownColor: _kBg,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: _dropDeco(),
                items: _kRegions.map((r) => DropdownMenuItem(
                  value: r.currency,
                  child: Row(children: [
                    Text(r.flag, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${r.country} (${r.currency})',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14))),
                  ]),
                )).toList(),
                onChanged: (v) { if (v != null) ss(() => tc = v); },
              ),
              const SizedBox(height: 20),
              _sLabel('💱 Display Balance In'),
              const SizedBox(height: 4),
              const Text(
                'Shows your balance converted to another currency '
                'alongside your wallet currency.',
                style: TextStyle(color: _kMuted, fontSize: 12)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: td, isExpanded: true, dropdownColor: _kBg,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: _dropDeco(),
                items: _kRegions.map((r) => DropdownMenuItem(
                  value: r.currency,
                  child: Row(children: [
                    Text(r.flag, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                        '${r.symbol} ${r.currency} — ${r.country}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14))),
                  ]),
                )).toList(),
                onChanged: (v) { if (v != null) ss(() => td = v); },
              ),
              if (tc != td)
                FutureBuilder(
                  future: _FxService.load(tc),
                  builder: (_, __) {
                    final rv = _FxService.rate(tc, td);
                    final dr = _region(td);
                    return Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0x1A00B0A0),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x3300B0A0)),
                      ),
                      child: Text(
                        rv != null
                            ? '1 $tc ≈ ${dr.symbol}${rv.toStringAsFixed(4)} $td'
                            : 'Fetching live rate…',
                        style: const TextStyle(color: _kTeal, fontSize: 13)),
                    );
                  },
                ),
              const SizedBox(height: 28),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kTeal,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  setState(() { _currency = tc; _dispCurrency = td; });
                  await _savePrefs();
                  try {
                    await http.post(
                      Uri.parse('${widget.serverUrl}/api/wallet/currency'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(
                          {'userId': widget.userId, 'currency': _currency}),
                    );
                  } catch (_) {}
                  await _FxService.load(_currency);
                  if (mounted) { Navigator.pop(ctx); _snack('✅ Settings saved'); }
                },
                child: const Text('Save Settings',
                    style: TextStyle(color: Colors.black,
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _sLabel(String t) => Text(t,
      style: const TextStyle(color: _kMuted,
          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1));

  static InputDecoration _dropDeco() => InputDecoration(
    filled: true, fillColor: _kCard,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white12)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white12)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}

// ── NETWORK GRID — shared by Airtime & Data tabs ──────────────────────────────
Widget _netGrid(List<NetItem> nets, String? selected, void Function(String) onTap) =>
    GridView.count(
      crossAxisCount: 4, shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.85,
      children: nets.map((n) => GestureDetector(
        onTap: () => onTap(n.id),
        child: _NetIcon(n, selected: selected == n.id),
      )).toList(),
    );

// ── SEND TAB ──────────────────────────────────────────────────────────────────

class _SendTab extends StatefulWidget {
  final RegionInfo region; final double balance;
  final String serverUrl, userId, currency;
  final String Function(double) fmt;
  final Future<void> Function() onSuccess;
  final void Function(String) snack;
  const _SendTab({required this.region, required this.balance,
      required this.serverUrl, required this.userId, required this.currency,
      required this.fmt, required this.onSuccess, required this.snack});
  @override State<_SendTab> createState() => _SendTabState();
}

class _SendTabState extends State<_SendTab> {
  bool _bankMode = false, _loadingBanks = true, _bankError = false;
  List<BankItem> _banks = [], _filtered = [];
  BankItem? _selBank;
  String _accNum = '', _accName = '', _resolved = '';
  bool _resolving = false;
  double _amount = 0;
  final _accCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();
  final _srchCtrl = TextEditingController();

  @override void initState() { super.initState(); _fetchBanks(); }
  @override void dispose() {
    _accCtrl.dispose(); _amtCtrl.dispose(); _srchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchBanks() async {
    setState(() { _loadingBanks = true; _bankError = false; });
    final cc = _kCurrToCC[widget.currency] ?? 'NG';
    try {
      final r = await http
          .get(Uri.parse(
              '${widget.serverUrl}/api/wallet/banklist?cc=$cc'))
          .timeout(const Duration(seconds: 10));
      final d = jsonDecode(r.body);
      if (d['success'] == true && (d['banks'] as List).isNotEmpty) {
        final list = (d['banks'] as List)
            .map((b) => BankItem.fromJson(b)).toList();
        setState(() {
          _banks = list; _filtered = list; _loadingBanks = false;
        });
        return;
      }
    } catch (_) {}
    setState(() { _loadingBanks = false; _bankError = true; });
  }

  void _filter(String q) => setState(() {
    _filtered = q.isEmpty ? _banks
        : _banks.where((b) =>
            b.name.toLowerCase().contains(q.toLowerCase())).toList();
  });

  Future<void> _resolve() async {
    if (_accNum.length < 10 || _selBank == null) return;
    setState(() { _resolving = true; _resolved = 'Verifying…'; });
    try {
      final r = await http.post(
        Uri.parse('${widget.serverUrl}/api/wallet/resolve'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'account_number': _accNum,
            'account_bank': _selBank!.code, 'currency': widget.currency}),
      ).timeout(const Duration(seconds: 10));
      final d = jsonDecode(r.body);
      setState(() {
        _resolving = false;
        if (d['success'] == true) {
          _resolved = '✅ ${d['account_name']}';
          _accName  = d['account_name'] ?? '';
        } else { _resolved = '⚠️ Could not verify — proceed with caution'; }
      });
    } catch (_) {
      setState(() { _resolving = false; _resolved = '⚠️ Verification unavailable'; });
    }
  }

  Future<void> _send() async {
    if (_selBank == null)         { widget.snack('Select a bank'); return; }
    if (_accNum.length < 6)       { widget.snack('Enter account number'); return; }
    if (_amount < 1)              { widget.snack('Enter a valid amount'); return; }
    if (_amount > widget.balance) { widget.snack('Insufficient balance'); return; }
    widget.snack('Processing transfer…');
    try {
      final r = await http.post(
        Uri.parse('${widget.serverUrl}/api/wallet/send-bank'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'account_bank': _selBank!.code,
            'account_number': _accNum, 'amount': _amount,
            'currency': widget.currency, 'narration': 'XamePay Transfer',
            'accName': _accName, 'userId': widget.userId}),
      ).timeout(const Duration(seconds: 20));
      final d = jsonDecode(r.body);
      if (d['success'] == true) {
        await widget.onSuccess(); widget.snack('✅ Transfer successful!');
      } else { widget.snack('❌ ${d['message'] ?? 'Transfer failed'}'); }
    } catch (_) { widget.snack('❌ Network error'); }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('💸 Send Money',
          style: TextStyle(color: Colors.white,
              fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Send to contacts or any bank in the world',
          style: TextStyle(color: _kMuted, fontSize: 13)),
      const SizedBox(height: 16),
      Row(children: [
        _tog('To Contact', !_bankMode, () => setState(() => _bankMode = false)),
        const SizedBox(width: 10),
        _tog('To Bank',    _bankMode,  () => setState(() => _bankMode = true)),
      ]),
      const SizedBox(height: 20),
      if (!_bankMode) ...[
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: _kCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10)),
          child: const Center(child: Text(
              'Tap a contact from the Chats list to send money.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kMuted, fontSize: 13))),
        ),
      ] else ...[
        const Text('Select Bank',
            style: TextStyle(color: _kMuted,
                fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (_bankError) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _kCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10)),
            child: Row(children: [
              const Icon(Icons.wifi_off_rounded, color: _kMuted, size: 20),
              const SizedBox(width: 12),
              const Expanded(child: Text(
                  'Could not load banks. Check connection.',
                  style: TextStyle(color: _kMuted, fontSize: 13))),
              TextButton(onPressed: _fetchBanks,
                  child: const Text('Retry',
                      style: TextStyle(color: _kTeal,
                          fontWeight: FontWeight.w700))),
            ]),
          ),
        ] else ...[
          _xf(_srchCtrl, '🔍 Search bank or microfinance…',
              TextInputType.text, (v) {
            _filter(v);
            if (_selBank != null) setState(() { _selBank = null; });
          }),
          if (_selBank != null) ...[
            const SizedBox(height: 8),
            _chip('✅ ${_selBank!.name}'),
          ] else if (_loadingBanks) ...[
            const Padding(padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(
                    color: _kTeal, strokeWidth: 2))),
          ] else ...[
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10)),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filtered.isEmpty ? 1 : _filtered.length,
                itemBuilder: (_, i) {
                  if (_filtered.isEmpty) return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No banks found',
                        style: TextStyle(color: _kMuted, fontSize: 13)));
                  final b = _filtered[i];
                  return InkWell(
                    onTap: () {
                      setState(() { _selBank = b; _srchCtrl.text = b.name; });
                      if (_accNum.length >= 10) _resolve();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(border: Border(bottom:
                          BorderSide(color: Colors.white.withOpacity(0.05)))),
                      child: Text(b.name, style: const TextStyle(
                          color: Colors.white, fontSize: 14))),
                  );
                },
              ),
            ),
          ],
        ],
        const SizedBox(height: 16),
        const Text('Account Number',
            style: TextStyle(color: _kMuted,
                fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _xf(_accCtrl, 'Enter account number', TextInputType.number, (v) {
          _accNum = v; if (v.length >= 10) _resolve();
        }),
        if (_resolving)
          const Padding(padding: EdgeInsets.only(bottom: 8),
              child: Text('Verifying…',
                  style: TextStyle(color: _kMuted, fontSize: 12))),
        if (!_resolving && _resolved.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _kCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10)),
            child: Text(_resolved, style: TextStyle(
                color: _resolved.startsWith('✅')
                    ? _kTeal : const Color(0xFFF0A500),
                fontSize: 13)),
          ),
        const SizedBox(height: 8),
      ],
      const Text('Amount',
          style: TextStyle(color: _kMuted,
              fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      _xf(_amtCtrl, 'Enter amount',
          const TextInputType.numberWithOptions(decimal: true),
          (v) => _amount = double.tryParse(v) ?? 0),
      const SizedBox(height: 6),
      Text('Balance: ${widget.fmt(widget.balance)}',
          style: const TextStyle(color: _kMuted, fontSize: 12)),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _kTeal,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
          onPressed: _bankMode ? _send : () => widget.snack('Select a contact'),
          child: const Text('Send Money',
              style: TextStyle(color: Colors.black,
                  fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );

  Widget _tog(String l, bool on, VoidCallback f) => Expanded(
    child: GestureDetector(onTap: f,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? _kTeal : _kCard,
          borderRadius: BorderRadius.circular(10),
          border: on ? null : Border.all(color: Colors.white12),
        ),
        child: Text(l, style: TextStyle(
            color: on ? Colors.black : Colors.white,
            fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    ),
  );

  Widget _chip(String t) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: const Color(0x1A00B0A0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x3300B0A0))),
    child: Text(t, style: const TextStyle(color: _kTeal,
        fontSize: 13, fontWeight: FontWeight.w600)),
  );
}

// ── AIRTIME TAB ───────────────────────────────────────────────────────────────

class _AirtimeTab extends StatefulWidget {
  final RegionInfo region; final double balance;
  final String serverUrl, userId;
  final String Function(double) fmt;
  final Future<void> Function() onSuccess;
  final void Function(String) snack;
  const _AirtimeTab({required this.region, required this.balance,
      required this.serverUrl, required this.userId, required this.fmt,
      required this.onSuccess, required this.snack});
  @override State<_AirtimeTab> createState() => _AirtimeTabState();
}

class _AirtimeTabState extends State<_AirtimeTab> {
  String? _net; String _phone = '', _amt = '';
  final _pCtrl = TextEditingController();
  final _aCtrl = TextEditingController();
  @override void dispose() { _pCtrl.dispose(); _aCtrl.dispose(); super.dispose(); }

  Future<void> _buy() async {
    if (_net == null)          { widget.snack('Select a network'); return; }
    if (_phone.length < 6)     { widget.snack('Enter phone number'); return; }
    final a = double.tryParse(_amt) ?? 0;
    if (a < 1)                 { widget.snack('Enter amount'); return; }
    if (a > widget.balance)    { widget.snack('Insufficient balance'); return; }
    widget.snack('Processing…');
    try {
      final r = await http.post(
          Uri.parse('${widget.serverUrl}/api/wallet/airtime'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': _phone, 'operatorId': _net,
              'amount': a, 'userId': widget.userId}))
          .timeout(const Duration(seconds: 15));
      final d = jsonDecode(r.body);
      if (d['success'] == true) {
        await widget.onSuccess(); widget.snack('✅ Airtime sent!');
      } else { widget.snack('❌ ${d['message'] ?? 'Failed'}'); }
    } catch (_) { widget.snack('❌ Network error'); }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('📱 Buy Airtime',
          style: TextStyle(color: Colors.white,
              fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 20),
      const Text('Select Network',
          style: TextStyle(color: _kMuted,
              fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      _netGrid(widget.region.networks, _net,
          (id) => setState(() => _net = id)),
      const SizedBox(height: 16),
      const Text('Phone Number',
          style: TextStyle(color: _kMuted,
              fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      _xf(_pCtrl, 'Enter phone number',
          TextInputType.phone, (v) => _phone = v),
      const SizedBox(height: 16),
      const Text('Amount',
          style: TextStyle(color: _kMuted,
              fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      GridView.count(
        crossAxisCount: 3, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 2.5,
        children: [50, 100, 200, 500, 1000, 2000].map((a) => GestureDetector(
          onTap: () { setState(() => _amt = '$a'); _aCtrl.text = '$a'; },
          child: Container(alignment: Alignment.center,
            decoration: BoxDecoration(color: _kCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _amt == '$a' ? _kTeal : Colors.white12)),
            child: Text(widget.fmt(a.toDouble()),
                style: const TextStyle(color: Colors.white,
                    fontSize: 13, fontWeight: FontWeight.w600))),
        )).toList(),
      ),
      const SizedBox(height: 8),
      _xf(_aCtrl, 'Or enter custom amount',
          const TextInputType.numberWithOptions(decimal: true),
          (v) => _amt = v),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _kTeal,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
          onPressed: _buy,
          child: const Text('Buy Airtime',
              style: TextStyle(color: Colors.black,
                  fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );
}

// ── DATA TAB ──────────────────────────────────────────────────────────────────

class _DataTab extends StatefulWidget {
  final RegionInfo region; final double balance;
  final String serverUrl, userId;
  final String Function(double) fmt;
  final Future<void> Function() onSuccess;
  final void Function(String) snack;
  const _DataTab({required this.region, required this.balance,
      required this.serverUrl, required this.userId, required this.fmt,
      required this.onSuccess, required this.snack});
  @override State<_DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<_DataTab> {
  String? _net; String _phone = '';
  final _pCtrl = TextEditingController();
  @override void dispose() { _pCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('📶 Buy Data',
          style: TextStyle(color: Colors.white,
              fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 20),
      const Text('Select Network',
          style: TextStyle(color: _kMuted,
              fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      _netGrid(widget.region.networks, _net,
          (id) => setState(() => _net = id)),
      const SizedBox(height: 16),
      const Text('Phone Number',
          style: TextStyle(color: _kMuted,
              fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      _xf(_pCtrl, 'Enter phone number',
          TextInputType.phone, (v) => _phone = v),
      if (_net != null) ...[
        const SizedBox(height: 16),
        const Text('Plans loaded from server per network.',
            style: TextStyle(color: _kMuted, fontSize: 12)),
      ],
    ]),
  );
}

// ── BILLS TAB ─────────────────────────────────────────────────────────────────

class _BillsTab extends StatelessWidget {
  final RegionInfo region; final double balance;
  final String serverUrl, userId, currency;
  final String Function(double) fmt;
  final Future<void> Function() onSuccess;
  final void Function(String) snack;
  const _BillsTab({required this.region, required this.balance,
      required this.serverUrl, required this.userId, required this.currency,
      required this.fmt, required this.onSuccess, required this.snack});

  static const _bills = [
    ['electricity', 'Electricity', '💡'],
    ['cable',       'Cable TV',    '📺'],
    ['internet',    'Internet',    '🌐'],
    ['water',       'Water',       '💧'],
    ['gas',         'Gas',         '🔥'],
  ];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('🧾 Pay Bills',
          style: TextStyle(color: Colors.white,
              fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 20),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 1.3,
        children: _bills.map((b) => GestureDetector(
          onTap: () => _billForm(context, b),
          child: Container(
            decoration: BoxDecoration(color: _kCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Text(b[2], style: const TextStyle(fontSize: 32)),
              const SizedBox(height: 10),
              Text(b[1], style: const TextStyle(color: Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
          ),
        )).toList(),
      ),
    ]),
  );

  void _billForm(BuildContext ctx, List<String> b) {
    String acc = '', amtS = '';
    final aC = TextEditingController(), amC = TextEditingController();
    showModalBottomSheet(
      context: ctx, isScrollControlled: true, backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('${b[2]} ${b[1]}', style: const TextStyle(color: Colors.white,
                fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            const Text('Account / Meter Number',
                style: TextStyle(color: _kMuted,
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _xf(aC, 'Enter account number', TextInputType.text, (v) => acc = v),
            const SizedBox(height: 16),
            const Text('Amount', style: TextStyle(color: _kMuted,
                fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _xf(amC, 'Enter amount',
                const TextInputType.numberWithOptions(decimal: true),
                (v) => amtS = v),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _kTeal,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                onPressed: () async {
                  final a = double.tryParse(amtS) ?? 0;
                  if (acc.isEmpty) { snack('Enter account number'); return; }
                  if (a < 1)       { snack('Enter amount'); return; }
                  Navigator.pop(ctx);
                  try {
                    snack('Processing payment…');
                    final r = await http.post(
                        Uri.parse('$serverUrl/api/wallet/bills/pay'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({'userId': userId,
                            'biller_code': b[0], 'item_code': b[0],
                            'customer': acc, 'amount': a,
                            'country': region.countryCode}))
                        .timeout(const Duration(seconds: 20));
                    final d = jsonDecode(r.body);
                    if (d['success'] == true) {
                      await onSuccess(); snack('✅ Bill paid!');
                    } else { snack('❌ ${d['message'] ?? 'Payment failed'}'); }
                  } catch (_) { snack('❌ Network error'); }
                },
                child: Text('Pay ${b[1]}', style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── HISTORY TAB ───────────────────────────────────────────────────────────────

class _HistoryTab extends StatelessWidget {
  final List<WalletTx> txs;
  final String Function(double) fmt;
  const _HistoryTab({required this.txs, required this.fmt});

  @override
  Widget build(BuildContext context) {
    if (txs.isEmpty) return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('📭', style: TextStyle(fontSize: 48)),
        SizedBox(height: 14),
        Text('No transactions yet',
            style: TextStyle(color: _kMuted,
                fontSize: 15, fontWeight: FontWeight.w600)),
      ]));
    return ListView.separated(
      padding: const EdgeInsets.all(16), itemCount: txs.length,
      separatorBuilder: (_, __) =>
          const Divider(color: Colors.white10, height: 1),
      itemBuilder: (_, i) {
        final tx = txs[i]; final cr = tx.type == 'credit';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Container(width: 42, height: 42,
              decoration: BoxDecoration(
                color: cr ? const Color(0x1A00B0A0) : const Color(0x1AFF6464),
                shape: BoxShape.circle),
              child: Center(child: Text(tx.icon,
                  style: const TextStyle(fontSize: 18)))),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx.label, style: const TextStyle(color: Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w600)),
              Text('${tx.ts.substring(0, 10)} • ${tx.status}',
                  style: const TextStyle(color: _kMuted, fontSize: 11)),
            ])),
            Text('${cr ? '+' : '-'}${fmt(tx.amount)}',
                style: TextStyle(
                    color: cr ? _kTeal : const Color(0xFFFF6464),
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
        );
      },
    );
  }
}

// ── SHARED FIELD WIDGET ───────────────────────────────────────────────────────

Widget _xf(TextEditingController c, String hint, TextInputType kt,
    void Function(String) fn) =>
    TextField(
      controller: c, keyboardType: kt,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _kMuted, fontSize: 14),
        filled: true, fillColor: _kCard,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white12)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _kTeal)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      onChanged: fn,
    );
