import 'package:acme_control/data/models/equipment.dart';
import 'package:acme_control/data/models/profile.dart';
import 'package:acme_control/features/auth/login_screen.dart';
import 'package:acme_control/features/process/process_diagram.dart';
import 'package:acme_control/features/shell/navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Equipment eq(String tag, EquipmentKind kind, {String actual = 'normal', String? requested, String? mode, double? level, double? flow, bool maint = false}) =>
    Equipment.fromJson({
      'id': 'id-$tag',
      'plant_id': 'north-valley',
      'tag': tag,
      'name': 'Test $tag',
      'kind': kind.name,
      'area': 'Test',
      'control_mode': mode,
      'requested_state': requested,
      'actual_state': actual,
      'in_maintenance': maint,
      'fault_active': false,
      'level_pct': level,
      'volume_m3': level == null ? null : level * 5,
      'capacity_m3': level == null ? null : 500,
      'flow_m3h': flow,
      'position_pct': kind == EquipmentKind.valve ? 100 : null,
      'rated_flow_m3h': kind == EquipmentKind.pump ? 240 : null,
      'value': kind == EquipmentKind.instrument ? 12.3 : null,
      'unit': kind == EquipmentKind.instrument ? 'm³/h' : null,
      'run_hours': 10,
      'starts_count': 2,
      'health_pct': 95,
      'sort_order': 0,
    });

Map<String, Equipment> plant() => {
      for (final e in [
        eq('XV-101', EquipmentKind.valve, actual: 'open', requested: 'open', mode: 'auto', flow: 200),
        eq('T-101', EquipmentKind.tank, level: 62),
        eq('P-101', EquipmentKind.pump, actual: 'running', requested: 'running', mode: 'auto', flow: 204),
        eq('P-102', EquipmentKind.pump, actual: 'locked_out', requested: 'running', mode: 'manual', maint: true),
        eq('XV-102', EquipmentKind.valve, actual: 'open', requested: 'open', mode: 'auto', flow: 204),
        eq('T-102', EquipmentKind.tank, level: 71),
        eq('P-201', EquipmentKind.pump, actual: 'interlocked', requested: 'running', mode: 'manual'),
        eq('XV-201', EquipmentKind.valve, actual: 'closing', requested: 'closed', mode: 'manual', flow: 50),
        for (final t in ['LT-101', 'LT-102', 'FT-101', 'FT-102', 'FT-201', 'PT-101', 'PT-201']) eq(t, EquipmentKind.instrument),
      ])
        e.tag: e,
    };

void main() {
  group('role-based navigation', () {
    test('operators can operate but not review setpoints', () {
      expect(UserRole.operator.canCommand, isTrue);
      expect(UserRole.operator.canReviewSetpoints, isFalse);
      expect(sectionsFor(UserRole.operator), contains(AppSection.commands));
    });

    test('engineers propose setpoints but have no command console', () {
      expect(UserRole.engineer.canProposeSetpoints, isTrue);
      expect(UserRole.engineer.canCommand, isFalse);
      expect(sectionsFor(UserRole.engineer), isNot(contains(AppSection.commands)));
      expect(canAccessPath(UserRole.engineer, '/commands'), isFalse);
      expect(canAccessPath(UserRole.engineer, '/setpoints'), isTrue);
    });

    test('maintenance sees work orders and lockout, not simulation', () {
      expect(UserRole.maintenance.canLockout, isTrue);
      expect(sectionsFor(UserRole.maintenance), contains(AppSection.maintenance));
      expect(canAccessPath(UserRole.maintenance, '/simulation'), isFalse);
      expect(canAccessPath(UserRole.maintenance, '/maintenance/abc'), isTrue);
    });

    test('supervisors see every section', () {
      expect(sectionsFor(UserRole.supervisor), AppSection.values);
      expect(UserRole.supervisor.canReviewSetpoints, isTrue);
    });

    test('profile, settings and search are always reachable', () {
      for (final r in UserRole.values) {
        expect(canAccessPath(r, '/profile'), isTrue);
        expect(canAccessPath(r, '/search'), isTrue);
      }
    });
  });

  group('equipment model', () {
    test('requested vs actual mismatch is detected', () {
      final p = plant();
      expect(p['P-101']!.hasMismatch, isFalse);
      expect(p['P-102']!.hasMismatch, isTrue); // requested running, actual locked out
      expect(p['P-201']!.hasMismatch, isTrue); // interlocked
      expect(p['XV-201']!.hasMismatch, isFalse); // travelling is not a mismatch
    });

    test('primary reading and trend tag', () {
      final p = plant();
      expect(p['T-101']!.primaryReading, '62.0 %');
      expect(p['P-101']!.trendTag, 'FT-102');
      expect(p['T-102']!.trendTag, 'LT-102');
    });
  });

  group('process diagram', () {
    for (final portrait in [false, true]) {
      testWidgets('renders and selects equipment by tap (portrait: $portrait)', (tester) async {
        String? selected;
        final size = portrait ? const Size(400, 766.7) : const Size(1200, 560);
        await tester.binding.setSurfaceSize(Size(size.width, size.height));
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: size.width,
              height: size.height,
              child: ProcessDiagram(equipment: plant(), onSelect: (t) => selected = t, enable3d: false, animate: true, portrait: portrait),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);

        final layout = portrait ? DiagramLayout.portrait() : DiagramLayout.landscape();
        final (scale, off) = layout.fit(size);
        final p101 = layout.pumps['P-101']! * scale + off;
        await tester.tapAt(p101);
        expect(selected, 'P-101');

        final t102 = layout.tanks['T-102']!.center * scale + off;
        await tester.tapAt(t102);
        expect(selected, 'T-102');
        await tester.binding.setSurfaceSize(null);
      });
    }

    testWidgets('3D perspective mode renders without errors', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 700));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProcessDiagram(equipment: plant(), onSelect: (_) {}, onToggle3d: (_) {}))));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('3D'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });
  });

  testWidgets('login form validates input before contacting the server', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: LoginScreen())));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter your email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);

    await tester.tap(find.text('Supervisor'));
    await tester.pump();
    expect(find.text('supervisor@acme-control.test'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
