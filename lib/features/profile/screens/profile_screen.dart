import '../../gallery/widgets/profile_portfolio_grid.dart';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/config/constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../shared/models/xame_user.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../settings/screens/theme_picker_screen.dart';
import '../../../core/theme/app_theme.dart';
import '../avatar_builder.dart';

// ── Providers ─────────────────────────────────────────────────────────────────
final _sessionsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, userId) async {
  final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
  final res  = await dio.get('/api/sessions/$userId');
  if (res.data['success'] == true) {
    return List<Map<String, dynamic>>.from(res.data['sessions'] ?? []);
  }
  return [];
});

final _extraSecProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, userId) async {
  final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
  final res  = await dio.get('/api/extra-security/$userId');
  return Map<String, dynamic>.from(res.data['extraSecurity'] ?? {});
});

// ── Screen ────────────────────────────────────────────────────────────────────
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {

  final _nameCtrl   = TextEditingController();
  final _dio        = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
  final _picker     = ImagePicker();

  bool   _hideName    = false;
  bool   _hidePic     = false;
  bool   _saving      = false;
  File?  _newImage;
  bool   _removeImage = false;
  late AnimationController _fadeCtrl;
  late Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUser());
  }

  void _loadUser() {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    _nameCtrl.text = user.preferredName ?? user.firstName;
    setState(() {
      _hideName = user.hidePreferredName;
      _hidePic  = user.hideProfilePicture;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Pick image ──────────────────────────────────────────────────────────────
  Future<void> _pickImage() async {
    final x = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: XameColors.darkSurface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 8),
          Container(width: 36, height: 4,
            decoration: BoxDecoration(color: context.xMuted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2))),
          SizedBox(height: 16),
          ListTile(
            leading: Icon(Icons.camera_alt_outlined, color: context.xText.withValues(alpha: 0.7)),
            title: Text('Camera', style: TextStyle(color: context.xText)),
            onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(
            leading: Icon(Icons.photo_library_outlined, color: context.xText.withValues(alpha: 0.7)),
            title: Text('Gallery', style: TextStyle(color: context.xText)),
            onTap: () => Navigator.pop(context, ImageSource.gallery)),
          ListTile(
            leading: Icon(Icons.face_outlined, color: XameColors.primary),
            title: Text('🎨 Build Avatar', style: TextStyle(color: context.xText)),
            onTap: () { Navigator.pop(context); _openAvatarBuilder(); }),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: const Text('Remove Photo',
                style: TextStyle(color: Colors.redAccent)),
            onTap: () {
              setState(() { _removeImage = true; _newImage = null; });
              Navigator.pop(context);
            }),
          const SizedBox(height: 16),
        ],
      )),
    );
    if (x == null) return;
    final picked = await _picker.pickImage(source: x, imageQuality: 85);
    if (picked != null) {
      setState(() { _newImage = File(picked.path); _removeImage = false; });
    }
  }

  // ── Save profile ────────────────────────────────────────────────────────────

  void _openAvatarBuilder() {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    AvatarBuilderSheet.show(
      context,
      xameId: user.xameId,
      onSaved: (dataUrl) {
        final updated = XameUser(
          xameId:               user.xameId,
          firstName:            user.firstName,
          lastName:             user.lastName,
          email:                user.email,
          phone:                user.phone,
          preferredName:        user.preferredName,
          profilePic:           dataUrl,
          hidePreferredName:    user.hidePreferredName,
          hideProfilePicture:   user.hideProfilePicture,
          personalStatusEmoji:  user.personalStatusEmoji,
          personalStatusMessage: user.personalStatusMessage,
          sessionToken:         user.sessionToken,
        );
        ref.read(currentUserProvider.notifier).state = updated;
        _snack("Avatar saved!", success: true);
      },
    );
  }
  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final name = _nameCtrl.text.trim();
    if (name.length < 2) {
      _snack('Name must be at least 2 characters');
      return;
    }
    setState(() => _saving = true);
    try {
      final form = FormData.fromMap({
        'userId':             user.xameId,
        'preferredName':      name,
        'hidePreferredName':  _hideName.toString(),
        'hideProfilePicture': _hidePic.toString(),
        if (_removeImage) 'removeProfilePic': 'true',
        if (_newImage != null)
          'profilePic': await MultipartFile.fromFile(
              _newImage!.path, filename: 'profile_pic.jpg'),
      });

      final res = await _dio.post('/api/update-profile', data: form);
      if (res.data['success'] == true) {
        // Update local user state
        final updated = XameUser(
          xameId:             user.xameId,
          firstName:          user.firstName,
          lastName:           user.lastName,
          email:              user.email,
          phone:              user.phone,
          preferredName:      res.data['preferredName'] ?? name,
          profilePic:         res.data['profilePicUrl'] ?? user.profilePic,
          hidePreferredName:  res.data['hidePreferredName']  ?? _hideName,
          hideProfilePicture: res.data['hideProfilePicture'] ?? _hidePic,
          personalStatusEmoji:   user.personalStatusEmoji,
          personalStatusMessage: user.personalStatusMessage,
          sessionToken:       user.sessionToken,
        );
        ref.read(currentUserProvider.notifier).state = updated;
        setState(() { _newImage = null; _removeImage = false; });
        _snack('Profile saved successfully ✓', success: true);
      } else {
        _snack(res.data['message'] ?? 'Failed to save profile');
      }
    } catch (e) {
      _snack('Error saving profile');
    } finally {
      setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle(color: context.xText)),
      backgroundColor: success
          ? XameColors.accent : XameColors.darkSurface,
      behavior:  SnackBarBehavior.floating,
      shape:     RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration:  Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final user     = ref.watch(currentUserProvider);
    if (user == null) return Scaffold(
        backgroundColor: context.xBg);

    final photoUrl = _removeImage ? null
        : _newImage != null ? null
        : user.profilePic;
    final initials = (user.preferredName ?? user.firstName)
        .trim().split(' ').take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();

    return Scaffold(
      backgroundColor: context.xBg,
      body: FadeTransition(
        opacity: _fade,
        child: CustomScrollView(slivers: [

          // ── App Bar ────────────────────────────────────────────────────────
          SliverAppBar(
            pinned:          true,
            expandedHeight:  200,
            backgroundColor: context.xBg,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new,
                  color: context.xText, size: 18),
              onPressed: () => context.go('/contacts')),
            actions: [
              TextButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: context.xPrimary, strokeWidth: 2))
                    : Text('Save',
                        style: TextStyle(color: context.xPrimary,
                            fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [context.xSurface, context.xBg],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: 40),
                    // Avatar
                    GestureDetector(
                      onTap: _pickImage,
                      child: Stack(children: [
                        Container(
                          width: 90, height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: context.xAccent, width: 2.5),
                          ),
                          child: ClipOval(child: _newImage != null
                            ? Image.file(_newImage!, fit: BoxFit.cover)
                            : photoUrl != null && photoUrl.isNotEmpty
                              ? CachedNetworkImage(imageUrl: photoUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) =>
                                      _initialsWidget(initials))
                              : _initialsWidget(initials)),
                        ),
                        Positioned(
                          bottom: 0, right: 0,
                          child: Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: context.xPrimary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.camera_alt,
                                color: Colors.black, size: 14),
                          ),
                        ),
                      ]),
                    ),
                    SizedBox(height: 10),
                    Text('@${user.xameId}',
                      style: TextStyle(color: context.xText.withValues(alpha: 0.5),
                          fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Display Name ─────────────────────────────────────────────
                _sectionTitle('Display Name'),
                SizedBox(height: 10),
                _inputField(
                  controller: _nameCtrl,
                  hint:       'Your display name',
                  icon:       Icons.person_outline,
                ),

                SizedBox(height: 24),

                // ── XameID ──────────────────────────────────────────────────
                _sectionTitle('XameID'),
                SizedBox(height: 10),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: user.xameId));
                    _snack('XameID copied!', success: true);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.xSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.xMuted.withValues(alpha: 0.1)),
                    ),
                    child: Row(children: [
                      Icon(Icons.tag, color: context.xPrimary, size: 18),
                      SizedBox(width: 12),
                      Text(user.xameId,
                        style: TextStyle(color: context.xText,
                            fontSize: 15, fontWeight: FontWeight.w500)),
                      Spacer(),
                      Icon(Icons.copy_outlined,
                          color: context.xMuted, size: 16),
                    ]),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Privacy ──────────────────────────────────────────────────
                _sectionTitle('Privacy'),
                const SizedBox(height: 10),
                _toggleTile(
                  icon:    Icons.person_off_outlined,
                  title:   'Hide Display Name',
                  subtitle: 'Show XameID instead of your name',
                  value:   _hideName,
                  onChanged: (v) => setState(() => _hideName = v),
                ),
                const SizedBox(height: 8),
                _toggleTile(
                  icon:    Icons.hide_image_outlined,
                  title:   'Hide Profile Picture',
                  subtitle: 'Others won\'t see your photo',
                  value:   _hidePic,
                  onChanged: (v) => setState(() => _hidePic = v),
                ),

                SizedBox(height: 24),

                // ── Appearance ──────────────────────────────────────────
                _sectionTitle('Appearance'),
                SizedBox(height: 10),
                Consumer(builder: (_, ref, __) {
                  final theme = ref.watch(themeProvider);
                  return _actionTile(
                    icon:    Icons.palette_outlined,
                    title:   'Theme',
                    subtitle: '\${theme.emoji} \${theme.name}',
                    color:   theme.primary,
                    onTap:   () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => ThemePickerScreen())),
                  );
                }),
                SizedBox(height: 24),

                // ── Security ─────────────────────────────────────────────────
                _sectionTitle('Security'),
                SizedBox(height: 10),
                _actionTile(
                  icon:    Icons.shield_outlined,
                  title:   'Extra Security',
                  subtitle: 'OTP on new device login',
                  color:   context.xAccent,
                  onTap:   () => _showExtraSecuritySheet(user.xameId),
                ),
                const SizedBox(height: 8),
                _actionTile(
                  icon:    Icons.devices_outlined,
                  title:   'Active Sessions',
                  subtitle: 'Manage logged-in devices',
                  color:   Colors.blueAccent,
                  onTap:   () => _showSessionsSheet(user.xameId),
                ),

                const SizedBox(height: 24),

                // ── Danger zone ──────────────────────────────────────────────
                _sectionTitle('Account'),
                const SizedBox(height: 10),
                _actionTile(
                  icon:    Icons.logout,
                  title:   'Log Out',
                  subtitle: 'Sign out from this device',
                  color:   Colors.redAccent,
                  onTap:   () async {
                    const FlutterSecureStorage().delete(key: AppConstants.keyUser);
                    ref.read(currentUserProvider.notifier).state = null;
                    context.go('/login');
                  },
                ),

                const SizedBox(height: 40),
              ],
            ),
          )),
        ]),
      ),
    );
  }

  // ── Extra Security Sheet ──────────────────────────────────────────────────
  void _showExtraSecuritySheet(String userId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExtraSecuritySheet(userId: userId, dio: _dio),
    );
  }

  // ── Sessions Sheet ────────────────────────────────────────────────────────
  void _showSessionsSheet(String userId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Consumer(builder: (_, ref, __) {
        final sessions = ref.watch(_sessionsProvider(userId));
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize:     0.9,
          builder: (_, ctrl) => Container(
            decoration: BoxDecoration(
              color: XameColors.darkCard,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(children: [
              _sheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Row(children: [
                  Icon(Icons.devices_outlined,
                      color: Colors.blueAccent, size: 20),
                  SizedBox(width: 10),
                  Text('Active Sessions',
                    style: TextStyle(color: context.xText, fontSize: 17,
                        fontWeight: FontWeight.w700)),
                  Spacer(),
                  TextButton(
                    onPressed: () async {
                      await _dio.post('/api/sessions/kill-all',
                          data: {'userId': userId});
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack('All other devices logged out', success: true);
                    },
                    child: Text('Log out all',
                        style: TextStyle(color: Colors.redAccent,
                            fontSize: 12))),
                ]),
              ),
              Expanded(child: sessions.when(
                loading: () => Center(child: CircularProgressIndicator(
                    color: XameColors.primary, strokeWidth: 2)),
                error: (_, __) => Center(
                    child: Text('Failed to load sessions',
                        style: TextStyle(color: context.xMuted))),
                data: (list) => ListView.builder(
                  controller:  ctrl,
                  padding:     const EdgeInsets.symmetric(horizontal: 20),
                  itemCount:   list.length,
                  itemBuilder: (_, i) {
                    final s      = list[i];
                    final date   = DateTime.tryParse(
                        s['createdAt']?.toString() ?? '') ?? DateTime.now();
                    final device = _parseDevice(s['deviceInfo'] ?? '');
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.xText.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.xText10),
                      ),
                      child: Row(children: [
                        Icon(Icons.phone_android,
                            color: context.xText.withValues(alpha: 0.54), size: 20),
                        SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(device,
                              style: TextStyle(color: context.xText,
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                            SizedBox(height: 3),
                            Text('Logged in: ${_fmtDate(date)}',
                              style: TextStyle(color: context.xMuted,
                                  fontSize: 11)),
                          ],
                        )),
                        GestureDetector(
                          onTap: () async {
                            await _dio.post('/api/sessions/kill',
                                data: {'userId': userId, 'sessionId': s['id']});
                            ref.refresh(_sessionsProvider(userId));
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.3)),
                            ),
                            child: const Text('Log out',
                              style: TextStyle(color: Colors.redAccent,
                                  fontSize: 12)),
                          ),
                        ),
                      ]),
                    );
                  },
                ),
              )),
            ]),
          ),
        );
      }),
    );
  }

  String _parseDevice(String ua) {
    if (ua.contains('Android')) {
      if (ua.contains('HUAWEI')) return 'Huawei · Android';
      if (ua.contains('SM-'))    return 'Samsung · Android';
      if (ua.contains('Pixel'))  return 'Google Pixel · Android';
      if (ua.contains('Xiaomi')) return 'Xiaomi · Android';
      return 'Android Device';
    }
    if (ua.contains('iPhone'))  return 'iPhone · iOS';
    if (ua.contains('Windows')) return 'Windows PC';
    if (ua.contains('Mac'))     return 'Mac';
    return 'Unknown Device';
  }

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';

  // ── Widgets ──────────────────────────────────────────────────────────────
  Widget _initialsWidget(String initials) => Container(
    color: XameColors.darkSurface,
    child: Center(child: Text(initials,
      style: TextStyle(color: context.xText, fontSize: 32,
          fontWeight: FontWeight.w600))));

  Widget _sectionTitle(String t) => Text(t,
    style: TextStyle(color: context.xMuted, fontSize: 12,
        fontWeight: FontWeight.w600, letterSpacing: 0.8));

  Widget _inputField({
    required TextEditingController controller,
    required String hint, required IconData icon,
  }) => Container(
    decoration: BoxDecoration(
      color: XameColors.darkSurface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.xText10),
    ),
    child: TextField(
      controller: controller,
      style: TextStyle(color: context.xText, fontSize: 15),
      decoration: InputDecoration(
        hintText:    hint,
        hintStyle:   TextStyle(color: context.xText30),
        prefixIcon:  Icon(icon, color: context.xMuted, size: 20),
        border:      InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
      ),
    ),
  );

  Widget _toggleTile({
    required IconData icon, required String title,
    required String subtitle, required bool value,
    required ValueChanged<bool> onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: XameColors.darkSurface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.xText10),
    ),
    child: Row(children: [
      Icon(icon, color: context.xText.withValues(alpha: 0.54), size: 20),
      SizedBox(width: 14),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: context.xText,
              fontSize: 14, fontWeight: FontWeight.w500)),
          Text(subtitle, style: TextStyle(color: context.xMuted,
              fontSize: 12)),
        ],
      )),
      Switch(
        value:           value,
        onChanged:       onChanged,
        activeColor:     XameColors.accent,
        inactiveTrackColor: context.xMuted.withValues(alpha: 0.25),
      ),
    ]),
  );

  Widget _actionTile({
    required IconData icon, required String title,
    required String subtitle, required Color color,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: XameColors.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.xText10),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: color,
                fontSize: 14, fontWeight: FontWeight.w500)),
            Text(subtitle, style: TextStyle(color: context.xMuted,
                fontSize: 12)),
          ],
        )),
        Icon(Icons.chevron_right, color: context.xMuted.withValues(alpha: 0.5), size: 20),
      ]),
    ),
  );

  Widget _sheetHandle() => Container(
    margin: const EdgeInsets.only(top: 12, bottom: 8),
    width: 40, height: 4,
    decoration: BoxDecoration(color: context.xMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(2)));
}

// ── Extra Security Sheet ──────────────────────────────────────────────────────
class _ExtraSecuritySheet extends ConsumerStatefulWidget {
  final String userId;
  final Dio dio;
  const _ExtraSecuritySheet({required this.userId, required this.dio});
  @override
  ConsumerState<_ExtraSecuritySheet> createState() =>
      _ExtraSecuritySheetState();
}

class _ExtraSecuritySheetState extends ConsumerState<_ExtraSecuritySheet> {
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool  _enabled   = false;
  bool  _saving    = false;
  bool  _loaded    = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.dio.get(
          '/api/extra-security/${widget.userId}');
      final es  = res.data['extraSecurity'] ?? {};
      setState(() {
        _enabled       = es['enabled']  ?? false;
        _emailCtrl.text = es['email']   ?? '';
        _phoneCtrl.text = es['phone']   ?? '';
        _loaded        = true;
      });
    } catch (_) { setState(() => _loaded = true); }
  }

  Future<void> _save() async {
    if (_enabled && _emailCtrl.text.isEmpty && _phoneCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter email or phone number'),
        backgroundColor: Colors.redAccent));
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await widget.dio.post('/api/extra-security/setup', data: {
        'userId':  widget.userId,
        'email':   _emailCtrl.text.trim(),
        'phone':   _phoneCtrl.text.trim(),
        'enabled': _enabled,
      });
      if (res.data['success'] == true) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Extra security settings saved ✓'),
          backgroundColor: XameColors.primary));
      }
    } catch (_) {} finally {
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() { _emailCtrl.dispose(); _phoneCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize:     0.9,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: context.xSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(controller: ctrl, padding: const EdgeInsets.all(20),
          children: [
            Center(child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: context.xMuted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2)))),

            Row(children: [
              Text('🛡️', style: TextStyle(fontSize: 20)),
              SizedBox(width: 10),
              Text('Extra Security',
                style: TextStyle(color: context.xText, fontSize: 18,
                    fontWeight: FontWeight.w700)),
            ]),
            SizedBox(height: 8),
            Text(
              'When enabled, a one-time code will be sent to your '
              'email or phone every time you log in from an unrecognised device.',
              style: TextStyle(color: context.xText.withValues(alpha: 0.54), fontSize: 13, height: 1.6)),

            SizedBox(height: 24),

            // Enable toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: context.xText.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Text('Enable Extra Security',
                  style: TextStyle(color: context.xText, fontSize: 14,
                      fontWeight: FontWeight.w600)),
                Spacer(),
                Switch(
                  value:     _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                  activeColor: context.xAccent,
                ),
              ]),
            ),

            SizedBox(height: 16),

            // Email
            Text('📧 Email for OTP',
              style: TextStyle(color: context.xText.withValues(alpha: 0.54), fontSize: 12,
                  fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            _field(_emailCtrl, 'your@email.com', TextInputType.emailAddress),

            SizedBox(height: 16),

            // Phone
            Text('📱 Phone for OTP (with country code)',
              style: TextStyle(color: context.xText.withValues(alpha: 0.54), fontSize: 12,
                  fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            _field(_phoneCtrl, '+2348012345678', TextInputType.phone),

            SizedBox(height: 24),

            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor:     context.xAccent,
                  foregroundColor:     Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.black, strokeWidth: 2))
                    : Text('Save Security Settings',
                        style: TextStyle(fontSize: 15,
                            fontWeight: FontWeight.w700)),
              ),
            ),

            SizedBox(height: 400, child: ProfilePortfolioGrid(
              items: List.generate(6, (i) => "item"),
              onShowLightbox: (index) {},),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint,
      TextInputType type) => Container(
    decoration: BoxDecoration(
      color: context.xText.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.xText10),
    ),
    child: TextField(
      controller: ctrl, keyboardType: type,
      style: TextStyle(color: context.xText, fontSize: 14),
      decoration: InputDecoration(
        hintText:    hint,
        hintStyle:   TextStyle(color: context.xText30),
        border:      InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 12),
      ),
    ),
  );
}
