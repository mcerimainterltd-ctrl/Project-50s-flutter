import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsLockScreen extends StatefulWidget {
  final Future<bool> Function(String pin) onVerify;
  final Future<void> Function()? onForgot;
  final int pinLength;

  const SettingsLockScreen({
    super.key,
    required this.onVerify,
    this.onForgot,
    this.pinLength = 6,
  });

  @override
  State<SettingsLockScreen> createState() => _SettingsLockScreenState();
}

class _SettingsLockScreenState extends State<SettingsLockScreen>
    with TickerProviderStateMixin {

  String _pin      = '';
  String _error    = '';
  int    _attempts = 0;
  bool   _locked   = false;
  int    _countdown = 0;
  bool   _keypadVisible = false;

  late AnimationController _cursorCtrl;   // cursor blink
  late AnimationController _revealCtrl;   // keypad reveal
  late AnimationController _shakeCtrl;    // error shake
  late Animation<double>   _revealAnim;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;
  late Animation<double>   _shakeAnim;

  @override
  void initState() {
    super.initState();

    _cursorCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);

    _revealCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 680));
    _revealAnim = CurvedAnimation(parent: _revealCtrl, curve: Curves.easeOutExpo);
    _fadeAnim   = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _revealCtrl, curve: const Interval(0.0, 0.6)));
    _slideAnim  = Tween<Offset>(
            begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(CurvedAnimation(parent: _revealCtrl, curve: Curves.easeOutExpo));

    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _shakeAnim = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));
  }

  @override
  void dispose() {
    _cursorCtrl.dispose();
    _revealCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _toggleKeypad() {
    HapticFeedback.lightImpact();
    setState(() => _keypadVisible = !_keypadVisible);
    if (_keypadVisible) _revealCtrl.forward();
    else _revealCtrl.reverse();
  }

  void _onKey(String val) {
    if (_locked) return;
    if (val == '⌫') {
      setState(() { _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1); _error = ''; });
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
        _error = _attempts >= 5 ? 'Too many attempts.' : 'Wrong PIN · ${5 - _attempts} left';
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
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF06060A),
        body: SafeArea(
          child: Stack(children: [

            // ── Ambient glow backdrop ──────────────────────────────────────
            Positioned(
              top: -80, left: -60,
              child: _GlowBlob(color: const Color(0xFF00D4FF), size: 280, opacity: 0.06),
            ),
            Positioned(
              bottom: 80, right: -80,
              child: _GlowBlob(color: const Color(0xFF7B2FFF), size: 320, opacity: 0.05),
            ),

            // ── Main content ───────────────────────────────────────────────
            Column(children: [
              const Spacer(flex: 3),

              // Lock hint text
              AnimatedOpacity(
                opacity: _keypadVisible ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: Text(
                  'Settings are locked',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.18),
                    fontSize: 13,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // ── Cursor / PIN dots ──────────────────────────────────────
              GestureDetector(
                onTap: _toggleKeypad,
                child: AnimatedBuilder(
                  animation: _shakeAnim,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(_shakeAnim.value * 7 *
                        ((_shakeAnim.value * 10).round().isEven ? 1 : -1), 0),
                    child: child,
                  ),
                  child: _keypadVisible ? _PinDots(pin: _pin, length: widget.pinLength)
                      : _BlinkingCursor(controller: _cursorCtrl),
                ),
              ),

              const SizedBox(height: 16),

              // Error / lockout
              SizedBox(
                height: 18,
                child: _locked
                    ? Text('Try again in $_countdown s',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12,
                            letterSpacing: 0.5))
                    : _error.isNotEmpty
                        ? Text(_error,
                            style: const TextStyle(color: Colors.redAccent,
                                fontSize: 12, letterSpacing: 0.5))
                        : null,
              ),

              const Spacer(flex: 2),

              // ── Keypad (materializes) ──────────────────────────────────
              SlideTransition(
                position: _slideAnim,
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: _keypadVisible
                      ? _buildKeypad()
                      : const SizedBox.shrink(),
                ),
              ),

              const SizedBox(height: 24),

              // Forgot PIN
              AnimatedOpacity(
                opacity: _keypadVisible && widget.onForgot != null ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: TextButton(
                  onPressed: widget.onForgot,
                  child: Text('Forgot PIN?',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.25),
                          fontSize: 12,
                          letterSpacing: 0.8)),
                ),
              ),

              const Spacer(flex: 1),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 56),
      child: Column(children: [
        _keyRow(['1', '2', '3']),
        const SizedBox(height: 12),
        _keyRow(['4', '5', '6']),
        const SizedBox(height: 12),
        _keyRow(['7', '8', '9']),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const SizedBox(width: 72, height: 72),
          _SilkKey(label: '0', onTap: () => _onKey('0'), locked: _locked),
          _SilkKey(label: '⌫', onTap: () => _onKey('⌫'), locked: _locked),
        ]),
      ]),
    );
  }

  Widget _keyRow(List<String> keys) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: keys.map((k) =>
        _SilkKey(label: k, onTap: () => _onKey(k), locked: _locked)).toList(),
  );
}

// ── Blinking cursor ──────────────────────────────────────────────────────────
class _BlinkingCursor extends StatelessWidget {
  final AnimationController controller;
  const _BlinkingCursor({required this.controller});

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: controller,
      child: Container(
        width: 2,
        height: 32,
        decoration: BoxDecoration(
          color: const Color(0xFF00D4FF),
          borderRadius: BorderRadius.circular(1),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00D4FF).withValues(alpha: 0.8),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}

// ── PIN dots ─────────────────────────────────────────────────────────────────
class _PinDots extends StatelessWidget {
  final String pin;
  final int    length;
  const _PinDots({required this.pin, required this.length});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(length, (i) {
        final filled = i < pin.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 9),
          width:  filled ? 14 : 11,
          height: filled ? 14 : 11,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? const Color(0xFF00D4FF)
                : Colors.white.withValues(alpha: 0.15),
            boxShadow: filled
                ? [BoxShadow(
                    color: const Color(0xFF00D4FF).withValues(alpha: 0.6),
                    blurRadius: 10,
                    spreadRadius: 1)]
                : null,
          ),
        );
      }),
    );
  }
}

// ── Silk key button ───────────────────────────────────────────────────────────
class _SilkKey extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool locked;
  const _SilkKey({required this.label, required this.onTap, this.locked = false});

  @override
  State<_SilkKey> createState() => _SilkKeyState();
}

class _SilkKeyState extends State<_SilkKey>
    with SingleTickerProviderStateMixin {
  late AnimationController _press;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 80),
        reverseDuration: const Duration(milliseconds: 200));
    _scale = Tween(begin: 1.0, end: 0.88)
        .animate(CurvedAnimation(parent: _press, curve: Curves.easeOut));
  }

  @override
  void dispose() { _press.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isBack = widget.label == '⌫';
    return GestureDetector(
      onTapDown:   (_) { if (!widget.locked) _press.forward(); },
      onTapUp:     (_) { _press.reverse(); if (!widget.locked) widget.onTap(); },
      onTapCancel: ()  { _press.reverse(); },
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isBack
                ? Colors.transparent
                : Colors.white.withValues(alpha: widget.locked ? 0.03 : 0.07),
            border: Border.all(
              color: Colors.white.withValues(alpha: isBack ? 0.0 : 0.08),
            ),
            boxShadow: isBack ? null : [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.03),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: isBack
                ? Icon(Icons.backspace_outlined,
                    color: widget.locked
                        ? Colors.white12
                        : Colors.white.withValues(alpha: 0.5),
                    size: 20)
                : Text(widget.label,
                    style: TextStyle(
                      color: widget.locked ? Colors.white12 : Colors.white.withValues(alpha: 0.9),
                      fontSize: 22,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 0.5,
                    )),
          ),
        ),
      ),
    );
  }
}

// ── Ambient glow blob ─────────────────────────────────────────────────────────
class _GlowBlob extends StatelessWidget {
  final Color  color;
  final double size;
  final double opacity;
  const _GlowBlob({required this.color, required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: opacity),
        ),
      ),
    );
  }
}
