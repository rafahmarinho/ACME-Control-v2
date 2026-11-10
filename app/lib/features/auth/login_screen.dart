import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/env.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/auth_repository.dart';
import 'auth_layout.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  static const _demo = [
    ('Operator', 'operator@acme-control.test', Icons.monitor_heart_outlined),
    ('Engineer', 'engineer@acme-control.test', Icons.engineering_outlined),
    ('Supervisor', 'supervisor@acme-control.test', Icons.verified_user_outlined),
    ('Maintenance', 'maintenance@acme-control.test', Icons.build_outlined),
  ];

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signIn(_email.text, _password.text);
      // The router redirects automatically once the session exists.
    } catch (e) {
      if (mounted) setState(() => _error = ErrorView.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (MediaQuery.sizeOf(context).width < 980) ...[const Center(child: BrandMark()), const SizedBox(height: 36)],
            const Text('Sign in', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Use your ACME Control account to continue.', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 24),
            if (_error != null) ...[FormErrorBanner(_error!), const SizedBox(height: 16)],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email, AutofillHints.username],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email)),
              validator: (v) {
                final s = v?.trim() ?? '';
                if (s.isEmpty) return 'Enter your email address';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) return 'Enter a valid email address';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => context.go('/forgot-password'), child: const Text('Forgot password?')),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : const Text('Sign in'),
            ),
            const SizedBox(height: 32),
            const Row(children: [
              Expanded(child: Divider()),
              Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Demo accounts', style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
              Expanded(child: Divider()),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              for (final (label, email, icon) in _demo)
                ActionChip(
                  avatar: Icon(icon, size: 18),
                  label: Text(label),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  onPressed: () {
                    setState(() {
                      _email.text = email;
                      if (Env.demoPassword.isNotEmpty) _password.text = Env.demoPassword;
                      _error = null;
                    });
                  },
                ),
            ]),
            const SizedBox(height: 10),
            Text(
              Env.demoPassword.isNotEmpty
                  ? 'Tap a role to fill in its demo credentials.'
                  : 'Tap a role to fill in its email. The demo password is in the README.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ]),
        ),
      ),
    );
  }
}
