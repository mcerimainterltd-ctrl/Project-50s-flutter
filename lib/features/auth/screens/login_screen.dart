import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/xame_user.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _xameIdCtrl  = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading      = false;
  bool _obscure      = true;
  String? _error;

  @override
  void dispose() {
    _xameIdCtrl.dispose();
    _passwordCtrl.dispose();
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
      final auth = ref.read(authServiceProvider);
      final user = await auth.login(xameId, password);
      ref.read(currentUserProvider.notifier).state = user;
      if (mounted) context.go('/contacts');
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: XameColors.darkBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              // Logo
              Center(
                child: Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: XameColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: XameColors.primary, width: 1.5),
                  ),
                  child: const Icon(Icons.chat_bubble_rounded, color: XameColors.primary, size: 36),
                ),
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text('XamePage',
                  style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
              const Center(
                child: Text('Ultramodern calling & messaging',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
              ),
              const SizedBox(height: 48),
              const Text('Welcome back', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text('Sign in to continue', style: TextStyle(color: Colors.white38, fontSize: 14)),
              const SizedBox(height: 32),

              // Xame-ID
              _label('Xame-ID'),
              const SizedBox(height: 8),
              _field(
                controller: _xameIdCtrl,
                hint: 'Enter your Xame-ID',
                icon: Icons.alternate_email,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              ),
              const SizedBox(height: 20),

              // Password
              _label('Password'),
              const SizedBox(height: 8),
              _field(
                controller: _passwordCtrl,
                hint: 'Enter your password',
                icon: Icons.lock_outline,
                obscure: _obscure,
                suffix: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white38, size: 20),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                onSubmitted: (_) => _login(),
              ),
              const SizedBox(height: 12),

              // Error
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: XameColors.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: XameColors.danger.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: XameColors.danger, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: XameColors.danger, fontSize: 13))),
                  ]),
                ),

              const SizedBox(height: 28),

              // Login button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: XameColors.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _loading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),

              // Register link
              Center(
                child: GestureDetector(
                  onTap: () => context.go('/register'),
                  child: RichText(text: const TextSpan(
                    text: "Don't have an account? ",
                    style: TextStyle(color: Colors.white38, fontSize: 14),
                    children: [TextSpan(text: 'Sign Up', style: TextStyle(color: XameColors.primary, fontWeight: FontWeight.w600))],
                  )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500));

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    Function(String)? onSubmitted,
  }) => TextField(
    controller:     controller,
    obscureText:    obscure,
    onSubmitted:    onSubmitted,
    style:          const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText:        hint,
      hintStyle:       const TextStyle(color: Colors.white24),
      prefixIcon:      Icon(icon, color: Colors.white38, size: 20),
      suffixIcon:      suffix,
      filled:          true,
      fillColor:       XameColors.darkCard,
      border:          OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder:   OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: XameColors.primary, width: 1.5)),
      contentPadding:  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );
}
