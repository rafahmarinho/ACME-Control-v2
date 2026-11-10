import 'json.dart';

class Plant {
  const Plant({
    required this.id,
    required this.name,
    required this.code,
    required this.location,
    this.description,
    required this.timezone,
    required this.designCapacity,
    required this.baseInflow,
    required this.baseDemand,
    this.commissionedOn,
  });

  final String id;
  final String name;
  final String code;
  final String location;
  final String? description;
  final String timezone;
  final double designCapacity;
  final double baseInflow;
  final double baseDemand;
  final DateTime? commissionedOn;

  String get shortName => name.replaceAll(' Water Treatment Plant', '');

  factory Plant.fromJson(Json j) => Plant(
        id: j['id'] as String,
        name: asString(j['name']) ?? '',
        code: asString(j['code']) ?? '',
        location: asString(j['location']) ?? '',
        description: asString(j['description']),
        timezone: asString(j['timezone']) ?? 'UTC',
        designCapacity: asDoubleOr(j['design_capacity_m3h']),
        baseInflow: asDoubleOr(j['base_inflow_m3h']),
        baseDemand: asDoubleOr(j['base_demand_m3h']),
        commissionedOn: asDate(j['commissioned_on']),
      );
}

class PlantState {
  const PlantState({
    required this.plantId,
    required this.scenarioId,
    required this.autoRun,
    required this.simTime,
    required this.lastTickAt,
    required this.tick,
    required this.inletFlow,
    required this.transferFlow,
    required this.distributionFlow,
    required this.demand,
    required this.transferPressure,
    required this.distributionPressure,
    required this.status,
    this.updatedAt,
  });

  final String plantId;
  final String scenarioId;
  final bool autoRun;
  final DateTime simTime;
  final DateTime lastTickAt;
  final int tick;
  final double inletFlow;
  final double transferFlow;
  final double distributionFlow;
  final double demand;
  final double transferPressure;
  final double distributionPressure;
  final String status; // normal | warning | alarm
  final DateTime? updatedAt;

  factory PlantState.fromJson(Json j) => PlantState(
        plantId: j['plant_id'] as String,
        scenarioId: asString(j['scenario_id']) ?? 'normal',
        autoRun: asBool(j['auto_run']),
        simTime: asDate(j['sim_time']) ?? DateTime.now(),
        lastTickAt: asDate(j['last_tick_at']) ?? DateTime.now(),
        tick: asInt(j['tick']),
        inletFlow: asDoubleOr(j['inlet_flow_m3h']),
        transferFlow: asDoubleOr(j['transfer_flow_m3h']),
        distributionFlow: asDoubleOr(j['distribution_flow_m3h']),
        demand: asDoubleOr(j['demand_m3h']),
        transferPressure: asDoubleOr(j['transfer_pressure_bar']),
        distributionPressure: asDoubleOr(j['distribution_pressure_bar']),
        status: asString(j['status']) ?? 'normal',
        updatedAt: asDate(j['updated_at']),
      );
}

class Scenario {
  const Scenario({
    required this.id,
    required this.name,
    required this.description,
    required this.inflowFactor,
    required this.demandFactor,
    required this.faultTags,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String description;
  final double inflowFactor;
  final double demandFactor;
  final List<String> faultTags;
  final int sortOrder;

  factory Scenario.fromJson(Json j) => Scenario(
        id: j['id'] as String,
        name: asString(j['name']) ?? '',
        description: asString(j['description']) ?? '',
        inflowFactor: asDoubleOr(j['inflow_factor'], 1),
        demandFactor: asDoubleOr(j['demand_factor'], 1),
        faultTags: asStringList(j['fault_tags']),
        sortOrder: asInt(j['sort_order']),
      );
}
