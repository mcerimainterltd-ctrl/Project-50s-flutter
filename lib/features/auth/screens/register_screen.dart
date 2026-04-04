import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl  = TextEditingController();
  final _passwordCtrl  = TextEditingController();
  final _confirmCtrl   = TextEditingController();
  final _dobDayCtrl    = TextEditingController();
  final _dobMonthCtrl  = TextEditingController();
  final _dobYearCtrl   = TextEditingController();
  final _monthFocus    = FocusNode();
  final _yearFocus     = FocusNode();
  bool _loading  = false;
  bool _obscure  = true;
  bool _obscure2 = true;
  String? _error;
  String? _returnedXameId;

  @override
  void dispose() {
    for (final c in [_firstNameCtrl,_lastNameCtrl,_passwordCtrl,
                     _confirmCtrl,_dobDayCtrl,_dobMonthCtrl,_dobYearCtrl]) c.dispose();
    for (final f in [_monthFocus,_yearFocus]) f.dispose();
    super.dispose();
  }

  String? _buildDob() {
    final d = _dobDayCtrl.text.trim().padLeft(2,'0');
    final m = _dobMonthCtrl.text.trim().padLeft(2,'0');
    final y = _dobYearCtrl.text.trim();
    if (y.length != 4 || d.length != 2 || m.length != 2) return null;
    return '$y-$m-$d';
  }

  Future<void> _register() async {
    setState(() { _error = null; _loading = true; _returnedXameId = null; });
    try {
      final auth   = ref.read(authServiceProvider);
      final day    = int.tryParse(_dobDayCtrl.text)  ?? 0;
      final month  = int.tryParse(_dobMonthCtrl.text) ?? 0;
      final year   = int.tryParse(_dobYearCtrl.text)  ?? 0;
      final dobErr = auth.validateDob(day, month, year);
      if (dobErr != null) { setState(() { _error = dobErr; _loading = false; }); return; }
      final dob = _buildDob();
      if (dob == null) { setState(() { _error = 'Please enter a valid date of birth.'; _loading = false; }); return; }
      if (_passwordCtrl.text != _confirmCtrl.text) {
        setState(() { _error = 'Passwords do not match.'; _loading = false; }); return;
      }
      final v = auth.validatePassword(_passwordCtrl.text);
      if (!v.isValid) { setState(() { _error = v.errors.join(' · '); _loading = false; }); return; }

      final user = await auth.register(
        firstName: _firstNameCtrl.text,
        lastName:  _lastNameCtrl.text,
        dob:       dob,
        password:  _passwordCtrl.text,
      );
      setState(() => _returnedXameId = user.xameId);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_returnedXameId != null) {
      return Scaffold(
        backgroundColor: XameColors.darkBg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: XameColors.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: XameColors.accent, width: 1.5),
                  ),
                  child: const Icon(Icons.check_rounded, color: XameColors.accent, size: 40),
                ),
                const SizedBox(height: 28),
                const Text('Account Created!',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text('Your Xame-ID is:',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: XameColors.darkCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: XameColors.primary, width: 1.5),
                  ),
                  child: Text(_returnedXameId!,
                    style: const TextStyle(color: XameColors.primary, fontSize: 26,
                      fontWeight: FontWeight.bold, letterSpacing: 2)),
                ),
                const SizedBox(height: 12),
                const Text('Save this ID — you need it to log in.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: () => context.go('/login'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: XameColors.primary,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Sign In Now',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: XameColors.darkBg,
      appBar: AppBar(
        backgroundColor: XameColors.darkBg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => context.go('/login'),
        ),
        title: const Text('Create Account',
          style: TextStyle(color: Colors.white, fontSize: 18)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: _section('First Name',
                  _field(_firstNameCtrl, 'First name', Icons.person_outline))),
                const SizedBox(width: 12),
                Expanded(child: _section('Last Name',
                  _field(_lastNameCtrl, 'Last name', Icons.person_outline))),
              ]),
              const SizedBox(height: 16),
              _label('Date of Birth'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _dobField(_dobDayCtrl,   'DD',   null,        _monthFocus, 2, 1,    31)),
                const SizedBox(width: 8),
                Expanded(child: _dobField(_dobMonthCtrl, 'MM',   _monthFocus, _yearFocus,  2, 1,    12)),
                const SizedBox(width: 8),
                Expanded(flex: 2,
                  child: _dobField(_dobYearCtrl, 'YYYY', _yearFocus, null, 4, 1900, DateTime.now().year)),
              ]),
              const SizedBox(height: 16),
              _section('Password', _field(_passwordCtrl, 'Min 8 characters', Icons.lock_outline,
                obscure: _obscure,
                suffix: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white38, size: 20),
                  onPressed: () => setState(() => _obscure = !_obscure)))),
              const SizedBox(height: 16),
              _section('Confirm Password', _field(_confirmCtrl, 'Re-enter password', Icons.lock_outline,
                obscure: _obscure2,
                suffix: IconButton(
                  icon: Icon(_obscure2 ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white38, size: 20),
                  onPressed: () => setState(() => _obscure2 = !_obscure2)))),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: XameColors.darkCard, borderRadius: BorderRadius.circular(10)),
                child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Password must contain:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  SizedBox(height: 4),
                  Text('· At least 8 characters  · One uppercase letter', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  Text('· One lowercase letter   · One number',           style: TextStyle(color: Colors.white38, fontSize: 11)),
                  Text('· One special character',                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                ]),
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: XameColors.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _loading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Text('Create Account',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: GestureDetector(
                  onTap: () => context.go('/login'),
                  child: RichText(text: const TextSpan(
                    text: 'Already have an account? ',
                    style: TextStyle(color: Colors.white38, fontSize: 14),
                    children: [TextSpan(text: 'Sign In',
                      style: TextStyle(color: XameColors.primary, fontWeight: FontWeight.w600))],
                  )),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [_label(label), const SizedBox(height: 8), child]);

  Widget _label(String text) => Text(text,
    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500));

  Widget _field(TextEditingController ctrl, String hint, IconData icon,
      {bool obscure = false, Widget? suffix, TextInputType? type}) =>
    TextField(
      controller: ctrl, obscureText: obscure, keyboardType: type,
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

  Widget _dobField(TextEditingController ctrl, String hint,
      FocusNode? focus, FocusNode? next, int maxLen, int min, int max) =>
    TextField(
      controller: ctrl, focusNode: focus,
      keyboardType: TextInputType.number, maxLength: maxLen,
      style: const TextStyle(color: Colors.white), textAlign: TextAlign.center,
      onChanged: (v) {
        final clean = v.replaceAll(RegExp(r'[^0-9]'), '');
        if (clean != v) ctrl.text = clean;
        if (clean.length == maxLen) {
          final n = int.tryParse(clean) ?? 0;
          if (n < min || n > max) ctrl.clear();
          else if (next != null) FocusScope.of(context).requestFocus(next);
        }
      },
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: Colors.white24),
        counterText: '', filled: true, fillColor: XameColors.darkCard,
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: XameColors.primary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      ),
    );
}
