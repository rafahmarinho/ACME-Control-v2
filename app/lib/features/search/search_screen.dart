import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/operations_repository.dart';
import '../../data/repositories/plant_repository.dart';
import '../../data/services/core_providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _query = v.trim()));
  }

  static const _icons = {
    'equipment': Icons.precision_manufacturing_outlined,
    'work_order': Icons.build_outlined,
    'alarm': Icons.notifications_outlined,
    'event': Icons.receipt_long_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(isOnlineProvider);
    final results = _query.length >= 2 ? ref.watch(searchProvider(_query)) : null;
    final plants = {for (final p in ref.watch(plantsProvider).value ?? const []) p.id: p.shortName};

    return PageBody(
      maxWidth: 900,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const PageHeader(title: 'Search', subtitle: 'Find equipment, alarms, work orders and events across all plants'),
        SearchField(controller: _ctl, autofocus: true, hint: 'e.g. P-102, seal, overflow, WO-24003', onChanged: _onChanged),
        const SizedBox(height: 12),
        Expanded(
          child: !online
              ? const EmptyState(icon: Icons.cloud_off, title: 'Search needs a connection', message: 'Reconnect to search the plant database.')
              : results == null
                  ? const EmptyState(icon: Icons.manage_search, title: 'Type at least 2 characters to search')
                  : AsyncValueView<List<SearchHit>>(
                      value: results,
                      onRetry: () => ref.invalidate(searchProvider(_query)),
                      data: (hits) {
                        if (hits.isEmpty) return EmptyState(icon: Icons.search_off, title: 'No results for “$_query”');
                        return ListView.separated(
                          itemCount: hits.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (_, i) {
                            final h = hits[i];
                            return Card(
                              child: ListTile(
                                leading: Icon(_icons[h.kind] ?? Icons.circle, color: AppColors.primary),
                                title: Text(h.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${h.subtitle} · ${plants[h.plantId] ?? h.plantId}'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  ref.read(selectedPlantIdProvider.notifier).select(h.plantId);
                                  context.go(h.route);
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
