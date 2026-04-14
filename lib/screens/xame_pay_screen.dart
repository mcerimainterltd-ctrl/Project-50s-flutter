// lib/screens/xame_pay_screen.dart
// XamePay â€” go_router-aware wallet for XamePage 2.1  (Build 239+)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// â”€â”€ COLOURS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const _kTeal  = Color(0xFF00B0A0);
const _kBg    = Color(0xFF0D1520);
const _kCard  = Color(0xFF111E2E);
const _kMuted = Color(0xFF7A9BB5);

// â”€â”€ MODELS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class WalletTx {
  final String id, label, icon, type, status, ts;
  final double amount;
  WalletTx.fromJson(Map<String, dynamic> j)
      : id     = j['id']?.toString() ?? '${DateTime.now().millisecondsSinceEpoch}',
        label  = j['label']  ?? '',
        icon   = j['icon']   ?? 'ðŸ’³',
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

// â”€â”€ REGION INFO â€” symbol + networks ONLY; bank names always from server â”€â”€â”€â”€â”€â”€â”€
class RegionInfo {
  final String currency, country, countryCode, symbol;
  final List<List<String>> networks; // [id, label, emoji]
  const RegionInfo(this.currency, this.country, this.countryCode,
      this.symbol, this.networks);
}

const _kRegions = <RegionInfo>[
  RegionInfo('NGN','Nigeria','NG','â‚¦',         [['MTN-NG','MTN','ðŸŸ¡'],['AIRTEL-NG','Airtel','ðŸ”´'],['GLO-NG','Glo','ðŸŸ¢'],['9MOBILE-NG','9mobile','ðŸ’š']]),
  RegionInfo('GHS','Ghana','GH','GHâ‚µ',         [['MTN-GH','MTN','ðŸŸ¡'],['VODAFONE-GH','Vodafone','ðŸ”´'],['AIRTELTIGO-GH','AirtelTigo','ðŸŸ ']]),
  RegionInfo('KES','Kenya','KE','KSh',         [['SAFARICOM-KE','Safaricom','ðŸŸ¢'],['AIRTEL-KE','Airtel','ðŸ”´'],['TELKOM-KE','Telkom','ðŸ”µ']]),
  RegionInfo('ZAR','South Africa','ZA','R',    [['VODACOM-ZA','Vodacom','ðŸ”´'],['MTN-ZA','MTN','ðŸŸ¡'],['CELL-ZA','Cell C','âš«'],['TELKOM-ZA','Telkom','ðŸ”µ']]),
  RegionInfo('USD','United States','US','\$',  [['ATT-US','AT&T','ðŸ”µ'],['TMOBILE-US','T-Mobile','ðŸ©·'],['VERIZON-US','Verizon','ðŸ”´'],['CRICKET-US','Cricket','ðŸŸ¢']]),
  RegionInfo('GBP','United Kingdom','GB','Â£',  [['EE-UK','EE','ðŸŸ¢'],['O2-UK','O2','ðŸ”µ'],['VODAFONE-UK','Vodafone','ðŸ”´'],['THREE-UK','Three','âš«']]),
  RegionInfo('EUR','Europe','DE','â‚¬',          [['VODAFONE-EU','Vodafone','ðŸ”´'],['ORANGE-EU','Orange','ðŸŸ '],['TMOBILE-EU','T-Mobile','ðŸ©·'],['O2-EU','O2','ðŸ”µ']]),
  RegionInfo('INR','India','IN','â‚¹',           [['JIO-IN','Jio','ðŸ”µ'],['AIRTEL-IN','Airtel','ðŸ”´'],['VI-IN','Vi','ðŸŸ£'],['BSNL-IN','BSNL','ðŸŸ ']]),
  RegionInfo('AED','UAE','AE','Ø¯.Ø¥',           [['ETISALAT-AE','e&','ðŸŸ¢'],['DU-AE','du','ðŸŸ£']]),
  RegionInfo('CAD','Canada','CA','CA\$',       [['ROGERS-CA','Rogers','ðŸ”´'],['BELL-CA','Bell','ðŸ”µ'],['TELUS-CA','Telus','ðŸŸ¢'],['FREEDOM-CA','Freedom','ðŸŸ£']]),
  RegionInfo('AUD','Australia','AU','A\$',     [['TELSTRA-AU','Telstra','ðŸ”µ'],['OPTUS-AU','Optus','ðŸŸ¡'],['VODAFONE-AU','Vodafone','ðŸ”´'],['TPG-AU','TPG','âš«']]),
  RegionInfo('JPY','Japan','JP','Â¥',           [['DOCOMO-JP','NTT Docomo','ðŸ”´'],['SOFTBANK-JP','SoftBank','âš«'],['AU-JP','au','ðŸŸ '],['RAKUTEN-JP','Rakuten','ðŸ©·']]),
  RegionInfo('SGD','Singapore','SG','S\$',     [['SINGTEL-SG','Singtel','ðŸ”´'],['STARHUB-SG','StarHub','ðŸŸ¢'],['M1-SG','M1','ðŸ”µ'],['TPG-SG','TPG','ðŸŸ£']]),
  RegionInfo('EGP','Egypt','EG','EÂ£',          [['ORANGE-EG','Orange','ðŸŸ '],['VODAFONE-EG','Vodafone','ðŸ”´'],['ETISALAT-EG','Etisalat','ðŸŸ¢'],['WE-EG','WE','ðŸ”µ']]),
  RegionInfo('SAR','Saudi Arabia','SA','Ø±.Ø³',  [['STC-SA','STC','ðŸŸ£'],['MOBILY-SA','Mobily','ðŸŸ¢'],['ZAIN-SA','Zain','ðŸ”µ']]),
  RegionInfo('TRY','Turkey','TR','â‚º',          [['TURKCELL-TR','Turkcell','ðŸ”µ'],['VODAFONE-TR','Vodafone TR','ðŸ”´'],['TURKTELEKOM-TR','Turk Telekom','ðŸŸ ']]),
  RegionInfo('MXN','Mexico','MX','MX\$',       [['TELCEL-MX','Telcel','ðŸ”µ'],['MOVISTAR-MX','Movistar','ðŸŸ¢'],['ATT-MX','AT&T Mexico','ðŸ”µ']]),
  RegionInfo('IDR','Indonesia','ID','Rp',      [['TELKOMSEL-ID','Telkomsel','ðŸ”´'],['INDOSAT-ID','Indosat','ðŸŸ¡'],['XL-ID','XL Axiata','ðŸ”µ']]),
  RegionInfo('PHP','Philippines','PH','â‚±',     [['GLOBE-PH','Globe','ðŸ”µ'],['SMART-PH','Smart','ðŸŸ¢'],['DITO-PH','DITO','ðŸŸ ']]),
  RegionInfo('MYR','Malaysia','MY','RM',       [['MAXIS-MY','Maxis','ðŸ”µ'],['CELCOM-MY','Celcom','ðŸŸ¡'],['DIGI-MY','Digi','ðŸŸ¡'],['UMOBILE-MY','U Mobile','ðŸŸ¢']]),
  RegionInfo('BRL','Brazil','BR','R\$',        [['VIVO-BR','Vivo','ðŸŸ£'],['CLARO-BR','Claro','ðŸ”´'],['TIM-BR','TIM','ðŸ”µ']]),
  RegionInfo('ZMW','Zambia','ZM','ZK',         [['MTN-ZM','MTN','ðŸŸ¡'],['AIRTEL-ZM','Airtel','ðŸ”´'],['ZAMTEL-ZM','Zamtel','ðŸŸ¢']]),
  RegionInfo('UGX','Uganda','UG','USh',        [['MTN-UG','MTN','ðŸŸ¡'],['AIRTEL-UG','Airtel','ðŸ”´'],['AFRICELL-UG','Africell','ðŸ”µ']]),
  RegionInfo('TZS','Tanzania','TZ','TSh',      [['VODACOM-TZ','Vodacom','ðŸ”´'],['AIRTEL-TZ','Airtel','ðŸŸ '],['TIGO-TZ','Tigo','ðŸ”µ']]),
  RegionInfo('RWF','Rwanda','RW','Fr',         [['MTN-RW','MTN','ðŸŸ¡'],['AIRTEL-RW','Airtel','ðŸ”´']]),
  RegionInfo('XOF','West Africa (CFA)','SN','CFA',[['ORANGE-WA','Orange','ðŸŸ '],['MTN-WA','MTN','ðŸŸ¡'],['MOOV-WA','Moov','ðŸ”µ']]),
  RegionInfo('CMR','Cameroon','CM','FCFA',     [['MTN-CM','MTN','ðŸŸ¡'],['ORANGE-CM','Orange','ðŸŸ ']]),
  RegionInfo('QAR','Qatar','QA','QR',          [['OOREDOO-QA','Ooredoo','ðŸ”´'],['VODAFONE-QA','Vodafone QA','ðŸ”´']]),
  RegionInfo('VND','Vietnam','VN','â‚«',         [['VIETTEL-VN','Viettel','ðŸ”´'],['VINAPHONE-VN','Vinaphone','ðŸ”µ'],['MOBIFONE-VN','Mobifone','ðŸŸ¢']]),
  RegionInfo('THB','Thailand','TH','à¸¿',        [['AIS-TH','AIS','ðŸŸ¢'],['DTAC-TH','DTAC','ðŸ”µ'],['TRUE-TH','True Move','ðŸ”´']]),
  RegionInfo('PKR','Pakistan','PK','â‚¨',        [['JAZZ-PK','Jazz','ðŸŸ '],['TELENOR-PK','Telenor','ðŸ”µ'],['ZONG-PK','Zong','ðŸ”´'],['UFONE-PK','Ufone','ðŸŸ¢']]),
  RegionInfo('MAD','Morocco','MA','MAD',       [['MAROCTELECOM-MA','Maroc Telecom','ðŸŸ¢'],['ORANGE-MA','Orange','ðŸŸ '],['INWI-MA','Inwi','ðŸ”µ']]),
  RegionInfo('ETB','Ethiopia','ET','Br',       [['ETHIOTELECOM-ET','Ethio Telecom','ðŸŸ¢'],['SAFARICOM-ET','Safaricom ET','ðŸ”µ']]),
  RegionInfo('ZWL','Zimbabwe','ZW','Z\$',      [['ECONET-ZW','Econet','ðŸ”µ'],['NETONE-ZW','NetOne','ðŸŸ¢'],['TELECEL-ZW','Telecel','ðŸ”´']]),
  RegionInfo('COP','Colombia','CO','COL\$',    [['CLARO-CO','Claro','ðŸ”´'],['MOVISTAR-CO','Movistar','ðŸŸ¢'],['TIGO-CO','Tigo','ðŸ”µ']]),
  RegionInfo('ARS','Argentina','AR','AR\$',    [['CLARO-AR','Claro','ðŸ”´'],['PERSONAL-AR','Personal','ðŸ”µ'],['MOVISTAR-AR','Movistar','ðŸŸ¢']]),
];

// currency â†’ Flutterwave country code
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

// â”€â”€ CURRENCY CONVERTER â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

// â”€â”€ SCREEN â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class XamePayScreen extends StatefulWidget {
  final String userId, serverUrl;
  // Provided by router.dart as: onBack: () => context.go('/contacts')
  // This is the ONLY back mechanism â€” no Navigator.pop anywhere.
  final VoidCallback? onBack;

  const XamePayScreen({
    super.key,
    required this.userId,
    required this.serverUrl,
    this.onBack,
  });

  @override
  State<XamePayScreen> createState() => _XamePayScreenState();
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

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

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
      if (d['currency'] != null && p.getString('wallet:currency') == null) {
        _currency = d['currency'];
      }
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
      if (d['success'] == true) {
        setState(() {
          _balance = (d['balance'] as num?)?.toDouble() ?? 0;
          _txs = (d['transactions'] as List? ?? [])
              .map((t) => WalletTx.fromJson(t)).toList();
        });
      }
    } catch (_) {}
  }

  // Called by AppBar back button AND WillPopScope (hardware back).
  void _goBack() {
    if (widget.onBack != null) {
      widget.onBack!(); // e.g. context.go('/contacts') from router.dart
    }
    // If no onBack provided (e.g. opened in a test), do nothing â€”
    // go_router controls the stack, not us.
  }

  RegionInfo get _ri      => _region(_currency);
  String      _fmt(double n) => '${_ri.symbol}${_fmtN(n)}';

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
    return 'â‰ˆ ${_region(_dispCurrency).symbol}${_fmtN(v)} $_dispCurrency';
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  // â”€â”€ BUILD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Intercept Android hardware back â€” route through _goBack().
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
          title: const Row(mainAxisSize: MainAxisSize.min, children: [
            Text('ðŸ’³', style: TextStyle(fontSize: 18)),
            SizedBox(width: 6),
            Text('XamePay',
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

  // â”€â”€ BALANCE CARD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(conv,
                style: const TextStyle(
                    color: Color(0xB3FFFFFF), fontSize: 13))),
        Text('XamePay â€¢ $_currency',
            style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12)),
        const SizedBox(height: 20),
        Row(children: [
          _cBtn('+ Add Money', () => _showAddMoney()),
          const SizedBox(width: 8),
          _cBtn('â†— Send',     () => _tab.animateTo(3)),
          const SizedBox(width: 8),
          _cBtn('ðŸ“Š History', () => _tab.animateTo(4)),
        ]),
      ]),
    );
  }

  Widget _cBtn(String l, VoidCallback f) => Expanded(
    child: GestureDetector(
      onTap: f,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x33FFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x4DFFFFFF)),
        ),
        child: Text(l,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white,
                fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    ),
  );

  // â”€â”€ TAB BAR â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
        Tab(text: 'ðŸ“± Airtime'),
        Tab(text: 'ðŸ“¶ Data'),
        Tab(text: 'ðŸ§¾ Bills'),
        Tab(text: 'ðŸ’¸ Send'),
        Tab(text: 'ðŸ“Š History'),
      ],
    ),
  );

  // â”€â”€ ADD MONEY SHEET â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showAddMoney() {
    final methods = [
      ['ðŸ’³', 'Debit / Credit Card',   'Instant â€¢ Visa, Mastercard, Verve'],
      ['ðŸ¦', 'Bank Transfer',          'Instant â€¢ Virtual account'],
      ['ðŸ“Ÿ', 'USSD',                   'No internet needed'],
      ['ðŸ“¥', 'Receive from Contact',   'From another XamePage user'],
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.55,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.all(24),
          children: [
            const Text('ðŸ’³ Add Money',
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

  // â”€â”€ SETTINGS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showSettings() {
    String tc = _currency, td = _dispCurrency;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => DraggableScrollableSheet(
          expand: false, initialChildSize: 0.75,
          builder: (_, sc) => ListView(
            controller: sc,
            padding: const EdgeInsets.all(24),
            children: [
              Row(children: [
                const Expanded(child: Text('âš™ï¸ Wallet Settings',
                    style: TextStyle(color: Colors.white,
                        fontSize: 17, fontWeight: FontWeight.w700))),
                IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(ctx)),
              ]),
              const SizedBox(height: 16),
              _sLabel('ðŸŒ Region & Currency'),
              const SizedBox(height: 8),
              _sDrop<String>(
                value: tc,
                items: _kRegions.map((r) => DropdownMenuItem(
                  value: r.currency,
                  child: Text('${r.country} (${r.currency})',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14)))).toList(),
                onChange: (v) { if (v != null) ss(() => tc = v); },
              ),
              const SizedBox(height: 20),
              _sLabel('ðŸ’± Display Balance In'),
              const SizedBox(height: 4),
              const Text(
                'Shows your balance converted to another currency '
                'alongside your wallet currency.',
                style: TextStyle(color: _kMuted, fontSize: 12)),
              const SizedBox(height: 8),
              _sDrop<String>(
                value: td,
                items: _kRegions.map((r) => DropdownMenuItem(
                  value: r.currency,
                  child: Text('${r.symbol} ${r.currency} â€” ${r.country}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14)))).toList(),
                onChange: (v) { if (v != null) ss(() => td = v); },
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
                            ? '1 $tc â‰ˆ ${dr.symbol}${rv.toStringAsFixed(4)} $td'
                            : 'Fetching live rateâ€¦',
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
                      Uri.parse(
                          '${widget.serverUrl}/api/wallet/currency'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({
                        'userId': widget.userId,
                        'currency': _currency
                      }),
                    );
                  } catch (_) {}
                  await _FxService.load(_currency);
                  if (mounted) {
                    Navigator.pop(ctx);
                    _snack('âœ… Settings saved');
                  }
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

  static Widget _sDrop<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChange,
  }) =>
      DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        dropdownColor: _kBg,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          filled: true, fillColor: _kCard,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        items: items,
        onChanged: onChange,
      );
}

// â”€â”€ SEND TAB â€” banks exclusively from Flutterwave API â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SendTab extends StatefulWidget {
  final RegionInfo region;
  final double balance;
  final String serverUrl, userId, currency;
  final String Function(double) fmt;
  final Future<void> Function() onSuccess;
  final void Function(String) snack;

  const _SendTab({
    required this.region, required this.balance,
    required this.serverUrl, required this.userId, required this.currency,
    required this.fmt, required this.onSuccess, required this.snack,
  });

  @override
  State<_SendTab> createState() => _SendTabState();
}

class _SendTabState extends State<_SendTab> {
  bool _bankMode = false, _loadingBanks = true, _bankError = false;
  List<BankItem> _banks = [], _filtered = [];
  BankItem? _selBank;
  String _accNum = '', _accName = '', _resolved = '';
  bool _resolving = false;
  double _amount = 0;

  final _accCtrl  = TextEditingController();
  final _amtCtrl  = TextEditingController();
  final _srchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _fetchBanks(); }

  @override
  void dispose() {
    _accCtrl.dispose(); _amtCtrl.dispose(); _srchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchBanks() async {
    setState(() { _loadingBanks = true; _bankError = false; });
    final cc = _kCurrToCC[widget.currency] ?? 'NG';
    try {
      final r = await http
          .get(Uri.parse('${widget.serverUrl}/api/wallet/banklist?cc=$cc'))
          .timeout(const Duration(seconds: 10));
      final d = jsonDecode(r.body);
      if (d['success'] == true && (d['banks'] as List).isNotEmpty) {
        final list = (d['banks'] as List)
            .map((b) => BankItem.fromJson(b)).toList();
        setState(() { _banks = list; _filtered = list; _loadingBanks = false; });
        return;
      }
    } catch (_) {}
    // API failed â€” show retry, never show hardcoded names
    setState(() { _loadingBanks = false; _bankError = true; });
  }

  void _filter(String q) => setState(() {
    _filtered = q.isEmpty
        ? _banks
        : _banks
            .where((b) => b.name.toLowerCase().contains(q.toLowerCase()))
            .toList();
  });

  Future<void> _resolve() async {
    if (_accNum.length < 10 || _selBank == null) return;
    setState(() { _resolving = true; _resolved = 'Verifyingâ€¦'; });
    try {
      final r = await http.post(
        Uri.parse('${widget.serverUrl}/api/wallet/resolve'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'account_number': _accNum,
          'account_bank':   _selBank!.code,
          'currency':       widget.currency,
        }),
      ).timeout(const Duration(seconds: 10));
      final d = jsonDecode(r.body);
      setState(() {
        _resolving = false;
        if (d['success'] == true) {
          _resolved = 'âœ… ${d['account_name']}';
          _accName  = d['account_name'] ?? '';
        } else {
          _resolved = 'âš ï¸ Could not verify â€” proceed with caution';
        }
      });
    } catch (_) {
      setState(() { _resolving = false; _resolved = 'âš ï¸ Verification unavailable'; });
    }
  }

  Future<void> _send() async {
    if (_selBank == null)          { widget.snack('Select a bank'); return; }
    if (_accNum.length < 6)        { widget.snack('Enter account number'); return; }
    if (_amount < 1)               { widget.snack('Enter a valid amount'); return; }
    if (_amount > widget.balance)  { widget.snack('Insufficient balance'); return; }
    widget.snack('Processing transferâ€¦');
    try {
      final r = await http.post(
        Uri.parse('${widget.serverUrl}/api/wallet/send-bank'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'account_bank':    _selBank!.code,
          'account_number':  _accNum,
          'amount':          _amount,
          'currency':        widget.currency,
          'narration':       'XamePay Transfer',
          'accName':         _accName,
          'userId':          widget.userId,
        }),
      ).timeout(const Duration(seconds: 20));
      final d = jsonDecode(r.body);
      if (d['success'] == true) {
        await widget.onSuccess();
        widget.snack('âœ… Transfer successful!');
      } else {
        widget.snack('âŒ ${d['message'] ?? 'Transfer failed'}');
      }
    } catch (_) { widget.snack('âŒ Network error'); }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ðŸ’¸ Send Money',
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

        // â”€â”€ Bank search â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
              const Icon(Icons.wifi_off_rounded,
                  color: _kMuted, size: 20),
              const SizedBox(width: 12),
              const Expanded(child: Text(
                  'Could not load banks. Check connection.',
                  style: TextStyle(color: _kMuted, fontSize: 13))),
              TextButton(
                onPressed: _fetchBanks,
                child: const Text('Retry',
                    style: TextStyle(color: _kTeal,
                        fontWeight: FontWeight.w700))),
            ]),
          ),
        ] else ...[
          _xf(_srchCtrl, 'ðŸ” Search bank or microfinanceâ€¦',
              TextInputType.text, (v) {
            _filter(v);
            if (_selBank != null) setState(() { _selBank = null; });
          }),

          if (_selBank != null) ...[
            const SizedBox(height: 8),
            _chip('âœ… ${_selBank!.name}'),
          ] else if (_loadingBanks) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(
                  color: _kTeal, strokeWidth: 2))),
          ] else ...[
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10)),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filtered.isEmpty ? 1 : _filtered.length,
                itemBuilder: (_, i) {
                  if (_filtered.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No banks found',
                          style: TextStyle(color: _kMuted,
                              fontSize: 13)));
                  }
                  final b = _filtered[i];
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selBank = b;
                        _srchCtrl.text = b.name;
                      });
                      if (_accNum.length >= 10) _resolve();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(
                              color: Colors.white
                                  .withOpacity(0.05)))),
                      child: Text(b.name,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14)),
                    ),
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
        _xf(_accCtrl, 'Enter account number',
            TextInputType.number, (v) {
          _accNum = v;
          if (v.length >= 10) _resolve();
        }),
        if (_resolving)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Verifyingâ€¦',
                style: TextStyle(color: _kMuted, fontSize: 12))),
        if (!_resolving && _resolved.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _kCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10)),
            child: Text(_resolved,
                style: TextStyle(
                    color: _resolved.startsWith('âœ…')
                        ? _kTeal
                        : const Color(0xFFF0A500),
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
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _kTeal,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _bankMode ? _send : () => widget.snack('Select a contact'),
          child: const Text('Send Money',
              style: TextStyle(color: Colors.black,
                  fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );

  Widget _tog(String l, bool on, VoidCallback f) => Expanded(
    child: GestureDetector(
      onTap: f,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? _kTeal : _kCard,
          borderRadius: BorderRadius.circular(10),
          border: on ? null : Border.all(color: Colors.white12),
        ),
        child: Text(l,
            style: TextStyle(
                color: on ? Colors.black : Colors.white,
                fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    ),
  );

  Widget _chip(String t) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0x1A00B0A0),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0x3300B0A0)),
    ),
    child: Text(t,
        style: const TextStyle(
            color: _kTeal, fontSize: 13, fontWeight: FontWeight.w600)),
  );
}

// â”€â”€ AIRTIME TAB â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
    widget.snack('Processingâ€¦');
    try {
      final r = await http.post(
          Uri.parse('${widget.serverUrl}/api/wallet/airtime'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': _phone, 'operatorId': _net,
              'amount': a, 'userId': widget.userId}))
          .timeout(const Duration(seconds: 15));
      final d = jsonDecode(r.body);
      if (d['success'] == true) {
        await widget.onSuccess(); widget.snack('âœ… Airtime sent!');
      } else { widget.snack('âŒ ${d['message'] ?? 'Failed'}'); }
    } catch (_) { widget.snack('âŒ Network error'); }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ðŸ“± Buy Airtime',
          style: TextStyle(color: Colors.white,
              fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 20),
      const Text('Select Network',
          style: TextStyle(color: _kMuted,
              fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 4, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.9,
        children: widget.region.networks.map((n) => GestureDetector(
          onTap: () => setState(() => _net = n[0]),
          child: Container(
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _net == n[0] ? _kTeal : Colors.white12, width: 2)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Text(n[2], style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 4),
              Text(n[1], style: const TextStyle(color: Colors.white,
                  fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        )).toList(),
      ),
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
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: _amt == '$a' ? _kTeal : Colors.white12)),
            child: Text(widget.fmt(a.toDouble()),
                style: const TextStyle(color: Colors.white,
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        )).toList(),
      ),
      const SizedBox(height: 8),
      _xf(_aCtrl, 'Or enter custom amount',
          const TextInputType.numberWithOptions(decimal: true),
          (v) => _amt = v),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _kTeal,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _buy,
          child: const Text('Buy Airtime',
              style: TextStyle(color: Colors.black,
                  fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );
}

// â”€â”€ DATA TAB â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
  String? _net;
  String  _phone = '';
  final _pCtrl = TextEditingController();
  @override void dispose() { _pCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ðŸ“¶ Buy Data',
          style: TextStyle(color: Colors.white,
              fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 20),
      const Text('Select Network',
          style: TextStyle(color: _kMuted,
              fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 4, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.9,
        children: widget.region.networks.map((n) => GestureDetector(
          onTap: () => setState(() => _net = n[0]),
          child: Container(
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _net == n[0] ? _kTeal : Colors.white12, width: 2)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Text(n[2], style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 4),
              Text(n[1], style: const TextStyle(color: Colors.white,
                  fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        )).toList(),
      ),
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

// â”€â”€ BILLS TAB â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _BillsTab extends StatelessWidget {
  final RegionInfo region; final double balance;
  final String serverUrl, userId, currency;
  final String Function(double) fmt;
  final Future<void> Function() onSuccess;
  final void Function(String) snack;
  const _BillsTab({required this.region, required this.balance,
      required this.serverUrl, required this.userId, required this.currency,
      required this.fmt, required this.onSuccess, required this.snack});

  // Bill categories fetched from server per region
  static const _skeletonBills = [
    ['electricity', 'Electricity', 'ðŸ’¡'],
    ['cable',       'Cable TV',    'ðŸ“º'],
    ['internet',    'Internet',    'ðŸŒ'],
    ['water',       'Water',       'ðŸ’§'],
    ['gas',         'Gas',         'ðŸ”¥'],
  ];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ðŸ§¾ Pay Bills',
          style: TextStyle(color: Colors.white,
              fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 20),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 1.3,
        children: _skeletonBills.map((b) => GestureDetector(
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
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('${b[2]} ${b[1]}',
                style: const TextStyle(color: Colors.white,
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            const Text('Account / Meter Number',
                style: TextStyle(color: _kMuted,
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _xf(aC, 'Enter account number',
                TextInputType.text, (v) => acc = v),
            const SizedBox(height: 16),
            const Text('Amount',
                style: TextStyle(color: _kMuted,
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _xf(amC, 'Enter amount',
                const TextInputType.numberWithOptions(decimal: true),
                (v) => amtS = v),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kTeal,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  final a = double.tryParse(amtS) ?? 0;
                  if (acc.isEmpty) { snack('Enter account number'); return; }
                  if (a < 1)       { snack('Enter amount'); return; }
                  Navigator.pop(ctx);
                  try {
                    snack('Processing paymentâ€¦');
                    final r = await http.post(
                        Uri.parse('$serverUrl/api/wallet/bills/pay'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({
                          'userId':      userId,
                          'biller_code': b[0],
                          'item_code':   b[0],
                          'customer':    acc,
                          'amount':      a,
                          'country':     region.countryCode,
                        }))
                        .timeout(const Duration(seconds: 20));
                    final d = jsonDecode(r.body);
                    if (d['success'] == true) {
                      await onSuccess(); snack('âœ… Bill paid!');
                    } else {
                      snack('âŒ ${d['message'] ?? 'Payment failed'}');
                    }
                  } catch (_) { snack('âŒ Network error'); }
                },
                child: Text('Pay ${b[1]}',
                    style: const TextStyle(color: Colors.black,
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// â”€â”€ HISTORY TAB â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _HistoryTab extends StatelessWidget {
  final List<WalletTx> txs;
  final String Function(double) fmt;
  const _HistoryTab({required this.txs, required this.fmt});

  @override
  Widget build(BuildContext context) {
    if (txs.isEmpty) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min,
          children: [
        Text('ðŸ“­', style: TextStyle(fontSize: 48)),
        SizedBox(height: 14),
        Text('No transactions yet',
            style: TextStyle(color: _kMuted,
                fontSize: 15, fontWeight: FontWeight.w600)),
      ]));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: txs.length,
      separatorBuilder: (_, __) =>
          const Divider(color: Colors.white10, height: 1),
      itemBuilder: (_, i) {
        final tx = txs[i];
        final cr = tx.type == 'credit';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: cr
                    ? const Color(0x1A00B0A0)
                    : const Color(0x1AFF6464),
                shape: BoxShape.circle),
              child: Center(
                  child: Text(tx.icon,
                      style: const TextStyle(fontSize: 18)))),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx.label, style: const TextStyle(color: Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w600)),
              Text('${tx.ts.substring(0, 10)} â€¢ ${tx.status}',
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

// â”€â”€ SHARED FIELD WIDGET â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Widget _xf(TextEditingController c, String hint, TextInputType kt,
    void Function(String) fn) =>
    TextField(
      controller: c,
      keyboardType: kt,
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      onChanged: fn,
    );
