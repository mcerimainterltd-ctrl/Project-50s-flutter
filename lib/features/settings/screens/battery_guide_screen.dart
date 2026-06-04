// lib/features/settings/screens/battery_guide_screen.dart
// Manufacturer-specific battery optimization guide for XamePage 24/7 availability

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BatteryGuideScreen extends StatefulWidget {
  const BatteryGuideScreen({Key? key}) : super(key: key);
  @override
  State<BatteryGuideScreen> createState() => _BatteryGuideScreenState();
}

class _BatteryGuideScreenState extends State<BatteryGuideScreen> {
  static const _bridge = MethodChannel('com.xamepage.app/android_bridge');
  String _brand = '';

  @override
  void initState() {
    super.initState();
    _detectBrand();
  }

  void _detectBrand() {
    _bridge.invokeMethod('getDeviceBrand').then((v) {
      if (v != null && mounted) setState(() => _brand = v.toString().toLowerCase());
    }).catchError((_) {});
  }

  Map<String, dynamic> get _guide {
    if (_brand.contains('xiaomi') || _brand.contains('redmi') || _brand.contains('poco')) {
      return {
        'name': 'Xiaomi / Redmi / POCO (MIUI)',
        'icon': '📱',
        'color': const Color(0xFFFF6900),
        'steps': [
          'Open Phone Settings',
          'Go to "Apps" → find XamePage',
          'Tap "Battery Saver" → select "No restrictions"',
          'Go back to App info → tap "Autostart"',
          'Enable Autostart for XamePage',
          'Go to Settings → "Battery & Performance"',
          'Tap "Choose apps" → find XamePage',
          'Set to "No restrictions"',
        ],
        'tip': 'MIUI aggressively kills background apps. Autostart is critical.',
      };
    } else if (_brand.contains('huawei') || _brand.contains('honor')) {
      return {
        'name': 'Huawei / Honor (EMUI)',
        'icon': '📱',
        'color': const Color(0xFFCF0A2C),
        'steps': [
          'Open Phone Settings',
          'Go to "Apps" → find XamePage',
          'Tap "Battery" → enable "Allow background activity"',
          'Go to Settings → "Battery" → "Launch"',
          'Find XamePage → disable "Manage automatically"',
          'Enable "Auto-launch", "Secondary launch" and "Run in background"',
        ],
        'tip': 'Huawei\'s Launch Manager controls background access. All three toggles must be on.',
      };
    } else if (_brand.contains('samsung')) {
      return {
        'name': 'Samsung (One UI)',
        'icon': '📱',
        'color': const Color(0xFF1428A0),
        'steps': [
          'Open Phone Settings',
          'Go to "Battery" → "Background usage limits"',
          'Make sure XamePage is NOT in "Sleeping apps" or "Deep sleeping apps"',
          'Go to Settings → "Apps" → XamePage',
          'Tap "Battery" → select "Unrestricted"',
          'Go back → tap "Mobile data" → enable "Allow background data usage"',
        ],
        'tip': 'Samsung\'s "Sleeping apps" list is the main culprit. Remove XamePage from it.',
      };
    } else if (_brand.contains('oppo') || _brand.contains('realme') || _brand.contains('oneplus')) {
      return {
        'name': 'OPPO / Realme / OnePlus (ColorOS)',
        'icon': '📱',
        'color': const Color(0xFF1D8348),
        'steps': [
          'Open Phone Settings',
          'Go to "Battery" → "Battery optimization"',
          'Find XamePage → tap "Don\'t optimize"',
          'Go to Settings → "Apps" → XamePage → "Battery"',
          'Enable "Allow auto-launch" and "Allow background running"',
          'Go to Settings → "Additional Settings" → "Battery"',
          'Add XamePage to the whitelist',
        ],
        'tip': 'ColorOS has both app-level and system-level battery controls. Both must be set.',
      };
    } else if (_brand.contains('vivo')) {
      return {
        'name': 'Vivo (OriginOS / FuntouchOS)',
        'icon': '📱',
        'color': const Color(0xFF415FFF),
        'steps': [
          'Open Phone Settings',
          'Go to "Battery" → "High background power consumption"',
          'Add XamePage to exceptions',
          'Go to Settings → "Apps" → XamePage',
          'Tap "Battery" → enable "Background running"',
          'Go to "i Manager" → "App Management"',
          'Find XamePage → enable "Auto-start"',
        ],
        'tip': 'Vivo\'s i Manager controls autostart separately from Settings.',
      };
    } else {
      return {
        'name': 'Your Device',
        'icon': '📱',
        'color': const Color(0xFF00BCD4),
        'steps': [
          'Open Phone Settings',
          'Go to "Battery" or "Battery & Performance"',
          'Find "Battery optimization" or "Power saving exceptions"',
          'Find XamePage and select "Don\'t optimize" or "No restrictions"',
          'Go to Settings → "Apps" → XamePage → "Battery"',
          'Set to "Unrestricted" or "No restrictions"',
          'Look for "Autostart" or "Background activity" and enable it',
        ],
        'tip': 'Settings names vary by manufacturer. Look for battery, autostart, or background activity options.',
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final guide = _guide;
    final color = guide['color'] as Color;
    final steps = guide['steps'] as List<String>;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Stay Connected 24/7',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withOpacity(0.2), color.withOpacity(0.05)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
                  child: Icon(Icons.battery_charging_full_rounded, color: color, size: 22)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Enable Background Access',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Detected: ${guide['name']}',
                      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
                ])),
              ]),
              const SizedBox(height: 12),
              const Text(
                'To receive calls and messages when XamePage is in the background, follow these steps for your device:',
                style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.5)),
            ]),
          ),
          const SizedBox(height: 24),

          // Steps
          ...List.generate(steps.length, (i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle,
                    border: Border.all(color: color.withOpacity(0.4))),
                child: Center(child: Text('${i + 1}',
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)))),
              const SizedBox(width: 12),
              Expanded(child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(steps[i],
                    style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)))),
            ]),
          )),

          const SizedBox(height: 16),

          // Tip
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.2))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lightbulb_outline_rounded, color: Colors.amber, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(guide['tip'] as String,
                  style: const TextStyle(color: Colors.amber, fontSize: 12, height: 1.4))),
            ]),
          ),

          const SizedBox(height: 24),

          // Open battery settings button
          SizedBox(width: double.infinity, height: 50,
            child: ElevatedButton.icon(
              onPressed: () async {
                try {
                  await _bridge.invokeMethod('openBatterySettings');
                } catch (e) {
                  debugPrint('openBatterySettings error: \$e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not open settings: \$e')));
                  }
                }
              },
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('Open Battery Settings',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'After completing these steps, XamePage will stay connected and you\'ll never miss a call or message.',
            style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
            textAlign: TextAlign.center),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}
