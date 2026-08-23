import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/xame_space_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/auth_service.dart';
import 'space_screen.dart';

class CreateSpaceScreen extends ConsumerStatefulWidget {
  const CreateSpaceScreen({super.key});
  @override
  ConsumerState<CreateSpaceScreen> createState() => _CreateSpaceScreenState();
}

class _CreateSpaceScreenState extends ConsumerState<CreateSpaceScreen> {
  final _nameCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _archetype = 'community';
  String _visibility = 'public_link';
  bool _allowGuests = true;
  bool _creating = false;
  String? _error;

  static const _archetypes = [
    ('family',    '👨‍👩‍👧‍👦', 'Family',    'Private family hub'),
    ('school',    '🎓',         'School',    'Class & study groups'),
    ('business',  '💼',         'Business',  'Team collaboration'),
    ('community', '🌍',         'Community', 'Open community space'),
    ('project',   '🚀',         'Project',   'Project workspace'),
    ('event',     '🎉',         'Event',     'Event coordination'),
  ];

  void _onNameChanged(String v) {
    final slug = v.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    _slugCtrl.text = slug;
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    final slug = _slugCtrl.text.trim();
    if (name.isEmpty || slug.isEmpty) {
      setState(() => _error = 'Name and slug are required');
      return;
    }
    final userId = ref.read(currentUserProvider)?.xameId;
    if (userId == null) {
      setState(() => _error = 'You must be signed in to create a Space');
      return;
    }
    setState(() { _creating = true; _error = null; });
    final space = await XameSpaceService.createSpace(
      userId: userId, name: name, spaceSlug: slug, archetype: _archetype,
      description: _descCtrl.text.trim(),
      visibility: _visibility, allowGuestPosting: _allowGuests);
    if (!mounted) return;
    setState(() => _creating = false);
    if (space != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => SpaceScreen(spaceSlug: space.spaceSlug)));
    } else {
      setState(() => _error = 'Could not create Space. Slug may already be taken.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: XameColors.darkBg,
    appBar: AppBar(backgroundColor: XameColors.darkSurface,
      title: const Text('Create a Space', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      leading: IconButton(icon: const Icon(Icons.close, color: Colors.white),
        onPressed: () => Navigator.pop(context))),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Archetype picker
        const Text('Choose a type', style: TextStyle(color: Colors.white70, fontSize: 13,
          fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        GridView.count(crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.2,
          children: _archetypes.map((a) {
            final selected = _archetype == a.$1;
            return GestureDetector(
              onTap: () => setState(() => _archetype = a.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: selected ? XameColors.primary.withValues(alpha: 0.15) : XameColors.darkCard,
                  border: Border.all(color: selected ? XameColors.primary : Colors.white12, width: 1.5),
                  borderRadius: BorderRadius.circular(12)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(a.$2, style: const TextStyle(fontSize: 24)),
                  const SizedBox(height: 4),
                  Text(a.$3, style: TextStyle(color: selected ? XameColors.primary : Colors.white,
                    fontSize: 11, fontWeight: FontWeight.w600)),
                ])));
          }).toList()),
        const SizedBox(height: 24),
        // Name
        _label('Space Name'),
        _field(_nameCtrl, 'e.g. Agbor Family', onChanged: _onNameChanged),
        const SizedBox(height: 16),
        // Slug
        _label('Space URL  (xamepage.com/space/...)'),
        _field(_slugCtrl, 'e.g. agbor-family',
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9-]'))]),
        const SizedBox(height: 16),
        // Description
        _label('Description (optional)'),
        _field(_descCtrl, 'What is this Space for?', maxLines: 3),
        const SizedBox(height: 24),
        // Visibility
        _label('Who can join?'),
        const SizedBox(height: 8),
        ...{
          'public_link': '🔗 Anyone with the link',
          'open':        '🌍 Open to everyone',
          'unlisted':    '👁 Unlisted (invite only)',
          'private':     '🔒 Private (approval required)',
        }.entries.map((e) => RadioListTile<String>(
          value: e.key, groupValue: _visibility,
          onChanged: (v) => setState(() => _visibility = v!),
          activeColor: XameColors.primary,
          title: Text(e.value, style: const TextStyle(color: Colors.white, fontSize: 14)),
          contentPadding: EdgeInsets.zero)),
        const SizedBox(height: 8),
        SwitchListTile(
          value: _allowGuests,
          onChanged: (v) => setState(() => _allowGuests = v),
          activeColor: XameColors.primary,
          title: const Text('Allow guests to post', style: TextStyle(color: Colors.white)),
          subtitle: Text('Non-registered users can send messages',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
          contentPadding: EdgeInsets.zero),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: _creating ? null : _create,
            style: ElevatedButton.styleFrom(backgroundColor: XameColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: _creating
              ? const CircularProgressIndicator(color: Colors.black, strokeWidth: 2)
              : const Text('Create Space 🚀', style: TextStyle(color: Colors.black,
                  fontWeight: FontWeight.w800, fontSize: 16)))),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
      ]),
    ),
  );

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6),
    child: Text(t, style: const TextStyle(color: Colors.white70, fontSize: 13,
      fontWeight: FontWeight.w600)));

  Widget _field(TextEditingController ctrl, String hint, {
    int maxLines = 1, Function(String)? onChanged,
    List<TextInputFormatter>? inputFormatters,
  }) => TextField(
    controller: ctrl, maxLines: maxLines, onChanged: onChanged,
    inputFormatters: inputFormatters,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hint, hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
      filled: true, fillColor: XameColors.darkCard,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: XameColors.primary))));
}
