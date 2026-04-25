import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _xameIdCtrl   = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _otpCtrl      = TextEditingController();
  bool    _loading    = false;
  bool    _obscure    = true;
  bool    _needsOTP   = false;
  String? _error;
  String? _otpMessage;

  @override
  void dispose() {
    _xameIdCtrl.dispose(); _passwordCtrl.dispose(); _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final xameId   = _xameIdCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (xameId.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter your Xame-ID and password.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final auth   = ref.read(authServiceProvider);
      final result = await auth.login(xameId, password,
        otp: _needsOTP && _otpCtrl.text.isNotEmpty ? _otpCtrl.text.trim() : null);

      switch (result.type) {
        case LoginResultType.success:
          ref.read(currentUserProvider.notifier).state = result.user;
          if (mounted) context.go('/contacts');
          break;
        case LoginResultType.needsOTP:
          setState(() { _needsOTP = true; _otpMessage = result.message; });
          break;
        case LoginResultType.needsPasswordSetup:
          if (mounted) _showPasswordSetupDialog(result.user!);
          break;
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showPasswordSetupDialog(user) {
    final pwCtrl  = TextEditingController();
    final pw2Ctrl = TextEditingController();
    String? err;
    showDialog(context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        backgroundColor: XameColors.darkCard,
        title: const Text('Set Your Password',
          style: TextStyle(color: Colors.white, fontSize: 18)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Welcome back, ${user.firstName}! Please set a password.',
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 16),
          _dialogField(pwCtrl,  'New password',     true),
          const SizedBox(height: 12),
          _dialogField(pw2Ctrl, 'Confirm password', true),
          if (err != null) ...[
            const SizedBox(height: 8),
            Text(err!, style: const TextStyle(color: XameColors.danger, fontSize: 12)),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: XameColors.primary, foregroundColor: Colors.black),
            onPressed: () async {
              if (pwCtrl.text != pw2Ctrl.text) { setS(() => err = 'Passwords do not match'); return; }
              final v = ref.read(authServiceProvider).validatePassword(pwCtrl.text);
              if (!v.isValid) { setS(() => err = v.errors.first); return; }
              try {
                await ref.read(authServiceProvider).setPassword(user.xameId, pwCtrl.text);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Password set! Please sign in.'),
                  backgroundColor: XameColors.accent));
              } catch (e) { setS(() => err = e.toString().replaceFirst('Exception:', '')); }
            },
            child: const Text('Set Password'),
          ),
        ],
      )),
    );
  }

  Widget _dialogField(TextEditingController ctrl, String hint, bool obscure) =>
    TextField(
      controller: ctrl, obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: Colors.white24),
        filled: true, fillColor: XameColors.darkBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: XameColors.primary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.xBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Center(
                child: Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: context.xPrimary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: context.xPrimary, width: 1.5),
                  ),
                  child: Icon(Icons.chat_bubble_rounded, color: context.xPrimary, size: 36),
                ),
              ),
              const SizedBox(height: 24),
              const Center(child: Text('XamePage',
                style: TextStyle(color: Colors.white, fontSize: 28,
                  fontWeight: FontWeight.bold, letterSpacing: 1))),
              const Center(child: Text('Ultramodern calling & messaging',
                style: TextStyle(color: Colors.white38, fontSize: 13))),
              const SizedBox(height: 48),
              const Text('Welcome back',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text('Sign in to continue',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
              const SizedBox(height: 32),
              _label('Xame-ID'),
              const SizedBox(height: 8),
              _field(controller: _xameIdCtrl, hint: 'Enter your Xame-ID',
                icon: Icons.alternate_email,
                onSubmitted: (_) => FocusScope.of(context).nextFocus()),
              const SizedBox(height: 20),
              _label('Password'),
              const SizedBox(height: 8),
              _field(
                controller: _passwordCtrl, hint: 'Enter your password',
                icon: Icons.lock_outline, obscure: _obscure,
                suffix: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white38, size: 20),
                  onPressed: () => setState(() => _obscure = !_obscure)),
                onSubmitted: (_) => _needsOTP ? FocusScope.of(context).nextFocus() : _login(),
              ),
              if (_needsOTP) ...[
                const SizedBox(height: 20),
                if (_otpMessage != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.xPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.xPrimary.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Icon(Icons.info_outline, color: context.xPrimary, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_otpMessage!,
                        style: TextStyle(color: context.xPrimary, fontSize: 13))),
                    ]),
                  ),
                const SizedBox(height: 12),
                _label('One-Time Code'),
                const SizedBox(height: 8),
                _field(controller: _otpCtrl, hint: 'Enter 6-digit OTP',
                  icon: Icons.security, type: TextInputType.number,
                  onSubmitted: (_) => _login()),
              ],
              const SizedBox(height: 12),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.xDanger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.xDanger.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    Icon(Icons.error_outline, color: context.xDanger, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!,
                      style: TextStyle(color: context.xDanger, fontSize: 13))),
                  ]),
                ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.xPrimary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _loading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : Text(_needsOTP ? 'Verify & Sign In' : 'Sign In',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: GestureDetector(
                  onTap: () => context.go('/register'),
                  child: RichText(text: const TextSpan(
                    text: "Don't have an account? ",
                    style: TextStyle(color: Colors.white38, fontSize: 14),
                    children: [TextSpan(text: 'Sign Up',
                      style: TextStyle(color: context.xPrimary, fontWeight: FontWeight.w600))],
                  )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500));

  Widget _field({
    required TextEditingController controller,
    required String hint, required IconData icon,
    bool obscure = false, Widget? suffix,
    TextInputType? type, Function(String)? onSubmitted,
  }) => TextField(
    controller: controller, obscureText: obscure,
    keyboardType: type, onSubmitted: onSubmitted,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hint, hintStyle: const TextStyle(color: Colors.white24),
      prefixIcon: Icon(icon, color: Colors.white38, size: 20),
      suffixIcon: suffix, filled: true, fillColor: XameColors.darkCard,
      border:        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: XameColors.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );
}
