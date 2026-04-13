// lib/screens/xame_pay_screen.dart
// XamePay – Full wallet for XamePage 2.1  (Build 237+)
//
// Fixes:
//   1. Name is XamePay everywhere (not XameWallet)
//   2. Send to Banks restored — regional bank list + microfinances + search
//   3. Region/currency switcher with live internal currency converter
//   4. Balance shown in display currency (converter) alongside wallet currency

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── COLOURS ──────────────────────────────────────────────────────────────────
const kTeal  = Color(0xFF00B0A0);
const kBg    = Color(0xFF0D1520);
const kCard  = Color(0xFF111E2E);
const kMuted = Color(0xFF7A9BB5);

// ── MODELS ───────────────────────────────────────────────────────────────────

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
  BankItem.fromJson(Map<String, dynamic> j)
      : name = j['name'] ?? '', code = j['code'] ?? '';
  BankItem(this.name, this.code);
}

// ── REGION DATA ───────────────────────────────────────────────────────────────

class RegionData {
  final String currency, country, countryCode, symbol;
  final List<List<String>> networks; // [id, label, icon]
  final List<String> banks;
  final List<List<String>> bills;    // [id, label, icon, provider1|provider2]
  const RegionData(this.currency, this.country, this.countryCode, this.symbol,
      this.networks, this.banks, this.bills);
}

const List<RegionData> kRegions = [
  RegionData('NGN','Nigeria','NG','₦',
    [['MTN-NG','MTN','🟡'],['AIRTEL-NG','Airtel','🔴'],['GLO-NG','Glo','🟢'],['9MOBILE-NG','9mobile','💚']],
    ['Access Bank','GTBank','Zenith Bank','First Bank','UBA','Fidelity Bank','Sterling Bank','Wema Bank','Kuda Bank','Opay','PalmPay','Polaris Bank','Union Bank','Stanbic IBTC','FCMB','Ecobank Nigeria','Heritage Bank','Jaiz Bank'],
    [['electricity','Electricity','💡','IKEDC|EKEDC|AEDC|PHEDC|IBEDC|BEDC|KEDCO|EEDC'],['cable','Cable TV','📺','DSTV|GOtv|Startimes'],['water','Water','💧','Lagos Water|Abuja Water'],['internet','Internet','🌐','Spectranet|Smile|ipNX|Swift']]),
  RegionData('GHS','Ghana','GH','GH₵',
    [['MTN-GH','MTN','🟡'],['VODAFONE-GH','Vodafone','🔴'],['AIRTELTIGO-GH','AirtelTigo','🟠']],
    ['GCB Bank','Ecobank Ghana','Absa Ghana','Stanbic Ghana','Fidelity Bank Ghana','Cal Bank','Republic Bank Ghana','ARB Apex Bank'],
    [['electricity','Electricity','💡','ECG|NEDCo'],['water','Water','💧','GWCL'],['cable','Cable TV','📺','DSTV|GOtv|Startimes']]),
  RegionData('KES','Kenya','KE','KSh',
    [['SAFARICOM-KE','Safaricom','🟢'],['AIRTEL-KE','Airtel','🔴'],['TELKOM-KE','Telkom','🔵']],
    ['Equity Bank','KCB Bank','Co-operative Bank','Absa Kenya','NCBA Bank','DTB Bank','Family Bank','I&M Bank','Stanbic Kenya'],
    [['electricity','Electricity','💡','Kenya Power'],['water','Water','💧','Nairobi Water|Mombasa Water'],['cable','Cable TV','📺','DSTV|GOtv|Startimes|Zuku']]),
  RegionData('ZAR','South Africa','ZA','R',
    [['VODACOM-ZA','Vodacom','🔴'],['MTN-ZA','MTN','🟡'],['CELL-ZA','Cell C','⚫'],['TELKOM-ZA','Telkom','🔵']],
    ['Standard Bank','Absa','FNB','Nedbank','Capitec','Discovery Bank','Investec','Tyme Bank'],
    [['electricity','Electricity','💡','Eskom|City Power|Cape Town Electricity'],['water','Water','💧','Johannesburg Water|Cape Town Water'],['cable','Cable TV','📺','DSTV|GOtv']]),
  RegionData('USD','United States','US','\$',
    [['ATT-US','AT&T','🔵'],['TMOBILE-US','T-Mobile','🩷'],['VERIZON-US','Verizon','🔴'],['CRICKET-US','Cricket','🟢']],
    ['Chase','Bank of America','Wells Fargo','Citibank','US Bank','Capital One','TD Bank','PNC Bank','Ally Bank','Chime'],
    [['electricity','Electricity','💡','ConEd|PG&E|Duke Energy|FPL'],['internet','Internet','🌐','Comcast Xfinity|AT&T Fiber|Verizon Fios|Spectrum'],['gas','Gas','🔥','National Grid|SoCalGas']]),
  RegionData('GBP','United Kingdom','GB','£',
    [['EE-UK','EE','🟢'],['O2-UK','O2','🔵'],['VODAFONE-UK','Vodafone','🔴'],['THREE-UK','Three','⚫']],
    ['Barclays','HSBC','Lloyds','NatWest','Santander UK','Halifax','Monzo','Revolut','Starling Bank'],
    [['electricity','Electricity','💡','British Gas|EDF Energy|E.ON|Scottish Power'],['internet','Internet','🌐','BT Broadband|Sky Broadband|Virgin Media|TalkTalk'],['gas','Gas','🔥','British Gas|E.ON|EDF Energy']]),
  RegionData('EUR','Europe','DE','€',
    [['VODAFONE-EU','Vodafone','🔴'],['ORANGE-EU','Orange','🟠'],['TMOBILE-EU','T-Mobile','🩷'],['O2-EU','O2','🔵']],
    ['Deutsche Bank','BNP Paribas','Santander','ING','HSBC Europe','UniCredit','Société Générale','N26'],
    [['electricity','Electricity','💡','EDF|E.ON|Vattenfall|Iberdrola|Enel'],['internet','Internet','🌐','Deutsche Telekom|Orange|Telecom Italia']]),
  RegionData('INR','India','IN','₹',
    [['JIO-IN','Jio','🔵'],['AIRTEL-IN','Airtel','🔴'],['VI-IN','Vi','🟣'],['BSNL-IN','BSNL','🟠']],
    ['SBI','HDFC Bank','ICICI Bank','Axis Bank','Kotak Mahindra','Punjab National Bank','Bank of Baroda','Paytm Payments Bank'],
    [['electricity','Electricity','💡','TATA Power|Adani Electricity|BSES|MSEDCL'],['cable','Cable TV','📺','Tata Play|Airtel DTH|Sun Direct|Dish TV'],['gas','Gas (LPG)','🔥','HP Gas|Bharat Gas|Indane']]),
  RegionData('AED','UAE','AE','AED',
    [['ETISALAT-AE','e&','🟢'],['DU-AE','du','🟣']],
    ['Emirates NBD','ADCB','FAB','Dubai Islamic Bank','Mashreq','ADIB','RAKBank','Commercial Bank of Dubai'],
    [['electricity','Electricity & Water','💡','DEWA|SEWA|ADDC|FEWA'],['internet','Internet','🌐','Etisalat eLife|du Home']]),
  RegionData('CAD','Canada','CA','CA\$',
    [['ROGERS-CA','Rogers','🔴'],['BELL-CA','Bell','🔵'],['TELUS-CA','Telus','🟢'],['FREEDOM-CA','Freedom','🟣']],
    ['RBC','TD Bank','Scotiabank','BMO','CIBC','National Bank','Tangerine','EQ Bank','Simplii'],
    [['electricity','Electricity','💡','Hydro One|BC Hydro|Hydro-Quebec|Epcor'],['internet','Internet','🌐','Rogers Internet|Bell Internet|Telus Internet']]),
  RegionData('AUD','Australia','AU','A\$',
    [['TELSTRA-AU','Telstra','🔵'],['OPTUS-AU','Optus','🟡'],['VODAFONE-AU','Vodafone','🔴'],['TPG-AU','TPG','⚫']],
    ['CBA','ANZ','Westpac','NAB','Macquarie','ING Australia','Bendigo Bank','Bank of Queensland'],
    [['electricity','Electricity','💡','AGL|Origin Energy|Energy Australia'],['internet','Internet','🌐','Telstra|Optus|TPG|Aussie Broadband']]),
  RegionData('JPY','Japan','JP','¥',
    [['DOCOMO-JP','NTT Docomo','🔴'],['SOFTBANK-JP','SoftBank','⚫'],['AU-JP','au (KDDI)','🟠'],['RAKUTEN-JP','Rakuten','🩷']],
    ['Japan Post Bank','MUFG','SMBC','Mizuho','Rakuten Bank','PayPay Bank','Resona Bank'],
    [['electricity','Electricity','💡','TEPCO|Kansai Electric|Chubu Electric'],['internet','Internet','🌐','NTT Flets|SoftBank Hikari|au Hikari|NURO']]),
  RegionData('SGD','Singapore','SG','S\$',
    [['SINGTEL-SG','Singtel','🔴'],['STARHUB-SG','StarHub','🟢'],['M1-SG','M1','🔵'],['TPG-SG','TPG','🟣']],
    ['DBS','OCBC','UOB','Standard Chartered SG','Citibank SG','CIMB Singapore'],
    [['electricity','Electricity','💡','SP Group|Geneco|Sembcorp'],['internet','Internet','🌐','Singtel Fibre|StarHub Fibre|M1 Fibre']]),
  RegionData('EGP','Egypt','EG','E£',
    [['ORANGE-EG','Orange','🟠'],['VODAFONE-EG','Vodafone','🔴'],['ETISALAT-EG','Etisalat','🟢'],['WE-EG','WE','🔵']],
    ['National Bank of Egypt','Banque Misr','CIB','QNB Egypt','HSBC Egypt','Bank of Alexandria'],
    [['electricity','Electricity','💡','Cairo Electricity|Alexandria Electricity'],['internet','Internet','🌐','TE Data|Orange Home|Vodafone Home']]),
  RegionData('SAR','Saudi Arabia','SA','SAR',
    [['STC-SA','STC','🟣'],['MOBILY-SA','Mobily','🟢'],['ZAIN-SA','Zain','🔵']],
    ['Al Rajhi Bank','NCB','Riyad Bank','Alinma Bank','SABB','Banque Saudi Fransi','STC Pay'],
    [['electricity','Electricity','💡','SEC'],['water','Water','💧','NWC'],['internet','Internet','🌐','STC Home|Mobily Home|Zain Home']]),
  RegionData('TRY','Turkey','TR','₺',
    [['TURKCELL-TR','Turkcell','🔵'],['VODAFONE-TR','Vodafone TR','🔴'],['TURKTELEKOM-TR','Turk Telekom','🟠']],
    ['Ziraat Bank','Is Bank','Garanti BBVA','Akbank','Yapi Kredi','Halkbank','Papara'],
    [['electricity','Electricity','💡','BEDAS|AYEDAS|TOROSLAR'],['internet','Internet','🌐','Turk Telekom ADSL|Superonline|Turkcell Superbox']]),
  RegionData('MXN','Mexico','MX','MX\$',
    [['TELCEL-MX','Telcel','🔵'],['MOVISTAR-MX','Movistar','🟢'],['ATT-MX','AT&T Mexico','🔵']],
    ['BBVA Mexico','Banamex','Santander Mexico','Banorte','HSBC Mexico','Scotiabank Mexico','Nu Mexico'],
    [['electricity','Electricity','💡','CFE'],['internet','Internet','🌐','Telmex|Izzi|Total Play|Megacable']]),
  RegionData('IDR','Indonesia','ID','Rp',
    [['TELKOMSEL-ID','Telkomsel','🔴'],['INDOSAT-ID','Indosat','🟡'],['XL-ID','XL Axiata','🔵']],
    ['BCA','BRI','Mandiri','BNI','CIMB Niaga','GoPay (GoTo)','OVO','DANA'],
    [['electricity','Electricity','💡','PLN'],['internet','Internet','🌐','IndiHome|Biznet|FirstMedia']]),
  RegionData('PHP','Philippines','PH','₱',
    [['GLOBE-PH','Globe','🔵'],['SMART-PH','Smart','🟢'],['DITO-PH','DITO','🟠']],
    ['BDO','BPI','Metrobank','Landbank','PNB','Security Bank','GCash (Mynt)','Maya'],
    [['electricity','Electricity','💡','Meralco|VECO|DLPC'],['internet','Internet','🌐','PLDT Home|Globe At Home|Converge|Sky Fiber']]),
  RegionData('MYR','Malaysia','MY','RM',
    [['MAXIS-MY','Maxis','🔵'],['CELCOM-MY','Celcom','🟡'],['DIGI-MY','Digi','🟡'],['UMOBILE-MY','U Mobile','🟢']],
    ['Maybank','CIMB','Public Bank','RHB','Hong Leong Bank','AmBank','Bank Islam','Touch n Go e-Wallet'],
    [['electricity','Electricity','💡','TNB|SESB'],['internet','Internet','🌐','unifi|Maxis Home|TIME']]),
  RegionData('BRL','Brazil','BR','R\$',
    [['VIVO-BR','Vivo','🟣'],['CLARO-BR','Claro','🔴'],['TIM-BR','TIM','🔵']],
    ['Banco do Brasil','Itau','Bradesco','Caixa','Santander Brasil','Nubank','Inter Bank'],
    [['electricity','Electricity','💡','Enel|Cemig|Copel|Light'],['internet','Internet','🌐','Vivo Fibra|Claro Net|TIM Live']]),
  RegionData('ZMW','Zambia','ZM','ZK',
    [['MTN-ZM','MTN','🟡'],['AIRTEL-ZM','Airtel','🔴'],['ZAMTEL-ZM','Zamtel','🟢']],
    ['Zanaco','Standard Chartered Zambia','Stanbic Zambia','FNB Zambia','Absa Zambia','UBA Zambia'],
    [['electricity','Electricity','💡','ZESCO'],['cable','Cable TV','📺','DSTV|GOtv|Startimes']]),
  RegionData('UGX','Uganda','UG','USh',
    [['MTN-UG','MTN','🟡'],['AIRTEL-UG','Airtel','🔴'],['AFRICELL-UG','Africell','🔵']],
    ['Stanbic Uganda','DFCU Bank','Centenary Bank','Equity Bank Uganda','Absa Uganda','Housing Finance Bank'],
    [['electricity','Electricity','💡','UMEME|Yaka'],['cable','Cable TV','📺','DSTV|GOtv|Startimes']]),
  RegionData('TZS','Tanzania','TZ','TSh',
    [['VODACOM-TZ','Vodacom','🔴'],['AIRTEL-TZ','Airtel','🟠'],['TIGO-TZ','Tigo','🔵']],
    ['CRDB Bank','NMB Bank','NBC','Stanbic Tanzania','Absa Tanzania','Diamond Trust Bank Tanzania'],
    [['electricity','Electricity','💡','TANESCO'],['cable','Cable TV','📺','DSTV|Startimes|Azam TV']]),
  RegionData('RWF','Rwanda','RW','Fr',
    [['MTN-RW','MTN','🟡'],['AIRTEL-RW','Airtel','🔴']],
    ['Bank of Kigali','Equity Bank Rwanda','I&M Bank Rwanda','Ecobank Rwanda','Cogebanque'],
    [['electricity','Electricity','💡','REG|EUCL'],['cable','Cable TV','📺','DSTV|GOtv|Startimes']]),
  RegionData('XOF','West Africa (CFA)','SN','CFA',
    [['ORANGE-WA','Orange','🟠'],['MTN-WA','MTN','🟡'],['MOOV-WA','Moov','🔵']],
    ['Ecobank','UBA West Africa','Bank of Africa','Coris Bank','Societe Generale West Africa'],
    [['electricity','Electricity','💡','CIE|SENELEC|SBEE'],['cable','Cable TV','📺','Canal+|Startimes']]),
  RegionData('CMR','Cameroon','CM','FCFA',
    [['MTN-CM','MTN','🟡'],['ORANGE-CM','Orange','🟠']],
    ['Afriland First Bank','Societe Generale Cameroon','Ecobank Cameroon','UBC','CCA Bank','Express Union MFI','MC2 MFI'],
    [['electricity','Electricity','💡','ENEO'],['water','Water','💧','CDE/CAMWATER']]),
  RegionData('QAR','Qatar','QA','QR',
    [['OOREDOO-QA','Ooredoo','🔴'],['VODAFONE-QA','Vodafone QA','🔴']],
    ['QNB','Commercial Bank Qatar','Doha Bank','Qatar Islamic Bank','Ahlibank Qatar'],
    [['electricity','Electricity & Water','💡','Kahramaa'],['internet','Internet','🌐','Ooredoo Home|Vodafone Home']]),
  RegionData('VND','Vietnam','VN','₫',
    [['VIETTEL-VN','Viettel','🔴'],['VINAPHONE-VN','Vinaphone','🔵'],['MOBIFONE-VN','Mobifone','🟢']],
    ['Vietcombank','Agribank','BIDV','VietinBank','Techcombank','MB Bank','MoMo'],
    [['electricity','Electricity','💡','EVN|EVNHANOI|EVNHCMC'],['internet','Internet','🌐','Viettel Fiber|VNPT Fiber|FPT Telecom']]),
  RegionData('THB','Thailand','TH','฿',
    [['AIS-TH','AIS','🟢'],['DTAC-TH','DTAC','🔵'],['TRUE-TH','True Move','🔴']],
    ['Bangkok Bank','Kasikorn Bank','SCB','Krungthai Bank','UOB Thailand','PromptPay'],
    [['electricity','Electricity','💡','MEA|PEA'],['internet','Internet','🌐','True Online|AIS Fibre|3BB']]),
  RegionData('PKR','Pakistan','PK','₨',
    [['JAZZ-PK','Jazz','🟠'],['TELENOR-PK','Telenor','🔵'],['ZONG-PK','Zong','🔴'],['UFONE-PK','Ufone','🟢']],
    ['HBL','MCB Bank','UBL','Allied Bank','Meezan Bank','Bank Alfalah','EasyPaisa','JazzCash'],
    [['electricity','Electricity','💡','LESCO|KESC|IESCO|GEPCO|FESCO'],['gas','Gas','🔥','SSGC|SNGPL']]),
  RegionData('MAD','Morocco','MA','MAD',
    [['MAROCTELECOM-MA','Maroc Telecom','🟢'],['ORANGE-MA','Orange','🟠'],['INWI-MA','Inwi','🔵']],
    ['Attijariwafa Bank','Banque Populaire','BMCE Bank','CIH Bank','BMCI','Al Barid Bank'],
    [['electricity','Electricity','💡','ONEE|Redal|Amendis|Lydec'],['internet','Internet','🌐','Maroc Telecom ADSL|Inwi Box|Orange Fibre']]),
  RegionData('ETB','Ethiopia','ET','Br',
    [['ETHIOTELECOM-ET','Ethio Telecom','🟢'],['SAFARICOM-ET','Safaricom ET','🔵']],
    ['Commercial Bank of Ethiopia','Dashen Bank','Awash Bank','Abyssinia Bank','Wegagen Bank'],
    [['electricity','Electricity','💡','EEU'],['cable','Cable TV','📺','ETV|DSTV|Startimes']]),
  RegionData('ZWL','Zimbabwe','ZW','Z\$',
    [['ECONET-ZW','Econet','🔵'],['NETONE-ZW','NetOne','🟢'],['TELECEL-ZW','Telecel','🔴']],
    ['CBZ Bank','Stanbic Zimbabwe','FBC Bank','ZB Bank','Steward Bank','EcoCash'],
    [['electricity','Electricity','💡','ZESA'],['cable','Cable TV','📺','DSTV|GOtv|Startimes|ZBC']]),
  RegionData('COP','Colombia','CO','COL\$',
    [['CLARO-CO','Claro','🔴'],['MOVISTAR-CO','Movistar','🟢'],['TIGO-CO','Tigo','🔵']],
    ['Bancolombia','Davivienda','Banco de Bogota','BBVA Colombia','Nequi','Daviplata'],
    [['electricity','Electricity','💡','EPM|Codensa|Electricaribe'],['internet','Internet','🌐','Claro Hogar|Movistar Hogar|ETB']]),
  RegionData('ARS','Argentina','AR','AR\$',
    [['CLARO-AR','Claro','🔴'],['PERSONAL-AR','Personal','🔵'],['MOVISTAR-AR','Movistar','🟢']],
    ['Banco Nacion','Santander Argentina','BBVA Argentina','Galicia','Macro','Brubank','Mercado Pago'],
    [['electricity','Electricity','💡','Edenor|Edesur|EPEC'],['gas','Gas','🔥','Metrogas|Camuzzi']]),
];

RegionData regionFor(String c) =>
    kRegions.firstWhere((r) => r.currency == c, orElse: () => kRegions.first);

// ── CURRENCY CONVERTER ────────────────────────────────────────────────────────

class FxService {
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
        _r    = Map<String, double>.from(
            (d['rates'] as Map).map((k, v) => MapEntry('$k', (v as num).toDouble())));
        _base = base;
        _ts   = DateTime.now();
      }
    } catch (_) {}
  }

  static double? convert(double amount, String from, String to) {
    if (_base.isEmpty || from == to) return from == to ? amount : null;
    final inBase = from == _base ? amount : amount / (_r[from] ?? 1);
    if (to == _base) return inBase;
    final rate = _r[to]; return rate == null ? null : inBase * rate;
  }

  static double? rate(String from, String to) {
    if (_base.isEmpty || from == to) return from == to ? 1 : null;
    final f = _r[from], t = _r[to];
    return (f == null || t == null) ? null : t / f;
  }
}

// ── MAIN SCREEN ───────────────────────────────────────────────────────────────

class XamePayScreen extends StatefulWidget {
  final String userId, serverUrl, userName;
  const XamePayScreen({
    super.key,
    required this.userId,
    required this.serverUrl,
    this.userName = '',
  });
  @override State<XamePayScreen> createState() => _XamePayScreenState();
}

class _XamePayScreenState extends State<XamePayScreen>
    with SingleTickerProviderStateMixin {
  String _currency = 'NGN', _dispCurrency = 'NGN';
  double _balance  = 0;
  bool   _loading  = true, _serverOk = false;
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
      _currency     = p.getString('wallet:currency')        ?? 'NGN';
      _dispCurrency = p.getString('wallet:dispCurrency')    ?? _currency;
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
      _serverOk = d['configured'] == true;
      final p = await SharedPreferences.getInstance();
      if (d['currency'] != null && p.getString('wallet:currency') == null)
        _currency = d['currency'];
    } catch (_) {}
    await _loadWallet();
    await FxService.load(_currency);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadWallet() async {
    try {
      final r = await http
          .get(Uri.parse('${widget.serverUrl}/api/wallet/me?userId=${widget.userId}'))
          .timeout(const Duration(seconds: 8));
      final d = jsonDecode(r.body);
      if (d['status'] == 'success') {
        setState(() {
          _balance = (d['balance'] as num?)?.toDouble() ?? 0;
          _txs = (d['transactions'] as List? ?? [])
              .map((t) => WalletTx.fromJson(t)).toList();
        });
      }
    } catch (_) {}
  }

  RegionData get _region => regionFor(_currency);
  String _fmt(double n) => '${_region.symbol}${_fmtNum(n)}';
  static String _fmtNum(double n) {
    final s = n.toStringAsFixed(2);
    final i = s.split('.')[0], d = s.split('.')[1];
    final buf = StringBuffer();
    int c = 0;
    for (int j = i.length - 1; j >= 0; j--) {
      if (c > 0 && c % 3 == 0) buf.write(',');
      buf.write(i[j]); c++;
    }
    return '${buf.toString().split('').reversed.join()}.$d';
  }

  String _convertedLine() {
    if (_dispCurrency == _currency) return '';
    final v = FxService.convert(_balance, _currency, _dispCurrency);
    if (v == null) return '';
    final dr = regionFor(_dispCurrency);
    return '≈ ${dr.symbol}${_fmtNum(v)} $_dispCurrency';
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kCard, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          Text('💳', style: TextStyle(fontSize: 18)),
          SizedBox(width: 6),
          Text('XamePay',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
        ]),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.tune, color: kTeal), onPressed: _showSettings),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kTeal))
          : Column(children: [
              _balanceCard(),
              _tabBar(),
              Expanded(child: TabBarView(
                controller: _tab,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _AirtimeTab(region: _region, balance: _balance,
                      serverUrl: widget.serverUrl, userId: widget.userId,
                      fmt: _fmt, onSuccess: _loadWallet, snack: _snack),
                  _DataTab(region: _region, balance: _balance,
                      serverUrl: widget.serverUrl, userId: widget.userId,
                      fmt: _fmt, onSuccess: _loadWallet, snack: _snack),
                  _BillsTab(region: _region, balance: _balance,
                      serverUrl: widget.serverUrl, userId: widget.userId,
                      currency: _currency, fmt: _fmt,
                      onSuccess: _loadWallet, snack: _snack),
                  _SendTab(region: _region, balance: _balance,
                      serverUrl: widget.serverUrl, userId: widget.userId,
                      currency: _currency, fmt: _fmt,
                      onSuccess: _loadWallet, snack: _snack),
                  _HistoryTab(txs: _txs, fmt: _fmt),
                ],
              )),
            ]),
    );
  }

  Widget _balanceCard() {
    final conv = _convertedLine();
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
            style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 12, letterSpacing: 1)),
        const SizedBox(height: 8),
        Text(_fmt(_balance),
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
        if (conv.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4),
              child: Text(conv, style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 13))),
        Text('XamePay • $_currency',
            style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12)),
        const SizedBox(height: 20),
        Row(children: [
          _cBtn('+ Add Money', () => _showAddMoney()),
          const SizedBox(width: 8),
          _cBtn('↗ Send',      () => _tab.animateTo(3)),
          const SizedBox(width: 8),
          _cBtn('📊 History',  () => _tab.animateTo(4)),
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
        child: Text(l,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    ),
  );

  Widget _tabBar() => Container(
    color: kCard,
    child: TabBar(
      controller: _tab, isScrollable: true, tabAlignment: TabAlignment.start,
      indicatorColor: kTeal, labelColor: kTeal, unselectedLabelColor: kMuted,
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      tabs: const [Tab(text:'📱 Airtime'),Tab(text:'📶 Data'),
                   Tab(text:'🧾 Bills'), Tab(text:'💸 Send'),Tab(text:'📊 History')],
    ),
  );

  void _showAddMoney() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddMoneySheet(
        userId: widget.userId, serverUrl: widget.serverUrl,
        currency: _currency, serverConfigured: _serverOk,
        onFunded: (a) { setState(() => _balance += a); _loadWallet(); _snack('✅ +${_fmt(a)}'); },
      ),
    );
  }

  void _showSettings() {
    String tc = _currency, td = _dispCurrency;
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) =>
        DraggableScrollableSheet(expand: false, initialChildSize: 0.75,
          builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.all(24),
            children: [
              Row(children: [
                const Expanded(child: Text('⚙️ Wallet Settings',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(ctx)),
              ]),
              const SizedBox(height: 16),
              _sLabel('🌍 Region & Currency'),
              const SizedBox(height: 8),
              _sDrop<String>(value: tc,
                items: kRegions.map((r) => DropdownMenuItem(value: r.currency,
                    child: Text('${r.country} (${r.currency})',
                        style: const TextStyle(color: Colors.white, fontSize: 14)))).toList(),
                onChange: (v) { if (v != null) ss(() => tc = v); }),
              const SizedBox(height: 20),
              _sLabel('💱 Display Balance In'),
              const SizedBox(height: 4),
              const Text('Shows your balance converted to another currency on the balance card.',
                  style: TextStyle(color: kMuted, fontSize: 12)),
              const SizedBox(height: 8),
              _sDrop<String>(value: td,
                items: kRegions.map((r) => DropdownMenuItem(value: r.currency,
                    child: Text('${r.symbol} ${r.currency} — ${r.country}',
                        style: const TextStyle(color: Colors.white, fontSize: 14)))).toList(),
                onChange: (v) { if (v != null) ss(() => td = v); }),
              if (tc != td)
                FutureBuilder(future: FxService.load(tc), builder: (_, __) {
                  final rv = FxService.rate(tc, td);
                  final dr = regionFor(td);
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
                      style: const TextStyle(color: kTeal, fontSize: 13)),
                  );
                }),
              const SizedBox(height: 28),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kTeal,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  setState(() { _currency = tc; _dispCurrency = td; });
                  await _savePrefs();
                  try {
                    await http.post(
                      Uri.parse('${widget.serverUrl}/api/wallet/currency'),
                      headers: {'Authorization': 'Bearer FLWPUBK_YOUR_KEY', 'Content-Type': 'application/json'},
                      body: jsonEncode({'userId': widget.userId, 'currency': _currency}),
                    );
                  } catch (_) {}
                  await FxService.load(_currency);
                  if (mounted) { Navigator.pop(ctx); _snack('✅ Settings saved'); }
                },
                child: const Text('Save Settings',
                    style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _sLabel(String t) => Text(t,
      style: const TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1));

  static Widget _sDrop<T>({required T value, required List<DropdownMenuItem<T>> items,
      required void Function(T?) onChange}) =>
    DropdownButtonFormField<T>(
      value: value, isExpanded: true,
      dropdownColor: kBg,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        filled: true, fillColor: kCard,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      items: items, onChanged: onChange,
    );
}

// ── ADD MONEY SHEET ───────────────────────────────────────────────────────────

class _AddMoneySheet extends StatelessWidget {
  final String userId, serverUrl, currency;
  final bool serverConfigured;
  final void Function(double) onFunded;
  const _AddMoneySheet({required this.userId, required this.serverUrl,
      required this.currency, required this.serverConfigured, required this.onFunded});

  static const _methods = [
    ['💳','Debit / Credit Card','Instant • Visa, Mastercard, Verve'],
    ['🏦','Bank Transfer','Instant • Virtual account'],
    ['📟','USSD','No internet needed'],
    ['📥','Receive from Contact','From another XamePage user'],
  ];

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false, initialChildSize: 0.55,
    builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.all(24),
      children: [
        const Text('💳 Add Money',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        ..._methods.map((m) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12)),
              child: Row(children: [
                Text(m[0], style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m[1], style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(m[2], style: const TextStyle(color: kMuted, fontSize: 12)),
                ])),
                const Icon(Icons.chevron_right, color: kMuted),
              ]),
            ),
          ),
        )),
      ],
    ),
  );
}

// ── SEND TAB — banks + microfinances restored ─────────────────────────────────

class _SendTab extends StatefulWidget {
  final RegionData region; final double balance;
  final String serverUrl, userId, currency;
  final String Function(double) fmt;
  final Future<void> Function() onSuccess;
  final void Function(String) snack;
  const _SendTab({required this.region, required this.balance, required this.serverUrl,
      required this.userId, required this.currency, required this.fmt,
      required this.onSuccess, required this.snack});
  @override State<_SendTab> createState() => _SendTabState();
}

class _SendTabState extends State<_SendTab> {
  bool _bankMode = false, _loadingBanks = true;
  List<BankItem> _banks = [], _filtered = [];
  BankItem? _selBank;
  String _accNum = '', _accName = '', _resolved = '';
  bool _resolving = false;
  double _amount = 0;
  final _accCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();
  final _srchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _fetchBanks(); }

  @override
  void dispose() { _accCtrl.dispose(); _amtCtrl.dispose(); _srchCtrl.dispose(); super.dispose(); }

  static const _ccMap = {
    'NGN':'NG','GHS':'GH','KES':'KE','ZAR':'ZA','TZS':'TZ','UGX':'UG',
    'ZMW':'ZM','RWF':'RW','ETB':'ET','USD':'US','GBP':'GB','EUR':'DE',
    'INR':'IN','CAD':'CA','AUD':'AU','MXN':'MX','BRL':'BR','PHP':'PH',
    'MYR':'MY','EGP':'EG','MAD':'MA','XOF':'SN','CMR':'CM',
  };

  Future<void> _fetchBanks() async {
    final cc = _ccMap[widget.currency] ?? 'NG';
    try {
      final r = await http.get(
          Uri.parse('https://api.flutterwave.com/v3/banks/NG'), headers: {'Authorization': 'Bearer FLWPUBK_YOUR_KEY'})
          .timeout(const Duration(seconds: 8));
      final d = jsonDecode(r.body);
      if (d['status'] == 'success' && (d['data'] as List).isNotEmpty) {
        final list = (d['data'] as List).map((b) => BankItem.fromJson(b)).toList();
        setState(() { _banks = list; _filtered = list; _loadingBanks = false; });
        return;
      }
    } catch (_) {}
    // fallback to local list (includes microfinances)
    final local = widget.region.banks.map((n) => BankItem(n, n)).toList();
    setState(() { _banks = local; _filtered = local; _loadingBanks = false; });
  }

  void _filter(String q) => setState(() {
    _filtered = q.isEmpty ? _banks
        : _banks.where((b) => b.name.toLowerCase().contains(q.toLowerCase())).toList();
  });

  Future<void> _resolve() async {
    if (_accNum.length < 10 || _selBank == null) return;
    setState(() { _resolving = true; _resolved = 'Verifying…'; });
    try {
      final r = await http.post(
        Uri.parse('${widget.serverUrl}/api/wallet/resolve'),
        headers: {'Authorization': 'Bearer FLWPUBK_YOUR_KEY', 'Content-Type':'application/json'},
        body: jsonEncode({'account_number':_accNum,'account_bank':_selBank!.code,'currency':widget.currency}),
      ).timeout(const Duration(seconds: 10));
      final d = jsonDecode(r.body);
      setState(() {
        _resolving = false;
        if (d['status'] == 'success') {
          _resolved = '✅ ${d['account_name']}';
          _accName  = d['account_name'] ?? '';
        } else { _resolved = '⚠️ Could not verify — proceed with caution'; }
      });
    } catch (_) { setState(() { _resolving = false; _resolved = '⚠️ Verification unavailable'; }); }
  }

  Future<void> _send() async {
    if (_selBank == null) { widget.snack('Select a bank'); return; }
    if (_accNum.length < 6) { widget.snack('Enter account number'); return; }
    if (_amount < 1)        { widget.snack('Enter a valid amount'); return; }
    if (_amount > widget.balance) { widget.snack('Insufficient balance'); return; }
    widget.snack('Processing transfer…');
    try {
      final r = await http.post(
        Uri.parse('${widget.serverUrl}/api/wallet/send-bank'),
        headers: {'Authorization': 'Bearer FLWPUBK_YOUR_KEY', 'Content-Type':'application/json'},
        body: jsonEncode({'account_bank':_selBank!.code,'account_number':_accNum,
            'amount':_amount,'currency':widget.currency,'narration':'XamePay Transfer',
            'accName':_accName,'userId':widget.userId}),
      ).timeout(const Duration(seconds: 20));
      final d = jsonDecode(r.body);
      if (d['status'] == 'success') { await widget.onSuccess(); widget.snack('✅ Transfer successful!'); }
      else { widget.snack('❌ ${d['message'] ?? 'Transfer failed'}'); }
    } catch (_) { widget.snack('❌ Network error'); }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('💸 Send Money',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Send to contacts or any bank in the world',
          style: TextStyle(color: kMuted, fontSize: 13)),
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
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10)),
          child: const Center(child: Text(
              'Select a contact from the Contacts module to send.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kMuted, fontSize: 13))),
        ),
      ] else ...[
        // ── Bank search ────────────────────────────────────────────────────
        const Text('Select Bank', style: TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _xf(_srchCtrl, '🔍 Search bank or microfinance…', TextInputType.text, (v) {
          _filter(v);
          if (_selBank != null) setState(() { _selBank = null; });
        }),
        if (_selBank != null) ...[
          const SizedBox(height: 8),
          _chip('✅ ${_selBank!.name}'),
        ] else if (!_loadingBanks) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10)),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _filtered.length,
              itemBuilder: (_, i) => InkWell(
                onTap: () {
                  setState(() { _selBank = _filtered[i]; _srchCtrl.text = _filtered[i].name; });
                  if (_accNum.length >= 10) _resolve();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
                  child: Text(_filtered[i].name,
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                ),
              ),
            ),
          ),
        ] else
          const Padding(padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(color: kTeal, strokeWidth: 2))),
        const SizedBox(height: 16),
        // ── Account number ────────────────────────────────────────────────
        const Text('Account Number', style: TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _xf(_accCtrl, 'Enter account number', TextInputType.number, (v) {
          _accNum = v; if (v.length >= 10) _resolve();
        }),
        if (_resolving)
          const Padding(padding: EdgeInsets.only(bottom: 8),
              child: Text('Verifying…', style: TextStyle(color: kMuted, fontSize: 12))),
        if (!_resolving && _resolved.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10)),
            child: Text(_resolved,
                style: TextStyle(
                    color: _resolved.startsWith('✅') ? kTeal : const Color(0xFFF0A500),
                    fontSize: 13)),
          ),
        const SizedBox(height: 8),
      ],
      const Text('Amount', style: TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      _xf(_amtCtrl, 'Enter amount',
          const TextInputType.numberWithOptions(decimal: true), (v) => _amount = double.tryParse(v) ?? 0),
      const SizedBox(height: 6),
      Text('Balance: ${widget.fmt(widget.balance)}',
          style: const TextStyle(color: kMuted, fontSize: 12)),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: kTeal, padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          onPressed: _bankMode ? _send : () => widget.snack('Select a contact'),
          child: const Text('Send Money',
              style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );

  Widget _tog(String l, bool on, VoidCallback f) => Expanded(
    child: GestureDetector(onTap: f,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10), alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? kTeal : kCard, borderRadius: BorderRadius.circular(10),
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
    decoration: BoxDecoration(
      color: const Color(0x1A00B0A0), borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0x3300B0A0)),
    ),
    child: Text(t, style: const TextStyle(color: kTeal, fontSize: 13, fontWeight: FontWeight.w600)),
  );
}

// ── AIRTIME TAB ───────────────────────────────────────────────────────────────

class _AirtimeTab extends StatefulWidget {
  final RegionData region; final double balance;
  final String serverUrl, userId;
  final String Function(double) fmt;
  final Future<void> Function() onSuccess;
  final void Function(String) snack;
  const _AirtimeTab({required this.region, required this.balance, required this.serverUrl,
      required this.userId, required this.fmt, required this.onSuccess, required this.snack});
  @override State<_AirtimeTab> createState() => _AirtimeTabState();
}

class _AirtimeTabState extends State<_AirtimeTab> {
  String? _net; String _phone = '', _amt = '';
  final _pCtrl = TextEditingController();
  final _aCtrl = TextEditingController();
  @override void dispose() { _pCtrl.dispose(); _aCtrl.dispose(); super.dispose(); }

  Future<void> _buy() async {
    if (_net == null) { widget.snack('Select a network'); return; }
    if (_phone.length < 6) { widget.snack('Enter valid phone number'); return; }
    final a = double.tryParse(_amt) ?? 0;
    if (a < 1) { widget.snack('Enter amount'); return; }
    if (a > widget.balance) { widget.snack('Insufficient balance'); return; }
    widget.snack('Processing…');
    try {
      final r = await http.post(Uri.parse('${widget.serverUrl}/api/wallet/airtime'),
          headers: {'Authorization': 'Bearer FLWPUBK_YOUR_KEY', 'Content-Type':'application/json'},
          body: jsonEncode({'phone':_phone,'operatorId':_net,'amount':a,'userId':widget.userId}))
          .timeout(const Duration(seconds: 15));
      final d = jsonDecode(r.body);
      if (d['status'] == 'success') { await widget.onSuccess(); widget.snack('✅ Airtime sent!'); }
      else { widget.snack('❌ ${d['message'] ?? 'Failed'}'); }
    } catch (_) { widget.snack('❌ Network error'); }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('📱 Buy Airtime',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 20),
      const Text('Select Network', style: TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      GridView.count(crossAxisCount: 4, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.9,
        children: widget.region.networks.map((n) => GestureDetector(
          onTap: () => setState(() => _net = n[0]),
          child: Container(
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _net == n[0] ? kTeal : Colors.white12, width: 2)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(n[2], style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 4),
              Text(n[1], style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        )).toList(),
      ),
      const SizedBox(height: 16),
      const Text('Phone Number', style: TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      _xf(_pCtrl, 'Enter phone number', TextInputType.phone, (v) => _phone = v),
      const SizedBox(height: 16),
      const Text('Amount', style: TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      GridView.count(crossAxisCount: 3, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 2.5,
        children: [50,100,200,500,1000,2000].map((a) => GestureDetector(
          onTap: () { setState(() => _amt = '$a'); _aCtrl.text = '$a'; },
          child: Container(alignment: Alignment.center,
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _amt == '$a' ? kTeal : Colors.white12)),
            child: Text(widget.fmt(a.toDouble()),
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        )).toList(),
      ),
      const SizedBox(height: 8),
      _xf(_aCtrl, 'Or enter custom amount',
          const TextInputType.numberWithOptions(decimal: true), (v) => _amt = v),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kTeal,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          onPressed: _buy,
          child: const Text('Buy Airtime',
              style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );
}

// ── DATA TAB ──────────────────────────────────────────────────────────────────

class _DataTab extends StatefulWidget {
  final RegionData region; final double balance;
  final String serverUrl, userId;
  final String Function(double) fmt;
  final Future<void> Function() onSuccess;
  final void Function(String) snack;
  const _DataTab({required this.region, required this.balance, required this.serverUrl,
      required this.userId, required this.fmt, required this.onSuccess, required this.snack});
  @override State<_DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<_DataTab> {
  String? _net;
  final _pCtrl = TextEditingController();
  @override void dispose() { _pCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('📶 Buy Data',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 20),
      const Text('Select Network', style: TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      GridView.count(crossAxisCount: 4, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.9,
        children: widget.region.networks.map((n) => GestureDetector(
          onTap: () => setState(() => _net = n[0]),
          child: Container(
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _net == n[0] ? kTeal : Colors.white12, width: 2)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(n[2], style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 4),
              Text(n[1], style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        )).toList(),
      ),
      const SizedBox(height: 16),
      const Text('Phone Number', style: TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      _xf(_pCtrl, 'Enter phone number', TextInputType.phone, (_) {}),
      const SizedBox(height: 16),
      if (_net != null) ...[
        const Text('Plans loaded from server per network (callReloadly data API).',
            style: TextStyle(color: kMuted, fontSize: 12)),
      ],
    ]),
  );
}

// ── BILLS TAB ─────────────────────────────────────────────────────────────────

class _BillsTab extends StatelessWidget {
  final RegionData region; final double balance;
  final String serverUrl, userId, currency;
  final String Function(double) fmt;
  final Future<void> Function() onSuccess;
  final void Function(String) snack;
  const _BillsTab({required this.region, required this.balance, required this.serverUrl,
      required this.userId, required this.currency, required this.fmt,
      required this.onSuccess, required this.snack});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('🧾 Pay Bills',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 20),
      GridView.count(crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 1.3,
        children: region.bills.map((b) => GestureDetector(
          onTap: () => _billForm(context, b),
          child: Container(
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(b[2], style: const TextStyle(fontSize: 32)),
              const SizedBox(height: 10),
              Text(b[1], style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
          ),
        )).toList(),
      ),
    ]),
  );

  void _billForm(BuildContext ctx, List<String> b) {
    final providers = b[3].split('|');
    String prov = providers.first, acc = '', amtS = '';
    final aC = TextEditingController(), amC = TextEditingController();
    showModalBottomSheet(
      context: ctx, isScrollControlled: true, backgroundColor: kCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx2, ss) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom),
        child: SingleChildScrollView(padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${b[2]} ${b[1]}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            const Text('Provider', style: TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: prov, dropdownColor: kBg,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(filled: true, fillColor: kBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
              items: providers.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (v) { if (v != null) ss(() => prov = v); },
            ),
            const SizedBox(height: 16),
            const Text('Account / Meter Number', style: TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _xf(aC, 'Enter account number', TextInputType.text, (v) => acc = v),
            const SizedBox(height: 16),
            const Text('Amount', style: TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _xf(amC, 'Enter amount', const TextInputType.numberWithOptions(decimal: true), (v) => amtS = v),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kTeal,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: () async {
                  final a = double.tryParse(amtS) ?? 0;
                  if (acc.isEmpty) { snack('Enter account number'); return; }
                  if (a < 1) { snack('Enter amount'); return; }
                  Navigator.pop(ctx2);
                  try {
                    snack('Processing payment…');
                    final r = await http.post(Uri.parse('$serverUrl/api/wallet/bills/pay'),
                        headers: {'Authorization': 'Bearer FLWPUBK_YOUR_KEY', 'Content-Type':'application/json'},
                        body: jsonEncode({'userId':userId,'biller_code':b[0],
                            'item_code':b[0],'customer':acc,'amount':a,'country':region.countryCode}))
                        .timeout(const Duration(seconds: 20));
                    final d = jsonDecode(r.body);
                    if (d['status'] == 'success') { await onSuccess(); snack('✅ Bill paid!'); }
                    else { snack('❌ ${d['message'] ?? 'Payment failed'}'); }
                  } catch (_) { snack('❌ Network error'); }
                },
                child: Text('Pay ${b[1]}',
                    style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      )),
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
            style: TextStyle(color: kMuted, fontSize: 15, fontWeight: FontWeight.w600)),
      ]),
    );
    return ListView.separated(
      padding: const EdgeInsets.all(16), itemCount: txs.length,
      separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
      itemBuilder: (_, i) {
        final tx = txs[i]; final cr = tx.type == 'credit';
        return Padding(padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Container(width: 42, height: 42,
              decoration: BoxDecoration(
                color: cr ? const Color(0x1A00B0A0) : const Color(0x1AFF6464),
                shape: BoxShape.circle),
              child: Center(child: Text(tx.icon, style: const TextStyle(fontSize: 18)))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx.label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              Text('${tx.ts.substring(0,10)} • ${tx.status}',
                  style: const TextStyle(color: kMuted, fontSize: 11)),
            ])),
            Text('${cr ? '+' : '-'}${fmt(tx.amount)}',
                style: TextStyle(
                    color: cr ? kTeal : const Color(0xFFFF6464),
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
        );
      },
    );
  }
}

// ── SHARED HELPER WIDGETS ─────────────────────────────────────────────────────

Widget _xf(TextEditingController c, String hint, TextInputType kt,
    void Function(String) fn) =>
  TextField(
    controller: c, keyboardType: kt,
    style: const TextStyle(color: Colors.white, fontSize: 15),
    decoration: InputDecoration(
      hintText: hint, hintStyle: const TextStyle(color: kMuted, fontSize: 14),
      filled: true, fillColor: kCard,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kTeal)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    onChanged: fn,
  );
