import 'package:cached_network_image/cached_network_image.dart';
// lib/screens/xame_pay_screen.dart
import 'dart:async';
// XamePay — go_router-aware wallet for XamePage 2.1  (Build 264+)

import 'dart:convert';
import 'dart:ui' as ui;
import 'package:share_plus/share_plus.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'transaction_details_screen.dart';
import 'dart:io';
import '../core/services/push_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/socket_service.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── COLOURS ───────────────────────────────────────────────────────────────────
const _kTeal  = Color(0xFF00B0A0);
const _kBg    = Color(0xFF0D1520);
const _kCard  = Color(0xFF111E2E);
const _kMuted = Color(0xFF7A9BB5);

// ── MODELS ────────────────────────────────────────────────────────────────────

// Parsed transaction label: splits "Method · Party Info" into
// a method name and (for bank transfers) sender/recipient name + bank.
class _ParsedTxLabel {
  final String method;
  final String? partyName;
  final String? partyInfo;
  const _ParsedTxLabel({required this.method, this.partyName, this.partyInfo});
}

_ParsedTxLabel _parseTxLabel(String label, String type) {
  // Expected formats:
  //  "Card Payment · Visa ****1234"
  //  "Bank Transfer · GIBSON BERNARD AGBOR (Indulge MFB)"
  //  "Bank Transfer" / "Card Payment" (no extra info)
  //  anything else (e.g. "Topped up...", "Call Credits Top-up")
  final parts = label.split(' · ');
  final method = parts.isNotEmpty ? parts.first.trim() : label;
  if (parts.length < 2) {
    return _ParsedTxLabel(method: method.isEmpty ? label : method);
  }
  final rest = parts.sublist(1).join(' · ').trim();

  final isBankTransfer = method.toLowerCase().contains('bank');
  if (isBankTransfer) {
    // "GIBSON BERNARD AGBOR (Indulge MFB)" -> name + bank
    final match = RegExp(r'^(.*?)(?:\s*\((.+)\))?\$').firstMatch(rest);
    final name  = match?.group(1)?.trim();
    final bank  = match?.group(2)?.trim();
    return _ParsedTxLabel(
      method: 'Bank Transfer',
      partyName: (name != null && name.isNotEmpty) ? name : null,
      partyInfo: bank,
    );
  }

  // Card payment — "Visa ****1234"
  return _ParsedTxLabel(method: method, partyInfo: rest);
}

class WalletTx {
  final String id, label, icon, type, status, ts, flwRef;
  final double amount;
  final double? sentAmount, recvAmount, fxRate, principal, fee;
  final int? cashback;
  final String? sentCurrency, recvCurrency, recipient;
  final String txSenderName, txSenderBankName, txSenderAccountNumber, txRecipientName, txBankName, txAccountNumber, txRecipientBankName, txRecipientAccountNumber;
  WalletTx.fromJson(Map<String, dynamic> j)
      : id               = j['_id']?.toString() ?? j['id']?.toString() ?? '${DateTime.now().millisecondsSinceEpoch}',
        flwRef           = j['flwRef']?.toString() ?? '',
        label            = j['label']  ?? '',
        icon             = j['icon']   ?? '💳',
        type             = j['type']   ?? 'debit',
        status           = j['status'] ?? 'Completed',
        ts               = j['ts']     ?? DateTime.now().toIso8601String(),
        amount           = (j['amount']     as num?)?.toDouble() ?? 0,
        sentAmount       = (j['sentAmount'] as num?)?.toDouble(),
        recvAmount       = (j['recvAmount'] as num?)?.toDouble(),
        fxRate           = (j['fxRate']     as num?)?.toDouble(),
        principal        = (j['principal']  as num?)?.toDouble(),
        fee              = (j['fee']        as num?)?.toDouble(),
        cashback         = (j['cashback']   as num?)?.toInt(),
        sentCurrency     = j['sentCurrency']?.toString(),
        txSenderName            = j['senderName']?.toString()              ?? '',
        txSenderBankName        = j['senderBankName']?.toString()          ?? '',
        txSenderAccountNumber   = j['senderAccountNumber']?.toString()     ?? '',
        txRecipientName         = j['recipientName']?.toString()           ?? '',
        txBankName              = j['bankName']?.toString()                ?? '',
        txAccountNumber         = j['accountNumber']?.toString()           ?? '',
        txRecipientBankName     = j['recipientBankName']?.toString()       ?? '',
        txRecipientAccountNumber = j['recipientAccountNumber']?.toString() ?? '',
        recvCurrency = j['recvCurrency']?.toString(),
        recipient    = j['recipient']?.toString();
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
  final VoidCallback? onBack;
  final List<Map<String,String>> xameContacts;
  const XamePayScreen({
    super.key,
    required this.userId,
    required this.serverUrl,
    this.onBack,
    this.xameContacts = const [],
  });
  @override State<XamePayScreen> createState() => _XamePayScreenState();
}

class _XamePayScreenState extends State<XamePayScreen>
    with SingleTickerProviderStateMixin {

  String _currency = 'NGN', _dispCurrency = 'NGN';
  double _balance  = 0;
  Map<String, String>? _myVirtualAccount;
  bool _balanceHidden = true; // hidden by default
  bool   _loading  = true;
  List<WalletTx> _txs = [];
  late TabController _tab;
  StreamSubscription? _walletSub;
  StreamSubscription? _walletDebitSub;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) return;
      final idx = _tab.index;
      // Reset to no tab selected (show none active)
      Future.microtask(() => _openTabFullscreen(idx));
    });
    _loadPrefs().then((_) => _init());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final socket = ProviderScope.containerOf(context).read(socketServiceProvider);
      _walletDebitSub = socket.walletDebit.listen((data) {
        if (!mounted) return;
        _init();
        final amount   = data['amount']   ?? '';
        final currency = data['currency'] ?? 'NGN';
        final to       = data['toName']   ?? data['recipientName'] ?? '';
        ProviderScope.containerOf(context).read(pushServiceProvider)
            .showAlertNotification(
          '💸 Wallet Debited',
          to.isNotEmpty ? '$currency $amount sent to $to' : '$currency $amount debited from your wallet',
        );
      });
      _walletSub = socket.walletReceive.listen((data) {
        if (!mounted) return;
        final senderName = data.senderName ?? data.senderId ?? 'Someone';
        final amount = data.amount.toStringAsFixed(2);
        final currency = data.currency;
        _snack('❤️ Received $currency $amount from $senderName');
        _init();
        ProviderScope.containerOf(context).read(pushServiceProvider)
            .showAlertNotification(
          '💰 Wallet Credited',
          'Received $currency $amount from $senderName',
        );
      });
    });
  }

  @override void dispose() { _walletDebitSub?.cancel(); _walletSub?.cancel(); _tab.dispose(); super.dispose(); }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _dispCurrency  = p.getString('wallet:dispCurrency') ?? _currency;
      _balanceHidden = p.getBool('wallet:balanceHidden') ?? true;
    });
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
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
        if (d['dispCurrency'] != null && (d['dispCurrency'] as String).isNotEmpty) {
          _dispCurrency = d['dispCurrency'];
          await p.setString('wallet:dispCurrency', _dispCurrency);
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
        final newDisp = d['dispCurrency']?.toString() ?? '';
        setState(() {
          _balance = (d['balance'] as num?)?.toDouble() ?? 0;
          if (newDisp.isNotEmpty) _dispCurrency = newDisp;
          _txs = (d['transactions'] as List? ?? [])
              .map((t) => WalletTx.fromJson(t)).toList()
            ..sort((a, b) {
              final da = DateTime.tryParse(a.ts) ?? DateTime(0);
              final db = DateTime.tryParse(b.ts) ?? DateTime(0);
              return db.compareTo(da); // latest first
            });
          _pinEnabled = d['pinEnabled'] as bool? ?? false;
          final va = d['virtualAccount'];
          if (va != null && (va['accountNumber'] ?? '').toString().isNotEmpty) {
            _myVirtualAccount = {
              'accountNumber': va['accountNumber'].toString(),
              'bankName':      va['bankName']?.toString() ?? '',
              'accountName':   (va['accountName'] ?? '').toString().isNotEmpty
                  ? va['accountName'].toString()
                  : 'XamePay',
            };
          }
        });
        if (newDisp.isNotEmpty) {
          final p2 = await SharedPreferences.getInstance();
          await p2.setString('wallet:dispCurrency', newDisp);
        }
      }
    } catch (_) {}
  }

  bool _pinEnabled = false;

  void _goBack() { if (widget.onBack != null) widget.onBack!(); }

  RegionInfo get _ri => _region(_dispCurrency);
  String _fmt(double n) => '${_region(_dispCurrency).symbol}${_fmtN(n)}';

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

  // When dispCurrency differs, main shows converted amount, small line shows original
  double get _displayBalance {
    if (_dispCurrency == _currency) return _balance;
    return _FxService.convert(_balance, _currency, _dispCurrency) ?? _balance;
  }

  String get _displaySymbol =>
      _region(_dispCurrency == _currency ? _currency : _dispCurrency).symbol;

  String get _displayCurrency =>
      _dispCurrency == _currency ? _currency : _dispCurrency;

  String _convLine() {
    if (_dispCurrency == _currency) return '';
    return '≈ ${_region(_currency).symbol}${_fmtN(_balance)} $_currency';
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
            Text(_region(_dispCurrency).flag, style: const TextStyle(fontSize: 18)),
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
                        region: _ri, balance: _displayBalance,
                        serverUrl: widget.serverUrl, userId: widget.userId,
                        fmt: _fmt, onSuccess: _loadWallet, snack: _snack),
                    _DataTab(
                        region: _ri, balance: _displayBalance,
                        serverUrl: widget.serverUrl, userId: widget.userId,
                        fmt: _fmt, onSuccess: _loadWallet, snack: _snack),
                    _BillsTab(
                        region: _ri, balance: _displayBalance,
                        serverUrl: widget.serverUrl, userId: widget.userId,
                        currency: _dispCurrency, fmt: _fmt,
                        onSuccess: _loadWallet, snack: _snack),
                    _SendTab(
                        region: _ri, balance: _displayBalance,
                        serverUrl: widget.serverUrl, userId: widget.userId,
                        currency: _dispCurrency, fmt: _fmt,
                        onSuccess: _loadWallet, snack: _snack,
                        contacts: widget.xameContacts, pinEnabled: _pinEnabled),
                    _MoreTab(txs: _txs, fmt: _fmt, virtualAccount: _myVirtualAccount, userId: widget.userId, serverUrl: widget.serverUrl),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Wallet Balance',
                style: TextStyle(color: Color(0xCCFFFFFF),
                    fontSize: 12, letterSpacing: 1)),
            GestureDetector(
              onTap: () async {
                setState(() => _balanceHidden = !_balanceHidden);
                final p = await SharedPreferences.getInstance();
                await p.setBool('wallet:balanceHidden', _balanceHidden);
              },
              child: Icon(
                _balanceHidden ? Icons.visibility_off : Icons.visibility,
                color: const Color(0xCCFFFFFF), size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(_balanceHidden ? '••••••' : '$_displaySymbol${_fmtN(_displayBalance)}',
            style: const TextStyle(color: Colors.white,
                fontSize: 32, fontWeight: FontWeight.w800)),
        if (conv.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4),
              child: Text(conv, style: const TextStyle(
                  color: Color(0xB3FFFFFF), fontSize: 13))),
        Text('XamePay • $_displayCurrency',
            style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12)),
        const SizedBox(height: 20),
        Row(children: [
          _cBtn('+ Add Money', () => _showAddMoney()),
          const SizedBox(width: 8),
          _cBtn('↗ Send',     () => _tab.animateTo(3)),
          const SizedBox(width: 8),
          _cBtn('⋯ More', () => _tab.animateTo(4)),
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

  void _openTabFullscreen(int idx) {
    final tabs = [
      ('📱 Airtime',  _AirtimeTab(region: _ri, balance: _displayBalance, serverUrl: widget.serverUrl, userId: widget.userId, fmt: _fmt, onSuccess: _loadWallet, snack: _snack)),
      ('📶 Data',     _DataTab(region: _ri, balance: _displayBalance, serverUrl: widget.serverUrl, userId: widget.userId, fmt: _fmt, onSuccess: _loadWallet, snack: _snack)),
      ('🧾 Bills',    _BillsTab(region: _ri, balance: _displayBalance, serverUrl: widget.serverUrl, userId: widget.userId, currency: _dispCurrency, fmt: _fmt, onSuccess: _loadWallet, snack: _snack)),
      ('💸 Send',     _SendTab(region: _ri, balance: _displayBalance, serverUrl: widget.serverUrl, userId: widget.userId, currency: _dispCurrency, fmt: _fmt, onSuccess: _loadWallet, snack: _snack, contacts: widget.xameContacts, pinEnabled: _pinEnabled)),
      ('⋯ More',     _MoreTab(txs: _txs, fmt: _fmt, virtualAccount: _myVirtualAccount, userId: widget.userId, serverUrl: widget.serverUrl)),
    ];
    if (idx >= tabs.length) return;
    final (title, body) = tabs[idx];
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: _kCard,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_fmt(_displayBalance),
                style: const TextStyle(color: _kTeal, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ],
        ),
        body: body,
      ),
    )).then((_) => _loadWallet());
  }

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
        Tab(text: '⋯ More'),
      ],
    ),
  );

  // ── ADD MONEY SHEET ───────────────────────────────────────────────────────

  // ── ADD MONEY SHEET ─────────────────────────────────────────────────────

  void _showAddMoney() {
    final methods = [
      ['💳', 'Debit / Credit Card',  'Instant • Visa, Mastercard, Verve'],
      ['🏦', 'Bank Transfer',        'Instant • Virtual account'],
      ['📟', 'USSD',                 'No internet needed'],
      ['📥', 'Receive from Contact', 'Request from another XamePage user'],
      ['🌍', 'International Card / USD', 'Powered by Squad · Card, Bank, USSD'],
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
            ...methods.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Navigator.pop(context);
                  switch (e.key) {
                    case 0: _showCardPayment(); break;
                    case 1: _showBankTransfer(); break;
                    case 2: _showUSSD(); break;
                    case 3: _showRequestFromContact(); break;
                    case 4: _showSquadPayment(); break;
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1E2D3D),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24)),
                  child: Row(children: [
                    Text(e.value[0], style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 16),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(e.value[1], style: const TextStyle(color: Colors.white,
                          fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(e.value[2], style: const TextStyle(
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

  // ── CARD PAYMENT ─────────────────────────────────────────────────────────
  void _showCardPayment() {
    final amtCtrl = TextEditingController();
    showModalBottomSheet(
      context: context, backgroundColor: _kCard, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Padding(padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text("💳 Card Payment",
                style: TextStyle(color: Colors.white,
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text("Visa, Mastercard, Verve accepted",
                style: TextStyle(color: _kMuted, fontSize: 12)),
            const SizedBox(height: 20),
            TextField(
              controller: amtCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Amount ($_currency)",
                labelStyle: const TextStyle(color: _kMuted),
                filled: true, fillColor: const Color(0xFF1E2D3D),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white24)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white24)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _kTeal,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  final amt = double.tryParse(amtCtrl.text.trim());
                  if (amt == null || amt <= 0) { _snack("Enter a valid amount"); return; }
                  Navigator.pop(ctx);
                  _snack("Initializing payment...");
                  try {
                    final r = await http.post(
                      Uri.parse("${widget.serverUrl}/api/wallet/flw/init-payment"),
                      headers: {"Content-Type": "application/json"},
                      body: jsonEncode({
                        "userId": widget.userId, "amount": amt,
                        "currency": _currency,
                        "email": "${widget.userId}@xamepage.app",
                        "name": "",
                      }),
                    ).timeout(const Duration(seconds: 15));
                    final d = jsonDecode(r.body);
                    if (d["success"] == true) {
                      final url = Uri.parse(d["paymentLink"]);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      } else { _snack("Could not open payment page"); }
                    } else { _snack(d["message"] ?? "Payment initialization failed"); }
                  } catch (_) { _snack("Payment failed — check connection"); }
                },
                child: const Text("Proceed to Payment",
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
              )),
          ]),
        ),
      ),
    );
  }

  // ── SQUAD (INTERNATIONAL CARD / USD) ────────────────────────────────────────
  void _showSquadPayment() {
    final amtCtrl = TextEditingController();
    String squadCurrency = _currency == 'USD' ? 'USD' : 'NGN';
    showModalBottomSheet(
      context: context, backgroundColor: _kCard, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Padding(padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text("🌍 Pay with Squad",
                  style: TextStyle(color: Colors.white,
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text("Card or bank payment — NGN or USD",
                  style: TextStyle(color: _kMuted, fontSize: 12)),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: squadCurrency,
                dropdownColor: const Color(0xFF1E2D3D),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Currency",
                  labelStyle: const TextStyle(color: _kMuted),
                  filled: true, fillColor: const Color(0xFF1E2D3D),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24)),
                ),
                items: const [
                  DropdownMenuItem(value: 'NGN', child: Text('NGN')),
                  DropdownMenuItem(value: 'USD', child: Text('USD')),
                ],
                onChanged: (v) => setSheetState(() => squadCurrency = v ?? 'NGN'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amtCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Amount ($squadCurrency)",
                  labelStyle: const TextStyle(color: _kMuted),
                  filled: true, fillColor: const Color(0xFF1E2D3D),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _kTeal,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    final amt = double.tryParse(amtCtrl.text.trim());
                    if (amt == null || amt <= 0) { _snack("Enter a valid amount"); return; }
                    Navigator.pop(ctx);
                    _snack("Initializing payment...");
                    try {
                      final r = await http.post(
                        Uri.parse("${widget.serverUrl}/api/wallet/squad/init-payment"),
                        headers: {"Content-Type": "application/json"},
                        body: jsonEncode({
                          "userId": widget.userId, "amount": amt,
                          "currency": squadCurrency,
                          "email": "${widget.userId}@xamepage.app",
                          "name": "",
                        }),
                      ).timeout(const Duration(seconds: 15));
                      final d = jsonDecode(r.body);
                      if (d["success"] == true) {
                        final url = Uri.parse(d["paymentLink"]);
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        } else { _snack("Could not open payment page"); }
                      } else { _snack(d["message"] ?? "Payment initialization failed"); }
                    } catch (_) { _snack("Payment failed — check connection"); }
                  },
                  child: const Text("Continue to Squad",
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
                )),
            ]),
          ),
        ),
      ),
    );
  }

  // ── BANK TRANSFER ────────────────────────────────────────────────────────
  void _showBankTransfer() {
    showModalBottomSheet(
      context: context, backgroundColor: _kCard, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _BankTransferSheet(
        userId: widget.userId, serverUrl: widget.serverUrl,
        currency: _currency, onSnack: _snack, pinEnabled: _pinEnabled,
      ),
    );
  }

  // ── USSD ─────────────────────────────────────────────────────────────────
  void _showUSSD() {
    final amtCtrl = TextEditingController();
    showModalBottomSheet(
      context: context, backgroundColor: _kCard, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Padding(padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("📟 USSD Payment",
                style: TextStyle(color: Colors.white,
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text("Works without internet",
                style: TextStyle(color: _kMuted, fontSize: 12)),
            const SizedBox(height: 20),
            TextField(
              controller: amtCtrl, keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Amount ($_currency)",
                labelStyle: const TextStyle(color: _kMuted),
                filled: true, fillColor: const Color(0xFF1E2D3D),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white24)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white24)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _kTeal,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  final amt = double.tryParse(amtCtrl.text.trim());
                  if (amt == null || amt <= 0) { _snack("Enter a valid amount"); return; }
                  Navigator.pop(ctx);
                  _snack("Generating USSD code...");
                  try {
                    final r = await http.post(
                      Uri.parse("${widget.serverUrl}/api/wallet/flw/ussd"),
                      headers: {"Content-Type": "application/json"},
                      body: jsonEncode({"userId": widget.userId, "amount": amt, "currency": _currency}),
                    ).timeout(const Duration(seconds: 15));
                    final d = jsonDecode(r.body);
                    if (d["success"] == true) { _showUSSDCode(d["ussdCode"], amt); }
                    else { _snack(d["message"] ?? "USSD generation failed"); }
                  } catch (_) { _snack("Failed — check connection"); }
                },
                child: const Text("Get USSD Code",
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
              )),
          ]),
        ),
      ),
    );
  }

  void _showUSSDCode(String code, double amount) {
    showModalBottomSheet(
      context: context, backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("📟 Dial this USSD code",
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFF1E2D3D),
                borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Text(code, style: const TextStyle(color: _kTeal,
                  fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 2)),
              const SizedBox(height: 8),
              Text("Amount: $_currency ${amount.toStringAsFixed(2)}",
                  style: const TextStyle(color: _kMuted, fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 16),
          const Text("Dial the code above on your phone to complete payment.",
              textAlign: TextAlign.center,
              style: TextStyle(color: _kMuted, fontSize: 13)),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kTeal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                final url = Uri(scheme: "tel", path: code);
                if (await canLaunchUrl(url)) await launchUrl(url);
              },
              child: const Text("Dial Now",
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
            )),
        ]),
      ),
    );
  }

  // ── REQUEST FROM CONTACT ─────────────────────────────────────────────────
  void _showRequestFromContact() {
    showModalBottomSheet(
      context: context, backgroundColor: _kCard, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _RequestMoneySheet(
        userId: widget.userId, serverUrl: widget.serverUrl,
        currency: _currency, contacts: widget.xameContacts, onSnack: _snack,
      ),
    );
  }

  // ── SETTINGS ──────────────────────────────────────────────────────────────

  void _showSetPinSheet({bool enableAfterSet = false}) {
    final pinCtrl    = TextEditingController();
    final confirmCtrl = TextEditingController();
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: const Color(0xFF13131A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(builder: (ctx, ss) {
          String? error;
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              const Text('Set Transaction PIN', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('PIN is required to authorise all transfers', style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 24),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                style: const TextStyle(color: Colors.white, letterSpacing: 8, fontSize: 20),
                decoration: const InputDecoration(
                  labelText: 'New PIN (4-6 digits)',
                  labelStyle: TextStyle(color: Colors.white54),
                  counterText: '',
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                style: const TextStyle(color: Colors.white, letterSpacing: 8, fontSize: 20),
                decoration: const InputDecoration(
                  labelText: 'Confirm PIN',
                  labelStyle: TextStyle(color: Colors.white54),
                  counterText: '',
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    final pin     = pinCtrl.text.trim();
                    final confirm = confirmCtrl.text.trim();
                    if (pin.length < 4) { _snack('PIN must be at least 4 digits'); return; }
                    if (pin != confirm)  { _snack('PINs do not match'); return; }
                    try {
                      final r = await http.post(
                        Uri.parse('${widget.serverUrl}/api/wallet/pin/set'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({'userId': widget.userId, 'pin': pin}),
                      );
                      final d = jsonDecode(r.body);
                      if (d['success'] == true) {
                        if (enableAfterSet) {
                          await http.post(
                            Uri.parse('${widget.serverUrl}/api/wallet/pin/toggle'),
                            headers: {'Content-Type': 'application/json'},
                            body: jsonEncode({'userId': widget.userId, 'enable': true}),
                          );
                          setState(() => _pinEnabled = true);
                        }
                        Navigator.pop(ctx);
                        _snack('✅ Transaction PIN set successfully');
                      } else { _snack('❌ ${d["message"] ?? "Failed to set PIN"}'); }
                    } catch (_) { _snack('❌ Network error'); }
                  },
                  child: const Text('Set PIN', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }

  void _showSettings() {
    String tc = _dispCurrency, td = _dispCurrency;
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
                onChanged: (v) {
                  if (v != null) {
                    ss(() { tc = v; td = v; });
                    _FxService.load(_currency).then((_) {
                      ss(() {});
                      setState(() { _dispCurrency = v; });
                    });
                  }
                },
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
                onChanged: (v) {
                  if (v != null) {
                    ss(() => td = v);
                    _FxService.load(_currency).then((_) {
                      ss(() {});
                      setState(() { _dispCurrency = v; });
                    });
                  }
                },
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
                  setState(() { _dispCurrency = td; });
                  await _savePrefs();
                  try {
                    await http.post(
                      Uri.parse('${widget.serverUrl}/api/wallet/currency'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(
                          {'userId': widget.userId, 'currency': _currency, 'dispCurrency': _dispCurrency}),
                    );
                  } catch (_) {}
                  await _FxService.load(_currency);
                  if (mounted) { Navigator.pop(ctx); _snack('✅ Settings saved'); }
                },
                child: const Text('Save Settings',
                    style: TextStyle(color: Colors.black,
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(children: [
                  const Icon(Icons.lock_outline_rounded, color: Color(0xFF00E5FF), size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Transaction PIN', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(_pinEnabled ? 'Enabled — required for transfers' : 'Disabled',
                        style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ])),
                  Switch(
                    value: _pinEnabled,
                    activeColor: const Color(0xFF00E5FF),
                    onChanged: (val) async {
                      if (val) {
                        Navigator.pop(ctx);
                        _showSetPinSheet(enableAfterSet: true);
                      } else {
                        // Require current PIN to disable
                        final ctrl = TextEditingController();
                        final pin = await showDialog<String>(context: ctx, builder: (_) => AlertDialog(
                          backgroundColor: const Color(0xFF13131A),
                          title: const Text('Enter Current PIN', style: TextStyle(color: Colors.white)),
                          content: TextField(controller: ctrl, keyboardType: TextInputType.number, obscureText: true, maxLength: 6, style: const TextStyle(color: Colors.white)),
                          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white38))), ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black), child: const Text('Confirm'))],
                        ));
                        if (pin == null) return;
                        final r = await http.post(
                          Uri.parse('${widget.serverUrl}/api/wallet/pin/toggle'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({'userId': widget.userId, 'enable': false, 'pin': pin}),
                        );
                        final d = jsonDecode(r.body);
                        if (d['success'] == true) {
                          setState(() => _pinEnabled = false);
                          ss(() {});
                          _snack('✅ Transaction PIN disabled');
                        } else { _snack('❌ ${d["message"] ?? "Failed"}'); }
                      }
                    },
                  ),
                ]),
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

// ── BANK TRANSFER SHEET ──────────────────────────────────────────────────────
class _BankTransferSheet extends StatefulWidget {
  final String userId, serverUrl, currency;
  final void Function(String) onSnack;
  final bool pinEnabled;
  const _BankTransferSheet({required this.userId, required this.serverUrl,
      required this.currency, required this.onSnack, this.pinEnabled = false});
  @override
  State<_BankTransferSheet> createState() => _BankTransferSheetState();
}


class _BankTransferSheetState extends State<_BankTransferSheet> {
  Map<String, dynamic>? _account;
  bool _loading = false;
  bool _switching = false;
  bool _bvnSubmitted = false;
  String? _error;
  final _bvnCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadExistingAccount();
  }

  Future<void> _loadExistingAccount() async {
    setState(() { _loading = true; });
    try {
      final r = await http.get(
        Uri.parse("${widget.serverUrl}/api/wallet/me?userId=${widget.userId}"),
      ).timeout(const Duration(seconds: 8));
      final d = jsonDecode(r.body);
      if (d["success"] == true) {
        final va = d["virtualAccount"];
        if (va != null &&
            (va["accountNumber"] ?? "").toString().isNotEmpty) {
          setState(() {
            _account = {
              "account_number": va["accountNumber"],
              "bank_name":      va["bankName"],
              "account_name":   "XamePay",
              "provider":       va["provider"] ?? "",
            };
            _bvnSubmitted = true;
          });
        }
      }
    } catch (_) {}
    setState(() { _loading = false; });
  }

  Future<void> _switchProvider(BuildContext context) async {
    final currentProvider = (_account?["provider"] ?? "flutterwave").toString();
    final targetProvider = currentProvider == "monnify" ? "flutterwave" : "monnify";
    final targetLabel = targetProvider == "monnify" ? "Monnify" : "Flutterwave";
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Switch to $targetLabel?',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
            "You'll get a new account number. Your old account number will stop receiving funds — only transfer to your new account from now on.",
            style: TextStyle(color: Colors.white60, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
            child: const Text('Switch', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() { _switching = true; _error = null; });
    try {
      final endpoint = targetProvider == "monnify"
          ? '/api/wallet/monnify/virtual-account'
          : '/api/wallet/flw/virtual-account';
      final r = await http.post(
        Uri.parse('${widget.serverUrl}$endpoint'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": widget.userId,
          "email": "${widget.userId}@xamepage.app",
          "confirmSwitch": true,
        }),
      ).timeout(const Duration(seconds: 15));
      final d = jsonDecode(r.body);
      if (d["success"] == true) {
        setState(() {
          _account = {
            "account_number": d["account"]["account_number"],
            "bank_name":      d["account"]["bank_name"],
            "account_name":   d["account"]["account_name"] ?? "XamePay",
            "provider":       targetProvider,
          };
          _switching = false;
        });
        widget.onSnack('Switched to $targetLabel. New account ready.');
      } else {
        setState(() { _switching = false; _error = d["message"] ?? "Switch failed"; });
      }
    } catch (e) {
      setState(() { _switching = false; _error = "Switch failed: $e"; });
    }
  }

  Future<void> _fetchVirtualAccount(String bvn) async {
    setState(() { _loading = true; _error = null; });
    try {
      // Save BVN to server for future use
      await http.post(
        Uri.parse('${widget.serverUrl}/api/wallet/save-bvn'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"userId": widget.userId, "bvn": bvn}),
      ).timeout(const Duration(seconds: 10));
      final r = await http.post(
        Uri.parse('${widget.serverUrl}/api/wallet/monnify/virtual-account'), // default new users to Monnify
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": widget.userId,
          "email": "${widget.userId}@xamepage.app",
          "name": "",
          "currency": widget.currency,
          "bvn": bvn,
        }),
      ).timeout(const Duration(seconds: 15));
      final d = jsonDecode(r.body);
      if (d["success"] == true) {
        setState(() { _account = d["account"]; _loading = false; _bvnSubmitted = true; });
      } else {
        setState(() { _error = d["message"] ?? "Could not load account"; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = "Connection failed: $e"; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.6,
      builder: (_, sc) => ListView(
        controller: sc, padding: const EdgeInsets.all(24),
        children: [
          const Text("🏦 Bank Transfer",
              style: TextStyle(color: Colors.white,
                  fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text("Transfer to this account to fund your wallet",
              style: TextStyle(color: _kMuted, fontSize: 12)),
          const SizedBox(height: 20),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: _kTeal))
          else if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kTeal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => setState(() { _error = null; _bvnSubmitted = false; }),
              child: const Text("Try Again", style: TextStyle(color: Colors.black))),
          ]
          else if (_bvnSubmitted && _account != null) ...[
            // Bank logo header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10)),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: 'https://nigerianbanks.xyz/logo/' +
                        (_account!["bank_name"] ?? "").toString().toLowerCase()
                            .replaceAll(' ', '-') + '.png',
                    width: 48, height: 48, fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B3A5C),
                        borderRadius: BorderRadius.circular(10)),
                      child: Center(child: Text(
                          ((_account!["bank_name"] ?? "B") as String).isNotEmpty
                              ? (_account!["bank_name"] as String)[0].toUpperCase()
                              : 'B',
                          style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w800, fontSize: 22)))),
                  ),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_account!["bank_name"]?.toString() ?? "Bank",
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const Text('Virtual Account',
                      style: TextStyle(color: _kMuted, fontSize: 11)),
                ]),
              ]),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _switching ? null : () => _switchProvider(context),
                icon: _switching
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
                    : const Icon(Icons.swap_horiz_rounded, size: 16, color: Color(0xFF00E5FF)),
                label: Text(_switching ? 'Switching…' : 'Switch funding provider',
                    style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 16),
            _accountRow("Account Number", _account!["account_number"] ?? ""),
            _accountRow("Account Name", _account!["account_name"] ?? "XamePay"),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _kTeal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kTeal.withOpacity(0.3))),
              child: const Row(children: [
                Icon(Icons.info_outline, color: _kTeal, size: 16),
                SizedBox(width: 8),
                Expanded(child: Text(
                  "Transfer any amount to this account. Your wallet will be credited automatically.",
                  style: TextStyle(color: _kTeal, fontSize: 12))),
              ]),
            ),
          ] else ...[
            const Text("Enter your BVN",
                style: TextStyle(color: _kMuted, fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _bvnCtrl,
              keyboardType: TextInputType.number,
              maxLength: 11,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "11-digit BVN",
                hintStyle: const TextStyle(color: _kMuted),
                filled: true, fillColor: const Color(0xFF1E2D3D),
                counterStyle: const TextStyle(color: _kMuted),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white24)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white24)),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withOpacity(0.3))),
              child: const Row(children: [
                Icon(Icons.lock_outline, color: Colors.orange, size: 14),
                SizedBox(width: 8),
                Expanded(child: Text(
                  "Your BVN is required to generate a virtual account. It is securely stored and used only for account creation.",
                  style: TextStyle(color: Colors.orange, fontSize: 11))),
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _kTeal,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  final bvn = _bvnCtrl.text.trim();
                  if (bvn.length != 11) {
                    widget.onSnack("Enter a valid 11-digit BVN"); return;
                  }
                  _fetchVirtualAccount(bvn);
                },
                child: const Text("Get Virtual Account",
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
              )),
          ],
        ],
      ),
    );
  }

  Widget _accountRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1E2D3D),
          borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: _kMuted, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white,
              fontSize: 15, fontWeight: FontWeight.w700)),
        ])),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: value));
            widget.onSnack("$value copied!");
          },
          child: const Icon(Icons.copy, color: _kTeal, size: 20)),
      ]),
    ),
  );
}

// ── REQUEST MONEY SHEET ───────────────────────────────────────────────────────
class _RequestMoneySheet extends StatefulWidget {
  final String userId, serverUrl, currency;
  final List<Map<String, String>> contacts;
  final void Function(String) onSnack;
  const _RequestMoneySheet({required this.userId, required this.serverUrl,
      required this.currency, required this.contacts, required this.onSnack});
  @override
  State<_RequestMoneySheet> createState() => _RequestMoneySheetState();
}

class _RequestMoneySheetState extends State<_RequestMoneySheet> {
  Map<String, String>? _selectedContact;
  final _amtCtrl  = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.7,
      builder: (_, sc) => ListView(
        controller: sc, padding: const EdgeInsets.all(24),
        children: [
          const Text("📥 Request Money",
              style: TextStyle(color: Colors.white,
                  fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text("Request payment from a XamePage contact",
              style: TextStyle(color: _kMuted, fontSize: 12)),
          const SizedBox(height: 20),
          // Contact picker
          const Text("Select Contact",
              style: TextStyle(color: _kMuted, fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<Map<String, String>>(
            value: _selectedContact,
            dropdownColor: _kCard,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              filled: true, fillColor: const Color(0xFF1E2D3D),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24)),
              hintText: "Choose contact",
              hintStyle: const TextStyle(color: _kMuted),
            ),
            items: widget.contacts.map((c) => DropdownMenuItem(
              value: c,
              child: Text(c["name"] ?? c["id"] ?? "",
                  style: const TextStyle(color: Colors.white)),
            )).toList(),
            onChanged: (v) => setState(() => _selectedContact = v),
          ),
          const SizedBox(height: 16),
          // Amount
          const Text("Amount",
              style: TextStyle(color: _kMuted, fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _amtCtrl, keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "0.00",
              hintStyle: const TextStyle(color: _kMuted),
              prefixText: "${widget.currency} ",
              prefixStyle: const TextStyle(color: _kTeal, fontWeight: FontWeight.w700),
              filled: true, fillColor: const Color(0xFF1E2D3D),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24)),
            ),
          ),
          const SizedBox(height: 16),
          // Note
          const Text("Note (optional)",
              style: TextStyle(color: _kMuted, fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "What is this for?",
              hintStyle: const TextStyle(color: _kMuted),
              filled: true, fillColor: const Color(0xFF1E2D3D),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24)),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kTeal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: _sending ? null : () async {
                if (_selectedContact == null) {
                  widget.onSnack("Select a contact"); return;
                }
                final amt = double.tryParse(_amtCtrl.text.trim());
                if (amt == null || amt <= 0) {
                  widget.onSnack("Enter a valid amount"); return;
                }
                setState(() => _sending = true);
                try {
                  final r = await http.post(
                    Uri.parse("${widget.serverUrl}/api/wallet/request"),
                    headers: {"Content-Type": "application/json"},
                    body: jsonEncode({
                      "fromId":  widget.userId,
                      "toId":    _selectedContact!["id"],
                      "amount":  amt,
                      "currency": widget.currency,
                      "note":    _noteCtrl.text.trim(),
                    }),
                  ).timeout(const Duration(seconds: 15));
                  final d = jsonDecode(r.body);
                  if (mounted) Navigator.pop(context);
                  widget.onSnack(d["success"] == true
                      ? "Request sent to ${_selectedContact!["name"]}"
                      : d["message"] ?? "Request failed");
                } catch (_) {
                  widget.onSnack("Request failed — check connection");
                } finally {
                  if (mounted) setState(() => _sending = false);
                }
              },
              child: _sending
                  ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Text("Send Request",
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
            )),
        ],
      ),
    );
  }
}

class _SendTab extends StatefulWidget {
  final RegionInfo region; final double balance;
  final String serverUrl, userId, currency;
  final String Function(double) fmt;
  final Future<void> Function() onSuccess;
  final void Function(String) snack;
  final List<Map<String,String>> contacts;
  final bool pinEnabled;
  const _SendTab({required this.region, required this.balance,
      required this.serverUrl, required this.userId, required this.currency,
      required this.fmt, required this.onSuccess, required this.snack,
      this.contacts = const [], this.pinEnabled = false});
  @override State<_SendTab> createState() => _SendTabState();
}

class _SendTabState extends State<_SendTab> {
  bool _bankMode = false, _loadingBanks = true, _bankError = false;
  bool _benefMode = false;
  List<BankItem> _banks = [], _filtered = [];
  BankItem? _selBank;
  String _accNum = '', _accName = '', _resolved = '';
  bool _resolving = false;
  double _amount = 0;
  final _accCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();
  final _srchCtrl = TextEditingController();
  // Contact mode
  String? _selContact;
  String  _contactQuery = '';
  final _contactSearchCtrl = TextEditingController();
  // Beneficiaries
  List<Map<String, dynamic>> _beneficiaries = [];
  bool _loadingBenef = false;
  List<Map<String,String>> get _filteredContacts => widget.contacts
    .where((c) => _contactQuery.isEmpty ||
      (c['name'] ?? '').toLowerCase().contains(_contactQuery.toLowerCase()) ||
      (c['id']   ?? '').toLowerCase().contains(_contactQuery.toLowerCase()))
    .toList();

  @override void initState() { super.initState(); _fetchBanks(); _fetchBeneficiaries(); }
  @override void dispose() {
    _accCtrl.dispose(); _amtCtrl.dispose(); _srchCtrl.dispose();
    _contactSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchBeneficiaries() async {
    setState(() => _loadingBenef = true);
    try {
      final r = await http.get(Uri.parse(
          '${widget.serverUrl}/api/wallet/beneficiaries/${widget.userId}'))
          .timeout(const Duration(seconds: 8));
      final d = jsonDecode(r.body);
      if (d['success'] == true && mounted) {
        setState(() => _beneficiaries = List<Map<String, dynamic>>.from(d['beneficiaries'] ?? []));
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingBenef = false);
  }

  Future<void> _saveBeneficiary() async {
    if (_selBank == null || _accNum.isEmpty || _accName.isEmpty) return;
    try {
      await http.post(
        Uri.parse('${widget.serverUrl}/api/wallet/beneficiaries/save'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': widget.userId,
          'accountNumber': _accNum,
          'bankCode': _selBank!.code,
          'bankName': _selBank!.name,
          'accountName': _accName,
        }),
      ).timeout(const Duration(seconds: 8));
      _fetchBeneficiaries();
    } catch (_) {}
  }

  Future<void> _deleteBeneficiary(String accountNumber) async {
    try {
      await http.delete(Uri.parse(
          '${widget.serverUrl}/api/wallet/beneficiaries/${widget.userId}/$accountNumber'))
          .timeout(const Duration(seconds: 8));
      _fetchBeneficiaries();
    } catch (_) {}
  }

  Future<void> _sendToContact() async {
    if (_selContact == null) { widget.snack('Select a contact'); return; }
    if (_amount < 1)         { widget.snack('Enter a valid amount'); return; }
    if (_amount > widget.balance) { widget.snack('Insufficient balance'); return; }
    widget.snack('Processing transfer…');
    try {
      final r = await http.post(
        Uri.parse('${widget.serverUrl}/api/wallet/p2p'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'senderId':    widget.userId,
          'recipientId': _selContact,
          'amount':      _amount,
          'currency':    widget.currency,
        }),
      ).timeout(const Duration(seconds: 15));
      final d = jsonDecode(r.body);
      if (d['success'] == true) {
        await widget.onSuccess();
        widget.snack('✅ ${widget.fmt(_amount)} sent to $_selContact!'
          '${d['fee'] != null ? '  Fee: ${widget.fmt((d['fee'] as num).toDouble())}' : ''}');
        setState(() { _selContact = null; _amtCtrl.clear(); _amount = 0; });
        // Reward: wallet payment sent
        try {
          http.post(
            Uri.parse('${widget.serverUrl}/api/rewards/wallet-send'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': widget.userId}),
          );
        } catch (_) {}
      } else {
        widget.snack('❌ ${d['message'] ?? 'Transfer failed'}');
      }
    } catch (_) { widget.snack('❌ Network error'); }
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

  Future<String?> _promptPin(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF13131A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Enter Transaction PIN',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          style: const TextStyle(color: Colors.white, letterSpacing: 8, fontSize: 20),
          decoration: const InputDecoration(
            hintText: '••••',
            hintStyle: TextStyle(color: Colors.white38),
            counterText: '',
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  // Mirrors the server's tiered flat fee — for display only, server is source of truth
  double _estimateFee(double amount) {
    if (amount <= 5000) return 15;
    if (amount <= 50000) return 40;
    return 75;
  }

  Future<bool> _showTransferConfirmation() async {
    final fee = _estimateFee(_amount);
    final total = _amount + fee;
    final cashbackEstimate = (_amount * 0.0002 / 0.1).floor(); // Basic tier estimate
    return await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: _kCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Confirm Transfer', style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('To $_accName${_selBank != null ? ' (${_selBank!.name})' : ''}',
              style: const TextStyle(color: _kMuted, fontSize: 13)),
          const SizedBox(height: 20),
          _confirmRow('Amount', widget.fmt(_amount)),
          _confirmRow('Service Fee', widget.fmt(fee)),
          if (cashbackEstimate > 0)
            _confirmRow('Estimated Cashback', '+$cashbackEstimate XameCoins', color: _kTeal),
          const Divider(color: Colors.white12, height: 24),
          _confirmRow('Total Debited', widget.fmt(total), bold: true),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Cancel', style: TextStyle(color: Colors.white)))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _kTeal,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Confirm & Send', style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.w700)))),
          ]),
        ]),
      ),
    ) ?? false;
  }

  Widget _confirmRow(String label, String value, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: _kMuted, fontSize: 13)),
      Text(value, style: TextStyle(
          color: color ?? Colors.white, fontSize: bold ? 16 : 14,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
    ]),
  );

  Future<void> _send() async {
    if (_selBank == null)         { widget.snack('Select a bank'); return; }
    if (_accNum.length < 6)       { widget.snack('Enter account number'); return; }
    if (_amount < 1)              { widget.snack('Enter a valid amount'); return; }
    if (_amount > widget.balance) { widget.snack('Insufficient balance'); return; }
    // Show full breakdown — user must confirm before proceeding
    final confirmed = await _showTransferConfirmation();
    if (!confirmed) return;
    // Verify PIN before transfer if enabled
    if (widget.pinEnabled) {
      final pin = await _promptPin(context);
      if (pin == null) return;
      final pinRes = await http.post(
        Uri.parse('${widget.serverUrl}/api/wallet/pin/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': widget.userId, 'pin': pin}),
      );
      final pinData = jsonDecode(pinRes.body);
      if (pinData['success'] != true) {
        widget.snack('❌ ${pinData['message'] ?? 'Invalid PIN'}'); return;
      }
    }
    widget.snack('Processing transfer…');
    try {
      final r = await http.post(
        Uri.parse('${widget.serverUrl}/api/wallet/send-bank'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'account_bank': _selBank!.code,
            'account_number': _accNum, 'amount': _amount,
            'currency': widget.currency, 'narration': 'XamePay Transfer',
            'accName': _accName, 'bankName': _selBank!.name, 'userId': widget.userId}),
      ).timeout(const Duration(seconds: 20));
      final d = jsonDecode(r.body);
      if (d['success'] == true) {
        await widget.onSuccess();
        _saveBeneficiary();
        if (mounted) {
          Navigator.of(context).pop(); // close the send sheet
          {
            final freshRecipientName = d['recipientName']?.toString() ?? _accName;
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => TransactionDetailsScreen(
              amount:         (d['principal'] as num?)?.toDouble() ?? _amount,
              fee:            (d['fee'] as num?)?.toDouble() ?? 0,
              totalDebit:     (d['totalDebit'] as num?)?.toDouble() ?? (_amount + ((d['fee'] as num?)?.toDouble() ?? 0)),
              cashbackCoins:  d['cashbackCoins'] as int?,
              senderName:          d['senderName']?.toString() ?? '',
              senderBankName:      d['senderBankName']?.toString() ?? '',
              senderAccountNumber: d['senderAccountNumber']?.toString() ?? '',
              recipientName:       freshRecipientName,
              bankName:            d['bankName']?.toString() ?? _selBank?.name ?? '',
              accountNumber:       d['accountNumber']?.toString() ?? _accNum,
              txRef:          d['txRef']?.toString() ?? '',
              sessionId:      d['txRef']?.toString() ?? '',
              paymentMethod:  'XamePay Wallet',
              ts:             DateTime.tryParse(d['ts']?.toString() ?? '') ?? DateTime.now(),
              fmt:            widget.fmt,
              description:    'Transfer to $freshRecipientName',
            )));
          }
        }
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
        _tog('To Contact',    !_bankMode && !_benefMode, () => setState(() { _bankMode = false; _benefMode = false; })),
        const SizedBox(width: 8),
        _tog('To Bank',       _bankMode,  () => setState(() { _bankMode = true; _benefMode = false; })),
        const SizedBox(width: 8),
        _tog('Beneficiaries', _benefMode, () => setState(() { _bankMode = false; _benefMode = true; })),
      ]),
      const SizedBox(height: 20),
      if (_benefMode) ...[
        if (_loadingBenef)
          const Center(child: CircularProgressIndicator(color: _kTeal))
        else if (_beneficiaries.isEmpty)
          const Center(child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('No saved beneficiaries yet. Beneficiaries are saved automatically after transfers.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kMuted, fontSize: 13)),
          ))
        else
          ...(_beneficiaries.map((b) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _kTeal.withOpacity(0.15),
                child: Text((b['bankName'] as String? ?? 'B').substring(0,1),
                  style: const TextStyle(color: _kTeal, fontWeight: FontWeight.w700))),
              title: Text(b['accountName'] as String? ?? '',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text('${b['bankName']} · ${b['accountNumber']}',
                style: const TextStyle(color: _kMuted, fontSize: 12)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: _kMuted, size: 18),
                onPressed: () => _deleteBeneficiary(b['accountNumber'] as String)),
              onTap: () {
                final bank = _banks.firstWhere((bk) => bk.code == b['bankCode'],
                    orElse: () => BankItem(b['bankCode'] as String? ?? '', b['bankName'] as String? ?? ''));
                setState(() {
                  _benefMode = false;
                  _bankMode = true;
                  _selBank = bank;
                  _accNum = b['accountNumber'] as String? ?? '';
                  _accCtrl.text = _accNum;
                  _accName = b['accountName'] as String? ?? '';
                  _resolved = '✅ ${b['accountName']}';
                });
              },
            ),
          ))).toList(),
      ] else if (!_bankMode) ...[
        // Contact search
        _xf(_contactSearchCtrl, '🔍 Search XamePage contacts…',
            TextInputType.text, (v) => setState(() => _contactQuery = v)),
        const SizedBox(height: 8),
        if (_selContact != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x1A00B0A0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x3300B0A0))),
            child: Row(children: [
              CircleAvatar(radius: 18,
                backgroundColor: _kTeal.withOpacity(0.2),
                child: Text(_selContact!.substring(0,1).toUpperCase(),
                  style: const TextStyle(color: _kTeal,
                      fontWeight: FontWeight.w700))),
              const SizedBox(width: 10),
              Expanded(child: Text(_selContact!,
                style: const TextStyle(color: Colors.white,
                    fontSize: 14, fontWeight: FontWeight.w600))),
              GestureDetector(
                onTap: () => setState(() => _selContact = null),
                child: const Icon(Icons.close, color: _kMuted, size: 18)),
            ]),
          ),
        ] else ...[
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10)),
            child: widget.contacts.isEmpty
              ? const Padding(padding: EdgeInsets.all(20),
                  child: Center(child: Text('No XamePage contacts found',
                    style: TextStyle(color: _kMuted, fontSize: 13))))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filteredContacts.length,
                  itemBuilder: (_, i) {
                    final c = _filteredContacts[i];
                    return InkWell(
                      onTap: () => setState(() {
                        _selContact = c['id'];
                        _contactSearchCtrl.clear();
                        _contactQuery = '';
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(border: Border(bottom:
                          BorderSide(color: Colors.white.withOpacity(0.05)))),
                        child: Row(children: [
                          CircleAvatar(radius: 16,
                            backgroundColor: _kTeal.withOpacity(0.15),
                            child: Text((c['name'] as String).substring(0,1).toUpperCase(),
                              style: const TextStyle(color: _kTeal,
                                  fontSize: 12, fontWeight: FontWeight.w700))),
                          const SizedBox(width: 10),
                          Column(crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                            Text(c['name'] as String,
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 14, fontWeight: FontWeight.w500)),
                            Text(c['id'] as String,
                              style: const TextStyle(
                                  color: _kMuted, fontSize: 11)),
                          ]),
                        ]),
                      ),
                    );
                  }),
          ),
        ],
        const SizedBox(height: 16),
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
            onPressed: _sendToContact,
            child: const Text('Send Money',
                style: TextStyle(color: Colors.black,
                    fontSize: 16, fontWeight: FontWeight.w700)),
          ),
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
        const SizedBox(height: 16),
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
        const SizedBox(height: 16),
        SizedBox(width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kTeal,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
            onPressed: _send,
            child: const Text('Send Money',
                style: TextStyle(color: Colors.black,
                    fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
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
        await widget.onSuccess(); widget.snack('✅ Airtime sent! XameCoins cashback credited 🎉');
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

// Data plan model
class DataPlan {
  final String size, operatorId;
  final int days;
  final double price;
  final String itemCode;
  final String billerType;
  final String billerCode;
  const DataPlan(this.operatorId, this.size, this.days, this.price, [this.itemCode = '', this.billerType = '', this.billerCode = '']);
}

// Full data plan catalogue — mirrors wallet.js GD.dataPlans
// Keyed by operatorId. Buy endpoint: /api/vtu/data
const _kDataPlans = <String, List<DataPlan>>{
  // ── Nigeria ──────────────────────────────────────────────────────────────
  'MTN-NG': [
    DataPlan('MTN-NG','500MB',30,300), DataPlan('MTN-NG','1GB',30,500),
    DataPlan('MTN-NG','2GB',30,1000),  DataPlan('MTN-NG','5GB',30,2000),
    DataPlan('MTN-NG','10GB',30,3500),
  ],
  'AIRTEL-NG': [
    DataPlan('AIRTEL-NG','500MB',30,300), DataPlan('AIRTEL-NG','1GB',30,500),
    DataPlan('AIRTEL-NG','2GB',30,1000),  DataPlan('AIRTEL-NG','5GB',30,2000),
  ],
  'GLO-NG': [
    DataPlan('GLO-NG','1GB',30,500), DataPlan('GLO-NG','2GB',30,1000),
    DataPlan('GLO-NG','5GB',30,2000),
  ],
  '9MOBILE-NG': [
    DataPlan('9MOBILE-NG','1GB',30,500), DataPlan('9MOBILE-NG','2GB',30,1000),
    DataPlan('9MOBILE-NG','5GB',30,2500),
  ],
  // ── Ghana ────────────────────────────────────────────────────────────────
  'MTN-GH': [
    DataPlan('MTN-GH','1GB',30,10), DataPlan('MTN-GH','2GB',30,18),
    DataPlan('MTN-GH','5GB',30,40),
  ],
  'VODAFONE-GH': [
    DataPlan('VODAFONE-GH','1GB',30,10), DataPlan('VODAFONE-GH','2GB',30,18),
    DataPlan('VODAFONE-GH','5GB',30,38),
  ],
  'AIRTELTIGO-GH': [
    DataPlan('AIRTELTIGO-GH','1GB',30,9), DataPlan('AIRTELTIGO-GH','2GB',30,16),
    DataPlan('AIRTELTIGO-GH','5GB',30,36),
  ],
  // ── Kenya ────────────────────────────────────────────────────────────────
  'SAFARICOM-KE': [
    DataPlan('SAFARICOM-KE','1GB',30,99), DataPlan('SAFARICOM-KE','2GB',30,149),
    DataPlan('SAFARICOM-KE','5GB',30,349),
  ],
  'AIRTEL-KE': [
    DataPlan('AIRTEL-KE','1GB',30,89), DataPlan('AIRTEL-KE','2GB',30,139),
    DataPlan('AIRTEL-KE','5GB',30,299),
  ],
  'TELKOM-KE': [
    DataPlan('TELKOM-KE','1GB',30,85), DataPlan('TELKOM-KE','2GB',30,130),
    DataPlan('TELKOM-KE','5GB',30,280),
  ],
  // ── South Africa ─────────────────────────────────────────────────────────
  'VODACOM-ZA': [
    DataPlan('VODACOM-ZA','1GB',30,99), DataPlan('VODACOM-ZA','2GB',30,169),
    DataPlan('VODACOM-ZA','5GB',30,349),
  ],
  'MTN-ZA': [
    DataPlan('MTN-ZA','1GB',30,89), DataPlan('MTN-ZA','2GB',30,149),
    DataPlan('MTN-ZA','5GB',30,299),
  ],
  'CELL-ZA': [
    DataPlan('CELL-ZA','1GB',30,79), DataPlan('CELL-ZA','2GB',30,139),
    DataPlan('CELL-ZA','5GB',30,269),
  ],
  'TELKOM-ZA': [
    DataPlan('TELKOM-ZA','1GB',30,69), DataPlan('TELKOM-ZA','2GB',30,129),
    DataPlan('TELKOM-ZA','5GB',30,249),
  ],
  // ── United States ────────────────────────────────────────────────────────
  'ATT-US': [
    DataPlan('ATT-US','5GB',30,35), DataPlan('ATT-US','15GB',30,50),
    DataPlan('ATT-US','Unlimited',30,65),
  ],
  'TMOBILE-US': [
    DataPlan('TMOBILE-US','5GB',30,30), DataPlan('TMOBILE-US','15GB',30,45),
    DataPlan('TMOBILE-US','Unlimited',30,60),
  ],
  'VERIZON-US': [
    DataPlan('VERIZON-US','5GB',30,40), DataPlan('VERIZON-US','15GB',30,55),
    DataPlan('VERIZON-US','Unlimited',30,70),
  ],
  'CRICKET-US': [
    DataPlan('CRICKET-US','5GB',30,25), DataPlan('CRICKET-US','10GB',30,35),
    DataPlan('CRICKET-US','Unlimited',30,55),
  ],
  // ── United Kingdom ───────────────────────────────────────────────────────
  'EE-UK': [
    DataPlan('EE-UK','5GB',30,10), DataPlan('EE-UK','20GB',30,18),
    DataPlan('EE-UK','Unlimited',30,28),
  ],
  'O2-UK': [
    DataPlan('O2-UK','5GB',30,9), DataPlan('O2-UK','20GB',30,16),
    DataPlan('O2-UK','Unlimited',30,25),
  ],
  'VODAFONE-UK': [
    DataPlan('VODAFONE-UK','5GB',30,10), DataPlan('VODAFONE-UK','20GB',30,17),
    DataPlan('VODAFONE-UK','Unlimited',30,27),
  ],
  'THREE-UK': [
    DataPlan('THREE-UK','5GB',30,8), DataPlan('THREE-UK','20GB',30,15),
    DataPlan('THREE-UK','Unlimited',30,22),
  ],
  // ── Europe ───────────────────────────────────────────────────────────────
  'VODAFONE-EU': [
    DataPlan('VODAFONE-EU','5GB',30,15), DataPlan('VODAFONE-EU','20GB',30,25),
    DataPlan('VODAFONE-EU','Unlimited',30,40),
  ],
  'ORANGE-EU': [
    DataPlan('ORANGE-EU','5GB',30,12), DataPlan('ORANGE-EU','20GB',30,22),
    DataPlan('ORANGE-EU','Unlimited',30,38),
  ],
  'TMOBILE-EU': [
    DataPlan('TMOBILE-EU','5GB',30,10), DataPlan('TMOBILE-EU','20GB',30,20),
    DataPlan('TMOBILE-EU','Unlimited',30,35),
  ],
  'O2-EU': [
    DataPlan('O2-EU','5GB',30,13), DataPlan('O2-EU','20GB',30,23),
    DataPlan('O2-EU','Unlimited',30,37),
  ],
  // ── India ────────────────────────────────────────────────────────────────
  'JIO-IN': [
    DataPlan('JIO-IN','1GB/day',28,239), DataPlan('JIO-IN','2GB/day',28,479),
    DataPlan('JIO-IN','Unlimited',84,719),
  ],
  'AIRTEL-IN': [
    DataPlan('AIRTEL-IN','1GB/day',28,265), DataPlan('AIRTEL-IN','2GB/day',28,499),
    DataPlan('AIRTEL-IN','Unlimited',84,839),
  ],
  'VI-IN': [
    DataPlan('VI-IN','1GB/day',28,249), DataPlan('VI-IN','2GB/day',28,479),
  ],
  'BSNL-IN': [
    DataPlan('BSNL-IN','1GB/day',30,187), DataPlan('BSNL-IN','Unlimited',90,599),
  ],
  // ── UAE ──────────────────────────────────────────────────────────────────
  'ETISALAT-AE': [
    DataPlan('ETISALAT-AE','5GB',30,65), DataPlan('ETISALAT-AE','15GB',30,110),
    DataPlan('ETISALAT-AE','Unlimited',30,180),
  ],
  'DU-AE': [
    DataPlan('DU-AE','5GB',30,55), DataPlan('DU-AE','15GB',30,95),
    DataPlan('DU-AE','Unlimited',30,160),
  ],
  // ── Canada ───────────────────────────────────────────────────────────────
  'ROGERS-CA': [
    DataPlan('ROGERS-CA','5GB',30,35), DataPlan('ROGERS-CA','20GB',30,55),
    DataPlan('ROGERS-CA','Unlimited',30,75),
  ],
  'BELL-CA': [
    DataPlan('BELL-CA','5GB',30,35), DataPlan('BELL-CA','20GB',30,55),
    DataPlan('BELL-CA','Unlimited',30,75),
  ],
  'TELUS-CA': [
    DataPlan('TELUS-CA','5GB',30,33), DataPlan('TELUS-CA','20GB',30,52),
    DataPlan('TELUS-CA','Unlimited',30,70),
  ],
  'FREEDOM-CA': [
    DataPlan('FREEDOM-CA','5GB',30,25), DataPlan('FREEDOM-CA','20GB',30,40),
    DataPlan('FREEDOM-CA','Unlimited',30,55),
  ],
  // ── Australia ────────────────────────────────────────────────────────────
  'TELSTRA-AU': [
    DataPlan('TELSTRA-AU','10GB',30,30), DataPlan('TELSTRA-AU','30GB',30,50),
    DataPlan('TELSTRA-AU','Unlimited',30,65),
  ],
  'OPTUS-AU': [
    DataPlan('OPTUS-AU','10GB',30,25), DataPlan('OPTUS-AU','30GB',30,45),
    DataPlan('OPTUS-AU','Unlimited',30,60),
  ],
  'VODAFONE-AU': [
    DataPlan('VODAFONE-AU','10GB',30,22), DataPlan('VODAFONE-AU','30GB',30,40),
    DataPlan('VODAFONE-AU','Unlimited',30,55),
  ],
  'TPG-AU': [
    DataPlan('TPG-AU','10GB',30,20), DataPlan('TPG-AU','30GB',30,35),
    DataPlan('TPG-AU','Unlimited',30,50),
  ],
  // ── Japan ────────────────────────────────────────────────────────────────
  'DOCOMO-JP': [
    DataPlan('DOCOMO-JP','3GB',30,1078), DataPlan('DOCOMO-JP','15GB',30,2970),
    DataPlan('DOCOMO-JP','Unlimited',30,4928),
  ],
  'SOFTBANK-JP': [
    DataPlan('SOFTBANK-JP','3GB',30,990), DataPlan('SOFTBANK-JP','15GB',30,2970),
    DataPlan('SOFTBANK-JP','Unlimited',30,4928),
  ],
  'AU-JP': [
    DataPlan('AU-JP','3GB',30,990), DataPlan('AU-JP','15GB',30,2970),
    DataPlan('AU-JP','Unlimited',30,4928),
  ],
  'RAKUTEN-JP': [
    DataPlan('RAKUTEN-JP','3GB',30,1078), DataPlan('RAKUTEN-JP','Unlimited',30,3278),
  ],
  // ── Singapore ────────────────────────────────────────────────────────────
  'SINGTEL-SG': [
    DataPlan('SINGTEL-SG','10GB',30,20), DataPlan('SINGTEL-SG','50GB',30,35),
    DataPlan('SINGTEL-SG','Unlimited',30,50),
  ],
  'STARHUB-SG': [
    DataPlan('STARHUB-SG','10GB',30,18), DataPlan('STARHUB-SG','50GB',30,32),
    DataPlan('STARHUB-SG','Unlimited',30,48),
  ],
  'M1-SG': [
    DataPlan('M1-SG','10GB',30,18), DataPlan('M1-SG','50GB',30,30),
    DataPlan('M1-SG','Unlimited',30,45),
  ],
  'TPG-SG': [
    DataPlan('TPG-SG','10GB',30,15), DataPlan('TPG-SG','50GB',30,25),
    DataPlan('TPG-SG','Unlimited',30,38),
  ],
  // ── Egypt ────────────────────────────────────────────────────────────────
  'ORANGE-EG': [
    DataPlan('ORANGE-EG','1GB',30,25), DataPlan('ORANGE-EG','3GB',30,60),
    DataPlan('ORANGE-EG','10GB',30,150),
  ],
  'VODAFONE-EG': [
    DataPlan('VODAFONE-EG','1GB',30,23), DataPlan('VODAFONE-EG','3GB',30,55),
    DataPlan('VODAFONE-EG','10GB',30,140),
  ],
  'ETISALAT-EG': [
    DataPlan('ETISALAT-EG','1GB',30,22), DataPlan('ETISALAT-EG','3GB',30,52),
    DataPlan('ETISALAT-EG','10GB',30,135),
  ],
  'WE-EG': [
    DataPlan('WE-EG','1GB',30,20), DataPlan('WE-EG','3GB',30,50),
    DataPlan('WE-EG','10GB',30,130),
  ],
  // ── Saudi Arabia ─────────────────────────────────────────────────────────
  'STC-SA': [
    DataPlan('STC-SA','10GB',30,75), DataPlan('STC-SA','30GB',30,130),
    DataPlan('STC-SA','Unlimited',30,200),
  ],
  'MOBILY-SA': [
    DataPlan('MOBILY-SA','10GB',30,70), DataPlan('MOBILY-SA','30GB',30,120),
    DataPlan('MOBILY-SA','Unlimited',30,185),
  ],
  'ZAIN-SA': [
    DataPlan('ZAIN-SA','10GB',30,68), DataPlan('ZAIN-SA','30GB',30,115),
    DataPlan('ZAIN-SA','Unlimited',30,175),
  ],
  // ── Turkey ───────────────────────────────────────────────────────────────
  'TURKCELL-TR': [
    DataPlan('TURKCELL-TR','10GB',30,150), DataPlan('TURKCELL-TR','30GB',30,250),
    DataPlan('TURKCELL-TR','Unlimited',30,400),
  ],
  'VODAFONE-TR': [
    DataPlan('VODAFONE-TR','10GB',30,140), DataPlan('VODAFONE-TR','30GB',30,235),
    DataPlan('VODAFONE-TR','Unlimited',30,380),
  ],
  'TURKTELEKOM-TR': [
    DataPlan('TURKTELEKOM-TR','10GB',30,135), DataPlan('TURKTELEKOM-TR','30GB',30,225),
    DataPlan('TURKTELEKOM-TR','Unlimited',30,360),
  ],
  // ── Mexico ───────────────────────────────────────────────────────────────
  'TELCEL-MX': [
    DataPlan('TELCEL-MX','3GB',30,199), DataPlan('TELCEL-MX','10GB',30,349),
    DataPlan('TELCEL-MX','Unlimited',30,499),
  ],
  'MOVISTAR-MX': [
    DataPlan('MOVISTAR-MX','3GB',30,179), DataPlan('MOVISTAR-MX','10GB',30,299),
    DataPlan('MOVISTAR-MX','Unlimited',30,449),
  ],
  'ATT-MX': [
    DataPlan('ATT-MX','3GB',30,189), DataPlan('ATT-MX','10GB',30,329),
    DataPlan('ATT-MX','Unlimited',30,479),
  ],
  // ── Indonesia ────────────────────────────────────────────────────────────
  'TELKOMSEL-ID': [
    DataPlan('TELKOMSEL-ID','7GB',30,65000), DataPlan('TELKOMSEL-ID','20GB',30,130000),
    DataPlan('TELKOMSEL-ID','Unlimited',30,199000),
  ],
  'INDOSAT-ID': [
    DataPlan('INDOSAT-ID','7GB',30,55000), DataPlan('INDOSAT-ID','20GB',30,110000),
    DataPlan('INDOSAT-ID','Unlimited',30,179000),
  ],
  'XL-ID': [
    DataPlan('XL-ID','7GB',30,50000), DataPlan('XL-ID','20GB',30,100000),
    DataPlan('XL-ID','Unlimited',30,159000),
  ],
  // ── Philippines ──────────────────────────────────────────────────────────
  'GLOBE-PH': [
    DataPlan('GLOBE-PH','8GB',30,299), DataPlan('GLOBE-PH','25GB',30,499),
    DataPlan('GLOBE-PH','Unlimited',30,799),
  ],
  'SMART-PH': [
    DataPlan('SMART-PH','8GB',30,279), DataPlan('SMART-PH','25GB',30,479),
    DataPlan('SMART-PH','Unlimited',30,749),
  ],
  'DITO-PH': [
    DataPlan('DITO-PH','8GB',30,199), DataPlan('DITO-PH','25GB',30,349),
    DataPlan('DITO-PH','Unlimited',30,599),
  ],
  // ── Malaysia ─────────────────────────────────────────────────────────────
  'MAXIS-MY': [
    DataPlan('MAXIS-MY','10GB',30,38), DataPlan('MAXIS-MY','30GB',30,68),
    DataPlan('MAXIS-MY','Unlimited',30,98),
  ],
  'CELCOM-MY': [
    DataPlan('CELCOM-MY','10GB',30,35), DataPlan('CELCOM-MY','30GB',30,65),
    DataPlan('CELCOM-MY','Unlimited',30,95),
  ],
  'DIGI-MY': [
    DataPlan('DIGI-MY','10GB',30,33), DataPlan('DIGI-MY','30GB',30,60),
    DataPlan('DIGI-MY','Unlimited',30,88),
  ],
  'UMOBILE-MY': [
    DataPlan('UMOBILE-MY','10GB',30,28), DataPlan('UMOBILE-MY','30GB',30,55),
    DataPlan('UMOBILE-MY','Unlimited',30,80),
  ],
  // ── Brazil ───────────────────────────────────────────────────────────────
  'VIVO-BR': [
    DataPlan('VIVO-BR','5GB',30,35), DataPlan('VIVO-BR','15GB',30,55),
    DataPlan('VIVO-BR','Unlimited',30,80),
  ],
  'CLARO-BR': [
    DataPlan('CLARO-BR','5GB',30,32), DataPlan('CLARO-BR','15GB',30,50),
    DataPlan('CLARO-BR','Unlimited',30,75),
  ],
  'TIM-BR': [
    DataPlan('TIM-BR','5GB',30,30), DataPlan('TIM-BR','15GB',30,48),
    DataPlan('TIM-BR','Unlimited',30,70),
  ],
  // ── Zambia ───────────────────────────────────────────────────────────────
  'MTN-ZM': [
    DataPlan('MTN-ZM','1GB',30,25), DataPlan('MTN-ZM','3GB',30,60),
    DataPlan('MTN-ZM','5GB',30,95),
  ],
  'AIRTEL-ZM': [
    DataPlan('AIRTEL-ZM','1GB',30,22), DataPlan('AIRTEL-ZM','3GB',30,55),
    DataPlan('AIRTEL-ZM','5GB',30,90),
  ],
  'ZAMTEL-ZM': [
    DataPlan('ZAMTEL-ZM','1GB',30,20), DataPlan('ZAMTEL-ZM','3GB',30,50),
    DataPlan('ZAMTEL-ZM','5GB',30,85),
  ],
  // ── Uganda ───────────────────────────────────────────────────────────────
  'MTN-UG': [
    DataPlan('MTN-UG','1GB',30,7000), DataPlan('MTN-UG','3GB',30,18000),
    DataPlan('MTN-UG','5GB',30,28000),
  ],
  'AIRTEL-UG': [
    DataPlan('AIRTEL-UG','1GB',30,6500), DataPlan('AIRTEL-UG','3GB',30,16000),
    DataPlan('AIRTEL-UG','5GB',30,25000),
  ],
  'AFRICELL-UG': [
    DataPlan('AFRICELL-UG','1GB',30,6000), DataPlan('AFRICELL-UG','3GB',30,15000),
    DataPlan('AFRICELL-UG','5GB',30,23000),
  ],
  // ── Tanzania ─────────────────────────────────────────────────────────────
  'VODACOM-TZ': [
    DataPlan('VODACOM-TZ','1GB',30,3000), DataPlan('VODACOM-TZ','3GB',30,7500),
    DataPlan('VODACOM-TZ','5GB',30,12000),
  ],
  'AIRTEL-TZ': [
    DataPlan('AIRTEL-TZ','1GB',30,2800), DataPlan('AIRTEL-TZ','3GB',30,7000),
    DataPlan('AIRTEL-TZ','5GB',30,11000),
  ],
  'TIGO-TZ': [
    DataPlan('TIGO-TZ','1GB',30,2500), DataPlan('TIGO-TZ','3GB',30,6500),
    DataPlan('TIGO-TZ','5GB',30,10000),
  ],
  // ── Rwanda ───────────────────────────────────────────────────────────────
  'MTN-RW': [
    DataPlan('MTN-RW','1GB',30,1200), DataPlan('MTN-RW','3GB',30,3000),
    DataPlan('MTN-RW','5GB',30,4500),
  ],
  'AIRTEL-RW': [
    DataPlan('AIRTEL-RW','1GB',30,1100), DataPlan('AIRTEL-RW','3GB',30,2800),
    DataPlan('AIRTEL-RW','5GB',30,4200),
  ],
  // ── West Africa CFA ──────────────────────────────────────────────────────
  'ORANGE-WA': [
    DataPlan('ORANGE-WA','1GB',30,1500), DataPlan('ORANGE-WA','3GB',30,3500),
    DataPlan('ORANGE-WA','5GB',30,6000),
  ],
  'MTN-WA': [
    DataPlan('MTN-WA','1GB',30,1400), DataPlan('MTN-WA','3GB',30,3200),
    DataPlan('MTN-WA','5GB',30,5500),
  ],
  'MOOV-WA': [
    DataPlan('MOOV-WA','1GB',30,1200), DataPlan('MOOV-WA','3GB',30,3000),
    DataPlan('MOOV-WA','5GB',30,5000),
  ],
  // ── Cameroon ─────────────────────────────────────────────────────────────
  'MTN-CM': [
    DataPlan('MTN-CM','1GB',30,1500), DataPlan('MTN-CM','3GB',30,3500),
    DataPlan('MTN-CM','5GB',30,6000),
  ],
  'ORANGE-CM': [
    DataPlan('ORANGE-CM','1GB',30,1400), DataPlan('ORANGE-CM','3GB',30,3200),
    DataPlan('ORANGE-CM','5GB',30,5500),
  ],
  // ── Qatar ────────────────────────────────────────────────────────────────
  'OOREDOO-QA': [
    DataPlan('OOREDOO-QA','10GB',30,60), DataPlan('OOREDOO-QA','30GB',30,110),
    DataPlan('OOREDOO-QA','Unlimited',30,170),
  ],
  'VODAFONE-QA': [
    DataPlan('VODAFONE-QA','10GB',30,55), DataPlan('VODAFONE-QA','30GB',30,100),
    DataPlan('VODAFONE-QA','Unlimited',30,160),
  ],
  // ── Vietnam ──────────────────────────────────────────────────────────────
  'VIETTEL-VN': [
    DataPlan('VIETTEL-VN','5GB',30,70000), DataPlan('VIETTEL-VN','15GB',30,150000),
    DataPlan('VIETTEL-VN','Unlimited',30,220000),
  ],
  'VINAPHONE-VN': [
    DataPlan('VINAPHONE-VN','5GB',30,65000), DataPlan('VINAPHONE-VN','15GB',30,140000),
    DataPlan('VINAPHONE-VN','Unlimited',30,210000),
  ],
  'MOBIFONE-VN': [
    DataPlan('MOBIFONE-VN','5GB',30,65000), DataPlan('MOBIFONE-VN','15GB',30,140000),
    DataPlan('MOBIFONE-VN','Unlimited',30,200000),
  ],
  // ── Thailand ─────────────────────────────────────────────────────────────
  'AIS-TH': [
    DataPlan('AIS-TH','10GB',30,299), DataPlan('AIS-TH','30GB',30,499),
    DataPlan('AIS-TH','Unlimited',30,699),
  ],
  'DTAC-TH': [
    DataPlan('DTAC-TH','10GB',30,279), DataPlan('DTAC-TH','30GB',30,479),
    DataPlan('DTAC-TH','Unlimited',30,659),
  ],
  'TRUE-TH': [
    DataPlan('TRUE-TH','10GB',30,269), DataPlan('TRUE-TH','30GB',30,459),
    DataPlan('TRUE-TH','Unlimited',30,629),
  ],
  // ── Pakistan ─────────────────────────────────────────────────────────────
  'JAZZ-PK': [
    DataPlan('JAZZ-PK','2GB',30,200), DataPlan('JAZZ-PK','6GB',30,450),
    DataPlan('JAZZ-PK','12GB',30,800),
  ],
  'TELENOR-PK': [
    DataPlan('TELENOR-PK','2GB',30,190), DataPlan('TELENOR-PK','6GB',30,430),
    DataPlan('TELENOR-PK','12GB',30,780),
  ],
  'ZONG-PK': [
    DataPlan('ZONG-PK','2GB',30,185), DataPlan('ZONG-PK','6GB',30,420),
    DataPlan('ZONG-PK','12GB',30,760),
  ],
  'UFONE-PK': [
    DataPlan('UFONE-PK','2GB',30,180), DataPlan('UFONE-PK','6GB',30,400),
    DataPlan('UFONE-PK','12GB',30,740),
  ],
  // ── Morocco ──────────────────────────────────────────────────────────────
  'MAROCTELECOM-MA': [
    DataPlan('MAROCTELECOM-MA','1GB',30,20), DataPlan('MAROCTELECOM-MA','5GB',30,70),
    DataPlan('MAROCTELECOM-MA','10GB',30,120),
  ],
  'ORANGE-MA': [
    DataPlan('ORANGE-MA','1GB',30,18), DataPlan('ORANGE-MA','5GB',30,65),
    DataPlan('ORANGE-MA','10GB',30,110),
  ],
  'INWI-MA': [
    DataPlan('INWI-MA','1GB',30,15), DataPlan('INWI-MA','5GB',30,60),
    DataPlan('INWI-MA','10GB',30,100),
  ],
  // ── Ethiopia ─────────────────────────────────────────────────────────────
  'ETHIOTELECOM-ET': [
    DataPlan('ETHIOTELECOM-ET','1GB',30,50), DataPlan('ETHIOTELECOM-ET','3GB',30,130),
    DataPlan('ETHIOTELECOM-ET','5GB',30,200),
  ],
  'SAFARICOM-ET': [
    DataPlan('SAFARICOM-ET','1GB',30,45), DataPlan('SAFARICOM-ET','3GB',30,120),
    DataPlan('SAFARICOM-ET','5GB',30,190),
  ],
  // ── Zimbabwe ─────────────────────────────────────────────────────────────
  'ECONET-ZW': [
    DataPlan('ECONET-ZW','1GB',30,5), DataPlan('ECONET-ZW','3GB',30,12),
    DataPlan('ECONET-ZW','5GB',30,18),
  ],
  'NETONE-ZW': [
    DataPlan('NETONE-ZW','1GB',30,4), DataPlan('NETONE-ZW','3GB',30,10),
    DataPlan('NETONE-ZW','5GB',30,16),
  ],
  'TELECEL-ZW': [
    DataPlan('TELECEL-ZW','1GB',30,4), DataPlan('TELECEL-ZW','3GB',30,10),
    DataPlan('TELECEL-ZW','5GB',30,15),
  ],
  // ── Colombia ─────────────────────────────────────────────────────────────
  'CLARO-CO': [
    DataPlan('CLARO-CO','3GB',30,25000), DataPlan('CLARO-CO','10GB',30,50000),
    DataPlan('CLARO-CO','Unlimited',30,80000),
  ],
  'MOVISTAR-CO': [
    DataPlan('MOVISTAR-CO','3GB',30,22000), DataPlan('MOVISTAR-CO','10GB',30,45000),
    DataPlan('MOVISTAR-CO','Unlimited',30,75000),
  ],
  'TIGO-CO': [
    DataPlan('TIGO-CO','3GB',30,20000), DataPlan('TIGO-CO','10GB',30,42000),
    DataPlan('TIGO-CO','Unlimited',30,70000),
  ],
  // ── Argentina ────────────────────────────────────────────────────────────
  'CLARO-AR': [
    DataPlan('CLARO-AR','5GB',30,2500), DataPlan('CLARO-AR','15GB',30,4500),
    DataPlan('CLARO-AR','Unlimited',30,7000),
  ],
  'PERSONAL-AR': [
    DataPlan('PERSONAL-AR','5GB',30,2400), DataPlan('PERSONAL-AR','15GB',30,4300),
    DataPlan('PERSONAL-AR','Unlimited',30,6800),
  ],
  'MOVISTAR-AR': [
    DataPlan('MOVISTAR-AR','5GB',30,2300), DataPlan('MOVISTAR-AR','15GB',30,4100),
    DataPlan('MOVISTAR-AR','Unlimited',30,6500),
  ],
};

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
  DataPlan? _plan;
  String _phone = '';
  final _pCtrl = TextEditingController();
  List<DataPlan> _fetchedPlans = [];
  bool _fetchingPlans = false;
  @override void dispose() { _pCtrl.dispose(); super.dispose(); }

  List<DataPlan> get _plans => _fetchedPlans.isNotEmpty ? _fetchedPlans : (_net == null ? [] : (_kDataPlans[_net] ?? []));

  Future<void> _fetchPlans(String operatorId) async {
    setState(() { _fetchingPlans = true; _fetchedPlans = []; });
    try {
      final r = await http.get(Uri.parse(
          '${widget.serverUrl}/api/vtu/bundles/$operatorId'))
          .timeout(const Duration(seconds: 8));
      final d = jsonDecode(r.body);
      if (d['success'] == true && mounted) {
        final bundles = d['bundles'] as List? ?? [];
        setState(() {
          _fetchedPlans = bundles.map((b) {
            final name = b['name'] as String? ?? '';
            // Parse duration from name
            int days = 30;
            if (name.toLowerCase().contains('1 day') || name.toLowerCase().contains('(1 day)') || name.toLowerCase().contains('one day')) days = 1;
            else if (name.toLowerCase().contains('2 day')) days = 2;
            else if (name.toLowerCase().contains('7 day') || name.toLowerCase().contains('(7 day)') || name.toLowerCase().contains('one week') || name.toLowerCase().contains('1 week')) days = 7;
            else if (name.toLowerCase().contains('2 week')) days = 14;
            else if (name.toLowerCase().contains('1 month') || name.toLowerCase().contains('one month') || name.toLowerCase().contains('30 day')) days = 30;
            else if (name.toLowerCase().contains('2 month') || name.toLowerCase().contains('60 day')) days = 60;
            else if (name.toLowerCase().contains('3 month') || name.toLowerCase().contains('90 day') || name.toLowerCase().contains('quarterly')) days = 90;
            else if (name.toLowerCase().contains('yearly') || name.toLowerCase().contains('1 year') || name.toLowerCase().contains('365 day')) days = 365;
            return DataPlan(operatorId, name, days, ((b['amount'] as num?)?.toDouble() ?? 0), b['item_code'] as String? ?? '', b['biller_type'] as String? ?? '', b['biller_code'] as String? ?? '');
          }).where((p) => p.price > 0).toList();
          // Sort by price
          _fetchedPlans.sort((a, b) => a.price.compareTo(b.price));
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _fetchingPlans = false);
  }

  Future<void> _buy() async {
    if (_net == null)          { widget.snack('Select a network'); return; }
    if (_phone.length < 6)     { widget.snack('Enter phone number'); return; }
    if (_plan == null)         { widget.snack('Select a plan'); return; }
    if (_plan!.price > widget.balance) { widget.snack('Insufficient balance'); return; }
    widget.snack('Processing…');
    try {
      final r = await http.post(
        Uri.parse('${widget.serverUrl}/api/vtu/data'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone':      _phone,
          'operatorId': _net,
          'amount':     _plan!.price,
          'userId':     widget.userId,
          'itemCode':   _plan!.itemCode,
          'billerType': _plan!.billerType,
          'billerCode': _plan!.billerCode,
        }),
      ).timeout(const Duration(seconds: 20));
      final d = jsonDecode(r.body);
      if (d['success'] == true) {
        await widget.onSuccess();
        widget.snack('✅ ${_plan!.size} data sent to $_phone. XameCoins cashback credited 🎉');
      } else {
        widget.snack('❌ ${d['message'] ?? 'Failed'}');
      }
    } catch (_) { widget.snack('❌ Network error'); }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('📶 Buy Data',
          style: TextStyle(color: Colors.white,
              fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 20),

      // ── Network picker ──────────────────────────────────────────────────
      const Text('Select Network',
          style: TextStyle(color: _kMuted,
              fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      _netGrid(widget.region.networks, _net, (id) {
        setState(() { _net = id; _plan = null; _fetchedPlans = []; });
        _fetchPlans(id);
      }),
      const SizedBox(height: 16),

      // ── Phone number ────────────────────────────────────────────────────
      const Text('Phone Number',
          style: TextStyle(color: _kMuted,
              fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      _xf(_pCtrl, 'Enter phone number',
          TextInputType.phone, (v) => _phone = v),

      // ── Plans ───────────────────────────────────────────────────────────
      if (_net != null) ...[
        const SizedBox(height: 20),
        const Text('Select Plan',
            style: TextStyle(color: _kMuted,
                fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        if (_fetchingPlans)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator(color: _kTeal, strokeWidth: 2)))
        else if (_plans.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No plans available for this network.',
                style: TextStyle(color: _kMuted, fontSize: 13)))
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _plans.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final p = _plans[i];
              final selected = _plan == p;
              return GestureDetector(
                onTap: () => setState(() => _plan = p),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0x1A00B0A0)
                        : _kCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: selected
                            ? _kTeal
                            : Colors.white12,
                        width: selected ? 2 : 1),
                  ),
                  child: Row(children: [
                    // Size badge (only for hardcoded plans)
                    if (_fetchedPlans.isEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? _kTeal : const Color(0x22FFFFFF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(p.size,
                            style: TextStyle(
                                color: selected ? Colors.black : Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          p.days == 1 ? '1 day' : p.days == 7 ? '1 week' : p.days == 30 ? '1 month' : '${p.days} days',
                          style: const TextStyle(color: _kMuted, fontSize: 13)),
                      ),
                    ] else
                      Expanded(
                        child: Text(p.size,
                            style: TextStyle(
                                color: selected ? _kTeal : Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                    // Price
                    Text(widget.fmt(p.price),
                        style: TextStyle(
                            color: selected ? _kTeal : Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              );
            },
          ),
      ],

      const SizedBox(height: 24),

      // ── Balance row ─────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: _kCard,
            borderRadius: BorderRadius.circular(12)),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Balance',
              style: TextStyle(color: _kMuted, fontSize: 13)),
          Text(widget.fmt(widget.balance),
              style: const TextStyle(color: Colors.white,
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ),
      const SizedBox(height: 16),

      // ── Buy button ──────────────────────────────────────────────────────
      SizedBox(width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _kTeal,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _buy,
          child: const Text('Buy Data',
              style: TextStyle(color: Colors.black,
                  fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );
}

// ── BILLS TAB ─────────────────────────────────────────────────────────────────

// Biller item (one package/product within a biller)
class _BillItem {
  final String itemCode, label, labelName;
  final double amount; // 0 = user enters amount
  const _BillItem(this.itemCode, this.label, this.labelName, this.amount);
  factory _BillItem.fromJson(Map<String, dynamic> j) => _BillItem(
    j['item_code'] ?? '',
    j['label']     ?? '',
    j['label_name'] ?? 'Customer ID',
    (j['amount'] as num?)?.toDouble() ?? 0,
  );
}

// A biller (e.g. "IKEDC", "DSTV")
class _Biller {
  final String name, billerCode;
  final List<_BillItem> items;
  const _Biller(this.name, this.billerCode, this.items);
  factory _Biller.fromJson(Map<String, dynamic> j) => _Biller(
    j['name']        ?? '',
    j['biller_code'] ?? '',
    ((j['items'] as List?) ?? []).map((i) => _BillItem.fromJson(i)).toList(),
  );
}

// Bill category descriptor
class _BillCat {
  final String type, label, icon;
  const _BillCat(this.type, this.label, this.icon);
}

const _kBillCats = [
  _BillCat('electricity', 'Electricity', '💡'),
  _BillCat('tv',          'Cable TV',    '📺'),
  _BillCat('internet',    'Internet',    '🌐'),
  _BillCat('data',        'Data Bundle', '📶'),
  _BillCat('airtime',     'Airtime',     '📱'),
];

// currency → 2-letter country code for bills API
const _kBillsCC = {
  'NGN':'NG','GHS':'GH','KES':'KE','ZAR':'ZA','USD':'US','GBP':'GB',
  'EUR':'DE','INR':'IN','AED':'AE','CAD':'CA','AUD':'AU','JPY':'JP',
  'SGD':'SG','EGP':'EG','SAR':'SA','TRY':'TR','MXN':'MX','IDR':'ID',
  'PHP':'PH','MYR':'MY','BRL':'BR','ZMW':'ZM','UGX':'UG','TZS':'TZ',
  'RWF':'RW','XOF':'SN','CMR':'CM','QAR':'QA','VND':'VN','THB':'TH',
  'PKR':'PK','MAD':'MA','ETB':'ET','ZWL':'ZW','COP':'CO','ARS':'AR',
};

class _BillsTab extends StatefulWidget {
  final RegionInfo region; final double balance;
  final String serverUrl, userId, currency;
  final String Function(double) fmt;
  final Future<void> Function() onSuccess;
  final void Function(String) snack;
  const _BillsTab({required this.region, required this.balance,
      required this.serverUrl, required this.userId, required this.currency,
      required this.fmt, required this.onSuccess, required this.snack});
  @override State<_BillsTab> createState() => _BillsTabState();
}

class _BillsTabState extends State<_BillsTab> {
  // Navigation state: null = category grid, set = drill-down
  _BillCat? _cat;
  _Biller?  _biller;

  // Biller list state
  bool _loadingBillers = false, _billersError = false;
  List<_Biller> _billers = [];

  // Payment form state
  _BillItem? _selItem;
  String _customer = '', _amtStr = '', _validated = '';
  bool _validating = false;
  final _custCtrl = TextEditingController();
  final _amtCtrl  = TextEditingController();

  @override
  void dispose() { _custCtrl.dispose(); _amtCtrl.dispose(); super.dispose(); }

  String get _cc => _kBillsCC[widget.currency] ?? 'NG';

  // ── Step 1 → 2: load billers for category ──────────────────────────────────
  Future<void> _loadBillers(_BillCat cat) async {
    setState(() { _cat = cat; _billers = []; _billersError = false; _loadingBillers = true; _biller = null; });
    try {
      final r = await http.get(Uri.parse(
        '${widget.serverUrl}/api/wallet/bills/categories'
        '?type=${cat.type}&country=$_cc'))
          .timeout(const Duration(seconds: 10));
      final d = jsonDecode(r.body);
      if (d['success'] == true && (d['categories'] as List).isNotEmpty) {
        setState(() {
          _billers = (d['categories'] as List).map((b) => _Biller.fromJson(b)).toList();
          _loadingBillers = false;
        });
      } else {
        setState(() { _loadingBillers = false; _billersError = true; });
      }
    } catch (_) {
      setState(() { _loadingBillers = false; _billersError = true; });
    }
  }

  // ── Step 2 → 3: select biller ──────────────────────────────────────────────
  void _selectBiller(_Biller b) {
    setState(() {
      _biller  = b;
      _selItem = b.items.isNotEmpty ? b.items.first : null;
      _customer = ''; _amtStr = ''; _validated = '';
      _custCtrl.clear(); _amtCtrl.clear();
    });
  }

  // ── Validate customer ID ────────────────────────────────────────────────────
  Future<void> _validate(String val) async {
    if (val.length < 4 || _biller == null || _selItem == null) return;
    setState(() { _validating = true; _validated = 'Verifying…'; });
    try {
      final r = await http.post(
        Uri.parse('${widget.serverUrl}/api/wallet/bills/validate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'item_code':    _selItem!.itemCode,
          'biller_code':  _biller!.billerCode,
          'customer':     val,
        }),
      ).timeout(const Duration(seconds: 10));
      final d = jsonDecode(r.body);
      setState(() {
        _validating = false;
        _validated = d['success'] == true
            ? '✅ ${d['name']}${d['address'] != null ? '  •  ${d['address']}' : ''}'
            : '⚠️ Could not verify — you can still proceed';
      });
    } catch (_) {
      setState(() { _validating = false; _validated = '⚠️ Validation unavailable'; });
    }
  }

  // ── Pay ─────────────────────────────────────────────────────────────────────
  Future<void> _pay() async {
    if (_customer.isEmpty) { widget.snack('Enter ${_selItem?.labelName ?? 'Customer ID'}'); return; }
    final amt = _selItem!.amount > 0 ? _selItem!.amount : (double.tryParse(_amtStr) ?? 0);
    if (amt < 1) { widget.snack('Enter amount'); return; }
    if (amt > widget.balance) { widget.snack('Insufficient balance'); return; }
    widget.snack('Processing payment…');
    try {
      final r = await http.post(
        Uri.parse('${widget.serverUrl}/api/wallet/bills/pay'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId':       widget.userId,
          'biller_code':  _biller!.billerCode,
          'item_code':    _selItem!.itemCode,
          'customer':     _customer,
          'amount':       amt,
          'country':      _cc,
        }),
      ).timeout(const Duration(seconds: 20));
      final d = jsonDecode(r.body);
      if (d['success'] == true) {
        await widget.onSuccess();
        widget.snack('✅ ${_cat!.label} paid! XameCoins cashback credited 🎉'
            '${d['fee'] != null ? '  Fee: ${widget.fmt((d['fee'] as num).toDouble())}' : ''}');
        // Return to category grid
        setState(() { _cat = null; _biller = null; _billers = []; });
      } else {
        widget.snack('❌ ${d['message'] ?? 'Payment failed'}');
      }
    } catch (_) { widget.snack('❌ Network error'); }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_biller != null)  return _buildPayForm();
    if (_cat != null)     return _buildBillerList();
    return _buildCategoryGrid();
  }

  // ── STEP 1: Category grid ──────────────────────────────────────────────────
  Widget _buildCategoryGrid() => SingleChildScrollView(
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
        children: _kBillCats.map((c) => GestureDetector(
          onTap: () => _loadBillers(c),
          child: Container(
            decoration: BoxDecoration(color: _kCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Text(c.icon, style: const TextStyle(fontSize: 32)),
              const SizedBox(height: 10),
              Text(c.label, style: const TextStyle(color: Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
          ),
        )).toList(),
      ),
    ]),
  );

  // ── STEP 2: Biller list ────────────────────────────────────────────────────
  Widget _buildBillerList() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Header with back
      Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: _kTeal, size: 28),
            onPressed: () => setState(() { _cat = null; _billers = []; _billersError = false; })),
          Text('${_cat!.icon}  ${_cat!.label}',
              style: const TextStyle(color: Colors.white,
                  fontSize: 17, fontWeight: FontWeight.w700)),
        ]),
      ),
      Expanded(child: _loadingBillers
        ? const Center(child: CircularProgressIndicator(color: _kTeal))
        : _billersError
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.wifi_off_rounded, color: _kMuted, size: 40),
                const SizedBox(height: 12),
                const Text('Could not load billers.',
                    style: TextStyle(color: _kMuted, fontSize: 14)),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _kTeal,
                      foregroundColor: Colors.black,
                      shape: const StadiumBorder()),
                  onPressed: () => _loadBillers(_cat!),
                  child: const Text('Retry')),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _billers.length,
                itemBuilder: (_, i) {
                  final b = _billers[i];
                  return GestureDetector(
                    onTap: () => _selectBiller(b),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(color: _kCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white10)),
                      child: Row(children: [
                        Expanded(child: Text(b.name,
                            style: const TextStyle(color: Colors.white,
                                fontSize: 14, fontWeight: FontWeight.w600))),
                        const Icon(Icons.chevron_right, color: _kMuted, size: 20),
                      ]),
                    ),
                  );
                },
              )),
    ],
  );

  // ── STEP 3: Payment form ───────────────────────────────────────────────────
  Widget _buildPayForm() {
    final firstItem = _biller!.items.isNotEmpty ? _biller!.items.first : null;
    final labelName = _selItem?.labelName ?? firstItem?.labelName ?? 'Customer ID';
    final isFixed   = (_selItem?.amount ?? 0) > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Back button
        GestureDetector(
          onTap: () => setState(() { _biller = null; _validated = ''; }),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.chevron_left, color: _kTeal, size: 24),
            Text(_biller!.name,
                style: const TextStyle(color: _kTeal,
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 16),

        Text('${_cat!.icon}  ${_biller!.name}',
            style: const TextStyle(color: Colors.white,
                fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Balance: ${widget.fmt(widget.balance)}',
            style: const TextStyle(color: _kMuted, fontSize: 12)),
        const SizedBox(height: 20),

        // Package selector (only when biller has multiple items)
        if (_biller!.items.length > 1) ...[
          const Text('Select Package',
              style: TextStyle(color: _kMuted,
                  fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selItem?.itemCode,
            dropdownColor: _kBg,
            isExpanded: true,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              filled: true, fillColor: _kBg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white12)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white12)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
            items: _biller!.items.map((item) => DropdownMenuItem(
              value: item.itemCode,
              child: Text(
                item.amount > 0
                    ? '${item.label}  —  ${widget.fmt(item.amount)}'
                    : item.label,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            )).toList(),
            onChanged: (v) => setState(() {
              _selItem = _biller!.items.firstWhere(
                  (i) => i.itemCode == v, orElse: () => _biller!.items.first);
              _validated = '';
              if (_customer.length >= 4) _validate(_customer);
            }),
          ),
          const SizedBox(height: 16),
        ],

        // Customer ID
        Text(labelName,
            style: const TextStyle(color: _kMuted,
                fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _custCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Enter $labelName',
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
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
          ),
          onChanged: (v) {
            _customer = v;
            if (v.length >= 4) {
              Future.delayed(const Duration(milliseconds: 600), () {
                if (_custCtrl.text == v) _validate(v);
              });
            } else {
              setState(() => _validated = '');
            }
          },
        ),
        // Validation result
        if (_validating)
          const Padding(padding: EdgeInsets.only(top: 6),
              child: Text('Verifying…',
                  style: TextStyle(color: _kMuted, fontSize: 12))),
        if (!_validating && _validated.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_validated,
                style: TextStyle(
                    color: _validated.startsWith('✅')
                        ? _kTeal : const Color(0xFFF0A500),
                    fontSize: 12)),
          ),
        const SizedBox(height: 16),

        // Amount (hidden for fixed-price packages)
        if (!isFixed) ...[
          const Text('Amount',
              style: TextStyle(color: _kMuted,
                  fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _xf(_amtCtrl, 'Enter amount',
              const TextInputType.numberWithOptions(decimal: true),
              (v) => _amtStr = v),
          const SizedBox(height: 16),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _kCard,
                borderRadius: BorderRadius.circular(12)),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
              const Text('Amount',
                  style: TextStyle(color: _kMuted, fontSize: 13)),
              Text(widget.fmt(_selItem!.amount),
                  style: const TextStyle(color: _kTeal,
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 16),
        ],

        // Pay button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kTeal,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _pay,
            child: Text('Pay ${_cat!.label}',
                style: const TextStyle(color: Colors.black,
                    fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}



// ── HISTORY TAB ───────────────────────────────────────────────────────────────

class _MoreTab extends StatefulWidget {
  final List<WalletTx> txs;
  final String Function(double) fmt;
  final Map<String, String>? virtualAccount;
  final String userId, serverUrl;
  const _MoreTab({required this.txs, required this.fmt, this.virtualAccount,
      required this.userId, required this.serverUrl});
  @override State<_MoreTab> createState() => _MoreTabState();
}

class _MoreTabState extends State<_MoreTab> with SingleTickerProviderStateMixin {
  late TabController _innerTab;

  @override
  void initState() {
    super.initState();
    _innerTab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() { _innerTab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: const Color(0xFF1A1A2E),
        child: TabBar(
          controller: _innerTab,
          indicatorColor: _kTeal,
          labelColor: _kTeal,
          unselectedLabelColor: _kMuted,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: '📊 History'),
            Tab(text: '🪙 Rewards'),
          ],
        ),
      ),
      Expanded(child: TabBarView(
        controller: _innerTab,
        children: [
          _HistoryTab(txs: widget.txs, fmt: widget.fmt, virtualAccount: widget.virtualAccount),
          _RewardsTab(userId: widget.userId, serverUrl: widget.serverUrl),
        ],
      )),
    ]);
  }
}

class _HistoryTab extends StatefulWidget {
  final List<WalletTx> txs;
  final String Function(double) fmt;
  final Map<String, String>? virtualAccount;
  const _HistoryTab({required this.txs, required this.fmt, this.virtualAccount});
  @override State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  final _screenshotCtrl = ScreenshotController();

  List<WalletTx> get txs => widget.txs;
  String Function(double) get fmt => widget.fmt;

  String _fmtTs(String ts) {
    try {
      final dt = DateTime.parse(ts).toLocal();
      final months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      final h = dt.hour.toString().padLeft(2,'0');
      final m = dt.minute.toString().padLeft(2,'0');
      return '${months[dt.month-1]} ${dt.day}, ${dt.year} • $h:$m';
    } catch (_) { return ts.length > 10 ? ts.substring(0,10) : ts; }
  }

  Future<void> _shareReceipt(WalletTx tx, bool asPdf) async {
    final image = await _screenshotCtrl.captureFromWidget(
      Material(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Row(children: [
              const Text('XamePay', style: TextStyle(color: _kTeal,
                  fontSize: 20, fontWeight: FontWeight.w800)),
              const Spacer(),
              const Text('Transaction Receipt', style: TextStyle(
                  color: Color(0xFF888888), fontSize: 11)),
            ]),
            const SizedBox(height: 16),
            // Amount — show principal (before fee) when available, not the total debited
            Center(child: Text(fmt(tx.principal ?? tx.amount),
                style: TextStyle(
                    color: tx.type == 'credit' ? _kTeal : const Color(0xFFFF6464),
                    fontSize: 36, fontWeight: FontWeight.w800))),
            Center(child: Text(tx.status, style: TextStyle(
                color: tx.status == 'Completed' ? _kTeal : const Color(0xFFF0A500),
                fontSize: 14))),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFFE0E0E0)),
            const SizedBox(height: 8),

            // ── Parse label into method + party details ─────────────────
            ...(() {
              final parsed = _parseTxLabel(tx.label, tx.type);
              final widgets = <Widget>[];

              widgets.add(_receiptRowLight('Description', parsed.method));
              widgets.add(_receiptRowLight('Date & Time', _fmtTs(tx.ts)));

              // ── Transparent fee/cashback breakdown ────────────────────
              if (tx.principal != null) {
                widgets.add(_receiptRowLight('Amount', fmt(tx.principal!)));
              }
              if (tx.fee != null && tx.fee! > 0) {
                widgets.add(_receiptRowLight('Service Fee', fmt(tx.fee!)));
              }
              if (tx.principal != null && tx.fee != null) {
                widgets.add(_receiptRowLight('Total Debited', fmt(tx.principal! + tx.fee!)));
              }
              if (tx.cashback != null && tx.cashback! > 0) {
                final ngnEquiv = tx.cashback! * 0.1;
                widgets.add(_receiptRowLight('Cashback Earned',
                    '+${tx.cashback} XameCoins (≈₦${ngnEquiv.toStringAsFixed(2)})'));
              }

              if (tx.sentCurrency != null && tx.recvCurrency != null &&
                  tx.sentCurrency != tx.recvCurrency) {
                widgets.add(_receiptRowLight('Sent',
                    '${tx.sentCurrency} ${tx.sentAmount?.toStringAsFixed(2)}'));
                widgets.add(_receiptRowLight('Received',
                    '${tx.recvCurrency} ${tx.recvAmount?.toStringAsFixed(2)}'));
                widgets.add(_receiptRowLight('FX Rate',
                    '1 ${tx.sentCurrency} = ${tx.fxRate?.toStringAsFixed(4)} ${tx.recvCurrency}'));
              }

              widgets.add(_receiptRowLight('Reference', tx.id));
              widgets.add(_receiptRowLight('Status', tx.status));

              // ── Own virtual account — "Recipient Details" for bank transfer credits ──
              final va = widget.virtualAccount;
              if (tx.type == 'credit' && parsed.method == 'Bank Transfer' &&
                  va != null && (va['accountNumber'] ?? '').isNotEmpty) {
                widgets.add(const SizedBox(height: 12));
                widgets.add(const Divider(color: Color(0xFFE0E0E0)));
                widgets.add(const SizedBox(height: 8));
                widgets.add(const Text('Recipient Details',
                    style: TextStyle(color: Color(0xFF888888),
                        fontSize: 12, fontWeight: FontWeight.w600)));
                widgets.add(const SizedBox(height: 6));
                widgets.add(Text('${va['accountName']}',
                    style: const TextStyle(color: Color(0xFF1A1A1A),
                        fontSize: 14, fontWeight: FontWeight.w700)));
                widgets.add(Text('${va['bankName']} | ${va['accountNumber']}',
                    style: const TextStyle(color: Color(0xFF888888), fontSize: 12)));
              }

              // ── Recipient / Sender Details block ─────────────────────
              if ((tx.recipient != null && tx.recipient!.isNotEmpty) ||
                  parsed.partyName != null || parsed.partyInfo != null) {
                widgets.add(const SizedBox(height: 12));
                widgets.add(const Divider(color: Color(0xFFE0E0E0)));
                widgets.add(const SizedBox(height: 8));
                widgets.add(Text(
                  tx.type == 'credit' ? 'Sender Details' : 'Recipient Details',
                  style: const TextStyle(color: Color(0xFF888888),
                      fontSize: 12, fontWeight: FontWeight.w600),
                ));
                widgets.add(const SizedBox(height: 6));
                if (tx.recipient != null && tx.recipient!.isNotEmpty)
                  widgets.add(Text(tx.recipient!,
                      style: const TextStyle(color: Color(0xFF1A1A1A),
                          fontSize: 14, fontWeight: FontWeight.w700)));
                if (parsed.partyName != null)
                  widgets.add(Text(parsed.partyName!,
                      style: const TextStyle(color: Color(0xFF1A1A1A),
                          fontSize: 14, fontWeight: FontWeight.w700)));
                if (parsed.partyInfo != null)
                  widgets.add(Text(parsed.partyInfo!,
                      style: const TextStyle(color: Color(0xFF888888),
                          fontSize: 12)));
              }

              return widgets;
            })(),

            const SizedBox(height: 16),
            const Divider(color: Color(0xFFE0E0E0)),
            const SizedBox(height: 8),
            Center(child: Text('Powered by XamePage',
                style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 10))),
          ]),
        ),
      ),
      pixelRatio: 2.0,
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/xamepay_receipt_${tx.id}.png');
    await file.writeAsBytes(image);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png')],
      text: 'XamePay Transaction Receipt',
      subject: 'XamePay Transaction Receipt',
    );
  }

  void _openTransactionDetails(BuildContext context, WalletTx tx) {
    final isCredit = tx.type == 'credit';
    // For credit: sender is external party, recipient is the wallet owner's VA
    // For debit: sender is the wallet owner's VA, recipient is external party
    final senderName        = isCredit ? tx.txSenderName        : tx.txSenderName;
    final senderBankName    = isCredit ? tx.txBankName          : tx.txSenderBankName;
    final senderAccountNumber = isCredit ? tx.txAccountNumber   : tx.txSenderAccountNumber;
    final recipientName     = isCredit ? tx.txRecipientName     : tx.txRecipientName;
    final recipientBankName = isCredit ? tx.txRecipientBankName : tx.txBankName;
    final recipientAccountNumber = isCredit ? tx.txRecipientAccountNumber : tx.txAccountNumber;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TransactionDetailsScreen(
      amount:              tx.principal ?? tx.amount,
      fee:                 tx.fee ?? 0,
      totalDebit:          (tx.principal ?? tx.amount) + (tx.fee ?? 0),
      cashbackCoins:       tx.cashback,
      senderName:          senderName,
      senderBankName:      senderBankName,
      senderAccountNumber: senderAccountNumber,
      recipientName:       recipientName,
      bankName:            recipientBankName,
      accountNumber:       recipientAccountNumber,
      txRef:               tx.flwRef.isNotEmpty ? tx.flwRef : tx.id,
      sessionId:           tx.id,
      paymentMethod:       'XamePay Wallet',
      ts:                  DateTime.tryParse(tx.ts) ?? DateTime.now(),
      fmt:                 widget.fmt,
      description:         tx.label,
    )));
  }

  void _showReceipt(BuildContext context, WalletTx tx) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _kCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Container(width: 56, height: 56,
            decoration: BoxDecoration(
              color: tx.type == 'credit'
                  ? const Color(0x1A00B0A0) : const Color(0x1AFF6464),
              shape: BoxShape.circle),
            child: Center(child: Text(tx.icon,
                style: const TextStyle(fontSize: 26)))),
          const SizedBox(height: 12),
          Text(fmt(tx.principal ?? tx.amount),
              style: TextStyle(
                  color: tx.type == 'credit' ? _kTeal : const Color(0xFFFF6464),
                  fontSize: 32, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(tx.status,
              style: TextStyle(
                  color: tx.status == 'Completed' ? _kTeal : const Color(0xFFF0A500),
                  fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          const Divider(color: Colors.white12),
          const SizedBox(height: 12),
          ...(() {
            final parsed = _parseTxLabel(tx.label, tx.type);
            final widgets = <Widget>[
              _receiptRow('Description', parsed.method),
              _receiptRow('Date & Time', _fmtTs(tx.ts)),
            ];

            // ── Transparent fee/cashback breakdown ──────────────────────
            if (tx.principal != null) {
              widgets.add(_receiptRow('Amount', fmt(tx.principal!)));
            }
            if (tx.fee != null && tx.fee! > 0) {
              widgets.add(_receiptRow('Service Fee', fmt(tx.fee!)));
            }
            if (tx.principal != null && tx.fee != null) {
              widgets.add(_receiptRow('Total Debited', fmt(tx.principal! + tx.fee!)));
            }
            if (tx.cashback != null && tx.cashback! > 0) {
              final ngnEquiv = tx.cashback! * 0.1;
              widgets.add(_receiptRow('Cashback Earned',
                  '+${tx.cashback} XameCoins (≈₦${ngnEquiv.toStringAsFixed(2)})'));
            }

            if (tx.sentAmount != null && tx.sentCurrency != null &&
                tx.recvAmount != null && tx.recvCurrency != null &&
                tx.sentCurrency != tx.recvCurrency) {
              widgets.add(_receiptRow('Sent',
                  '${tx.sentCurrency} ${tx.sentAmount!.toStringAsFixed(2)}'));
              widgets.add(_receiptRow('Received',
                  '${tx.recvCurrency} ${tx.recvAmount!.toStringAsFixed(2)}'));
              widgets.add(_receiptRow('FX Rate',
                  '1 ${tx.sentCurrency} = ${tx.fxRate?.toStringAsFixed(4)} ${tx.recvCurrency}'));
            }

            widgets.add(_receiptRow('Reference', tx.id));
            widgets.add(_receiptRow('Status', tx.status));

            // ── Own virtual account — "Recipient Details" for bank transfer credits ──
            final va2 = widget.virtualAccount;
            if (tx.type == 'credit' && parsed.method == 'Bank Transfer' &&
                va2 != null && (va2['accountNumber'] ?? '').isNotEmpty) {
              widgets.add(const SizedBox(height: 8));
              widgets.add(const Divider(color: Colors.white12));
              widgets.add(const SizedBox(height: 8));
              widgets.add(const Align(alignment: Alignment.centerLeft,
                child: Text('Recipient Details',
                    style: TextStyle(color: Colors.white54,
                        fontSize: 12, fontWeight: FontWeight.w600))));
              widgets.add(const SizedBox(height: 6));
              widgets.add(Align(alignment: Alignment.centerLeft,
                child: Text('${va2['accountName']}',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 14, fontWeight: FontWeight.w700))));
              widgets.add(Align(alignment: Alignment.centerLeft,
                child: Text('${va2['bankName']} | ${va2['accountNumber']}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12))));
            }

            if ((tx.recipient != null && tx.recipient!.isNotEmpty) ||
                parsed.partyName != null || parsed.partyInfo != null) {
              widgets.add(const SizedBox(height: 8));
              widgets.add(const Divider(color: Colors.white12));
              widgets.add(const SizedBox(height: 8));
              widgets.add(Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tx.type == 'credit' ? 'Sender Details' : 'Recipient Details',
                  style: const TextStyle(color: Colors.white54,
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ));
              widgets.add(const SizedBox(height: 6));
              if (tx.recipient != null && tx.recipient!.isNotEmpty)
                widgets.add(Align(
                  alignment: Alignment.centerLeft,
                  child: Text(tx.recipient!,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ));
              if (parsed.partyName != null)
                widgets.add(Align(
                  alignment: Alignment.centerLeft,
                  child: Text(parsed.partyName!,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ));
              if (parsed.partyInfo != null)
                widgets.add(Align(
                  alignment: Alignment.centerLeft,
                  child: Text(parsed.partyInfo!,
                      style: const TextStyle(color: Colors.white54,
                          fontSize: 12)),
                ));
            }

            return widgets;
          })(),
          const SizedBox(height: 20),
          const Divider(color: Colors.white12),
          const SizedBox(height: 16),
          const Text('Share Receipt',
              style: TextStyle(color: Colors.white,
                  fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                Navigator.pop(context);
                _shareReceipt(tx, false);
              },
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Image', style: TextStyle(fontSize: 13)))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: _kTeal,
                  side: const BorderSide(color: Color(0x4D00B0A0)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                Navigator.pop(context);
                _shareReceipt(tx, true);
              },
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('PDF', style: TextStyle(fontSize: 13)))),
          ]),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B0A0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                Navigator.pop(context);
                final image = await _screenshotCtrl.captureFromWidget(
                  Material(color: Colors.white,
                    child: Padding(padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Text('XamePay', style: TextStyle(color: _kTeal, fontSize: 20, fontWeight: FontWeight.w800)),
                          const Spacer(),
                          const Text('Transaction Receipt', style: TextStyle(color: Color(0xFF888888), fontSize: 11)),
                        ]),
                        const SizedBox(height: 16),
                        Center(child: Text(fmt(tx.amount), style: TextStyle(color: tx.type == 'credit' ? _kTeal : const Color(0xFFFF6464), fontSize: 36, fontWeight: FontWeight.w800))),
                        Center(child: Text(tx.status, style: TextStyle(color: tx.status == 'Completed' ? _kTeal : const Color(0xFFF0A500), fontSize: 14))),
                        const SizedBox(height: 16),
                        const Divider(color: Color(0xFFE0E0E0)),
                        const SizedBox(height: 8),
                        if (tx.recipient != null && tx.recipient!.isNotEmpty) _receiptRowLight('Beneficiary', tx.recipient!),
                        _receiptRowLight('Description', tx.label),
                        _receiptRowLight('Date & Time', _fmtTs(tx.ts)),
                        _receiptRowLight('Reference', tx.id),
                        _receiptRowLight('Status', tx.status),
                        const SizedBox(height: 16),
                        const Divider(color: Color(0xFFE0E0E0)),
                        const SizedBox(height: 8),
                        Center(child: Text('Powered by XamePage', style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 10))),
                      ]),
                    )),
                  pixelRatio: 2.0,
                );
                final dir = Directory('/storage/emulated/0/Pictures/XamePage');
                if (!await dir.exists()) await dir.create(recursive: true);
                final file = File('${dir.path}/xamepay_receipt_${tx.id}.png');
                await file.writeAsBytes(image);
                await Process.run('am', ['broadcast', '-a', 'android.intent.action.MEDIA_SCANNER_SCAN_FILE', '-d', 'file://${file.path}']);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Receipt saved to Gallery'), backgroundColor: Color(0xFF00B0A0)));
              },
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Save to Gallery', style: TextStyle(fontSize: 13)))),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _receiptRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 110,
          child: Text(label, style: const TextStyle(
              color: _kMuted, fontSize: 13))),
      Expanded(child: Text(value, style: const TextStyle(
          color: Colors.white, fontSize: 13,
          fontWeight: FontWeight.w500),
          textAlign: TextAlign.right)),
    ]),
  );

  Widget _receiptRowLight(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 110,
          child: Text(label, style: const TextStyle(
              color: Color(0xFF888888), fontSize: 13))),
      Expanded(child: Text(value, style: const TextStyle(
          color: Color(0xFF222222), fontSize: 13,
          fontWeight: FontWeight.w600),
          textAlign: TextAlign.right)),
    ]),
  );

  @override
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
        final tx = widget.txs[i]; final cr = tx.type == 'credit';
        return InkWell(
          onTap: () => _openTransactionDetails(context, tx),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
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
                    fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                if (tx.sentCurrency != null && tx.recvCurrency != null &&
                    tx.sentCurrency != tx.recvCurrency)
                  Text('${tx.sentCurrency} ${tx.sentAmount?.toStringAsFixed(2)} → ${tx.recvCurrency} ${tx.recvAmount?.toStringAsFixed(2)}',
                      style: const TextStyle(color: _kTeal, fontSize: 11)),
                Text(_fmtTs(tx.ts),
                    style: const TextStyle(color: _kMuted, fontSize: 11)),
                Text(tx.status,
                    style: TextStyle(
                        color: tx.status == 'Completed'
                            ? _kTeal : const Color(0xFFF0A500),
                        fontSize: 11, fontWeight: FontWeight.w500)),
              ])),
              const SizedBox(width: 8),
              Text('${cr ? "+" : "-"}${widget.fmt(tx.amount)}',
                  style: TextStyle(
                      color: cr ? _kTeal : const Color(0xFFFF6464),
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ]),
          ),
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


// ══════════════════════════════════════════════════════════════════════════════
// REWARDS TAB
// ══════════════════════════════════════════════════════════════════════════════

class _RewardsTab extends StatefulWidget {
  final String userId, serverUrl;
  const _RewardsTab({required this.userId, required this.serverUrl});
  @override State<_RewardsTab> createState() => _RewardsTabState();
}

class _RewardsTabState extends State<_RewardsTab> {
  Map<String, dynamic>? _account;
  List<dynamic> _txs = [];
  bool _loading = true;
  bool _withdrawing = false;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await http.get(Uri.parse('${widget.serverUrl}/api/rewards/${widget.userId}'));
      final d = jsonDecode(r.body);
      if (d['success'] == true && mounted) {
        setState(() {
          _account = d['account'];
          _txs     = d['transactions'] ?? [];
          _loading = false;
        });
      }
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _withdraw() async {
    final coins = _account?['coinBalance'] ?? 0;
    if (coins < 10000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum withdrawal is 10,000 coins'),
            behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _withdrawing = true);
    try {
      final r = await http.post(
        Uri.parse('${widget.serverUrl}/api/rewards/withdraw'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': widget.userId, 'coins': coins}),
      );
      final d = jsonDecode(r.body);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(d['message'] ?? (d['success'] ? 'Withdrawn!' : 'Failed')),
        behavior: SnackBarBehavior.floating));
      if (d['success'] == true) _load();
    } catch (_) {} finally { if (mounted) setState(() => _withdrawing = false); }
  }

  void _share() {
    final code = _account?['referralCode'] ?? '';
    final link = 'https://app.xamepage.com/join/$code';
    Share.share('Join me on XamePage! Download and earn XameCoins together:\n$link');
  }

  String _tierBadge(String tier) {
    switch (tier) {
      case 'silver':  return '🥈 Silver';
      case 'gold':    return '🥇 Gold';
      case 'diamond': return '💎 Diamond';
      default:        return '🥉 Bronze';
    }
  }

  String _txIcon(String type) {
    switch (type) {
      case 'call_minute':        return '📞';
      case 'invite_register':    return '👤';
      case 'invite_active':      return '✅';
      case 'invite_first_call':  return '🎉';
      case 'benchmark_weekly':   return '🏆';
      case 'benchmark_monthly':  return '🎯';
      case 'login_streak':       return '🔥';
      case 'first_message':      return '💬';
      case 'wallet_send':        return '💸';
      case 'withdrawal':         return '🏦';
      default:                   return '🪙';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _kTeal));
    if (_account == null) return Center(
      child: TextButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.refresh, color: _kTeal),
        label: const Text('Tap to load rewards', style: TextStyle(color: _kTeal)),
      ));

    final balance  = _account!['coinBalance']    as int? ?? 0;
    final earned   = _account!['totalEarned']    as int? ?? 0;
    final withdrawn= _account!['totalWithdrawn'] as int? ?? 0;
    final tier     = _account!['tier']           as String? ?? 'bronze';
    final streak   = _account!['streakDays']     as int? ?? 0;
    final refs     = _account!['activeReferrals']as int? ?? 0;
    final naira    = (balance * 0.1).toStringAsFixed(2);
    final canWithdraw = balance >= 10000;

    return RefreshIndicator(
      onRefresh: _load,
      color: _kTeal,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Coin Balance Card ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00B0A0), Color(0xFF007A72)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(children: [
              const Text('🪙 XameCoins Balance',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Text('$balance coins',
                style: const TextStyle(color: Colors.white,
                    fontSize: 36, fontWeight: FontWeight.w800)),
              Text('≈ ₦$naira',
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                Column(children: [
                  Text('$earned', style: const TextStyle(color: Colors.white,
                      fontSize: 16, fontWeight: FontWeight.w700)),
                  const Text('Total Earned', style: TextStyle(color: Colors.white60, fontSize: 11)),
                ]),
                Container(width: 1, height: 30, color: Colors.white30),
                Column(children: [
                  Text('$withdrawn', style: const TextStyle(color: Colors.white,
                      fontSize: 16, fontWeight: FontWeight.w700)),
                  const Text('Withdrawn', style: TextStyle(color: Colors.white60, fontSize: 11)),
                ]),
                Container(width: 1, height: 30, color: Colors.white30),
                Column(children: [
                  Text(_tierBadge(tier),
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                  const Text('Tier', style: TextStyle(color: Colors.white60, fontSize: 11)),
                ]),
              ]),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Stats Row ─────────────────────────────────────────────────
          Row(children: [
            Expanded(child: _statCard('🔥 Streak', '$streak days')),
            const SizedBox(width: 8),
            Expanded(child: _statCard('👥 Referrals', '$refs active')),
          ]),
          const SizedBox(height: 12),

          // ── Action Buttons ────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.share, size: 16),
                label: const Text('Share Referral'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kCard,
                  foregroundColor: _kTeal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: canWithdraw ? _withdraw : null,
                icon: _withdrawing
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.account_balance_wallet, size: 16),
                label: const Text('Withdraw'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: canWithdraw ? _kTeal : _kMuted,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          if (!canWithdraw)
            Text('${10000 - balance} more coins needed to withdraw',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kMuted, fontSize: 12)),
          const SizedBox(height: 16),

          // ── Tab Buttons ───────────────────────────────────────────────
          Row(children: [
            Expanded(child: _rewardsTabBtn('💡 How to Earn', () => _openRewardsFullscreen(
              '💡 How to Earn', ListView(padding: const EdgeInsets.all(16), children: [
                _earnRow('📞 Call XamePage users', '2 coins/min (max 60 mins/day)'),
                _earnRow('👤 Invite friends', '50 coins per registration'),
                _earnRow('🎉 Invite makes first call', '100 bonus coins'),
                _earnRow('✅ Invite active 30 days', '200 bonus coins'),
                _earnRow('🏆 Call 10 users in a week', '500 bonus coins'),
                _earnRow('🎯 5 referrals in a month', '1,000 bonus coins'),
                _earnRow('🔥 7-day login streak', '50 coins'),
                _earnRow('💬 First message daily', '5 coins'),
                _earnRow('💸 Send wallet payment', '10 coins'),
                _earnRow('📸 Post on Discovery', '10 coins per post'),
                _earnRow('❤️ Get likes on your post', '2 coins per like'),
                _earnRow('👁️ Get views on your post', '1 coin per 10 views'),
                _earnRow('🤝 Collab post accepted', '50 bonus coins'),
                _earnRow('📰 Become XamePage Reporter', '+50% bonus on monthly payout'),
                _earnRow('💎 Reach Diamond tier', '3× coin multiplier on all earnings'),
                _earnRow('🥇 Reach Gold tier', '2× coin multiplier on all earnings'),
                _earnRow('🥈 Reach Silver tier', '1.5× coin multiplier on all earnings'),
              ])))),
            const SizedBox(width: 8),
            Expanded(child: _rewardsTabBtn('📒 Coin Ledger', () => _openRewardsFullscreen(
                '📒 Coin Ledger',
                Builder(builder: (_) => _txs.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(24),
                      child: Text('No transactions yet. Start earning!',
                        style: TextStyle(color: _kMuted, fontSize: 13))))
                  : ListView(padding: const EdgeInsets.all(16), children:
                      _txs.map((tx) {
                        final coins = tx['coins'] as int? ?? 0;
                        final isPositive = coins > 0;
                        final ts = tx['ts'] != null ? DateTime.tryParse(tx['ts'].toString())?.toLocal() : null;
                        final dateStr = ts != null ? '${ts.day}/${ts.month}/${ts.year} ${ts.hour.toString().padLeft(2,"0")}:${ts.minute.toString().padLeft(2,"0")}' : '';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
                          child: Row(children: [
                            Text(_txIcon(tx['type'] ?? ''), style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(tx['description'] ?? tx['type'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                              if (dateStr.isNotEmpty) Text(dateStr, style: const TextStyle(color: _kMuted, fontSize: 11)),
                            ])),
                            Text('${isPositive ? "+" : ""}$coins', style: TextStyle(color: isPositive ? _kTeal : Colors.redAccent, fontSize: 14, fontWeight: FontWeight.w700)),
                          ]),
                        );
                      }).toList()),
                ),
              ))),
          ]),
        ],
      ),
    );
  }

  Widget _rewardsTabBtn(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kTeal.withOpacity(0.4)),
      ),
      child: Text(label, textAlign: TextAlign.center,
        style: const TextStyle(color: _kTeal, fontSize: 13, fontWeight: FontWeight.w700)),
    ),
  );

  void _openRewardsFullscreen(String title, Widget body) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: _kCard,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        body: body,
      ),
    ));
  }

  Widget _statCard(String label, String value) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _kCard, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white10)),
    child: Column(children: [
      Text(label, style: const TextStyle(color: _kMuted, fontSize: 12)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(color: Colors.white,
          fontSize: 15, fontWeight: FontWeight.w700)),
    ]));

  Widget _earnRow(String action, String reward) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(action, style: const TextStyle(color: Colors.white70, fontSize: 13))),
      Text(reward, style: const TextStyle(color: _kTeal, fontSize: 12, fontWeight: FontWeight.w600)),
    ]));
}
