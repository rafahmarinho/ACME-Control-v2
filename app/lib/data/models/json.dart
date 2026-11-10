// Small, defensive JSON readers for Supabase rows.

typedef Json = Map<String, dynamic>;

double? asDouble(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
double asDoubleOr(Object? v, [double fallback = 0]) => asDouble(v) ?? fallback;
int asInt(Object? v, [int fallback = 0]) => v == null ? fallback : (v is num ? v.toInt() : int.tryParse('$v') ?? fallback);
String? asString(Object? v) => v?.toString();
bool asBool(Object? v) => v == true || v == 'true';
DateTime? asDate(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
List<String> asStringList(Object? v) => v is List ? v.map((e) => '$e').toList() : const [];
Json asJson(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
