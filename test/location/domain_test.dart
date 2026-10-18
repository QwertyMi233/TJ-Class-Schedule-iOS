import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/features/location/domain.dart';

void main() {
  final now = DateTime(2026, 10, 14, 12);
  Fix point(double lat, double lon, {double accuracy = 5}) =>
      Fix(lat, lon, accuracy, now);
  Place place(Fix fix) => Place(
    id: 'a',
    name: '自行车',
    note: '',
    color: 0xff28a86b,
    fix: fix,
    createdAt: now,
  );
  test('相同位置与已知一度距离', () {
    expect(distanceMeters(point(0, 0), point(0, 0)), 0);
    expect(distanceMeters(point(0, 0), point(0, 1)), closeTo(111195.08, .1));
  });
  test('四个地理方向正确', () {
    expect(bearingDegrees(point(0, 0), point(1, 0)), 0);
    expect(bearingDegrees(point(0, 0), point(0, 1)), 90);
    expect(bearingDegrees(point(0, 0), point(-1, 0)), 180);
    expect(bearingDegrees(point(0, 0), point(0, -1)), 270);
  });
  test('跨日期变更线沿短距离计算', () {
    expect(
      distanceMeters(point(0, 179.999), point(0, -179.999)),
      closeTo(222.39, .1),
    );
    expect(
      bearingDegrees(point(0, 179.999), point(0, -179.999)),
      closeTo(90, .001),
    );
  });
  test('对跖点和高纬坐标不会产生 NaN', () {
    expect(distanceMeters(point(90, 0), point(-90, 180)).isFinite, true);
    expect(distanceMeters(point(0, 0), point(0, 180)), closeTo(20015114, 1));
  });
  test('相对方向与跨北向最短旋转', () {
    expect(turnAngle(1, 359), 2);
    expect(turnAngle(359, 1), -2);
    expect(turnLabel(turnAngle(90, 0)), '向右转');
    expect(turnLabel(turnAngle(270, 0)), '向左转');
    expect(turnLabel(turnAngle(180, 0)), '转身向后');
  });
  test('定位过期、未来时间或精度差不能保存', () {
    expect(point(1, 1).canSaveAt(now), true);
    expect(point(1, 1).canSaveAt(now.add(const Duration(seconds: 16))), false);
    expect(
      point(1, 1).canSaveAt(now.subtract(const Duration(seconds: 1))),
      false,
    );
    expect(point(1, 1, accuracy: 51).canSaveAt(now), false);
  });
  test('无效坐标与非有限精度拒绝', () {
    expect(() => point(91, 0), throwsFormatException);
    expect(() => point(0, 181), throwsFormatException);
    expect(() => point(double.nan, 0), throwsFormatException);
    expect(() => point(0, 0, accuracy: double.infinity), throwsFormatException);
  });
  test('附近依据两次定位误差，不宣称精确到达', () {
    final g = Guidance(point(0, 0), place(point(.00005, 0)));
    expect(g.nearby, true);
    expect(g.uncertainty, 10);
    expect(Guidance(point(0, 0), place(point(.001, 0))).nearby, false);
    expect(
      Guidance(point(0, 0, accuracy: 80), place(point(0, 0))).nearby,
      false,
    );
  });
  test('地图方位名称跨北方向', () {
    expect(cardinal(359), '北');
    expect(cardinal(45), '东北');
    expect(cardinal(-90), '西');
  });
}
