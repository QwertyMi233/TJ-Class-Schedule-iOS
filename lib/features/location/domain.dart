import 'dart:math' as math;

class Fix {
  final double latitude, longitude, accuracy;
  final DateTime time;
  Fix(this.latitude, this.longitude, this.accuracy, this.time) {
    if (!latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180 ||
        !accuracy.isFinite ||
        accuracy < 0) {
      throw const FormatException('定位数据无效');
    }
  }
  bool freshAt(DateTime now) {
    final age = now.difference(time);
    return age >= Duration.zero && age <= const Duration(seconds: 15);
  }

  bool canSaveAt(DateTime now) => freshAt(now) && accuracy <= 50;
}

class Place {
  final String id, name, note;
  final int color;
  final Fix fix;
  final DateTime createdAt;
  const Place({
    required this.id,
    required this.name,
    required this.note,
    required this.color,
    required this.fix,
    required this.createdAt,
  });
  Place renamed(String name, String note) => Place(
    id: id,
    name: name,
    note: note,
    color: color,
    fix: fix,
    createdAt: createdAt,
  );
  Map<String, Object> toMap() => {
    'id': id,
    'name': name,
    'note': note,
    'color': color,
    'lat': fix.latitude,
    'lon': fix.longitude,
    'accuracy': fix.accuracy,
    'fixed_at': fix.time.millisecondsSinceEpoch,
    'created_at': createdAt.millisecondsSinceEpoch,
  };
  factory Place.fromMap(Map<String, Object?> m) => Place(
    id: m['id'] as String,
    name: m['name'] as String,
    note: m['note'] as String,
    color: m['color'] as int,
    fix: Fix(
      (m['lat'] as num).toDouble(),
      (m['lon'] as num).toDouble(),
      (m['accuracy'] as num).toDouble(),
      DateTime.fromMillisecondsSinceEpoch(m['fixed_at'] as int),
    ),
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
  );
}

double normalize(double degrees) => (degrees % 360 + 360) % 360;
double turnAngle(double bearing, double heading) =>
    (normalize(bearing - heading) + 180) % 360 - 180;
double distanceMeters(Fix a, Fix b) {
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLat = lat2 - lat1;
  final dLon = (b.longitude - a.longitude) * math.pi / 180;
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
  return 6371008.8 * 2 * math.asin(math.sqrt(h.clamp(0, 1)));
}

double bearingDegrees(Fix a, Fix b) {
  final l1 = a.latitude * math.pi / 180, l2 = b.latitude * math.pi / 180;
  final dl = (b.longitude - a.longitude) * math.pi / 180;
  return normalize(
    math.atan2(
          math.sin(dl) * math.cos(l2),
          math.cos(l1) * math.sin(l2) -
              math.sin(l1) * math.cos(l2) * math.cos(dl),
        ) *
        180 /
        math.pi,
  );
}

String cardinal(double bearing) => [
  '北',
  '东北',
  '东',
  '东南',
  '南',
  '西南',
  '西',
  '西北',
][(normalize(bearing) / 45).round() % 8];
String turnLabel(double angle) {
  if (angle.abs() < 18) return '就在前方';
  if (angle.abs() > 150) return '转身向后';
  return angle > 0 ? '向右转' : '向左转';
}

class Guidance {
  final double distance, bearing, uncertainty;
  final bool nearby, poor;
  Guidance(Fix current, Place target)
    : distance = distanceMeters(current, target.fix),
      bearing = bearingDegrees(current, target.fix),
      uncertainty = current.accuracy + target.fix.accuracy,
      poor = current.accuracy > 50,
      nearby =
          current.accuracy <= 50 &&
          distanceMeters(current, target.fix) <=
              math.max(8, current.accuracy + target.fix.accuracy);
}
