import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/config/thresholds.dart';

void main() {
  group('NV1 - Trạng thái dự án và Ngưỡng cấu hình ban đầu', () {
    test('kPipelineEnabled đã được kích hoạt sau khi nối pipeline camera ở NV3', () {
      expect(kPipelineEnabled, isTrue);
    });

    test('Các ngưỡng không gian cơ bản phải hợp lệ', () {
      expect(kLeftBoundary, lessThan(kRightBoundary));
      expect(kNearBottomY, lessThan(kCriticalBottomY));
      expect(kNearAreaRatio, lessThan(kCriticalAreaRatio));
      expect(kSpeechCooldownMs, greaterThanOrEqualTo(2000));
    });
  });
}
