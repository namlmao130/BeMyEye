import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/services/spatial_analyzer.dart';
import 'package:be_my_eye_vn/models/detection_result.dart';

void main() {
  group('NV5 - SpatialAnalyzer: Sửa đang tới gần và ghép track 1-1 (Lỗi 3, 4)', () {
    test('Tiêu chí (a): Cột / ghế đứng yên + người đi tới -> KHÔNG BAO GIỜ là approaching', () {
      final analyzer = SpatialAnalyzer();

      // Giả lập người đi bộ đang tiến tới một chiếc ghế tĩnh (category: 'obstacle')
      // Diện tích chiếc ghế tăng dần do người đi bộ bước tới gần (từ 0.05 lên 0.18 trong 500ms)
      const walkingSpeed = 1.2; // 1.2 m/s

      final frames = [
        {'time': 0, 'w': 50.0, 'h': 50.0},
        {'time': 120, 'w': 58.0, 'h': 58.0},
        {'time': 240, 'w': 68.0, 'h': 68.0},
        {'time': 360, 'w': 80.0, 'h': 80.0},
        {'time': 480, 'w': 95.0, 'h': 95.0},
      ];

      for (final f in frames) {
        final w = f['w'] as double;
        final h = f['h'] as double;
        final t = f['time'] as int;

        final results = analyzer.analyze(
          [
            {
              'bbox': [100.0, 100.0, w, h],
              'label': 'chair',
              'vietnameseLabel': 'Ghế quán cóc',
              'category': 'obstacle', // Vật cản tĩnh
              'score': 0.88,
            }
          ],
          300.0,
          300.0,
          walkingSpeedMps: walkingSpeed,
          customNow: t,
        );

        expect(results.length, equals(1));
        // Khẳng định bắt buộc: Vật tĩnh tuyệt đối KHÔNG bao giờ là approaching
        expect(results[0].isApproaching, isFalse,
            reason: 'Vật thể loại obstacle không được coi là đang lao tới!');
      }
    });

    test('Tiêu chí (b): Xe máy phóng tới -> isApproaching chuyển sang true sau >= 2 frames vượt ngưỡng', () {
      final analyzer = SpatialAnalyzer();

      // Giả lập người đứng yên (0 m/s), xe máy (category: 'vehicle') phóng tới rất nhanh
      // Diện tích xe tăng vọt từ 0.05 lên 0.25 trong ~450ms
      final frames = [
        {'time': 0, 'w': 67.0, 'h': 67.0},   // areaRatio ~ 0.05
        {'time': 150, 'w': 90.0, 'h': 90.0}, // areaRatio ~ 0.09
        {'time': 300, 'w': 120.0, 'h': 120.0}, // areaRatio ~ 0.16 (growthRate cao, frame 1)
        {'time': 450, 'w': 150.0, 'h': 150.0}, // areaRatio ~ 0.25 (growthRate cao, frame 2)
      ];

      List<DetectionResult> lastResults = [];

      for (final f in frames) {
        final w = f['w'] as double;
        final h = f['h'] as double;
        final t = f['time'] as int;

        lastResults = analyzer.analyze(
          [
            {
              'bbox': [100.0, 100.0, w, h],
              'label': 'motorcycle',
              'vietnameseLabel': 'Xe máy',
              'category': 'vehicle',
              'score': 0.95,
            }
          ],
          300.0,
          300.0,
          walkingSpeedMps: 0.0,
          customNow: t,
        );
      }

      expect(lastResults.length, equals(1));
      // Sau 2 frame liên tiếp tốc độ tăng diện tích vượt ngưỡng, xe máy phải được đánh dấu lao tới
      expect(lastResults[0].isApproaching, isTrue);
      expect(lastResults[0].distanceLevel, equals(DistanceLevel.critical));
    });

    test('Tiêu chí (c): Hai xe máy gần nhau -> ghép track 1-1 gán 2 ID khác nhau, không bị trùng', () {
      final analyzer = SpatialAnalyzer();

      // Frame 1: 2 xe máy xuất hiện cạnh nhau (cx = 0.40 và cx = 0.55)
      final frame1Detections = [
        {
          'bbox': [100.0, 100.0, 60.0, 60.0],
          'label': 'motorcycle',
          'vietnameseLabel': 'Xe máy',
          'category': 'vehicle',
          'score': 0.92,
        },
        {
          'bbox': [150.0, 100.0, 60.0, 60.0],
          'label': 'motorcycle',
          'vietnameseLabel': 'Xe máy',
          'category': 'vehicle',
          'score': 0.90,
        },
      ];

      final results1 = analyzer.analyze(frame1Detections, 300.0, 300.0, customNow: 0);

      expect(results1.length, equals(2));
      final id1 = results1[0].id;
      final id2 = results1[1].id;

      // 2 xe phải có 2 track ID khác nhau rõ ràng
      expect(id1, isNot(equals(id2)));
      expect(id1, equals('track_1'));
      expect(id2, equals('track_2'));

      // Frame 2: Cả 2 xe dịch chuyển nhẹ (cx dịch một chút)
      final frame2Detections = [
        {
          'bbox': [102.0, 101.0, 62.0, 62.0],
          'label': 'motorcycle',
          'vietnameseLabel': 'Xe máy',
          'category': 'vehicle',
          'score': 0.92,
        },
        {
          'bbox': [153.0, 102.0, 62.0, 62.0],
          'label': 'motorcycle',
          'vietnameseLabel': 'Xe máy',
          'category': 'vehicle',
          'score': 0.90,
        },
      ];

      final results2 = analyzer.analyze(frame2Detections, 300.0, 300.0, customNow: 100);

      expect(results2.length, equals(2));
      // Kiểm tra ghép đúng 1-1: Không xe nào bị đổi ID hoặc nhập thành một
      expect(results2[0].id, equals(id1));
      expect(results2[1].id, equals(id2));
    });
  });
}
