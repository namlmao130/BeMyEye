import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/models/ground_hazard.dart';
import 'package:be_my_eye_vn/models/detection_result.dart';
import 'package:be_my_eye_vn/services/ground_analyzer.dart';

void main() {
  group('NV7 - GroundPlaneAnalyzer: Giảm báo nhầm bậc thềm (Lỗi 6)', () {
    const int width = 160;
    const int height = 120;

    test(
      'Kiểm tra đầu vào nghiêm ngặt: Ném lỗi ArgumentError khi kích thước sai',
      () {
        final analyzer = GroundPlaneAnalyzer();
        final invalidBuffer = Uint8List(100); // Quá ngắn so với 160x120 = 19200

        expect(
          () => analyzer.analyzeLuminance(invalidBuffer, 160, 120),
          throwsArgumentError,
        );

        expect(
          () => analyzer.analyzeLuminance(Uint8List(19200), -1, 120),
          throwsArgumentError,
        );
      },
    );

    test(
        'Loại bỏ vạch qua đường (Zebra Crosswalk) có nhiều đỉnh chu kỳ lặp lại',
        () {
      final analyzer = GroundPlaneAnalyzer();

      // Tạo khung hình mô phỏng vạch kẻ đi bộ qua đường:
      // Các sọc trắng đen xen kẽ cách nhau mỗi 16 pixel (nhiều hơn 6 chuyển đổi cạnh)
      final zebraFrame = Uint8List(width * height);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final bool isWhiteStripe = ((x ~/ 16) % 2 == 0);
          zebraFrame[y * width + x] = isWhiteStripe ? 230 : 40;
        }
      }

      // Đưa 8 frames vạch qua đường vào bộ phân tích
      List<GroundHazard> hazards = [];
      for (int i = 0; i < 8; i++) {
        hazards = analyzer.analyzeLuminance(zebraFrame, width, height);
      }

      // Vạch qua đường phải bị lọc bỏ hoàn toàn, không được báo nhầm là mép bậc
      expect(hazards, isEmpty);
    });

    test(
        'Loại bỏ các điểm ảnh cạnh ngang rời rạc không liên tục (Nhiễu mặt đường)',
        () {
      final analyzer = GroundPlaneAnalyzer();

      // Tạo frame có nhiều điểm cạnh ngang nhưng rải rác từng chấm 2-3 pixel,
      // không có đoạn nào liên tục đạt 35% chiều rộng ảnh (56 pixels)
      final noiseFrame = Uint8List(width * height);
      noiseFrame.fillRange(0, noiseFrame.length, 120);

      const targetY = 80;
      for (int x = 10; x < width - 10; x += 6) {
        // Cạnh rời rạc
        noiseFrame[(targetY - 1) * width + x] = 20;
        noiseFrame[(targetY + 1) * width + x] = 220;
      }

      for (int i = 0; i < 8; i++) {
        final hazards = analyzer.analyzeLuminance(noiseFrame, width, height);
        expect(
          hazards,
          isEmpty,
          reason: 'Cạnh rời rạc không đủ liên tục không được coi là bậc thềm!',
        );
      }
    });

    test(
        'Nhận diện chính xác mép bậc thật LIÊN TỤC và nhất quán qua nhiều frame (Mức tin cậy cao)',
        () {
      final analyzer = GroundPlaneAnalyzer();

      // Tạo frame có một mép bậc đi xuống thật sự:
      // Kéo dài 100 pixels liên tục (từ x=30 đến x=130), trên sáng (190), dưới tối (40)
      final stepDownFrame = Uint8List(width * height);
      stepDownFrame.fillRange(0, stepDownFrame.length, 120);

      const stepY = 85;
      for (int y = 0; y < stepY; y++) {
        for (int x = 20; x < 140; x++) {
          stepDownFrame[y * width + x] = 200; // Phía trên sáng
        }
      }
      for (int y = stepY; y < height; y++) {
        for (int x = 20; x < 140; x++) {
          stepDownFrame[y * width + x] = 40; // Phía dưới tối
        }
      }

      // Đưa 6 frame liên tục để đạt mức tin cậy cao (>= 5 hits)
      List<GroundHazard> hazards = [];
      for (int i = 0; i < 6; i++) {
        hazards = analyzer.analyzeLuminance(stepDownFrame, width, height);
      }

      expect(hazards.isNotEmpty, isTrue);
      expect(hazards.first.type, equals(GroundHazardType.stepDown));
      expect(hazards.first.isNegativeObstacle, isTrue);
      expect(hazards.first.vietnameseName, contains('Bậc đi xuống'));
    });

    test(
        'Hạ mức cam kết khi độ tin cậy chưa cao (3-4 hits): Đổi thành câu nhắc dùng gậy kiểm tra, không rung critical',
        () {
      final analyzer = GroundPlaneAnalyzer();

      final stepFrame = Uint8List(width * height);
      stepFrame.fillRange(0, stepFrame.length, 120);
      const stepY = 85;
      for (int y = 0; y < stepY; y++) {
        for (int x = 20; x < 140; x++) {
          stepFrame[y * width + x] = 200;
        }
      }
      for (int y = stepY; y < height; y++) {
        for (int x = 20; x < 140; x++) {
          stepFrame[y * width + x] = 40;
        }
      }

      // Cho xuất hiện 3 frame, sau đó xen kẽ frame trống để hitCount dừng ở mức 3
      analyzer.analyzeLuminance(stepFrame, width, height);
      analyzer.analyzeLuminance(stepFrame, width, height);
      final hazards = analyzer.analyzeLuminance(stepFrame, width, height);

      expect(hazards.isNotEmpty, isTrue);
      final h = hazards.first;

      // Tiêu chí hạ mức cam kết:
      expect(h.vietnameseName, equals('Có thể có bậc, hãy dùng gậy kiểm tra'));
      expect(
        h.isNegativeObstacle,
        isFalse,
      ); // Không dùng cờ negative obstacle để tránh rung khẩn cấp
      expect(
        h.distanceLevel,
        equals(DistanceLevel.near),
      ); // Không dùng critical
    });

    test(
        'Công cụ đo kiểm: countFalseAlarmsPerMinute trên đường bằng đạt 0.0 cảnh báo nhầm/phút',
        () {
      final analyzer = GroundPlaneAnalyzer();

      // Tạo chuỗi 100 frame đường bằng phẳng (mỗi frame 160x120 độ xám đồng nhất)
      final flatRoadFrames = List.generate(
        100,
        (_) => Uint8List(width * height)..fillRange(0, width * height, 110),
      );

      final falseAlarmsPerMin = analyzer.countFalseAlarmsPerMinute(
        flatRoadFrames,
        width,
        height,
        fps: 20,
      );

      // Đạt mục tiêu < 1 cảnh báo nhầm / phút trên đường bằng
      expect(falseAlarmsPerMin, equals(0.0));
    });
  });
}
