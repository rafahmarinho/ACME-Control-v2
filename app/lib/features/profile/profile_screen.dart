import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/auth_repository.dart';
import '../auth/reset_password_screen.dart' show validateNewPassword;
import '../shell/app_shell.dart' show UserAvatar;

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    return AsyncValueView<Profile?>(
      value: profile,
      onRetry: () => ref.invalidate(currentProfileProvider),
      data: (p) => p == null
          ? const LoadingView()
          : SingleChildScrollView(
              child: PageBody(
                maxWidth: 820,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const PageHeader(title: 'Profile', subtitle: 'Your account details and password'),
                  _ProfileForm(profile: p),
                  const SizedBox(height: 16),
                  const _PasswordForm(),
                ]),
              ),
            ),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.profile});
  final Profile profile;
  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.fullName);
  late final _title = TextEditingController(text: widget.profile.jobTitle ?? '');
  late final _phone = TextEditingController(text: widget.profile.phone ?? '');
  bool _saving = false;
  bool _uploading = false;

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg']);
    final f = picked.firstOrNull;
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) {
      if (mounted) showSnack(context, 'Please choose an image smaller than 2 MB.', error: true);
      return;
    }
    setState(() => _uploading = true);
    if (!mounted) return;
    await runAction(context, () => ref.read(currentProfileProvider.notifier).uploadAvatar(bytes, f.extension ?? 'png'), success: 'Profile photo updated.');
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (!ensureOnline(context, ref)) return;
    setState(() => _saving = true);
    await runAction(
      context,
      () => ref.read(currentProfileProvider.notifier).save({
        'full_name': _name.text.trim(),
        'job_title': _title.text.trim().isEmpty ? null : _title.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      }),
      success: 'Profile saved.',
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return SectionCard(
      title: 'Account',
      icon: Icons.person_outline,
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Stack(children: [
              UserAvatar(profile: p, radius: 40),
              Positioned(
                right: 0,
                bottom: 0,
                child: Material(
                  color: AppColors.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _uploading ? null : _pickAvatar,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: _uploading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.photo_camera, size: 16, color: Colors.black),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                Text(p.email, style: const TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: 8),
                StatusChip(p.role.label, color: AppColors.secondary, icon: Icons.badge_outlined),
                const SizedBox(height: 6),
                Text(p.role.description, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name'),
            validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Enter your name' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'Job title')),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (used for alarm paging)'),
            validator: (v) => v != null && v.trim().isNotEmpty && !RegExp(r'^[+0-9 ()-]{6,20}$').hasMatch(v.trim()) ? 'Enter a valid phone number' : null,
          ),
          const SizedBox(height: 8),
          const Text('Your role is managed by an administrator and cannot be changed here.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
              label: const Text('Save changes'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PasswordForm extends ConsumerStatefulWidget {
  const _PasswordForm();
  @override
  ConsumerState<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends ConsumerState<_PasswordForm> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (!ensureOnline(context, ref)) return;
    setState(() => _busy = true);
    final ok = await runAction(context, () => ref.read(authRepositoryProvider).changePassword(_current.text, _next.text), success: 'Password changed.');
    if (ok) {
      _current.clear();
      _next.clear();
      _confirm.clear();
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => SectionCard(
        title: 'Change password',
        icon: Icons.lock_outline,
        child: Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _current,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Current password'),
              validator: (v) => (v ?? '').isEmpty ? 'Enter your current password' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _next,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 8 characters, including a number'),
              validator: validateNewPassword,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm new password'),
              validator: (v) => v != _next.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.key),
                label: const Text('Update password'),
              ),
            ),
          ]),
        ),
      );
}
