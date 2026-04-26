
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xamepage/core/theme/app_theme.dart';

// ── Wallpaper presets ─────────────────────────────────────────────────────────
class WallpaperPreset {
  final String id;
  final String label;
  final Gradient gradient;
  const WallpaperPreset({required this.id, required this.label, required this.gradient});
}

final kWallpaperPresets = [
  WallpaperPreset(
    id: 'none', label: 'None',
    gradient: LinearGradient(colors: [Color(0xFF0A0A0F), Color(0xFF0A0A0F)]),
  ),
  WallpaperPreset(
    id: 'midnight', label: 'Midnight',
    gradient: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF0D1B2E), Color(0xFF1A2340), Color(0xFF0D1117)]),
  ),
  WallpaperPreset(
    id: 'aurora', label: 'Aurora',
    gradient: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF0A1628), Color(0xFF1A3A2F), Color(0xFF0D2137)]),
  ),
  WallpaperPreset(
    id: 'nebula', label: 'Nebula',
    gradient: LinearGradient(
      begin: Alignment.topRight, end: Alignment.bottomLeft,
      colors: [Color(0xFF1A0A2E), Color(0xFF2A1040), Color(0xFF0A0A1A)]),
  ),
  WallpaperPreset(
    id: 'ember', label: 'Ember',
    gradient: LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF1A0800), Color(0xFF2A1200), Color(0xFF0A0500)]),
  ),
  WallpaperPreset(
    id: 'ocean', label: 'Ocean',
    gradient: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF001A2E), Color(0xFF003354), Color(0xFF001020)]),
  ),
  WallpaperPreset(
    id: 'forest', label: 'Forest',
    gradient: LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF0A1A0A), Color(0xFF0F2A0F), Color(0xFF050F05)]),
  ),
];

// ── Wallpaper service ─────────────────────────────────────────────────────────
class WallpaperService {
  static const _box    = 'xame_wallpapers';
  static const _global = 'wallpaper_global';
  static String _contactKey(String id) => 'wallpaper_$id';

  static Future<Box> _open() => Hive.openBox(_box);

  // Get wallpaper for a contact (falls back to global)
  static Future<Map<String, dynamic>> getWallpaper(String contactId) async {
    final box = await _open();
    final contact = box.get(_contactKey(contactId));
    if (contact != null) return Map<String, dynamic>.from(contact);
    final global = box.get(_global);
    if (global != null) return Map<String, dynamic>.from(global);
    return {'type': 'preset', 'id': 'none'};
  }

  static Future<void> setGlobal(Map<String, dynamic> wallpaper) async {
    final box = await _open();
    await box.put(_global, wallpaper);
  }

  static Future<void> setContact(String contactId, Map<String, dynamic>? wallpaper) async {
    final box = await _open();
    if (wallpaper == null) {
      await box.delete(_contactKey(contactId));
    } else {
      await box.put(_contactKey(contactId), wallpaper);
    }
  }

  static Future<bool> hasContactOverride(String contactId) async {
    final box = await _open();
    return box.containsKey(_contactKey(contactId));
  }

  static Future<String> saveCustomImage(String sourcePath) async {
    final dir  = await getApplicationDocumentsDirectory();
    final dest = File('${dir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(sourcePath).copy(dest.path);
    return dest.path;
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────
final wallpaperProvider = FutureProvider.family<Map<String, dynamic>, String>(
  (ref, contactId) => WallpaperService.getWallpaper(contactId),
);

// ── Wallpaper picker sheet ────────────────────────────────────────────────────
class WallpaperPickerSheet extends ConsumerStatefulWidget {
  final String  contactId;
  final String  contactName;
  final bool    isGlobal;
  final VoidCallback onChanged;

  const WallpaperPickerSheet({
    super.key,
    required this.contactId,
    required this.contactName,
    this.isGlobal = false,
    required this.onChanged,
  });

  static Future<void> show(BuildContext context, {
    required String contactId,
    required String contactName,
    bool isGlobal = false,
    required VoidCallback onChanged,
  }) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => WallpaperPickerSheet(
      contactId: contactId,
      contactName: contactName,
      isGlobal: isGlobal,
      onChanged: onChanged,
    ),
  );

  @override
  ConsumerState<WallpaperPickerSheet> createState() => _WallpaperPickerSheetState();
}

class _WallpaperPickerSheetState extends ConsumerState<WallpaperPickerSheet> {
  Map<String, dynamic>? _selected;
  bool _hasOverride = false;
  bool _loading     = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final box    = await Hive.openBox('xame_wallpapers');
    final key    = widget.isGlobal ? 'wallpaper_global' : 'wallpaper_${widget.contactId}';
    final global = box.get('wallpaper_global');
    final contact = box.get('wallpaper_${widget.contactId}');
    setState(() {
      _hasOverride = contact != null;
      final raw = widget.isGlobal ? global : (contact ?? global);
      _selected = raw != null ? Map<String, dynamic>.from(raw) : {'type': 'preset', 'id': 'none'};
    });
  }

  Future<void> _pickCustom() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (img == null) return;
    setState(() => _loading = true);
    try {
      final path = await WallpaperService.saveCustomImage(img.path);
      setState(() => _selected = {'type': 'custom', 'path': path});
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _apply({bool global = false}) async {
    if (_selected == null) return;
    if (global || widget.isGlobal) {
      await WallpaperService.setGlobal(_selected!);
    } else {
      await WallpaperService.setContact(widget.contactId, _selected);
    }
    widget.onChanged();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _clearOverride() async {
    await WallpaperService.setContact(widget.contactId, null);
    widget.onChanged();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.xTheme;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141420),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20,
          MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.white24,
              borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),

        // Title
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.isGlobal ? 'Global Wallpaper' : 'Chat Wallpaper',
              style: const TextStyle(color: Colors.white,
                  fontSize: 17, fontWeight: FontWeight.w700)),
            Text(widget.isGlobal
                ? 'Applies to all chats'
                : widget.contactName,
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          ])),
          if (!widget.isGlobal && _hasOverride)
            TextButton(
              onPressed: _clearOverride,
              child: Text('Reset to Global',
                style: TextStyle(color: context.xPrimary, fontSize: 12)),
            ),
        ]),
        const SizedBox(height: 16),

        // Preset grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4, crossAxisSpacing: 10,
            mainAxisSpacing: 10, childAspectRatio: 0.85),
          itemCount: kWallpaperPresets.length + 1, // +1 for custom
          itemBuilder: (_, i) {
            if (i == kWallpaperPresets.length) {
              // Custom tile
              final isCustomSelected = _selected?['type'] == 'custom';
              return GestureDetector(
                onTap: _pickCustom,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E2E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCustomSelected
                          ? context.xPrimary : Colors.white12,
                      width: isCustomSelected ? 2 : 1),
                  ),
                  child: isCustomSelected && _selected!['path'] != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.file(
                            File(_selected!['path']), fit: BoxFit.cover))
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              color: Colors.white54, size: 22),
                          SizedBox(height: 4),
                          Text('Custom',
                              style: TextStyle(color: Colors.white54,
                                  fontSize: 9)),
                        ]),
                ),
              );
            }

            final preset = kWallpaperPresets[i];
            final isSelected = _selected?['type'] == 'preset' &&
                _selected?['id'] == preset.id;
            return GestureDetector(
              onTap: () => setState(() =>
                  _selected = {'type': 'preset', 'id': preset.id}),
              child: Stack(children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: preset.id == 'none' ? null : preset.gradient,
                    color: preset.id == 'none' ? const Color(0xFF0A0A0F) : null,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? context.xPrimary : Colors.white12,
                      width: isSelected ? 2 : 1),
                  ),
                  child: preset.id == 'none'
                    ? const Center(child: Text('None',
                        style: TextStyle(color: Colors.white38, fontSize: 10)))
                    : null,
                ),
                if (isSelected)
                  Positioned(top: 4, right: 4,
                    child: Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        color: context.xPrimary,
                        shape: BoxShape.circle),
                      child: const Icon(Icons.check,
                          color: Colors.white, size: 10))),
                Positioned(bottom: 4, left: 0, right: 0,
                  child: Text(preset.label, textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70,
                        fontSize: 8, fontWeight: FontWeight.w500))),
              ]),
            );
          },
        ),
        const SizedBox(height: 20),

        // Apply buttons
        if (!widget.isGlobal) ...[
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.xPrimary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
              onPressed: _loading ? null : () => _apply(),
              child: _loading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : const Text('Apply to This Chat',
                    style: TextStyle(fontWeight: FontWeight.w700)),
            )),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: context.xPrimary.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
              onPressed: _loading ? null : () => _apply(global: true),
              child: Text('Apply to All Chats',
                style: TextStyle(color: context.xPrimary,
                    fontWeight: FontWeight.w600)),
            )),
        ] else
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.xPrimary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
              onPressed: _loading ? null : () => _apply(global: true),
              child: _loading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : const Text('Save Global Wallpaper',
                    style: TextStyle(fontWeight: FontWeight.w700)),
            )),
      ]),
    );
  }
}
