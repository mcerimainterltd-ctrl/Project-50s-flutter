import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xamepage/core/config/constants.dart';

// ── Color palettes ────────────────────────────────────────────────────────────
const _skinColors  = ['#FDDBB4','#F5C89A','#E8A87C','#C68642','#8D5524','#4A2912'];
const _hairColors  = ['#1a1a1a','#2c1b0e','#6B3A2A','#A0522D','#C19A6B','#F4C842','#E8E8E8','#FF6B6B','#7B68EE'];
const _eyeColors   = ['#1a1a1a','#3B2314','#4E8098','#2D6A2D','#8B6914','#7B68EE'];
const _lipColors   = ['#C46B6B','#E88080','#FF9999','#A0522D','#8B4513','#FF6B6B'];
const _bgColors    = ['#1a3a4a','#2d1b4e','#1a4a2d','#4a1a1a','#1a2a4a','#3a3a1a','#4a2d1a','#1a4a4a'];

// ── Hair styles ───────────────────────────────────────────────────────────────
class _HairStyle {
  final String id;
  final String label;
  const _HairStyle(this.id, this.label);
}

const _hairStyles = [
  _HairStyle('short',  'Short'),
  _HairStyle('medium', 'Medium'),
  _HairStyle('long',   'Long'),
  _HairStyle('curly',  'Curly'),
  _HairStyle('bald',   'Bald'),
  _HairStyle('bun',    'Bun'),
];

// ── Accessories ───────────────────────────────────────────────────────────────
class _Accessory {
  final String id;
  final String label;
  const _Accessory(this.id, this.label);
}

const _accessories = [
  _Accessory('none',       'None'),
  _Accessory('glasses',    'Glasses'),
  _Accessory('sunglasses', 'Sunnies'),
  _Accessory('hat',        'Hat'),
  _Accessory('earrings',   'Earrings'),
  _Accessory('headband',   'Headband'),
];

// ── Avatar state ──────────────────────────────────────────────────────────────
class AvatarConfig {
  final String skin;
  final String hairColor;
  final String hairStyle;
  final String eyeColor;
  final String lipColor;
  final String accessory;
  final String bgColor;

  const AvatarConfig({
    required this.skin,
    required this.hairColor,
    required this.hairStyle,
    required this.eyeColor,
    required this.lipColor,
    required this.accessory,
    required this.bgColor,
  });

  AvatarConfig copyWith({
    String? skin, String? hairColor, String? hairStyle,
    String? eyeColor, String? lipColor, String? accessory, String? bgColor,
  }) => AvatarConfig(
    skin:      skin      ?? this.skin,
    hairColor: hairColor ?? this.hairColor,
    hairStyle: hairStyle ?? this.hairStyle,
    eyeColor:  eyeColor  ?? this.eyeColor,
    lipColor:  lipColor  ?? this.lipColor,
    accessory: accessory ?? this.accessory,
    bgColor:   bgColor   ?? this.bgColor,
  );

  static AvatarConfig get defaults => const AvatarConfig(
    skin:      '#FDDBB4',
    hairColor: '#1a1a1a',
    hairStyle: 'short',
    eyeColor:  '#1a1a1a',
    lipColor:  '#C46B6B',
    accessory: 'none',
    bgColor:   '#1a3a4a',
  );

  static AvatarConfig random() {
    final rnd = Random();
    return AvatarConfig(
      skin:      _skinColors [rnd.nextInt(_skinColors.length)],
      hairColor: _hairColors [rnd.nextInt(_hairColors.length)],
      hairStyle: _hairStyles [rnd.nextInt(_hairStyles.length)].id,
      eyeColor:  _eyeColors  [rnd.nextInt(_eyeColors.length)],
      lipColor:  _lipColors  [rnd.nextInt(_lipColors.length)],
      accessory: _accessories[rnd.nextInt(_accessories.length)].id,
      bgColor:   _bgColors   [rnd.nextInt(_bgColors.length)],
    );
  }
}

// ── SVG builder ───────────────────────────────────────────────────────────────
String buildAvatarSvg(AvatarConfig s) {
  final hair = _hairPath(s.hairStyle, s.hairColor);
  final acc  = _accessorySvg(s.accessory);
  return '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">
  <circle cx="50" cy="50" r="50" fill="${s.bgColor}"/>
  $hair
  <ellipse cx="50" cy="58" rx="28" ry="32" fill="${s.skin}"/>
  <ellipse cx="50" cy="45" rx="26" ry="28" fill="${s.skin}"/>
  <circle cx="36" cy="48" r="7" fill="white"/>
  <circle cx="64" cy="48" r="7" fill="white"/>
  <circle cx="37" cy="49" r="4" fill="${s.eyeColor}"/>
  <circle cx="65" cy="49" r="4" fill="${s.eyeColor}"/>
  <circle cx="38" cy="48" r="1.5" fill="white"/>
  <circle cx="66" cy="48" r="1.5" fill="white"/>
  <path d="M38,58 Q50,65 62,58 Q56,68 44,68Z" fill="${s.lipColor}"/>
  <path d="M38,58 Q50,62 62,58" fill="none" stroke="${s.lipColor}" stroke-width="1.5"/>
  <ellipse cx="28" cy="60" rx="6" ry="4" fill="${s.skin}" opacity="0.6"/>
  <ellipse cx="72" cy="60" rx="6" ry="4" fill="${s.skin}" opacity="0.6"/>
  <ellipse cx="28" cy="60" rx="4" ry="2.5" fill="#E88080" opacity="0.3"/>
  <ellipse cx="72" cy="60" rx="4" ry="2.5" fill="#E88080" opacity="0.3"/>
  <path d="M32,37 Q34,33 38,35" fill="none" stroke="${s.hairColor}" stroke-width="1.5" stroke-linecap="round"/>
  <path d="M62,35 Q66,33 68,37" fill="none" stroke="${s.hairColor}" stroke-width="1.5" stroke-linecap="round"/>
  $acc
</svg>''';
}

String _hairPath(String style, String color) {
  const paths = {
    'short':  'M10,35 Q20,5 50,5 Q80,5 90,35 Q75,15 50,15 Q25,15 10,35Z',
    'medium': 'M8,45 Q15,5 50,5 Q85,5 92,45 Q80,10 50,10 Q20,10 8,45Z M8,45 Q5,70 8,85 Q20,20 50,18 Q80,20 92,85 Q95,70 92,45Z',
    'long':   'M8,45 Q15,5 50,5 Q85,5 92,45 Q80,10 50,10 Q20,10 8,45Z M5,45 Q2,80 5,110 Q18,25 50,20 Q82,25 95,110 Q98,80 95,45Z',
    'curly':  'M15,40 Q10,10 30,8 Q20,20 25,30 Q35,5 50,5 Q65,5 75,30 Q80,20 70,8 Q90,10 85,40 Q78,12 50,12 Q22,12 15,40Z',
    'bun':    'M10,35 Q20,5 50,5 Q80,5 90,35 Q75,15 50,15 Q25,15 10,35Z M42,8 Q50,-5 58,8 Q55,2 50,2 Q45,2 42,8Z',
  };
  final path = paths[style];
  if (path == null || path.isEmpty) return '';
  return '<path d="$path" fill="$color"/>';
}

String _accessorySvg(String id) {
  switch (id) {
    case 'glasses':
      return '<rect x="22" y="48" width="20" height="12" rx="4" fill="none" stroke="#333" stroke-width="2"/>'
             '<rect x="58" y="48" width="20" height="12" rx="4" fill="none" stroke="#333" stroke-width="2"/>'
             '<line x1="42" y1="54" x2="58" y2="54" stroke="#333" stroke-width="2"/>'
             '<line x1="10" y1="52" x2="22" y2="52" stroke="#333" stroke-width="2"/>'
             '<line x1="78" y1="52" x2="90" y2="52" stroke="#333" stroke-width="2"/>';
    case 'sunglasses':
      return '<rect x="20" y="47" width="24" height="13" rx="4" fill="#222" opacity="0.85"/>'
             '<rect x="56" y="47" width="24" height="13" rx="4" fill="#222" opacity="0.85"/>'
             '<line x1="44" y1="53" x2="56" y2="53" stroke="#555" stroke-width="2"/>'
             '<line x1="8" y1="51" x2="20" y2="51" stroke="#555" stroke-width="2"/>'
             '<line x1="80" y1="51" x2="92" y2="51" stroke="#555" stroke-width="2"/>';
    case 'hat':
      return '<rect x="15" y="18" width="70" height="8" rx="4" fill="#333"/>'
             '<rect x="28" y="4" width="44" height="18" rx="6" fill="#333"/>';
    case 'earrings':
      return '<circle cx="12" cy="65" r="4" fill="#FFD700"/>'
             '<circle cx="88" cy="65" r="4" fill="#FFD700"/>';
    case 'headband':
      return '<path d="M12,38 Q50,28 88,38" fill="none" stroke="#FF6B6B" stroke-width="6" stroke-linecap="round"/>';
    default:
      return '';
  }
}

// ── Avatar Painter ────────────────────────────────────────────────────────────
class AvatarPainter extends StatelessWidget {
  final AvatarConfig config;
  final double size;

  const AvatarPainter({super.key, required this.config, this.size = 100});

  @override
  Widget build(BuildContext context) {
    // Render via SVG string displayed in a Container using a custom paint approach
    // We use the SVG as a data URI in an Image widget via memory
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: CustomPaint(
          size: Size(size, size),
          painter: _AvatarCustomPainter(config),
        ),
      ),
    );
  }
}

class _AvatarCustomPainter extends CustomPainter {
  final AvatarConfig config;
  _AvatarCustomPainter(this.config);

  Color _c(String hex) {
    final h = hex.replaceAll('#', '');
    final val = int.parse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return Color(val);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final paint = Paint()..isAntiAlias = true;

    // Background
    paint.color = _c(config.bgColor);
    canvas.drawCircle(Offset(50*s, 50*s), 50*s, paint);

    // Hair (back)
    _drawHair(canvas, s, paint, back: true);

    // Face
    paint.color = _c(config.skin);
    canvas.drawOval(Rect.fromCenter(
        center: Offset(50*s, 58*s), width: 56*s, height: 64*s), paint);
    canvas.drawOval(Rect.fromCenter(
        center: Offset(50*s, 45*s), width: 52*s, height: 56*s), paint);

    // Eyes white
    paint.color = Colors.white;
    canvas.drawCircle(Offset(36*s, 48*s), 7*s, paint);
    canvas.drawCircle(Offset(64*s, 48*s), 7*s, paint);

    // Iris
    paint.color = _c(config.eyeColor);
    canvas.drawCircle(Offset(37*s, 49*s), 4*s, paint);
    canvas.drawCircle(Offset(65*s, 49*s), 4*s, paint);

    // Eye shine
    paint.color = Colors.white;
    canvas.drawCircle(Offset(38*s, 48*s), 1.5*s, paint);
    canvas.drawCircle(Offset(66*s, 48*s), 1.5*s, paint);

    // Lips
    paint.color = _c(config.lipColor);
    final lipPath = Path()
      ..moveTo(38*s, 58*s)
      ..quadraticBezierTo(50*s, 65*s, 62*s, 58*s)
      ..quadraticBezierTo(56*s, 68*s, 44*s, 68*s)
      ..close();
    canvas.drawPath(lipPath, paint);

    // Cheeks
    paint.color = _c(config.skin).withOpacity(0.6);
    canvas.drawOval(Rect.fromCenter(
        center: Offset(28*s, 60*s), width: 12*s, height: 8*s), paint);
    canvas.drawOval(Rect.fromCenter(
        center: Offset(72*s, 60*s), width: 12*s, height: 8*s), paint);
    paint.color = const Color(0xFFE88080).withOpacity(0.3);
    canvas.drawOval(Rect.fromCenter(
        center: Offset(28*s, 60*s), width: 8*s, height: 5*s), paint);
    canvas.drawOval(Rect.fromCenter(
        center: Offset(72*s, 60*s), width: 8*s, height: 5*s), paint);

    // Eyebrows
    final browPaint = Paint()
      ..color = _c(config.hairColor)
      ..strokeWidth = 1.5*s
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final lb = Path()
      ..moveTo(32*s, 37*s)
      ..quadraticBezierTo(34*s, 33*s, 38*s, 35*s);
    final rb = Path()
      ..moveTo(62*s, 35*s)
      ..quadraticBezierTo(66*s, 33*s, 68*s, 37*s);
    canvas.drawPath(lb, browPaint);
    canvas.drawPath(rb, browPaint);

    // Hair (front)
    _drawHair(canvas, s, paint, back: false);

    // Accessory
    _drawAccessory(canvas, s, paint);
  }

  void _drawHair(Canvas canvas, double s, Paint paint, {required bool back}) {
    if (config.hairStyle == 'bald') return;
    if (back) return; // simplified — draw all hair in front pass
    paint.color = _c(config.hairColor);
    final path = Path();
    switch (config.hairStyle) {
      case 'short':
        path.moveTo(10*s, 35*s);
        path.quadraticBezierTo(20*s, 5*s, 50*s, 5*s);
        path.quadraticBezierTo(80*s, 5*s, 90*s, 35*s);
        path.quadraticBezierTo(75*s, 15*s, 50*s, 15*s);
        path.quadraticBezierTo(25*s, 15*s, 10*s, 35*s);
        break;
      case 'curly':
        path.moveTo(15*s, 40*s);
        path.quadraticBezierTo(10*s, 10*s, 30*s, 8*s);
        path.quadraticBezierTo(20*s, 20*s, 25*s, 30*s);
        path.quadraticBezierTo(35*s, 5*s, 50*s, 5*s);
        path.quadraticBezierTo(65*s, 5*s, 75*s, 30*s);
        path.quadraticBezierTo(80*s, 20*s, 70*s, 8*s);
        path.quadraticBezierTo(90*s, 10*s, 85*s, 40*s);
        path.quadraticBezierTo(78*s, 12*s, 50*s, 12*s);
        path.quadraticBezierTo(22*s, 12*s, 15*s, 40*s);
        break;
      default:
        path.moveTo(10*s, 35*s);
        path.quadraticBezierTo(20*s, 5*s, 50*s, 5*s);
        path.quadraticBezierTo(80*s, 5*s, 90*s, 35*s);
        path.quadraticBezierTo(75*s, 15*s, 50*s, 15*s);
        path.quadraticBezierTo(25*s, 15*s, 10*s, 35*s);
    }
    canvas.drawPath(path, paint);
  }

  void _drawAccessory(Canvas canvas, double s, Paint paint) {
    switch (config.accessory) {
      case 'glasses':
        final p = Paint()
          ..color = const Color(0xFF333333)
          ..strokeWidth = 2*s
          ..style = PaintingStyle.stroke;
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(22*s, 48*s, 20*s, 12*s), Radius.circular(4*s)), p);
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(58*s, 48*s, 20*s, 12*s), Radius.circular(4*s)), p);
        canvas.drawLine(Offset(42*s, 54*s), Offset(58*s, 54*s), p);
        break;
      case 'hat':
        paint.color = const Color(0xFF333333);
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(15*s, 18*s, 70*s, 8*s), Radius.circular(4*s)), paint);
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(28*s, 4*s, 44*s, 18*s), Radius.circular(6*s)), paint);
        break;
      case 'earrings':
        paint.color = const Color(0xFFFFD700);
        canvas.drawCircle(Offset(12*s, 65*s), 4*s, paint);
        canvas.drawCircle(Offset(88*s, 65*s), 4*s, paint);
        break;
      case 'headband':
        final p = Paint()
          ..color = const Color(0xFFFF6B6B)
          ..strokeWidth = 6*s
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        final path = Path()
          ..moveTo(12*s, 38*s)
          ..quadraticBezierTo(50*s, 28*s, 88*s, 38*s);
        canvas.drawPath(path, p);
        break;
    }
  }

  @override
  bool shouldRepaint(_AvatarCustomPainter old) => old.config != config;
}

// ── Avatar Builder Sheet ──────────────────────────────────────────────────────
class AvatarBuilderSheet extends StatefulWidget {
  final String xameId;
  final String serverUrl;
  final void Function(String dataUrl)? onSaved;

  const AvatarBuilderSheet({
    super.key,
    required this.xameId,
    required this.serverUrl,
    this.onSaved,
  });

  static Future<void> show(BuildContext context, {
    required String xameId,
    String? serverUrl,
    void Function(String dataUrl)? onSaved,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AvatarBuilderSheet(
        xameId:    xameId,
        serverUrl: serverUrl ?? AppConstants.serverUrl,
        onSaved:   onSaved,
      ),
    );
  }

  @override
  State<AvatarBuilderSheet> createState() => _AvatarBuilderSheetState();
}

class _AvatarBuilderSheetState extends State<AvatarBuilderSheet> {
  AvatarConfig _config = AvatarConfig.defaults;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: Color(0xFF111e2e),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                const Text('🎨 Avatar Builder',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Preview
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF00B0A0), width: 3),
                ),
                child: AvatarPainter(config: _config, size: 100),
              ),
            ),
          ),
          // Options
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _colorRow('Skin Tone',  _skinColors,  'skin'),
                  _styleRow('Hair Style', _hairStyles.map((h) => h.id).toList(),
                      _hairStyles.map((h) => h.label).toList(), 'hairStyle'),
                  _colorRow('Hair Color', _hairColors,  'hairColor'),
                  _colorRow('Eye Color',  _eyeColors,   'eyeColor'),
                  _colorRow('Lip Color',  _lipColors,   'lipColor'),
                  _styleRow('Accessory',
                      _accessories.map((a) => a.id).toList(),
                      _accessories.map((a) => a.label).toList(), 'accessory'),
                  _colorRow('Background', _bgColors,    'bgColor'),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        setState(() => _config = AvatarConfig.random()),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24)),
                    child: const Text('🎲 Random'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF00B0A0)),
                    child: Text(_saving ? 'Saving...' : '✓ Use Avatar'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorRow(String label, List<String> colors, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF7a9bb5),
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: colors.map((c) {
              final selected = _getVal(key) == c;
              return GestureDetector(
                onTap: () => setState(() => _setVal(key, c)),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(int.parse(
                        'FF${c.replaceAll('#', '')}', radix: 16)),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF00B0A0) : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _styleRow(String label, List<String> ids,
      List<String> labels, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF7a9bb5),
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(ids.length, (i) {
              final selected = _getVal(key) == ids[i];
              return GestureDetector(
                onTap: () => setState(() => _setVal(key, ids[i])),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF00B0A0)
                          : Colors.white12,
                    ),
                    color: selected
                        ? const Color(0xFF00B0A0).withOpacity(0.15)
                        : const Color(0xFF0d1520),
                  ),
                  child: Text(labels[i],
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12)),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  String _getVal(String key) {
    switch (key) {
      case 'skin':      return _config.skin;
      case 'hairColor': return _config.hairColor;
      case 'hairStyle': return _config.hairStyle;
      case 'eyeColor':  return _config.eyeColor;
      case 'lipColor':  return _config.lipColor;
      case 'accessory': return _config.accessory;
      case 'bgColor':   return _config.bgColor;
      default:          return '';
    }
  }

  void _setVal(String key, String val) {
    _config = _config.copyWith(
      skin:      key == 'skin'      ? val : null,
      hairColor: key == 'hairColor' ? val : null,
      hairStyle: key == 'hairStyle' ? val : null,
      eyeColor:  key == 'eyeColor'  ? val : null,
      lipColor:  key == 'lipColor'  ? val : null,
      accessory: key == 'accessory' ? val : null,
      bgColor:   key == 'bgColor'   ? val : null,
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final svg      = buildAvatarSvg(_config);
      final dataUrl  = 'data:image/svg+xml;base64,${base64Encode(utf8.encode(svg))}';
      final bytes    = await _svgToPng(svg);
      if (bytes != null) {
        final req = http.MultipartRequest(
          'POST',
          Uri.parse('${widget.serverUrl}/api/update-profile'),
        );
        req.fields['xameId'] = widget.xameId;
        req.files.add(http.MultipartFile.fromBytes(
            'profilePic', bytes, filename: 'avatar.png'));
        final res  = await req.send();
        final body = jsonDecode(await res.stream.bytesToString());
        if (body['success'] == true) {
          widget.onSaved?.call(body['profilePicUrl'] ?? dataUrl);
          if (mounted) Navigator.pop(context);
          return;
        }
      }
      // Fallback — save data URL locally
      widget.onSaved?.call(dataUrl);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('[AvatarBuilder] Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save avatar')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Uint8List?> _svgToPng(String svg) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas   = Canvas(recorder,
          const Rect.fromLTWH(0, 0, 200, 200));
      final painter  = _AvatarCustomPainter(_config);
      painter.paint(canvas, const Size(200, 200));
      final picture = recorder.endRecording();
      final img     = await picture.toImage(200, 200);
      final data    = await img.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[AvatarBuilder] PNG conversion error: $e');
      return null;
    }
  }
}
