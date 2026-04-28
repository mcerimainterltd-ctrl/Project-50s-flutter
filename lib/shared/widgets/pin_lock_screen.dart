import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

class PinLockScreen extends StatefulWidget {
  final String  title, subtitle, icon;
  final int     pinLength;
  final bool    showCancel;
  final Future<bool> Function(String pin) onVerify;
  final VoidCallback? onCancel, onForgot;
  final bool    autoBiometric;

  const PinLockScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onVerify,
    this.icon          = '🔐',
    this.pinLength     = 4,
    this.showCancel    = false,
    this.onCancel,
    this.onForgot,
    this.autoBiometric = false,
  });

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen>
    with SingleTickerProviderStateMixin {
  String _pin      = '';
  String _error    = '';
  int    _attempts = 0;
  bool   _locked   = false;
  int    _countdown = 0;
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
    if (_locked) return;
    if (val == '⌫') {
      setState(() {
        _pin  = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1);
        _error = '';
      });
      HapticFeedback.selectionClick();
    } else if (_pin.length < widget.pinLength) {
      final next = _pin + val;
      setState(() { _pin = next; _error = ''; });
      HapticFeedback.selectionClick();
      if (next.length == widget.pinLength) {
        Future.delayed(const Duration(milliseconds: 120), () => _verify(next));
      }
    }
  }

  Future<void> _verify(String pin) async {
    final ok = await widget.onVerify(pin);
    if (!ok && mounted) {
      _attempts++;
      _shakeCtrl.forward(from: 0);
      HapticFeedback.heavyImpact();
      setState(() {
        _pin   = '';
        _error = _attempts >= 5
            ? 'Too many attempts.'
            : 'Incorrect PIN · ${5 - _attempts} left';
      });
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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: XameColors.darkBg,
      body: SafeArea(
        child: Column(children: [
          // Cancel
          if (widget.showCancel && widget.onCancel != null)
            Align(
              alignment: Alignment.topLeft,
              child: TextButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white54)),
              ),
            )
          else
            const SizedBox(height: 16),

          const Spacer(),

          // Icon
          Text(widget.icon, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 14),

          // Title
          Text(widget.title,
              style: const TextStyle(color: Colors.white, fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),

          // Subtitle
          Text(widget.subtitle,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 13)),
          const SizedBox(height: 28),

          // PIN dots with shake
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
                final filled = i < _pin.length;
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
                    boxShadow: filled ? [
                      BoxShadow(color: XameColors.primary.withValues(alpha: 0.5),
                          blurRadius: 8)
                    ] : null,
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),

          // Error / lockout
          SizedBox(height: 20,
            child: _locked
                ? Text('Try again in $_countdown s',
                    style: const TextStyle(color: Colors.redAccent,
                        fontSize: 12))
                : _error.isNotEmpty
                    ? Text(_error,
                        style: const TextStyle(color: Colors.redAccent,
                            fontSize: 12))
                    : null,
          ),

          const SizedBox(height: 24),

          // Keypad
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 64),
            child: Column(
              children: [
                _keyRow(['1', '2', '3']),
                const SizedBox(height: 14),
                _keyRow(['4', '5', '6']),
                const SizedBox(height: 14),
                _keyRow(['7', '8', '9']),
                const SizedBox(height: 14),
                _keyRow(['', '0', '⌫']),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Forgot PIN
          if (widget.onForgot != null)
            TextButton(
              onPressed: widget.onForgot,
              child: Text('Forgot PIN?',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 13))),

          const Spacer(),
        ]),
      ),
    );
  }

  Widget _keyRow(List<String> keys) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: keys.map((k) => k.isEmpty
        ? const SizedBox(width: 72, height: 72)
        : _PinKey(
            label: k,
            onTap: () => _onKey(k),
            locked: _locked,
          )).toList(),
  );
}

class _PinKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool locked;
  const _PinKey({required this.label, required this.onTap,
      this.locked = false});

  @override
  Widget build(BuildContext context) {
    final isBack = label == '⌫';
    return GestureDetector(
      onTap: locked ? null : onTap,
      child: Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color: isBack
              ? Colors.transparent
              : Colors.white.withValues(alpha: locked ? 0.04 : 0.08),
          shape: BoxShape.circle,
          border: isBack ? null : Border.all(
              color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Center(
          child: isBack
              ? Icon(Icons.backspace_outlined,
                  color: locked
                      ? Colors.white24
                      : Colors.white.withValues(alpha: 0.7),
                  size: 22)
              : Text(label,
                  style: TextStyle(
                    color: locked ? Colors.white24 : Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                  )),
        ),
      ),
    );
  }
}
