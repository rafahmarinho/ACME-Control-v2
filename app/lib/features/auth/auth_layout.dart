import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shared frame for login / password screens: brand panel on wide screens.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: child),
      ),
    );
    return Scaffold(
      body: wide
          ? Row(children: [
              const Expanded(flex: 5, child: _BrandPanel()),
              Expanded(flex: 4, child: form),
            ])
          : SafeArea(child: form),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.water, AppColors.waterDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(size * 0.25),
          ),
          child: Icon(Icons.water_drop, color: Colors.white, size: size * 0.58),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ACME Control', style: TextStyle(fontSize: size * 0.5, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const Text('Water treatment operations', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ]),
      ]);
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF07263A), Color(0xFF0B0F14)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(56),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          BrandMark(size: 52),
          Spacer(),
          Text('Monitor and control your\nwater treatment plants.', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, height: 1.2)),
          SizedBox(height: 20),
          _Feature(Icons.account_tree_outlined, 'Live process diagrams with real-time flows, levels and pressures'),
          _Feature(Icons.notifications_active_outlined, 'Prioritised alarms with acknowledgement and audit trail'),
          _Feature(Icons.verified_user_outlined, 'Role-based control with supervisor review of setpoint changes'),
          _Feature(Icons.build_circle_outlined, 'Maintenance work orders with lockout/tagout'),
          Spacer(),
          Text('© 2026 ACME Industrial Systems · Demo environment', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ]),
      );
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(color: Color(0xFFC9D6E3)))),
        ]),
      );
}

class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner(this.message, {super.key, this.success = false});
  final String message;
  final bool success;
  @override
  Widget build(BuildContext context) {
    final color = success ? AppColors.running : AppColors.fault;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(success ? Icons.check_circle_outline : Icons.error_outline, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
    );
  }
}
