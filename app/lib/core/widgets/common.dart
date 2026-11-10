import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/core_providers.dart';
import '../theme/app_theme.dart';

extension ResponsiveContext on BuildContext {
  double get width => MediaQuery.sizeOf(this).width;
  bool get isMobile => width < 840;
  bool get isWide => width >= 1180;
}

/// Renders an [AsyncValue] with consistent loading / error states.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({super.key, required this.value, required this.data, this.onRetry, this.loading});
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return data(value.value as T);
    if (value.hasError) return ErrorView(error: value.error!, onRetry: onRetry);
    return loading ?? const LoadingView();
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message = 'Loading…'});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.6)),
            const SizedBox(height: 14),
            Text(message, style: const TextStyle(color: AppColors.textMuted)),
          ]),
        ),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry, this.compact = false});
  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  static String messageOf(Object e) {
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, color: AppColors.fault, size: 36),
      const SizedBox(height: 10),
      const Text('Something went wrong', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      const SizedBox(height: 6),
      Text(messageOf(error), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
      if (onRetry != null) ...[
        const SizedBox(height: 14),
        OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
      ],
    ]);
    return compact ? Padding(padding: const EdgeInsets.all(16), child: body) : Center(child: Padding(padding: const EdgeInsets.all(32), child: body));
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, required this.color, this.icon, this.dense = false});
  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 2 : 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: dense ? 12 : 14, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: color, fontSize: dense ? 11 : 12, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
        ]),
      );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.trailing, required this.child, this.padding = const EdgeInsets.all(16), this.icon});
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: padding,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (title != null) ...[
              Row(children: [
                if (icon != null) ...[Icon(icon, size: 18, color: AppColors.primary), const SizedBox(width: 8)],
                Expanded(child: Text(title!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                ?trailing,
              ]),
              const SizedBox(height: 12),
            ],
            child,
          ]),
        ),
      );
}

class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, this.unit, this.icon, this.color = AppColors.primary, this.width = 168});
  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final Color color;
  final double? width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                if (icon != null) ...[Icon(icon, size: 15, color: color), const SizedBox(width: 6)],
                Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 12))),
              ]),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                  if (unit != null) TextSpan(text: ' $unit', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ]),
                maxLines: 1,
              ),
            ]),
          ),
        ),
      );
}

class LabelValue extends StatelessWidget {
  const LabelValue(this.label, this.value, {super.key, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 150, child: Text(label, style: const TextStyle(color: AppColors.textMuted))),
          Expanded(child: Text(value, style: TextStyle(fontWeight: FontWeight.w500, color: valueColor))),
        ]),
      );
}

/// Page scaffold body with max width & padding.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.maxWidth = 1400, this.padding});
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(padding: padding ?? EdgeInsets.all(context.isMobile ? 12 : 20), child: child),
        ),
      );
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: TextStyle(fontSize: context.isMobile ? 20 : 24, fontWeight: FontWeight.w700)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: const TextStyle(color: AppColors.textMuted)),
              ],
            ]),
            if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      );
}

void showSnack(BuildContext context, String message, {bool error = false, Color? color}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      backgroundColor: error ? const Color(0xFF5B1D24) : (color ?? AppColors.surfaceHighest),
      duration: Duration(seconds: error ? 6 : 4),
    ));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.fault, foregroundColor: Colors.black) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Returns true when online; otherwise explains that control actions need a connection.
bool ensureOnline(BuildContext context, WidgetRef ref) {
  if (ref.read(isOnlineProvider)) return true;
  showSnack(context, 'You are offline. Control actions require a connection.', error: true);
  return false;
}

/// Runs an async action with uniform error reporting. Returns true on success.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) showSnack(context, success, color: const Color(0xFF14432F));
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, ErrorView.messageOf(e), error: true);
    return false;
  }
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.onChanged, this.hint = 'Search', this.controller, this.autofocus = false});
  final ValueChanged<String> onChanged;
  final String hint;
  final TextEditingController? controller;
  final bool autofocus;
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: hint, isDense: true),
      );
}
