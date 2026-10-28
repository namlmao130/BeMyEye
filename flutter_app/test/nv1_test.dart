import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/config/thresholds.dart';

void main() {
  group('NV1 - Trạng thái dự án và Ngưỡng cấu hình ban đầu', () {
    test(
      'Ngưỡng Watchdog và kiểm soát lỗi suy luận được định nghĩa chính xác',
      () {
        expect(kWatchdogFrameTimeoutMs, equals(1500));
        expect(kMaxConsecutiveInferenceErrors, equals(5));
      },
    );

    test('Các ngưỡng không gian cơ bản phải hợp lệ', () {
      expect(kLeftBoundary, lessThan(kRightBoundary));
      expect(kNearBottomY, lessThan(kCriticalBottomY));
      expect(kNearAreaRatio, lessThan(kCriticalAreaRatio));
      expect(kSpeechCooldownMs, greaterThanOrEqualTo(2000));
    });
  });
}
