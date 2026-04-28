import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/config/constants.dart';
import 'package:dio/dio.dart';
import '../../../core/services/app_lock_service.dart';
import '../../../core/services/settings_lock_service.dart';
import 'settings_lock_screen.dart';
import '../../../core/services/wallet_lock_service.dart';
import '../../../shared/widgets/pin_lock_screen.dart';
import '../../contacts/providers/contacts_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'theme_picker_screen.dart';
import '../../messaging/screens/chat_wallpaper.dart';
import '../../calling/call_settings.dart';

// ── Settings state ────────────────────────────────────────────────────────────
class SettingsData {
  // Privacy
  final String lastSeen;        // 'everyone' | 'contacts' | 'nobody'
  final String profilePhoto;    // 'everyone' | 'contacts' | 'nobody'
  final bool   readReceipts;
  final bool   typingIndicators;

  // Notifications
  final bool   msgSound;
  final bool   msgVibration;
  final bool   msgPreview;
  final bool   callSound;
  final bool   callVibration;
  final bool   callFullscreen;

  // Chats
  final bool   enterToSend;
  final String defaultTimer;    // 'off' | '5m' | '1h' | '1d' | '7d'

  // Calls
  final bool   silenceUnknown;
  final bool   lowData;
  final bool   noiseSuppression;
  final bool   echoCancellation;

  // Appearance
  final String fontSize;        // 'small' | 'normal' | 'large'
  final String bubbleStyle;     // 'modern' | 'classic' | 'minimal'
  final bool   reducedMotion;
  final bool   highContrast;

  const SettingsData({
    this.lastSeen        = 'contacts',
    this.profilePhoto    = 'contacts',
    this.readReceipts    = true,
    this.typingIndicators = true,
    this.msgSound        = true,
    this.msgVibration    = true,
    this.msgPreview      = true,
    this.callSound       = true,
    this.callVibration   = true,
    this.callFullscreen  = true,
    this.enterToSend     = false,
    this.defaultTimer    = 'off',
    this.silenceUnknown  = false,
    this.lowData         = false,
    this.noiseSuppression = true,
    this.echoCancellation = true,
    this.fontSize        = 'normal',
    this.bubbleStyle     = 'modern',
    this.reducedMotion   = false,
    this.highContrast    = false,
  });

  SettingsData copyWith({
    String? lastSeen, String? profilePhoto,
    bool? readReceipts, bool? typingIndicators,
    bool? msgSound, bool? msgVibration, bool? msgPreview,
    bool? callSound, bool? callVibration, bool? callFullscreen,
    bool? enterToSend, String? defaultTimer,
    bool? silenceUnknown, bool? lowData,
    bool? noiseSuppression, bool? echoCancellation,
    String? fontSize, String? bubbleStyle,
    bool? reducedMotion, bool? highContrast,
  }) => SettingsData(
    lastSeen:         lastSeen         ?? this.lastSeen,
    profilePhoto:     profilePhoto     ?? this.profilePhoto,
    readReceipts:     readReceipts     ?? this.readReceipts,
    typingIndicators: typingIndicators ?? this.typingIndicators,
    msgSound:         msgSound         ?? this.msgSound,
    msgVibration:     msgVibration     ?? this.msgVibration,
    msgPreview:       msgPreview       ?? this.msgPreview,
    callSound:        callSound        ?? this.callSound,
    callVibration:    callVibration    ?? this.callVibration,
    callFullscreen:   callFullscreen   ?? this.callFullscreen,
    enterToSend:      enterToSend      ?? this.enterToSend,
    defaultTimer:     defaultTimer     ?? this.defaultTimer,
    silenceUnknown:   silenceUnknown   ?? this.silenceUnknown,
    lowData:          lowData          ?? this.lowData,
    noiseSuppression: noiseSuppression ?? this.noiseSuppression,
    echoCancellation: echoCancellation ?? this.echoCancellation,
    fontSize:         fontSize         ?? this.fontSize,
    bubbleStyle:      bubbleStyle      ?? this.bubbleStyle,
    reducedMotion:    reducedMotion    ?? this.reducedMotion,
    highContrast:     highContrast     ?? this.highContrast,
  );

  Map<String, dynamic> toMap() => {
    'lastSeen': lastSeen, 'profilePhoto': profilePhoto,
    'readReceipts': readReceipts, 'typingIndicators': typingIndicators,
    'msgSound': msgSound, 'msgVibration': msgVibration, 'msgPreview': msgPreview,
    'callSound': callSound, 'callVibration': callVibration, 'callFullscreen': callFullscreen,
    'enterToSend': enterToSend, 'defaultTimer': defaultTimer,
    'silenceUnknown': silenceUnknown, 'lowData': lowData,
    'noiseSuppression': noiseSuppression, 'echoCancellation': echoCancellation,
    'fontSize': fontSize, 'bubbleStyle': bubbleStyle,
    'reducedMotion': reducedMotion, 'highContrast': highContrast,
  };

  factory SettingsData.fromMap(Map m) => SettingsData(
    lastSeen:         m['lastSeen']         ?? 'contacts',
    profilePhoto:     m['profilePhoto']     ?? 'contacts',
    readReceipts:     m['readReceipts']     ?? true,
    typingIndicators: m['typingIndicators'] ?? true,
    msgSound:         m['msgSound']         ?? true,
    msgVibration:     m['msgVibration']     ?? true,
    msgPreview:       m['msgPreview']       ?? true,
    callSound:        m['callSound']        ?? true,
    callVibration:    m['callVibration']    ?? true,
    callFullscreen:   m['callFullscreen']   ?? true,
    enterToSend:      m['enterToSend']      ?? false,
    defaultTimer:     m['defaultTimer']     ?? 'off',
    silenceUnknown:   m['silenceUnknown']   ?? false,
    lowData:          m['lowData']          ?? false,
    noiseSuppression: m['noiseSuppression'] ?? true,
    echoCancellation: m['echoCancellation'] ?? true,
    fontSize:         m['fontSize']         ?? 'normal',
    bubbleStyle:      m['bubbleStyle']      ?? 'modern',
    reducedMotion:    m['reducedMotion']    ?? false,
    highContrast:     m['highContrast']     ?? false,
  );
}

// ── Provider ──────────────────────────────────────────────────────────────────
class SettingsNotifier extends StateNotifier<SettingsData> {
  static const _box = 'xame_prefs';
  static const _key = 'settings_data';

  SettingsNotifier() : super(const SettingsData()) { _load(); }

  Future<void> _load() async {
    final box  = await Hive.openBox(_box);
    final raw  = box.get(_key);
    if (raw != null) state = SettingsData.fromMap(Map.from(raw));
  }

  Future<void> update(SettingsData s) async {
    state = s;
    final box = await Hive.openBox(_box);
    await box.put(_key, s.toMap());
  }

  Future<void> syncPrivacyToServer(String xameId) async {
    try {
      final dio = Dio();
      await dio.post(
        '${AppConstants.serverUrl}/api/users/$xameId/privacy',
        data: {
          'lastSeen':         state.lastSeen,
          'profilePhoto':     state.profilePhoto,
          'readReceipts':     state.readReceipts,
          'typingIndicators': state.typingIndicators,
        },
      );
    } catch (e) {
      debugPrint('syncPrivacyToServer error: $e');
    }
  }
}


final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsData>(
        (_) => SettingsNotifier());

// ── Screen ────────────────────────────────────────────────────────────────────
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = '${info.version} (${info.buildNumber})');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme    = ref.watch(themeProvider);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    void save(SettingsData s) => notifier.update(s);

    return Scaffold(
      backgroundColor: theme.bg,
      appBar: AppBar(
        backgroundColor: theme.surface,
        title: Text('Settings',
            style: TextStyle(color: theme.text, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: theme.text, size: 18),
          onPressed: () => context.canPop() ? context.pop() : context.go('/contacts')),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [

          // ── Account & Privacy ───────────────────────────────────────────────
          _Section(theme: theme, title: 'Account & Privacy', children: [
            _SelectTile(
              theme:   theme,
              icon:    Icons.access_time_rounded,
              title:   'Last Seen',
              value:   settings.lastSeen,
              options: const ['everyone', 'contacts', 'nobody'],
              labels:  const ['Everyone', 'My Contacts', 'Nobody'],
              onChanged: (v) async {
                save(settings.copyWith(lastSeen: v));
                final user = ref.read(currentUserProvider);
                if (user != null) await ref.read(settingsProvider.notifier).syncPrivacyToServer(user.xameId);
              },
            ),
            _SelectTile(
              theme:   theme,
              icon:    Icons.photo_outlined,
              title:   'Profile Photo',
              value:   settings.profilePhoto,
              options: const ['everyone', 'contacts', 'nobody'],
              labels:  const ['Everyone', 'My Contacts', 'Nobody'],
              onChanged: (v) async {
                save(settings.copyWith(profilePhoto: v));
                final user = ref.read(currentUserProvider);
                if (user != null) await ref.read(settingsProvider.notifier).syncPrivacyToServer(user.xameId);
              },
            ),
            _ToggleTile(
              theme:     theme,
              icon:      Icons.done_all_rounded,
              title:     'Read Receipts',
              subtitle:  'Show when messages are read',
              value:     settings.readReceipts,
              onChanged: (v) async {
                save(settings.copyWith(readReceipts: v));
                final user = ref.read(currentUserProvider);
                if (user != null) await ref.read(settingsProvider.notifier).syncPrivacyToServer(user.xameId);
              },
            ),
            _ToggleTile(
              theme:     theme,
              icon:      Icons.keyboard_outlined,
              title:     'Typing Indicators',
              subtitle:  'Show when you are typing',
              value:     settings.typingIndicators,
              onChanged: (v) async {
                save(settings.copyWith(typingIndicators: v));
                final user = ref.read(currentUserProvider);
                if (user != null) await ref.read(settingsProvider.notifier).syncPrivacyToServer(user.xameId);
              },
            ),
          ]),

          // ── Notifications ───────────────────────────────────────────────────
          _Section(theme: theme, title: 'Notifications', children: [
            _SectionSubtitle(theme: theme, text: 'Messages'),
            _ToggleTile(
              theme:     theme,
              icon:      Icons.volume_up_outlined,
              title:     'Sound',
              value:     settings.msgSound,
              onChanged: (v) => save(settings.copyWith(msgSound: v)),
            ),
            _ToggleTile(
              theme:     theme,
              icon:      Icons.vibration_rounded,
              title:     'Vibration',
              value:     settings.msgVibration,
              onChanged: (v) => save(settings.copyWith(msgVibration: v)),
            ),
            _ToggleTile(
              theme:     theme,
              icon:      Icons.visibility_outlined,
              title:     'Message Preview',
              subtitle:  'Show message content in notifications',
              value:     settings.msgPreview,
              onChanged: (v) => save(settings.copyWith(msgPreview: v)),
            ),
            _SectionSubtitle(theme: theme, text: 'Calls'),
            _ToggleTile(
              theme:     theme,
              icon:      Icons.ring_volume_outlined,
              title:     'Ringtone',
              value:     settings.callSound,
              onChanged: (v) => save(settings.copyWith(callSound: v)),
            ),
            _ToggleTile(
              theme:     theme,
              icon:      Icons.vibration_rounded,
              title:     'Vibration',
              value:     settings.callVibration,
              onChanged: (v) => save(settings.copyWith(callVibration: v)),
            ),
            _ToggleTile(
              theme:     theme,
              icon:      Icons.fullscreen_rounded,
              title:     'Full-Screen Incoming Calls',
              subtitle:  'Show call UI on lock screen',
              value:     settings.callFullscreen,
              onChanged: (v) => save(settings.copyWith(callFullscreen: v)),
            ),
            _NavTile(
              theme:    theme,
              icon:     Icons.block_outlined,
              title:    "Blocked Numbers",
              subtitle: "Manage blocked contacts",
              onTap: () {
                final contacts = ref.read(contactsProvider).valueOrNull ?? [];
                BlockedNumbersDialog.show(context,
                  contacts: contacts.map((c) => {'id': c.id, 'name': c.name}).toList());
              },
            ),
          ]),

          // ── Chats ───────────────────────────────────────────────────────────
          _Section(theme: theme, title: 'Chats', children: [
            _ToggleTile(
              theme:     theme,
              icon:      Icons.keyboard_return_rounded,
              title:     'Enter to Send',
              subtitle:  'Press Enter to send messages',
              value:     settings.enterToSend,
              onChanged: (v) => save(settings.copyWith(enterToSend: v)),
            ),
            _SelectTile(
              theme:   theme,
              icon:    Icons.timer_outlined,
              title:   'Default Disappearing Timer',
              value:   settings.defaultTimer,
              options: const ['off', '5m', '1h', '24h', '7d'],
              labels:  const ['Off', '5 Minutes', '1 Hour', '24 Hours', '7 Days'],
              onChanged: (v) => save(settings.copyWith(defaultTimer: v)),
            ),
          ]),

          // ── Calls ────────────────────────────────────────────────────────────
          _Section(theme: theme, title: 'Calls', children: [
            _ToggleTile(
              theme:     theme,
              icon:      Icons.block_rounded,
              title:     'Silence Unknown Callers',
              subtitle:  'Only ring for contacts',
              value:     settings.silenceUnknown,
              onChanged: (v) => save(settings.copyWith(silenceUnknown: v)),
            ),
            _ToggleTile(
              theme:     theme,
              icon:      Icons.data_saver_on_outlined,
              title:     'Low Data Mode',
              subtitle:  'Reduce data usage during calls',
              value:     settings.lowData,
              onChanged: (v) => save(settings.copyWith(lowData: v)),
            ),
            _ToggleTile(
              theme:     theme,
              icon:      Icons.noise_aware_rounded,
              title:     'Noise Suppression',
              value:     settings.noiseSuppression,
              onChanged: (v) => save(settings.copyWith(noiseSuppression: v)),
            ),
            _ToggleTile(
              theme:     theme,
              icon:      Icons.hearing_rounded,
              title:     'Echo Cancellation',
              value:     settings.echoCancellation,
              onChanged: (v) => save(settings.copyWith(echoCancellation: v)),
            ),
          ]),

          // ── Appearance ───────────────────────────────────────────────────────
          _Section(theme: theme, title: 'Appearance', children: [
            _NavTile(
              theme:    theme,
              icon:     Icons.palette_outlined,
              title:    'Theme',
              subtitle: '${ref.watch(themeProvider).emoji} ${ref.watch(themeProvider).name}',
              color:    theme.primary,
              onTap:    () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ThemePickerScreen())),
            ),
            _NavTile(
              theme:    theme,
              icon:     Icons.wallpaper_outlined,
              title:    'Chat Wallpaper',
              subtitle: 'Global wallpaper for all chats',
              color:    theme.accent,
              onTap:    () => WallpaperPickerSheet.show(context,
                contactId:   'global',
                contactName: 'All Chats',
                isGlobal:    true,
                onChanged:   () {},
              ),
            ),
            _SelectTile(
              theme:   theme,
              icon:    Icons.format_size_rounded,
              title:   'Font Size',
              value:   settings.fontSize,
              options: const ['small', 'normal', 'large'],
              labels:  const ['Small', 'Normal', 'Large'],
              onChanged: (v) => save(settings.copyWith(fontSize: v)),
            ),
            _SelectTile(
              theme:   theme,
              icon:    Icons.chat_bubble_outline_rounded,
              title:   'Bubble Style',
              value:   settings.bubbleStyle,
              options: const ['modern', 'classic', 'minimal'],
              labels:  const ['Modern', 'Classic', 'Minimal'],
              onChanged: (v) => save(settings.copyWith(bubbleStyle: v)),
            ),
            _ToggleTile(
              theme:     theme,
              icon:      Icons.motion_photos_off_outlined,
              title:     'Reduce Motion',
              subtitle:  'Disable animations',
              value:     settings.reducedMotion,
              onChanged: (v) => save(settings.copyWith(reducedMotion: v)),
            ),
            _ToggleTile(
              theme:     theme,
              icon:      Icons.contrast_rounded,
              title:     'High Contrast',
              value:     settings.highContrast,
              onChanged: (v) => save(settings.copyWith(highContrast: v)),
            ),
          ]),

          // ── Security ────────────────────────────────────────────────────────────
          _Section(theme: theme, title: 'Security', children: [
            _NavTile(
              theme:    theme,
              icon:     Icons.lock_outline_rounded,
              title:    'App Lock',
              subtitle: ref.watch(appLockProvider).enabled ? 'Enabled' : 'Disabled',
              onTap: () => _showAppLockSetup(context, ref),
            ),
            _NavTile(
              theme:    theme,
              icon: Icons.admin_panel_settings_outlined,
              title: 'Settings Lock',
              subtitle: ref.watch(settingsLockProvider).enabled ? 'Enabled' : 'Disabled',
              onTap: () => _showSettingsLockSetup(context, ref),
            ),
            _NavTile(
              theme:    theme,
              icon:     Icons.account_balance_wallet_outlined,
              title:    'Wallet PIN',
              subtitle: ref.watch(walletLockProvider).enabled ? 'Enabled' : 'Disabled',
              onTap: () => _showWalletLockSetup(context, ref),
            ),
          ]),

          // ── Help & About ─────────────────────────────────────────────────────
          _Section(theme: theme, title: 'Help & About', children: [
            _NavTile(
              theme:    theme,
              icon:     Icons.help_outline_rounded,
              title:    'FAQ',
              onTap:    () => launchUrl(Uri.parse('https://xamepage.com/faq'),
                  mode: LaunchMode.externalApplication),
            ),
            _NavTile(
              theme:    theme,
              icon:     Icons.support_agent_rounded,
              title:    'Contact Support',
              onTap:    () => launchUrl(
                Uri(scheme: 'mailto', path: 'support@xamepage.com',
                  queryParameters: {'subject': 'XamePage Support'}),
                mode: LaunchMode.externalApplication),
            ),
            _NavTile(
              theme:    theme,
              icon:     Icons.description_outlined,
              title:    'Terms of Service',
              onTap:    () => launchUrl(Uri.parse('https://xamepage.com/terms'),
                  mode: LaunchMode.externalApplication),
            ),
            _NavTile(
              theme:    theme,
              icon:     Icons.privacy_tip_outlined,
              title:    'Privacy Policy',
              onTap:    () => launchUrl(Uri.parse('https://xamepage.com/privacy'),
                  mode: LaunchMode.externalApplication),
            ),
            if (_version.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text('XamePage v$_version',
                  style: TextStyle(color: theme.textSecondary,
                      fontSize: 12, fontWeight: FontWeight.w500)),
              ),
          ]),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ── Shared tile widgets ───────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  final XameTheme theme;
  final String title;
  final List<Widget> children;
  _Section({required this.theme, required this.title,
      required this.children});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Text(title,
          style: TextStyle(color: theme.textSecondary, fontSize: 12,
              fontWeight: FontWeight.w600, letterSpacing: 0.8)),
      ),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color:  theme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: XameColors.darkBg.withValues(alpha: 0.06)),
        ),
        child: Column(children: _separated(children)),
      ),
    ],
  );

  List<Widget> _separated(List<Widget> items) {
    final result = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      result.add(items[i]);
      if (i < items.length - 1) {
        result.add(Divider(height: 1, color: XameColors.darkSurface,
            indent: 52));
      }
    }
    return result;
  }
}

class _SectionSubtitle extends StatelessWidget {
  final XameTheme theme;
  final String text;
  const _SectionSubtitle({required this.theme, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
    child: Text(text, style: TextStyle(color: theme.primary,
        fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)));
}

class _ToggleTile extends StatelessWidget {
  final XameTheme theme;
  final IconData  icon;
  final String    title;
  final String?   subtitle;
  final bool      value;
  final ValueChanged<bool> onChanged;
  _ToggleTile({required this.theme, required this.icon,
      required this.title, this.subtitle, required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Icon(icon, color: theme.textSecondary, size: 20),
      SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: theme.text, fontSize: 14,
              fontWeight: FontWeight.w500)),
          if (subtitle != null)
            Text(subtitle!, style: TextStyle(color: theme.textSecondary,
                fontSize: 12)),
        ])),
      Switch(
        value:     value,
        onChanged: onChanged,
        activeColor: theme.primary,
        inactiveTrackColor: XameColors.darkSurface,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ]),
  );
}

class _SelectTile extends StatelessWidget {
  final XameTheme     theme;
  final IconData      icon;
  final String        title;
  final String        value;
  final List<String>  options;
  final List<String>  labels;
  final ValueChanged<String> onChanged;
  const _SelectTile({required this.theme, required this.icon,
      required this.title, required this.value, required this.options,
      required this.labels, required this.onChanged});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => _showPicker(context),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(icon, color: theme.textSecondary, size: 20),
        SizedBox(width: 14),
        Expanded(child: Text(title, style: TextStyle(color: theme.text,
            fontSize: 14, fontWeight: FontWeight.w500))),
        Text(labels[options.indexOf(value)],
          style: TextStyle(color: theme.primary, fontSize: 13,
              fontWeight: FontWeight.w500)),
        SizedBox(width: 4),
        Icon(Icons.chevron_right, color: theme.textSecondary, size: 16),
      ]),
    ),
  );

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(color: XameColors.darkSurface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Text(title, style: TextStyle(color: theme.text,
                fontSize: 16, fontWeight: FontWeight.w700))),
          ...List.generate(options.length, (i) => InkWell(
            onTap: () { onChanged(options[i]); Navigator.pop(context); },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Text(labels[i], style: TextStyle(
                  color: options[i] == value ? theme.primary : theme.text,
                  fontSize: 15,
                  fontWeight: options[i] == value
                      ? FontWeight.w600 : FontWeight.normal)),
                const Spacer(),
                if (options[i] == value)
                  Icon(Icons.check_circle, color: theme.primary, size: 18),
              ]),
            ),
          )),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ]),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final XameTheme  theme;
  final IconData   icon;
  final String     title;
  final String?    subtitle;
  final Color?     color;
  final VoidCallback onTap;
  const _NavTile({required this.theme, required this.icon,
      required this.title, this.subtitle, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(icon, color: color ?? theme.textSecondary, size: 20),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(
              color: color ?? theme.text,
              fontSize: 14, fontWeight: FontWeight.w500)),
            if (subtitle != null)
              Text(subtitle!, style: TextStyle(color: theme.textSecondary,
                  fontSize: 12)),
          ],
        )),
        Icon(Icons.chevron_right, color: theme.textSecondary, size: 16),
      ]),
    ),
  );
}

void _showSettingsLockSetup(BuildContext context, WidgetRef ref) {
  final state    = ref.read(settingsLockProvider);
  final notifier = ref.read(settingsLockProvider.notifier);
  if (state.enabled) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.lock_open_outlined),
          title: const Text('Disable Settings Lock'),
          subtitle: const Text('Requires current PIN'),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => _VerifyThenDisableSettings(notifier: notifier)));
          }),
        const SizedBox(height: 8),
      ])),
    );
  } else {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _SetPinScreen(
      title: 'Set Settings Lock PIN',
      pinLength: 4,
      onSet: (pin) { notifier.enable(pin); Navigator.pop(context); },
    )));
  }
}

class _VerifyThenDisableSettings extends ConsumerStatefulWidget {
  final SettingsLockNotifier notifier;
  const _VerifyThenDisableSettings({required this.notifier});
  @override
  ConsumerState<_VerifyThenDisableSettings> createState() => _VTDSState();
}
class _VTDSState extends ConsumerState<_VerifyThenDisableSettings> {
  @override
  Widget build(BuildContext context) {
    return SettingsLockScreen(
      pinLength: 4,
      onVerify: (pin) async {
        final ok = widget.notifier.verify(pin);
        if (ok) {
          await widget.notifier.disable();
          if (mounted) Navigator.pop(context);
        }
        return ok;
      },
    );
  }
}

void _showAppLockSetup(BuildContext context, WidgetRef ref) {
  final state   = ref.read(appLockProvider);
  final notifier = ref.read(appLockProvider.notifier);
  if (state.enabled) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.lock_open_outlined),
          title: const Text('Disable App Lock'),
          onTap: () { Navigator.pop(context); notifier.disable(); }),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Lock Delay'),
          subtitle: Text(_lockDelayLabel(state.delayMs)),
          onTap: () { Navigator.pop(context); _showDelayPicker(context, ref); }),
        const SizedBox(height: 8),
      ])),
    );
  } else {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _SetPinScreen(
      title: 'Set App Lock PIN',
      pinLength: 6,
      onSet: (pin) { notifier.enable(pin); Navigator.pop(context); },
    )));
  }
}

void _showWalletLockSetup(BuildContext context, WidgetRef ref) {
  final state    = ref.read(walletLockProvider);
  final notifier = ref.read(walletLockProvider.notifier);
  if (state.enabled) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.lock_open_outlined),
          title: const Text('Disable Wallet PIN'),
          onTap: () { Navigator.pop(context); notifier.disable(); }),
        const SizedBox(height: 8),
      ])),
    );
  } else {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _SetPinScreen(
      title: 'Set Wallet PIN',
      pinLength: 4,
      onSet: (pin) { notifier.enable(pin); Navigator.pop(context); },
    )));
  }
}

void _showDelayPicker(BuildContext context, WidgetRef ref) {
  final options = [
    (0,       'Immediately'),
    (30000,   '30 seconds'),
    (60000,   '1 minute'),
    (300000,  '5 minutes'),
    (1800000, '30 minutes'),
    (-1,      'Never'),
  ];
  showModalBottomSheet(
    context: context,
    builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
      children: options.map((o) => ListTile(
        title: Text(o.$2),
        onTap: () {
          ref.read(appLockProvider.notifier).setDelay(o.$1);
          Navigator.pop(context);
        },
      )).toList())),
  );
}

String _lockDelayLabel(int ms) {
  if (ms == 0)       return 'Immediately';
  if (ms == 30000)   return '30 seconds';
  if (ms == 60000)   return '1 minute';
  if (ms == 300000)  return '5 minutes';
  if (ms == 1800000) return '30 minutes';
  if (ms == -1)      return 'Never';
  return '1 minute';
}

class _SetPinScreen extends StatefulWidget {
  final String title;
  final int    pinLength;
  final void Function(String pin) onSet;
  const _SetPinScreen({required this.title, required this.onSet,
      this.pinLength = 4});
  @override
  State<_SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<_SetPinScreen>
    with SingleTickerProviderStateMixin {
  String _pin1 = '', _pin2 = '';
  bool   _step2 = false;
  String _error = '';
  late AnimationController _shakeCtrl;
  late Animation<double>   _shake;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 400));
    _shake = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));
  }

  @override
  void dispose() { _shakeCtrl.dispose(); super.dispose(); }

  void _onKey(String val) {
    if (_step2) {
      if (val == '⌫') {
        setState(() { _pin2 = _pin2.isEmpty ? '' : _pin2.substring(0, _pin2.length-1); });
        return;
      }
      if (_pin2.length >= widget.pinLength) return;
      final next = _pin2 + val;
      setState(() => _pin2 = next);
      if (next.length == widget.pinLength) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (_pin1 == _pin2) {
            widget.onSet(_pin1);
          } else {
            _shakeCtrl.forward(from: 0);
            setState(() { _pin2 = ''; _error = 'PINs do not match. Try again.';
                _step2 = false; _pin1 = ''; });
          }
        });
      }
    } else {
      if (val == '⌫') {
        setState(() { _pin1 = _pin1.isEmpty ? '' : _pin1.substring(0, _pin1.length-1); });
        return;
      }
      if (_pin1.length >= widget.pinLength) return;
      final next = _pin1 + val;
      setState(() => _pin1 = next);
      if (next.length == widget.pinLength) {
        Future.delayed(const Duration(milliseconds: 150), () =>
            setState(() { _step2 = true; _error = ''; }));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pin = _step2 ? _pin2 : _pin1;
    return Scaffold(
      backgroundColor: XameColors.darkBg,
      appBar: AppBar(
        backgroundColor: XameColors.darkBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white70, size: 18),
          onPressed: () => Navigator.pop(context)),
        title: Text(widget.title,
            style: const TextStyle(color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: Column(children: [
          const Spacer(),
          // Step indicator
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _stepDot(active: !_step2, done: _step2),
            const SizedBox(width: 8),
            _stepDot(active: _step2, done: false),
          ]),
          const SizedBox(height: 20),
          Text(_step2 ? 'Confirm PIN' : 'Enter PIN',
              style: const TextStyle(color: Colors.white, fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(_step2
              ? 'Re-enter your PIN to confirm'
              : 'Choose a ${widget.pinLength}-digit PIN',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 13)),
          const SizedBox(height: 28),
          // PIN dots
          AnimatedBuilder(
            animation: _shake,
            builder: (_, child) => Transform.translate(
              offset: Offset(
                  _shake.value * 8 * ((_shake.value * 10).round().isEven ? 1 : -1),
                  0),
              child: child),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.pinLength, (i) {
                final filled = i < pin.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: filled ? 16 : 14,
                  height: filled ? 16 : 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? XameColors.primary
                        : Colors.white.withValues(alpha: 0.2),
                    boxShadow: filled ? [BoxShadow(
                        color: XameColors.primary.withValues(alpha: 0.5),
                        blurRadius: 8)] : null,
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(height: 20,
            child: _error.isNotEmpty
                ? Text(_error, style: const TextStyle(
                    color: Colors.redAccent, fontSize: 12))
                : null),
          const SizedBox(height: 24),
          // Keypad
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 64),
            child: Column(children: [
              _keyRow(['1','2','3']),
              const SizedBox(height: 14),
              _keyRow(['4','5','6']),
              const SizedBox(height: 14),
              _keyRow(['7','8','9']),
              const SizedBox(height: 14),
              _keyRow(['','0','⌫']),
            ]),
          ),
          const Spacer(),
        ]),
      ),
    );
  }

  Widget _stepDot({required bool active, required bool done}) =>
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: active ? 24 : 8, height: 8,
        decoration: BoxDecoration(
          color: done || active
              ? XameColors.primary
              : Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
        ),
      );

  Widget _keyRow(List<String> keys) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: keys.map((k) => k.isEmpty
        ? const SizedBox(width: 72, height: 72)
        : _PinKey(label: k, onTap: () => _onKey(k))).toList(),
  );
}

class _PinKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PinKey({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isBack = label == '⌫';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color: isBack
              ? Colors.transparent
              : Colors.white.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: isBack ? null : Border.all(
              color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Center(
          child: isBack
              ? Icon(Icons.backspace_outlined,
                  color: Colors.white.withValues(alpha: 0.7), size: 22)
              : Text(label,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 24, fontWeight: FontWeight.w400)),
        ),
      ),
    );
  }
}
