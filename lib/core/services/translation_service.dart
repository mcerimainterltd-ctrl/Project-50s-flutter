import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xamepage/core/theme/app_theme.dart';

// ── Language list (mirrors translation.js) ────────────────────────────────────
class XameLang {
  final String code, name;
  const XameLang(this.code, this.name);
}

const kLanguages = [
  XameLang('en','English'),   XameLang('es','Spanish'),
  XameLang('fr','French'),    XameLang('ar','Arabic'),
  XameLang('zh','Chinese'),   XameLang('hi','Hindi'),
  XameLang('pt','Portuguese'),XameLang('ru','Russian'),
  XameLang('de','German'),    XameLang('ja','Japanese'),
  XameLang('ko','Korean'),    XameLang('it','Italian'),
  XameLang('tr','Turkish'),   XameLang('nl','Dutch'),
  XameLang('pl','Polish'),    XameLang('sv','Swedish'),
  XameLang('da','Danish'),    XameLang('fi','Finnish'),
  XameLang('he','Hebrew'),    XameLang('id','Indonesian'),
  XameLang('ms','Malay'),     XameLang('th','Thai'),
  XameLang('vi','Vietnamese'),XameLang('uk','Ukrainian'),
  XameLang('ro','Romanian'),  XameLang('hu','Hungarian'),
  XameLang('cs','Czech'),     XameLang('el','Greek'),
  XameLang('bn','Bengali'),   XameLang('fa','Persian'),
  XameLang('ur','Urdu'),      XameLang('sw','Swahili'),
  XameLang('yo','Yoruba'),    XameLang('ig','Igbo'),
  XameLang('ha','Hausa'),     XameLang('am','Amharic'),
  XameLang('so','Somali'),    XameLang('zu','Zulu'),
  XameLang('af','Afrikaans'), XameLang('bg','Bulgarian'),
  XameLang('hr','Croatian'),  XameLang('et','Estonian'),
  XameLang('ka','Georgian'),  XameLang('gu','Gujarati'),
  XameLang('is','Icelandic'), XameLang('kn','Kannada'),
  XameLang('km','Khmer'),     XameLang('lv','Latvian'),
  XameLang('lt','Lithuanian'),XameLang('ml','Malayalam'),
  XameLang('mr','Marathi'),   XameLang('mn','Mongolian'),
  XameLang('ne','Nepali'),    XameLang('pa','Punjabi'),
  XameLang('sr','Serbian'),   XameLang('ta','Tamil'),
  XameLang('te','Telugu'),    XameLang('tl','Filipino'),
  XameLang('uz','Uzbek'),     XameLang('cy','Welsh'),
  XameLang('no','Norwegian'), XameLang('sq','Albanian'),
];

// ── Service ───────────────────────────────────────────────────────────────────
class TranslationService {
  static Future<Map<String, dynamic>> translate(
      String text, String targetLang) async {
    try {
      final url = Uri.parse(
        'https://api.mymemory.translated.net/get'
        '?q=${Uri.encodeComponent(text)}&langpair=en|$targetLang',
      );
      final res  = await http.get(url);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['responseStatus'] == 200) {
        return {
          'success': true,
          'text': data['responseData']['translatedText'] as String,
        };
      }
      return {
        'success': false,
        'error': data['responseDetails'] ?? 'Translation failed',
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error'};
    }
  }
}

// ── Preferred language provider ───────────────────────────────────────────────
final preferredLangProvider = StateProvider<String>((ref) => 'es');

// ── Show translate bottom sheet ───────────────────────────────────────────────
Future<void> showTranslateSheet(
    BuildContext context, WidgetRef ref, String messageText) async {
  await showModalBottomSheet(
    context:      context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TranslateSheet(
      messageText: messageText,
      ref:         ref,
    ),
  );
}

class _TranslateSheet extends ConsumerStatefulWidget {
  final String messageText;
  final WidgetRef ref;
  const _TranslateSheet({required this.messageText, required this.ref});

  @override
  ConsumerState<_TranslateSheet> createState() => _TranslateSheetState();
}

class _TranslateSheetState extends ConsumerState<_TranslateSheet> {
  final _searchCtrl = TextEditingController();
  String _query         = '';
  bool   _loading       = false;
  String? _result;
  String? _error;
  String? _resultLang;

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  List<XameLang> get _filtered => _query.isEmpty
      ? kLanguages
      : kLanguages.where((l) =>
          l.name.toLowerCase().contains(_query.toLowerCase()) ||
          l.code.toLowerCase().contains(_query.toLowerCase())).toList();

  Future<void> _translate(String langCode, String langName) async {
    setState(() { _loading = true; _result = null; _error = null; });
    ref.read(preferredLangProvider.notifier).state = langCode;
    final res = await TranslationService.translate(widget.messageText, langCode);
    setState(() {
      _loading    = false;
      _resultLang = langName;
      if (res['success'] == true) {
        _result = res['text'] as String;
      } else {
        _error = res['error'] as String;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final preferred = ref.watch(preferredLangProvider);
    final langs     = _filtered;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize:     0.95,
      minChildSize:     0.5,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: context.xCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: context.xMuted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2)),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Row(children: [
              Text('🌍', style: TextStyle(fontSize: 20)),
              SizedBox(width: 10),
              Text('Translate Message',
                style: TextStyle(color: context.xText, fontSize: 17,
                    fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.close, color: context.xMuted, size: 20)),
            ]),
          ),

          // Original text
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(14),
            constraints: const BoxConstraints(maxHeight: 80),
            decoration: BoxDecoration(
              color: context.xSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: Text(widget.messageText,
                style: TextStyle(color: context.xText.withValues(alpha: 0.7), fontSize: 14,
                    height: 1.5)),
            ),
          ),

          SizedBox(height: 16),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchCtrl,
              onChanged:  (v) => setState(() => _query = v),
              style: TextStyle(color: context.xText, fontSize: 14),
              decoration: InputDecoration(
                hintText:  'Search language...',
                hintStyle: TextStyle(color: context.xMuted.withValues(alpha: 0.3)),
                prefixIcon: Icon(Icons.search, color: context.xMuted.withValues(alpha: 0.3), size: 18),
                filled:    true,
                fillColor: context.xSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
              ),
            ),
          ),

          SizedBox(height: 12),

          // Language list
          Expanded(
            child: ListView.builder(
              controller:  ctrl,
              itemCount:   langs.length,
              itemBuilder: (_, i) {
                final lang     = langs[i];
                final selected = lang.code == preferred;
                return InkWell(
                  onTap: () => _translate(lang.code, lang.name),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 13),
                    color: selected
                        ? context.xAccent.withValues(alpha: 0.1)
                        : Colors.transparent,
                    child: Row(children: [
                      Text(lang.name,
                        style: TextStyle(
                          color:      selected
                              ? context.xAccent : context.xText.withValues(alpha: 0.7),
                          fontSize:   14,
                          fontWeight: selected
                              ? FontWeight.w600 : FontWeight.normal)),
                      const Spacer(),
                      Text(lang.code.toUpperCase(),
                        style: TextStyle(
                          color:    selected
                              ? context.xAccent : context.xMuted.withValues(alpha: 0.5),
                          fontSize: 11)),
                      if (selected)
                        Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.check_circle,
                              color: context.xPrimary, size: 16)),
                    ]),
                  ),
                );
              },
            ),
          ),

          // Result
          if (_loading)
            Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(
                  color: context.xPrimary, strokeWidth: 2),
            ),

          if (_result != null)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.xAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: context.xAccent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('🌍', style: TextStyle(fontSize: 12)),
                    SizedBox(width: 6),
                    Text(_resultLang ?? '',
                      style: TextStyle(color: context.xPrimary,
                          fontSize: 11, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _result!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Translation copied!'),
                            backgroundColor: context.xAccent,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Row(children: [
                        Icon(Icons.copy_outlined,
                            color: context.xPrimary, size: 14),
                        SizedBox(width: 4),
                        Text('Copy', style: TextStyle(
                            color: context.xPrimary, fontSize: 12,
                            fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ]),
                  SizedBox(height: 8),
                  Text(_result!,
                    style: TextStyle(color: context.xText,
                        fontSize: 14, height: 1.5)),
                ],
              ),
            ),

          if (_error != null)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Text('❌ $_error',
                style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ]),
      ),
    );
  }
}
