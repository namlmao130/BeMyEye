import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/models/detection_result.dart';
import 'package:be_my_eye_vn/services/spatial_analyzer.dart';

void main() {
  group('NV6 - SpatialAnalyzer: Ước lượng khoảng cách & Chặn báo nhầm vật thể lớn ở xa (Lỗi 5)', () {
    test('Tiêu chí 1: Xe buýt ở xa dù chiếm diện tích lớn trong khung hình (30%) vẫn KHÔNG bị báo critical', () {
      final analyzer = SpatialAnalyzer();

      // Giả lập một chiếc xe buýt ở cách 15m:
      // Bánh xe chạm đất ở nửa trên khung hình (bottomY = 0.55),
      // nhưng kích thước xe rất to nên diện tích chiếm tới 30% khung hình (areaRatio = 0.30)
      final busDetection = {
        'bbox': [20.0, 50.0, 260.0, 115.0], // w=260, h=115 -> area = 29900 / 90000 ~ 0.33
        'label': 'bus',
        'vietnameseLabel': 'Xe buýt',
        'category': 'vehicle',
        'score': 0.92,
      };

      final results = analyzer.analyze([busDetection], 300.0, 300.0, customNow: 0);

      expect(results.length, equals(1));
      final res = results[0];

      // Khẳng định bắt buộc: Xe buýt ở xa KHÔNG được xếp vào cự ly critical (< 1.5m)
      expect(res.distanceLevel, isNot(equals(DistanceLevel.critical)),
          reason: 'Xe buýt ở xa không được báo critical dù diện tích lớn!');
      expect(res.distanceLevel, equals(DistanceLevel.far));
      expect(res.approximateDistanceMeters, equals('> 3.0m'));
    });

    test('Tiêu chí 2: Người đi bộ đứng sát chân (bottomY = 0.90) dù diện tích nhỏ (10%) VẪN PHẢI BÁO critical', () {
      final analyzer = SpatialAnalyzer();

      // Giả lập một người đi bộ đứng sát ngay trước mũi chân (< 1.2m):
      // Thân người gầy nên diện tích chỉ chiếm 10% khung hình (areaRatio = 0.10),
      // nhưng bàn chân chạm sát đáy khung hình (bottomY = 0.92)
      final personDetection = {
        'bbox': [110.0, 50.0, 80.0, 226.0], // w=80, h=226 -> bottomY = (50+226)/300 = 0.92
        'label': 'person',
        'vietnameseLabel': 'Người',
        'category': 'pedestrian',
        'score': 0.90,
      };

      final results = analyzer.analyze([personDetection], 300.0, 300.0, customNow: 0);

      expect(results.length, equals(1));
      final res = results[0];

      // Khẳng định bắt buộc: Người đứng sát chân phải là critical để bảo vệ an toàn
      expect(res.distanceLevel, equals(DistanceLevel.critical),
          reason: 'Người đứng sát chân phải báo cự ly nguy cấp < 1.5m!');
      expect(res.approximateDistanceMeters, equals('< 1.5m'));
    });

    test('Bù trừ góc nghiêng điện thoại (Tilt Compensation): Khi điện thoại chúi xuống, ngưỡng được nâng lên tương ứng', () {
      final analyzer = SpatialAnalyzer();

      // Một vật cản có chân ở bottomY = 0.83 (ngang ngưỡng chuẩn 0.82)
      final obstacle = {
        'bbox': [100.0, 100.0, 100.0, 149.0], // bottomY = 249 / 300 = 0.83
        'label': 'chair',
        'vietnameseLabel': 'Ghế quán cóc',
        'category': 'obstacle',
        'score': 0.85,
      };

      // 1. Khi điện thoại thẳng đứng (tilt = 0.0 rad) -> Chân vật thể ở 0.83 >= 0.82 -> Critical
      final normalResults = analyzer.analyze([obstacle], 300.0, 300.0, tiltAngleRad: 0.0, customNow: 0);
      expect(normalResults[0].distanceLevel, equals(DistanceLevel.critical));

      // 2. Khi người dùng cúi người / điện thoại chúi xuống 20 độ (~0.35 rad):
      // Ngưỡng critical được bù trừ nâng lên: 0.82 + (0.35 * 0.35) = 0.94
      // Lúc này bottomY = 0.83 < 0.94 -> Không bị báo nhầm là critical!
      final tiltedResults = analyzer.analyze([obstacle], 300.0, 300.0, tiltAngleRad: 20.0 * pi / 180.0, customNow: 0);
      expect(tiltedResults[0].distanceLevel, equals(DistanceLevel.near),
          reason: 'Góc chúi xuống phải nâng ngưỡng để tránh báo nhầm mặt đất');
    });
  });
}
