import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/auth_repository.dart';
import 'auth_layout.dart';

String? validateNewPassword(String? v) {
  final s = v ?? '';
  if (s.length < 8) return 'Use at least 8 characters';
  if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) return 'Use letters and at least one number';
  return null;
}

/// Opened from the recovery email link (web: /reset-password, mobile: deep link).
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).updatePassword(_password.text);
      ref.read(passwordRecoveryProvider.notifier).set(false);
      if (mounted) {
        showSnack(context, 'Password updated. You are now signed in.', color: const Color(0xFF14432F));
        context.go('/process');
      }
    } catch (e) {
      if (mounted) setState(() => _error = ErrorView.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authStateProvider);
    final hasSession = ref.read(authRepositoryProvider).session != null;

    return AuthLayout(
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Choose a new password', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Your new password must have at least 8 characters, including a number.', style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 24),
          if (!hasSession) ...[
            const FormErrorBanner('This reset link is invalid or has expired. Request a new one from the sign-in page.'),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () => context.go('/forgot-password'), child: const Text('Request a new link')),
          ] else ...[
            if (_error != null) ...[FormErrorBanner(_error!), const SizedBox(height: 16)],
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'New password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: validateNewPassword,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Confirm new password', prefixIcon: Icon(Icons.lock_reset)),
              validator: (v) => v != _password.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : const Text('Update password'),
            ),
          ],
        ]),
      ),
    );
  }
}
