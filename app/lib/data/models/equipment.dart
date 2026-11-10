import 'json.dart';

enum EquipmentKind {
  tank('Tank'),
  pump('Pump'),
  valve('Valve'),
  instrument('Instrument');

  const EquipmentKind(this.label);
  final String label;
  static EquipmentKind parse(String? v) =>
      EquipmentKind.values.firstWhere((k) => k.name == v, orElse: () => EquipmentKind.instrument);
}

class Equipment {
  const Equipment({
    required this.id,
    required this.plantId,
    required this.tag,
    required this.name,
    required this.kind,
    required this.area,
    this.description,
    this.manufacturer,
    this.model,
    this.serialNumber,
    this.installedOn,
    this.controlMode,
    this.requestedState,
    required this.actualState,
    this.interlockReason,
    required this.inMaintenance,
    required this.faultActive,
    this.levelPct,
    this.volumeM3,
    this.capacityM3,
    this.ratedFlow,
    this.flow,
    this.speedPct,
    this.positionPct,
    this.pressureBar,
    this.value,
    this.unit,
    required this.runHours,
    required this.startsCount,
    required this.healthPct,
    required this.sortOrder,
    this.updatedAt,
  });

  final String id;
  final String plantId;
  final String tag;
  final String name;
  final EquipmentKind kind;
  final String area;
  final String? description;
  final String? manufacturer;
  final String? model;
  final String? serialNumber;
  final DateTime? installedOn;
  final String? controlMode; // auto | manual
  final String? requestedState;
  final String actualState;
  final String? interlockReason;
  final bool inMaintenance;
  final bool faultActive;
  final double? levelPct;
  final double? volumeM3;
  final double? capacityM3;
  final double? ratedFlow;
  final double? flow;
  final double? speedPct;
  final double? positionPct;
  final double? pressureBar;
  final double? value;
  final String? unit;
  final double runHours;
  final int startsCount;
  final double healthPct;
  final int sortOrder;
  final DateTime? updatedAt;

  bool get isPump => kind == EquipmentKind.pump;
  bool get isValve => kind == EquipmentKind.valve;
  bool get isTank => kind == EquipmentKind.tank;
  bool get isInstrument => kind == EquipmentKind.instrument;
  bool get isControllable => isPump || isValve;
  bool get isAuto => controlMode == 'auto';
  bool get isManual => controlMode == 'manual';

  bool get isActive => actualState == 'running' || actualState == 'open';
  bool get isAbnormal =>
      const {'fault', 'interlocked', 'locked_out', 'high', 'low', 'empty', 'overflow'}.contains(actualState) || faultActive;

  /// Requested state differs from what the process actually does.
  bool get hasMismatch {
    if (!isControllable || requestedState == null) return false;
    if (actualState == 'opening' || actualState == 'closing') return false;
    return requestedState != actualState;
  }

  /// The primary reading shown for this asset.
  String get primaryReading {
    switch (kind) {
      case EquipmentKind.tank:
        return '${(levelPct ?? 0).toStringAsFixed(1)} %';
      case EquipmentKind.pump:
        return '${(flow ?? 0).toStringAsFixed(0)} m³/h';
      case EquipmentKind.valve:
        return '${(positionPct ?? 0).toStringAsFixed(0)} % open';
      case EquipmentKind.instrument:
        final v = value ?? 0;
        return '${unit == 'bar' ? v.toStringAsFixed(2) : v.toStringAsFixed(1)} ${unit ?? ''}'.trim();
    }
  }

  /// Trend tag associated with this asset (for mini charts).
  String? get trendTag => switch (tag) {
        'T-101' => 'LT-101',
        'T-102' => 'LT-102',
        'XV-101' => 'FT-101',
        'P-101' || 'P-102' || 'XV-102' => 'FT-102',
        'P-201' || 'XV-201' => 'FT-201',
        _ => isInstrument ? tag : null,
      };

  factory Equipment.fromJson(Json j) => Equipment(
        id: j['id'] as String,
        plantId: asString(j['plant_id']) ?? '',
        tag: asString(j['tag']) ?? '',
        name: asString(j['name']) ?? '',
        kind: EquipmentKind.parse(asString(j['kind'])),
        area: asString(j['area']) ?? '',
        description: asString(j['description']),
        manufacturer: asString(j['manufacturer']),
        model: asString(j['model']),
        serialNumber: asString(j['serial_number']),
        installedOn: asDate(j['installed_on']),
        controlMode: asString(j['control_mode']),
        requestedState: asString(j['requested_state']),
        actualState: asString(j['actual_state']) ?? 'normal',
        interlockReason: asString(j['interlock_reason']),
        inMaintenance: asBool(j['in_maintenance']),
        faultActive: asBool(j['fault_active']),
        levelPct: asDouble(j['level_pct']),
        volumeM3: asDouble(j['volume_m3']),
        capacityM3: asDouble(j['capacity_m3']),
        ratedFlow: asDouble(j['rated_flow_m3h']),
        flow: asDouble(j['flow_m3h']),
        speedPct: asDouble(j['speed_pct']),
        positionPct: asDouble(j['position_pct']),
        pressureBar: asDouble(j['pressure_bar']),
        value: asDouble(j['value']),
        unit: asString(j['unit']),
        runHours: asDoubleOr(j['run_hours']),
        startsCount: asInt(j['starts_count']),
        healthPct: asDoubleOr(j['health_pct'], 100),
        sortOrder: asInt(j['sort_order']),
        updatedAt: asDate(j['updated_at']),
      );
}
