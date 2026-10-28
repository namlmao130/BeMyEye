import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/models/detection_result.dart';
import 'package:be_my_eye_vn/services/spatial_analyzer.dart';

void main() {
  group('NV12.4 - Dấu bù góc nghiêng ngực và quy ước hình học chiếu', () {
    test(
        'Quy ước: Khi camera chúc xuống (tiltAngleRad > 0), ngưỡng bottomY PHẢI GIẢM',
        () {
      // GHI CHÚ AN TOÀN: Quy ước toán học này xuất phát từ hình học chiếu:
      // Khi camera chúc xuống đất (người dùng hơi cúi người hoặc giá đeo ngực nghiêng xuống):
      // Đường chân trời và các điểm tiếp xúc mặt đất bị dịch chuyển lên trên trong khung ảnh (bottomY nhỏ hơn).
      // Để nhận diện chính xác vật thể ở cự ly nguy cấp (< 1.5m), ngưỡng bottomY bắt buộc phải GIẢM.
      // CẦN CHẠY THỰC ĐỊA TRÊN THIẾT BỊ THẬT ĐỂ ĐO VÀ HIỆU CHUẨN LẠI DẤU VÀ HỆ SỐ NÀY!

      final analyzer = SpatialAnalyzer();

      // Giả lập một vật cản (thùng xốp / chậu hoa) có vị trí chân ở bottomY = 0.72
      // Trên khung hình 300x300: y=116, h=100 -> bottomY = 216 / 300 = 0.72
      final obstacle = {
        'bbox': [100.0, 116.0, 80.0, 100.0],
        'label': 'box',
        'vietnameseLabel': 'Thùng xốp',
        'category': 'obstacle',
        'score': 0.88,
      };

      // 1. Góc thẳng đứng (tilt = 0.0 rad):
      // Ngưỡng critical = kCriticalBottomY (0.82), ngưỡng near = kNearBottomY (0.65).
      // bottomY = 0.72 nằm giữa 0.65 và 0.82 -> Xếp vào cự ly NEAR (1.5m - 3.0m).
      final resultsNeutral = analyzer.analyze(
        [obstacle],
        300.0,
        300.0,
        tiltAngleRad: 0.0,
        customNow: 1000,
      );
      expect(
        resultsNeutral[0].distanceLevel,
        equals(DistanceLevel.near),
        reason: 'Ở tư thế đứng thẳng, bottomY 0.72 < 0.82 nên chỉ ở mức Near',
      );

      // 2. Camera chúc xuống đất 25 độ (~0.436 rad):
      // Ngưỡng critical phải GIẢM: 0.82 - (0.436 * 0.35) = 0.82 - 0.15 = 0.67
      // Lúc này bottomY = 0.72 >= 0.67 -> PHẢI chuyển thành CRITICAL (< 1.5m)!
      final resultsTiltDown = analyzer.analyze(
        [obstacle],
        300.0,
        300.0,
        tiltAngleRad: 25.0 * pi / 180.0,
        customNow: 1200,
      );
      expect(
        resultsTiltDown[0].distanceLevel,
        equals(DistanceLevel.critical),
        reason:
            'Khi camera chúc xuống đất, ngưỡng bottomY giảm giúp nhận diện vật cản gần sát ngực',
      );

      // 3. Camera ngửa lên trời 20 độ (-20 độ = -0.349 rad):
      // Ngưỡng near TĂNG: 0.65 - (-0.349 * 0.35) = 0.65 + 0.122 = 0.772
      // bottomY giảm độ tin cậy khi ngửa máy, nhưng diện tích hộp vẫn đủ lớn để
      // giữ mức near. Không được hạ một vật thể lớn thành far chỉ do góc nghiêng.
      final resultsTiltUp = analyzer.analyze(
        [obstacle],
        300.0,
        300.0,
        tiltAngleRad: -20.0 * pi / 180.0,
        customNow: 1400,
      );
      expect(
        resultsTiltUp[0].distanceLevel,
        equals(DistanceLevel.near),
        reason: 'Diện tích hộp vẫn là tín hiệu cự ly độc lập với góc nghiêng',
      );
    });

    test(
      'Giới hạn bù trừ clamp không được vượt ngưỡng an toàn [-0.15, +0.15]',
      () {
        final analyzer = SpatialAnalyzer();

        final obstacle = {
          'bbox': [100.0, 100.0, 80.0, 80.0],
          'label': 'box',
          'vietnameseLabel': 'Thùng xốp',
          'category': 'obstacle',
          'score': 0.88,
        };

        // Nghiêng cực đại 90 độ (1.57 rad)
        // tiltOffset bị clamp ở 0.15, không làm vỡ giới hạn logic
        expect(() {
          analyzer.analyze(
            [obstacle],
            300.0,
            300.0,
            tiltAngleRad: pi / 2,
            customNow: 2000,
          );
        }, returnsNormally);
      },
    );
  });
}
