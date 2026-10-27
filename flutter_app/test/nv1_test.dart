import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/config/thresholds.dart';

void main() {
  group('NV1 - Trạng thái dự án và Ngưỡng cấu hình ban đầu', () {
    test('kPipelineEnabled phải là false cho đến khi hoàn thành NV3', () {
      expect(kPipelineEnabled, isFalse);
    });

    test('Các ngưỡng không gian cơ bản phải hợp lệ', () {
      expect(kLeftBoundary, lessThan(kRightBoundary));
      expect(kNearBottomY, lessThan(kCriticalBottomY));
      expect(kNearAreaRatio, lessThan(kCriticalAreaRatio));
      expect(kSpeechCooldownMs, greaterThanOrEqualTo(2000));
    });
  });
}
