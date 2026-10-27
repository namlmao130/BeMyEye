import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/services/detector_service.dart';
import 'package:be_my_eye_vn/services/audio_haptics_service.dart';
import 'package:be_my_eye_vn/services/alert_decision_engine.dart';
import 'package:be_my_eye_vn/services/navigation_service.dart';
import 'package:be_my_eye_vn/ui/accessible_screen.dart';

void main() {
  group('NV2 - DetectorService: Nạp nhãn, Class Mappings và Báo lỗi to', () {
    test('parseLabels phải phân tách chính xác danh sách 91 nhãn COCO SSD', () {
      final sample91 = List.generate(91, (i) => i == 0 ? '???' : 'label_$i').join('\n');
      final labels = DetectorService.parseLabels(sample91);
      expect(labels.length, equals(91));
      expect(labels.first, equals('???'));
      expect(labels.last, equals('label_90'));
    });

    test('Đồng bộ đầy đủ classMappings với bản web (15 classes chuẩn xác)', () {
      final mappings = DetectorService.classMappings;

      // Kiểm tra 4 lớp bắt buộc thêm mới theo yêu cầu NV2
      expect(mappings.containsKey('umbrella'), isTrue);
      expect(mappings['umbrella']!['vi'], equals('Dù bạt che'));
      expect(mappings['umbrella']!['category'], equals('obstacle'));
      expect(mappings['umbrella']!['priority'], equals(4));

      expect(mappings.containsKey('traffic light'), isTrue);
      expect(mappings['traffic light']!['vi'], equals('Đèn giao thông'));
      expect(mappings['traffic light']!['priority'], equals(6));

      expect(mappings.containsKey('fire hydrant'), isTrue);
      expect(mappings['fire hydrant']!['vi'], equals('Trụ nước'));
      expect(mappings['fire hydrant']!['priority'], equals(5));

      expect(mappings.containsKey('cat'), isTrue);
      expect(mappings['cat']!['vi'], equals('Mèo'));
      expect(mappings['cat']!['category'], equals('animal'));
      expect(mappings['cat']!['priority'], equals(7));

      // Kiểm tra các phương tiện và người đi bộ
      expect(mappings.containsKey('motorcycle'), isTrue);
      expect(mappings.containsKey('car'), isTrue);
      expect(mappings.containsKey('bicycle'), isTrue);
      expect(mappings.containsKey('bus'), isTrue);
      expect(mappings.containsKey('truck'), isTrue);
      expect(mappings.containsKey('person'), isTrue);
      expect(mappings.containsKey('chair'), isTrue);
      expect(mappings.containsKey('bench'), isTrue);
      expect(mappings.containsKey('potted plant'), isTrue);
      expect(mappings.containsKey('stop sign'), isTrue);
      expect(mappings.containsKey('dog'), isTrue);

      expect(mappings.length, equals(15));
    });

    test('parsePredictions áp dụng confidenceThreshold thật sự và kLabelOffset = 1 (Lệch nhãn SSD)', () async {
      final detector = DetectorService(
        stringLoader: (_) async => List.generate(91, (i) {
          if (i == 1) return 'person';
          if (i == 4) return 'motorcycle';
          if (i == 6) return 'bus';
          return '???';
        }).join('\n'),
        interpreterCreator: (_, {options}) => Future.error(Exception('mock interpreter offline')),
      );

      await detector.loadModel();

      // Kiểm tra nhãn nạp thành công
      expect(detector.labels.length, equals(91));

      // rawClasses xuất phát từ 0 theo chuẩn SSD MobileNet:
      // 0.0 -> class 0 + offset 1 = index 1 ('person')
      // 3.0 -> class 3 + offset 1 = index 4 ('motorcycle')
      final predictions = detector.parsePredictions(
        rawBoxes: [
          [0.1, 0.2, 0.5, 0.6], // person (ymin, xmin, ymax, xmax)
          [0.2, 0.3, 0.8, 0.9], // motorcycle
          [0.0, 0.0, 0.1, 0.1], // motorcycle nhưng score < threshold
        ],
        rawClasses: [0.0, 3.0, 3.0],
        rawScores: [0.85, 0.92, 0.30], // 0.30 thấp hơn ngưỡng mặc định 0.45
        count: 3,
        imageWidth: 1000,
        imageHeight: 1000,
      );

      // Điểm 0.30 bị loại bỏ -> chỉ còn 2 kết quả
      expect(predictions.length, equals(2));

      // Sắp xếp theo ưu tiên: motorcycle (priority 1) phải đứng trước person (priority 4)
      expect(predictions[0]['class'], equals('motorcycle'));
      expect(predictions[0]['vietnameseClass'], equals('Xe máy'));
      expect(predictions[0]['category'], equals('vehicle'));
      expect(predictions[0]['priority'], equals(1));
      expect(predictions[0]['score'], equals(0.92));
      expect(predictions[0]['bbox'], equals([300.0, 200.0, 600.0, 600.0]));

      expect(predictions[1]['class'], equals('person'));
      expect(predictions[1]['vietnameseClass'], equals('Người'));
      expect(predictions[1]['priority'], equals(4));
      expect(predictions[1]['bbox'], equals([200.0, 100.0, 400.0, 400.0]));
    });

    test('Kiểm tra biên kLabelOffset = 1: Bỏ qua chỉ số âm, vượt quá kích thước hoặc trúng ???', () async {
      final detector = DetectorService(
        stringLoader: (_) async => List.generate(91, (i) {
          if (i == 1) return 'person';
          if (i == 6) return 'bus';
          return '???';
        }).join('\n'),
        interpreterCreator: (_, {options}) => Future.error(Exception('mock interpreter offline')),
      );

      await detector.loadModel();

      final predictions = detector.parsePredictions(
        rawBoxes: [
          [0.1, 0.1, 0.5, 0.5], // Trúng ??? (class 1 -> 1+1=2 ???)
          [0.1, 0.1, 0.5, 0.5], // class 5 -> 5+1=6 ('bus')
          [0.1, 0.1, 0.5, 0.5], // Vượt biên (class 95)
          [0.1, 0.1, 0.5, 0.5], // Chỉ số âm (-1)
        ],
        rawClasses: [1.0, 5.0, 95.0, -1.0],
        rawScores: [0.90, 0.90, 0.90, 0.90],
        count: 4,
        imageWidth: 100,
        imageHeight: 100,
      );

      // Chỉ có lớp 5 (bus) hợp lệ
      expect(predictions.length, equals(1));
      expect(predictions.first['class'], equals('bus'));
      expect(predictions.first['vietnameseClass'], equals('Xe buýt'));
    });

    test('Báo lỗi to: Khi không tìm thấy file mô hình hoặc nhãn, loadError phải được lưu và isReady == false', () async {
      final detector = DetectorService(
        stringLoader: (_) => Future.error(Exception('File labelmap không tồn tại')),
      );

      await detector.loadModel();

      expect(detector.isReady, isFalse);
      expect(detector.isLoaded, isFalse);
      expect(detector.loadError, isNotNull);
      expect(detector.loadError, contains('Lỗi nạp labelmap'));
      expect(detector.activeDelegate, equals('LỖI'));
    });

    test('Báo lỗi to: Khi số lượng nhãn khác 91, loadError phải báo sai số lượng nhãn', () async {
      final detector = DetectorService(
        stringLoader: (_) async => 'person\ncar\nbicycle', // Chỉ có 3 nhãn
      );

      await detector.loadModel();

      expect(detector.isReady, isFalse);
      expect(detector.loadError, contains('yêu cầu 91 dòng'));
      expect(detector.activeDelegate, equals('LỖI'));
    });

    test('Báo lỗi to: Khi nạp mô hình TFLite thất bại, tự động bắt lỗi và lưu loadError', () async {
      final detector = DetectorService(
        stringLoader: (_) async => List.generate(91, (i) => 'label_$i').join('\n'),
        interpreterCreator: (_, {options}) => Future.error(Exception('Mô hình bị hỏng hoặc thiếu')),
      );

      await detector.loadModel();

      expect(detector.isReady, isFalse);
      expect(detector.loadError, isNotNull);
      expect(detector.loadError, contains('Không thể nạp mô hình'));
      expect(detector.activeDelegate, equals('LỖI'));
    });
  });

  group('NV2 - Giao diện AccessibleScreen: Khóa nút bấm khi mô hình lỗi', () {
    testWidgets('Nút bắt đầu bị khóa và hiển thị cảnh báo lỗi khi detectorService có lỗi', (WidgetTester tester) async {
      final audio = AudioHapticsService();
      final alertEngine = AlertDecisionEngine(audio: audio);
      final navService = NavigationService(audio: audio, alertEngine: alertEngine);

      // Tạo detector với lỗi giả lập
      final failingDetector = DetectorService(
        stringLoader: (_) => Future.error(Exception('Xóa model giả lập')),
      );
      await failingDetector.loadModel();

      expect(failingDetector.isReady, isFalse);
      expect(failingDetector.loadError, isNotNull);

      bool toggleCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: AccessibleScreen(
            audio: audio,
            alertEngine: alertEngine,
            navService: navService,
            detectorService: failingDetector,
            isAppActive: false,
            onToggleApp: () => toggleCalled = true,
          ),
        ),
      );

      // Kiểm tra banner lỗi xuất hiện
      expect(find.textContaining('LỖI MÔ HÌNH'), findsOneWidget);
      expect(find.textContaining('Đừng dùng ứng dụng để dẫn đường'), findsWidgets);

      // Kiểm tra chữ trên nút bấm báo KHÓA DẪN ĐƯỜNG
      expect(find.textContaining('KHÓA DẪN ĐƯỜNG'), findsOneWidget);

      // Tìm nút bấm chính
      final elevatedButtonFinder = find.byType(ElevatedButton).first;
      final ElevatedButton button = tester.widget(elevatedButtonFinder);

      // Nút phải bị disabled (onPressed == null)
      expect(button.onPressed, isNull);

      // Nhấn thử vào nút -> toggle không được gọi
      await tester.tap(elevatedButtonFinder);
      await tester.pump();
      expect(toggleCalled, isFalse);

      audio.dispose();
      navService.dispose();
    });
  });
}
