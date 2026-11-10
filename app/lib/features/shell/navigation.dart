import 'package:flutter/material.dart';

import '../../data/models/profile.dart';

/// Top-level sections of the app. Visibility depends on the user's role.
enum AppSection {
  process('/process', 'Process', Icons.account_tree_outlined, Icons.account_tree),
  plants('/plants', 'Plants', Icons.factory_outlined, Icons.factory),
  alarms('/alarms', 'Alarms', Icons.notifications_outlined, Icons.notifications_active),
  equipment('/equipment', 'Equipment', Icons.precision_manufacturing_outlined, Icons.precision_manufacturing),
  trends('/trends', 'Trends', Icons.show_chart_outlined, Icons.show_chart),
  commands('/commands', 'Commands', Icons.toggle_on_outlined, Icons.toggle_on),
  setpoints('/setpoints', 'Setpoints', Icons.tune_outlined, Icons.tune),
  maintenance('/maintenance', 'Maintenance', Icons.build_outlined, Icons.build),
  handover('/handover', 'Shift handover', Icons.swap_horiz_outlined, Icons.swap_horiz),
  simulation('/simulation', 'Simulation', Icons.science_outlined, Icons.science);

  const AppSection(this.path, this.label, this.icon, this.selectedIcon);
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Navigation per role (order = menu order).
List<AppSection> sectionsFor(UserRole role) => switch (role) {
      UserRole.operator => const [
          AppSection.process, AppSection.plants, AppSection.alarms, AppSection.equipment, AppSection.trends,
          AppSection.commands, AppSection.setpoints, AppSection.maintenance, AppSection.handover, AppSection.simulation,
        ],
      UserRole.engineer => const [
          AppSection.process, AppSection.plants, AppSection.trends, AppSection.setpoints, AppSection.alarms,
          AppSection.equipment, AppSection.maintenance, AppSection.simulation,
        ],
      UserRole.supervisor => AppSection.values,
      UserRole.maintenance => const [
          AppSection.process, AppSection.equipment, AppSection.maintenance, AppSection.alarms, AppSection.plants,
          AppSection.trends, AppSection.handover,
        ],
    };

bool canAccessPath(UserRole role, String path) {
  const always = ['/search', '/profile', '/settings', '/more'];
  if (always.any(path.startsWith)) return true;
  return sectionsFor(role).any((s) => path == s.path || path.startsWith('${s.path}/'));
}

/// Mobile bottom tabs: Plant · Alarms · Assets · More (as requested for phones).
const mobileTabs = [
  (path: '/process', label: 'Plant', icon: Icons.account_tree_outlined, selected: Icons.account_tree),
  (path: '/alarms', label: 'Alarms', icon: Icons.notifications_outlined, selected: Icons.notifications_active),
  (path: '/equipment', label: 'Assets', icon: Icons.precision_manufacturing_outlined, selected: Icons.precision_manufacturing),
  (path: '/more', label: 'More', icon: Icons.menu, selected: Icons.menu_open),
];
