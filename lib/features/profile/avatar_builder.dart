import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xamepage/core/config/constants.dart';
import 'package:xamepage/core/theme/app_theme.dart';

// ── Palettes ──────────────────────────────────────────────────────────────────
const _skinColors = ['#FDDBB4','#F5C89A','#E8A87C','#C68642','#8D5524','#4A2912'];
const _hairColors = ['#1a1a1a','#2c1b0e','#6B3A2A','#A0522D','#C19A6B','#F4C842',
                     '#E8E8E8','#FF6B6B','#7B68EE'];
const _eyeColors  = ['#1a1a1a','#3B2314','#4E8098','#2D6A2D','#8B6914','#7B68EE'];
const _lipColors  = ['#C46B6B','#E88080','#FF9999','#A0522D','#8B4513','#FF6B6B'];
const _bgColors   = ['#1a3a4a','#2d1b4e','#1a4a2d','#4a1a1a','#1a2a4a',
                     '#3a3a1a','#4a2d1a','#1a4a4a'];

class _HairStyle { final String id, label; const _HairStyle(this.id, this.label); }
class _Accessory  { final String id, label; const _Accessory(this.id, this.label); }

const _hairStyles = [
  _HairStyle('short',  'Short'),  _HairStyle('medium', 'Medium'),
  _HairStyle('long',   'Long'),   _HairStyle('curly',  'Curly'),
  _HairStyle('bald',   'Bald'),   _HairStyle('bun',    'Bun'),
];
const _accessories = [
  _Accessory('none',       'None'),      _Accessory('glasses',    'Glasses'),
  _Accessory('sunglasses', 'Sunnies'),   _Accessory('hat',        'Hat'),
  _Accessory('earrings',   'Earrings'),  _Accessory('headband',   'Headband'),
];

// ── Config ────────────────────────────────────────────────────────────────────
class AvatarConfig {
  final String skin, hairColor, hairStyle, eyeColor, lipColor, accessory, bgColor;
  const AvatarConfig({required this.skin, required this.hairColor,
      required this.hairStyle, required this.eyeColor, required this.lipColor,
      required this.accessory, required this.bgColor});

  AvatarConfig copyWith({String? skin, String? hairColor, String? hairStyle,
      String? eyeColor, String? lipColor, String? accessory,
      String? bgColor}) => AvatarConfig(
    skin:      skin      ?? this.skin,
    hairColor: hairColor ?? this.hairColor,
    hairStyle: hairStyle ?? this.hairStyle,
    eyeColor:  eyeColor  ?? this.eyeColor,
    lipColor:  lipColor  ?? this.lipColor,
    accessory: accessory ?? this.accessory,
    bgColor:   bgColor   ?? this.bgColor,
  );

  static AvatarConfig get defaults => const AvatarConfig(
    skin: '#FDDBB4', hairColor: '#1a1a1a', hairStyle: 'short',
    eyeColor: '#1a1a1a', lipColor: '#C46B6B', accessory: 'none',
    bgColor: '#1a3a4a');

  static AvatarConfig random() {
    final r = Random();
    return AvatarConfig(
      skin:      _skinColors[r.nextInt(_skinColors.length)],
      hairColor: _hairColors[r.nextInt(_hairColors.length)],
      hairStyle: _hairStyles[r.nextInt(_hairStyles.length)].id,
      eyeColor:  _eyeColors [r.nextInt(_eyeColors.length)],
      lipColor:  _lipColors [r.nextInt(_lipColors.length)],
      accessory: _accessories[r.nextInt(_accessories.length)].id,
      bgColor:   _bgColors  [r.nextInt(_bgColors.length)],
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
             '<line x1="42" y1="54" x2="58" y2="54" stroke="#333" stroke-width="2"/>';
    case 'sunglasses':
      return '<rect x="20" y="47" width="24" height="13" rx="4" fill="#222" opacity="0.85"/>'
             '<rect x="56" y="47" width="24" height="13" rx="4" fill="#222" opacity="0.85"/>'
             '<line x1="44" y1="53" x2="56" y2="53" stroke="#555" stroke-width="2"/>';
    case 'hat':
      return '<rect x="15" y="18" width="70" height="8" rx="4" fill="#333"/>'
             '<rect x="28" y="4" width="44" height="18" rx="6" fill="#333"/>';
    case 'earrings':
      return '<circle cx="12" cy="65" r="4" fill="#FFD700"/>'
             '<circle cx="88" cy="65" r="4" fill="#FFD700"/>';
    case 'headband':
      return '<path d="M12,38 Q50,28 88,38" fill="none" stroke="#FF6B6B" stroke-width="6" stroke-linecap="round"/>';
    default: return '';
  }
}

// ── Canvas Painter ────────────────────────────────────────────────────────────
class AvatarPainter extends StatelessWidget {
  final AvatarConfig config;
  final double size;
  const AvatarPainter({super.key, required this.config, this.size = 100});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size,
    child: ClipOval(child: CustomPaint(
      size: Size(size, size),
      painter: _AvatarCanvasPainter(config))),
  );
}

class _AvatarCanvasPainter extends CustomPainter {
  final AvatarConfig config;
  _AvatarCanvasPainter(this.config);

  Color _c(String hex) {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final p = Paint()..isAntiAlias = true;

    // Background
    p.color = _c(config.bgColor);
    canvas.drawCircle(Offset(50*s, 50*s), 50*s, p);

    // Hair
    _drawHair(canvas, s, p);

    // Face
    p.color = _c(config.skin);
    canvas.drawOval(Rect.fromCenter(center: Offset(50*s, 58*s),
        width: 56*s, height: 64*s), p);
    canvas.drawOval(Rect.fromCenter(center: Offset(50*s, 45*s),
        width: 52*s, height: 56*s), p);

    // Eyes
    p.color = XameColors.darkBg;
    canvas.drawCircle(Offset(36*s, 48*s), 7*s, p);
    canvas.drawCircle(Offset(64*s, 48*s), 7*s, p);
    p.color = _c(config.eyeColor);
    canvas.drawCircle(Offset(37*s, 49*s), 4*s, p);
    canvas.drawCircle(Offset(65*s, 49*s), 4*s, p);
    p.color = XameColors.darkBg;
    canvas.drawCircle(Offset(38*s, 48*s), 1.5*s, p);
    canvas.drawCircle(Offset(66*s, 48*s), 1.5*s, p);

    // Lips
    p.color = _c(config.lipColor);
    final lip = Path()
      ..moveTo(38*s, 58*s)
      ..quadraticBezierTo(50*s, 65*s, 62*s, 58*s)
      ..quadraticBezierTo(56*s, 68*s, 44*s, 68*s)
      ..close();
    canvas.drawPath(lip, p);

    // Cheeks
    p.color = XameColors.danger.withValues(alpha: 0.3);
    canvas.drawOval(Rect.fromCenter(center: Offset(28*s, 60*s),
        width: 8*s, height: 5*s), p);
    canvas.drawOval(Rect.fromCenter(center: Offset(72*s, 60*s),
        width: 8*s, height: 5*s), p);

    // Eyebrows
    final brow = Paint()
      ..color = _c(config.hairColor)
      ..strokeWidth = 1.5*s
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(Path()
      ..moveTo(32*s, 37*s)
      ..quadraticBezierTo(34*s, 33*s, 38*s, 35*s), brow);
    canvas.drawPath(Path()
      ..moveTo(62*s, 35*s)
      ..quadraticBezierTo(66*s, 33*s, 68*s, 37*s), brow);

    // Accessory
    _drawAccessory(canvas, s, p);
  }

  void _drawHair(Canvas canvas, double s, Paint p) {
    if (config.hairStyle == 'bald') return;
    p.color = _c(config.hairColor);
    final path = Path();
    switch (config.hairStyle) {
      case 'curly':
        path..moveTo(15*s, 40*s)
            ..quadraticBezierTo(10*s, 10*s, 30*s, 8*s)
            ..quadraticBezierTo(20*s, 20*s, 25*s, 30*s)
            ..quadraticBezierTo(35*s, 5*s, 50*s, 5*s)
            ..quadraticBezierTo(65*s, 5*s, 75*s, 30*s)
            ..quadraticBezierTo(80*s, 20*s, 70*s, 8*s)
            ..quadraticBezierTo(90*s, 10*s, 85*s, 40*s)
            ..quadraticBezierTo(78*s, 12*s, 50*s, 12*s)
            ..quadraticBezierTo(22*s, 12*s, 15*s, 40*s);
        break;
      default:
        path..moveTo(10*s, 35*s)
            ..quadraticBezierTo(20*s, 5*s, 50*s, 5*s)
            ..quadraticBezierTo(80*s, 5*s, 90*s, 35*s)
            ..quadraticBezierTo(75*s, 15*s, 50*s, 15*s)
            ..quadraticBezierTo(25*s, 15*s, 10*s, 35*s);
    }
    canvas.drawPath(path, p);
  }

  void _drawAccessory(Canvas canvas, double s, Paint p) {
    switch (config.accessory) {
      case 'glasses':
        final gp = Paint()
          ..color = XameColors.darkCard
          ..strokeWidth = 2*s
          ..style = PaintingStyle.stroke;
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(22*s, 48*s, 20*s, 12*s), Radius.circular(4*s)), gp);
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(58*s, 48*s, 20*s, 12*s), Radius.circular(4*s)), gp);
        canvas.drawLine(Offset(42*s, 54*s), Offset(58*s, 54*s), gp);
        break;
      case 'hat':
        p.color = XameColors.darkCard;
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(15*s, 18*s, 70*s, 8*s), Radius.circular(4*s)), p);
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(28*s, 4*s, 44*s, 18*s), Radius.circular(6*s)), p);
        break;
      case 'earrings':
        p.color = XameColors.accent;
        canvas.drawCircle(Offset(12*s, 65*s), 4*s, p);
        canvas.drawCircle(Offset(88*s, 65*s), 4*s, p);
        break;
      case 'headband':
        final hp = Paint()
          ..color = XameColors.danger
          ..strokeWidth = 6*s
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(Path()
          ..moveTo(12*s, 38*s)
          ..quadraticBezierTo(50*s, 28*s, 88*s, 38*s), hp);
        break;
    }
  }

  @override
  bool shouldRepaint(_AvatarCanvasPainter old) => old.config != config;
}

// ── Avatar Builder Sheet ──────────────────────────────────────────────────────
class AvatarBuilderSheet extends StatefulWidget {
  final String xameId, serverUrl;
  final void Function(String dataUrl)? onSaved;

  AvatarBuilderSheet({super.key, required this.xameId,
      required this.serverUrl, this.onSaved});

  static Future<void> show(BuildContext context, {
    required String xameId, String? serverUrl,
    void Function(String dataUrl)? onSaved,
  }) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AvatarBuilderSheet(xameId: xameId,
        serverUrl: serverUrl ?? AppConstants.serverUrl, onSaved: onSaved));

  @override
  State<AvatarBuilderSheet> createState() => _AvatarBuilderSheetState();
}

class _AvatarBuilderSheetState extends State<AvatarBuilderSheet> {
  bool _saving = false;
  String _seed = '';
  final List<String> _backgrounds = ['b6e3f4','c0aede','d1d4f9','ffd5dc','ffdfbf','f0e6ff','e8f4f8'];
  int _bgIndex = 0;

  @override
  void initState() {
    super.initState();
    _seed = widget.xameId;
  }

  String get _avatarUrl =>
    'https://api.dicebear.com/7.x/notionists/png?seed=$_seed&backgroundColor=${_backgrounds[_bgIndex]}&radius=50&size=200';

  void _randomize() => setState(() {
    _seed = DateTime.now().millisecondsSinceEpoch.toString();
    _bgIndex = (_bgIndex + 1) % _backgrounds.length;
  });

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final url = 'https://api.dicebear.com/7.x/notionists/png?seed=$_seed&backgroundColor=${_backgrounds[_bgIndex]}&radius=50&size=200';
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final req = http.MultipartRequest('POST',
            Uri.parse('${widget.serverUrl}/api/update-profile'));
        req.fields['userId'] = widget.xameId;
        req.files.add(http.MultipartFile.fromBytes('profilePic', res.bodyBytes,
            filename: 'avatar.png'));
        final upload = await req.send();
        final body   = jsonDecode(await upload.stream.bytesToString());
        if (body['success'] == true) {
          widget.onSaved?.call(body['profilePicUrl'] ?? _avatarUrl);
          if (mounted) Navigator.pop(context);
          return;
        }
      }
      widget.onSaved?.call(_avatarUrl);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('[AvatarBuilder] Save error: \$e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to save avatar'),
        behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.7,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: context.xSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Handle + header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
            child: Column(children: [
              Center(child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: context.xMuted.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2)),
              )),
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [context.xPrimary, context.xSurface],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.face_outlined, color: Colors.black, size: 20),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Avatar Builder', style: TextStyle(color: context.xText,
                      fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('Your unique Notionists avatar',
                      style: TextStyle(color: context.xMuted, fontSize: 12)),
                ]),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.close, color: context.xMuted)),
              ]),
            ]),
          ),
          const SizedBox(height: 24),
          // Preview
          Center(child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 140, height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: context.xPrimary, width: 3),
                  boxShadow: [BoxShadow(
                    color: context.xPrimary.withValues(alpha: 0.3),
                    blurRadius: 20)],
                ),
                child: ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: _avatarUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                    errorWidget: (_, __, ___) => const Icon(Icons.person),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _randomize,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: context.xPrimary,
                    shape: BoxShape.circle,
                    border: Border.all(color: context.xSurface, width: 2),
                  ),
                  child: const Icon(Icons.shuffle_rounded, color: Colors.black, size: 16),
                ),
              ),
            ],
          )),
          const SizedBox(height: 8),
          Text('Tap 🔀 to generate a new avatar',
              style: TextStyle(color: context.xMuted, fontSize: 12)),
          const Spacer(),
          // Save button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: GestureDetector(
              onTap: _saving ? null : _save,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: double.infinity, height: 52,
                decoration: BoxDecoration(
                  gradient: _saving ? null : LinearGradient(
                    colors: [context.xPrimary, context.xSurface]),
                  color: _saving ? context.xCard : null,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('✓ Use This Avatar',
                      style: TextStyle(color: Colors.black,
                          fontSize: 15, fontWeight: FontWeight.w700))),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
