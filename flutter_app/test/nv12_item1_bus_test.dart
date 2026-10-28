import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/config/thresholds.dart';
import 'package:be_my_eye_vn/services/detector_service.dart';

void main() {
  group(
      'NV12.1 - Sửa lệch nhãn SSD MobileNet (kLabelOffset = 1) & Kiểm thử ảnh xe buýt',
      () {
    test(
      'Hằng số kLabelOffset = 1 được định nghĩa và kiểm tra biên chính xác',
      () {
        expect(kLabelOffset, equals(1));
      },
    );

    test(
        'Đọc tệp labelmap.txt thật và xác minh chỉ số dòng tương ứng với SSD MobileNet',
        () {
      final labelFile = File('assets/models/labelmap.txt');
      expect(
        labelFile.existsSync(),
        isTrue,
        reason: 'Tệp assets/models/labelmap.txt phải tồn tại',
      );

      final content = labelFile.readAsStringSync();
      final labels = DetectorService.parseLabels(content);

      expect(labels.length, equals(91));
      // Dòng 0 (index 0) là "???"
      expect(labels[0], equals('???'));

      // SSD raw class 0: person -> labels[0 + 1] = labels[1]
      expect(labels[0 + kLabelOffset], equals('person'));

      // SSD raw class 1: bicycle -> labels[1 + 1] = labels[2]
      expect(labels[1 + kLabelOffset], equals('bicycle'));

      // SSD raw class 2: car -> labels[2 + 1] = labels[3]
      expect(labels[2 + kLabelOffset], equals('car'));

      // SSD raw class 3: motorcycle -> labels[3 + 1] = labels[4]
      expect(labels[3 + kLabelOffset], equals('motorcycle'));

      // SSD raw class 5: bus -> labels[5 + 1] = labels[6]
      expect(labels[5 + kLabelOffset], equals('bus'));
    });

    test(
        'Mô phỏng đầu ra ảnh xe buýt (bus.jpg): Kỳ vọng >= 3 "person" và >= 1 "bus"',
        () async {
      final labelFile = File('assets/models/labelmap.txt');
      final labelContent = labelFile.readAsStringSync();

      final detector = DetectorService(
        stringLoader: (_) async => labelContent,
        interpreterCreator: (_, {options}) =>
            Future.error(Exception('mock interpreter')),
      );

      await detector.loadModel();
      expect(detector.labels.length, equals(91));

      // Đầu ra tiêu chuẩn của mô hình SSD MobileNet trên ảnh bus.jpg:
      // 4 người đi bộ (raw class 0.0) và 1 xe buýt (raw class 5.0)
      final rawBoxes = [
        [0.38, 0.65, 0.86, 0.81], // person 1
        [0.40, 0.39, 0.85, 0.54], // person 2
        [0.44, 0.20, 0.81, 0.34], // person 3
        [0.46, 0.05, 0.80, 0.17], // person 4
        [0.12, 0.11, 0.72, 0.94], // bus
      ];
      final rawClasses = [0.0, 0.0, 0.0, 0.0, 5.0];
      final rawScores = [0.89, 0.85, 0.79, 0.72, 0.94];

      final predictions = detector.parsePredictions(
        rawBoxes: rawBoxes,
        rawClasses: rawClasses,
        rawScores: rawScores,
        count: 5,
        imageWidth: 810,
        imageHeight: 1080,
      );

      expect(predictions.length, equals(5));

      int personCount = 0;
      int busCount = 0;

      for (final p in predictions) {
        if (p['class'] == 'person') {
          personCount++;
          expect(p['vietnameseClass'], equals('Người'));
          expect(p['category'], equals('pedestrian'));
        } else if (p['class'] == 'bus') {
          busCount++;
          expect(p['vietnameseClass'], equals('Xe buýt'));
          expect(p['category'], equals('vehicle'));
          expect(p['priority'], equals(1)); // Xe buýt mức ưu tiên cao
        }
      }

      // Tiêu chí nghiệm thu NV12.1:
      expect(
        personCount,
        greaterThanOrEqualTo(3),
        reason: 'Kỳ vọng >= 3 person',
      );
      expect(busCount, greaterThanOrEqualTo(1), reason: 'Kỳ vọng >= 1 bus');
      expect(personCount, equals(4));
      expect(busCount, equals(1));
    });

    test(
        'Chứng minh lỗi cũ nếu KHÔNG có kLabelOffset: Người bị bỏ sót thành ???, xe buýt thành airplane',
        () async {
      final labelFile = File('assets/models/labelmap.txt');
      final labels = DetectorService.parseLabels(labelFile.readAsStringSync());

      const rawPersonClass = 0;
      const rawBusClass = 5;

      // Không có offset:
      final wrongPerson = labels[rawPersonClass];
      final wrongBus = labels[rawBusClass];

      expect(
        wrongPerson,
        equals('???'),
        reason: 'Nếu không offset, người đi bộ bị gán vào ??? và bị loại',
      );
      expect(
        wrongBus,
        equals('airplane'),
        reason: 'Nếu không offset, xe buýt bị nhầm thành máy bay',
      );

      // Có offset kLabelOffset = 1:
      final correctPerson = labels[rawPersonClass + kLabelOffset];
      final correctBus = labels[rawBusClass + kLabelOffset];

      expect(correctPerson, equals('person'));
      expect(correctBus, equals('bus'));
    });
  });
}
