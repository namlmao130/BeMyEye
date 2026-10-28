import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/models/detection_result.dart';
import 'package:be_my_eye_vn/services/spatial_analyzer.dart';

void main() {
  group(
      'NV12.3 - Làm mượt "tới gần": Hồi quy tuyến tính diện tích & Lọc nhiễu nhảy hộp',
      () {
    test(
        'Tiêu chí 1: Hộp nhảy dao động +-20% quanh giá trị cố định TUYỆT ĐỐI KHÔNG thành approaching',
        () {
      final analyzer = SpatialAnalyzer();

      // Giả lập xe máy đứng yên hoặc đỗ ven đường
      // Do nhiễu bóc tách detector, kích thước hộp dao động +-20% quanh diện tích chuẩn 0.10 (w=95, h=95 trên khung 300x300)
      // Mẫu diện tích: [0.10, 0.12, 0.08, 0.115, 0.085, 0.12, 0.082, 0.118, 0.088, 0.12]
      final noisyAreas = [
        0.100,
        0.120,
        0.080,
        0.115,
        0.085,
        0.120,
        0.082,
        0.118,
        0.088,
        0.120,
      ];

      for (int i = 0; i < noisyAreas.length; i++) {
        final area = noisyAreas[i];
        // Tính cạnh tương ứng với area trên khung 300x300
        final side = 300.0 * 0.3162 * (area / 0.10); // biến thiên kích thước
        final t = i * 70; // Mỗi khung cách nhau 70ms (~14 FPS)

        final results = analyzer.analyze(
          [
            {
              'bbox': [100.0, 100.0, side, side],
              'label': 'motorcycle',
              'vietnameseLabel': 'Xe máy',
              'category': 'vehicle',
              'score': 0.90,
            },
          ],
          300.0,
          300.0,
          walkingSpeedMps: 0.0,
          customNow: t,
        );

        expect(results.length, equals(1));
        // Hộp nhảy +-20% quanh giá trị cố định không được thành approaching
        expect(
          results[0].isApproaching,
          isFalse,
          reason:
              'Tại bước $i (t=${t}ms), hộp dao động ngẫu nhiên +-20% không được kích hoạt isApproaching!',
        );
      }
    });

    test(
        'Tiêu chí 2: Xe thật tiến lại gần (tăng liên tục qua >= 5 mẫu, >= 0.3s) thì isApproaching = true',
        () {
      final analyzer = SpatialAnalyzer();

      // Giả lập xe ô tô đang chạy tới phía người dùng
      // Diện tích tăng đều đặn, liên tục từ 0.05 lên 0.28 trong 500ms
      final approachingFrames = [
        {'t': 0, 'side': 67.0}, // area ~ 0.05
        {'t': 100, 'side': 82.0}, // area ~ 0.075
        {'t': 200, 'side': 100.0}, // area ~ 0.111
        {'t': 300, 'side': 120.0}, // area ~ 0.160
        {
          't': 400,
          'side': 140.0,
        }, // area ~ 0.218 (mẫu thứ 5, dt=400ms >= 0.3s, frame 1 vượt ngưỡng)
        {
          't': 500,
          'side': 160.0,
        }, // area ~ 0.284 (mẫu thứ 6, frame 2 liên tiếp vượt ngưỡng -> true)
      ];

      List<DetectionResult> lastResults = [];
      for (final f in approachingFrames) {
        final t = f['t'] as int;
        final side = f['side'] as double;

        lastResults = analyzer.analyze(
          [
            {
              'bbox': [80.0, 80.0, side, side],
              'label': 'car',
              'vietnameseLabel': 'Ô tô',
              'category': 'vehicle',
              'score': 0.92,
            },
          ],
          300.0,
          300.0,
          walkingSpeedMps: 0.0,
          customNow: t,
        );
      }

      expect(lastResults.length, equals(1));
      expect(
        lastResults[0].isApproaching,
        isTrue,
        reason:
            'Xe thật tiến lại gần với diện tích tăng liên tục phải kích hoạt isApproaching',
      );
      expect(
        lastResults[0].distanceLevel,
        equals(DistanceLevel.critical),
        reason: 'Phương tiện lao tới phải nâng mức cự ly thành critical',
      );
    });

    test(
        'Tiêu chí 3: Chưa đủ 5 mẫu hoặc chưa đủ 0.3s thì CHƯA được thành approaching',
        () {
      final analyzer = SpatialAnalyzer();

      // Chỉ có 3 mẫu trong 150ms
      final shortFrames = [
        {'t': 0, 'side': 67.0},
        {'t': 70, 'side': 100.0},
        {'t': 140, 'side': 150.0},
      ];

      List<DetectionResult> lastResults = [];
      for (final f in shortFrames) {
        final t = f['t'] as int;
        final side = f['side'] as double;

        lastResults = analyzer.analyze(
          [
            {
              'bbox': [80.0, 80.0, side, side],
              'label': 'car',
              'vietnameseLabel': 'Ô tô',
              'category': 'vehicle',
              'score': 0.92,
            },
          ],
          300.0,
          300.0,
          walkingSpeedMps: 0.0,
          customNow: t,
        );
      }

      expect(
        lastResults[0].isApproaching,
        isFalse,
        reason: 'Chưa đủ >= 5 mẫu và >= 0.3s thì không được kết luận vội vàng',
      );
    });

    test(
        'Tiêu chí 4: Vật thể tĩnh (obstacle) dù có diện tích tăng cũng KHÔNG BAO GIỜ là approaching',
        () {
      final analyzer = SpatialAnalyzer();

      // Giả lập người dùng đi bộ tiến lại gần một chậu cây hoặc cột điện (obstacle)
      final obstacleFrames = [
        {'t': 0, 'side': 67.0},
        {'t': 100, 'side': 82.0},
        {'t': 200, 'side': 100.0},
        {'t': 300, 'side': 120.0},
        {'t': 400, 'side': 140.0},
        {'t': 500, 'side': 160.0},
      ];

      List<DetectionResult> lastResults = [];
      for (final f in obstacleFrames) {
        final t = f['t'] as int;
        final side = f['side'] as double;

        lastResults = analyzer.analyze(
          [
            {
              'bbox': [80.0, 80.0, side, side],
              'label': 'chair',
              'vietnameseLabel': 'Ghế',
              'category': 'obstacle', // TĨNH
              'score': 0.88,
            },
          ],
          300.0,
          300.0,
          walkingSpeedMps: 1.0,
          customNow: t,
        );
      }

      expect(
        lastResults[0].isApproaching,
        isFalse,
        reason:
            'Vật thể loại obstacle tuyệt đối không bao giờ được đánh dấu isApproaching',
      );
    });
  });
}
