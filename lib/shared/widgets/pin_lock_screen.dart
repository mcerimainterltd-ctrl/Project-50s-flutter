
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

class PinLockScreen extends StatefulWidget {
  final String  title;
  final String  subtitle;
  final String  icon;
  final int     pinLength;
  final bool    showCancel;
  final Future<bool> Function(String pin) onVerify;
  final VoidCallback? onCancel;
  final VoidCallback? onForgot;
  final bool    autoBiometric;

  const PinLockScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onVerify,
    this.icon       = '🔐',
    this.pinLength  = 4,
    this.showCancel = false,
    this.onCancel,
    this.onForgot,
    this.autoBiometric = false,
  });

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  String _pin       = '';
  String _error     = '';
  int    _attempts  = 0;
  bool   _locked    = false;
  int    _countdown = 0;

  void _onKey(String val) {
    if (_locked) return;
    if (val == '⌫') {
      setState(() { _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1); _error = ''; });
    } else if (_pin.length < widget.pinLength) {
      final next = _pin + val;
      setState(() => _pin = next);
      if (next.length == widget.pinLength) {
        Future.delayed(const Duration(milliseconds: 100), () => _verify(next));
      }
    }
  }

  Future<void> _verify(String pin) async {
    final ok = await widget.onVerify(pin);
    if (!ok) {
      _attempts++;
      setState(() { _pin = ''; _error = _attempts >= 5
        ? 'Too many attempts.'
        : 'Incorrect PIN. \${5 - _attempts} attempts remaining.'; });
      HapticFeedback.heavyImpact();
      if (_attempts >= 5) _startLockout();
    }
  }

  void _startLockout() {
    setState(() { _locked = true; _countdown = 30; });
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _countdown--);
      if (_countdown <= 0) {
        setState(() { _locked = false; _attempts = 0; _error = ''; });
        return false;
      }
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: XameColors.darkBg,
      body: SafeArea(
        child: Column(children: [
          const Spacer(),
          Text(widget.icon, style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 16),
          Text(widget.title,
            style: const TextStyle(color: Colors.white,
                fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(widget.subtitle,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14)),
          const SizedBox(height: 32),
          // PIN dots
          Row(mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.pinLength, (i) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 14, height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _pin.length
                  ? XameColors.primary
                  : Colors.white.withValues(alpha: 0.2),
              ),
            )),
          ),
          const SizedBox(height: 16),
          if (_error.isNotEmpty)
            Text(_error,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          if (_locked)
            Text('Try again in \$_countdown seconds',
              style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          const SizedBox(height: 32),
          // Keypad
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                ...[1,2,3,4,5,6,7,8,9].map((n) => _Key(
                  label: '\$n', onTap: () => _onKey('\$n'), locked: _locked)),
                const SizedBox(),
                _Key(label: '0', onTap: () => _onKey('0'), locked: _locked),
                _Key(label: '⌫', onTap: () => _onKey('⌫'), locked: _locked),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (widget.onForgot != null)
            TextButton(
              onPressed: widget.onForgot,
              child: Text('Forgot PIN?',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 13))),
          if (widget.showCancel && widget.onCancel != null)
            TextButton(
              onPressed: widget.onCancel,
              child: Text('Cancel',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 13))),
          const Spacer(),
        ]),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool locked;
  const _Key({required this.label, required this.onTap, this.locked = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: locked ? null : onTap,
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12)),
      child: Center(
        child: Text(label,
          style: TextStyle(
            color: locked ? Colors.white30 : Colors.white,
            fontSize: label == '⌫' ? 20 : 22,
            fontWeight: FontWeight.w600))),
    ),
  );
}
