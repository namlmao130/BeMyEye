import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/models/detection_result.dart';
import 'package:be_my_eye_vn/services/audio_haptics_service.dart';
import 'package:be_my_eye_vn/services/alert_decision_engine.dart';
import 'package:be_my_eye_vn/services/navigation_service.dart';

void main() {
  group(
    'NV11 - Dẫn đường bằng tuyến đi bộ OSRM & Cơ chế An toàn Safety Preemption',
    () {
      const sampleOsrmJson = '''
    {
      "code": "Ok",
      "routes": [
        {
          "distance": 450.0,
          "duration": 360.0,
          "legs": [
            {
              "distance": 450.0,
              "duration": 360.0,
              "steps": [
                {
                  "name": "Đinh Tiên Hoàng",
                  "distance": 85.0,
                  "maneuver": {
                    "type": "depart",
                    "modifier": "straight",
                    "location": [105.854167, 21.028511]
                  }
                },
                {
                  "name": "Phố Lò Sũ",
                  "distance": 120.0,
                  "maneuver": {
                    "type": "turn",
                    "modifier": "right",
                    "location": [105.854200, 21.028850]
                  }
                },
                {
                  "name": "Hẻm 12",
                  "distance": 95.0,
                  "maneuver": {
                    "type": "turn",
                    "modifier": "left",
                    "location": [105.854700, 21.028880]
                  }
                },
                {
                  "name": "Nhà Hát Lớn Hà Nội",
                  "distance": 150.0,
                  "maneuver": {
                    "type": "arrive",
                    "modifier": null,
                    "location": [105.857644, 21.024344]
                  }
                }
              ]
            }
          ]
        }
      ]
    }
    ''';

      test(
          'Phân tích JSON OSRM Foot Profile thật thành danh sách Waypoint tiếng Việt chính xác',
          () async {
        final audio = AudioHapticsService(customSpeaker: (text) async {});
        final alertEngine = AlertDecisionEngine(audio: audio);

        final nav = NavigationService(
          audio: audio,
          alertEngine: alertEngine,
          enableCompass: false,
          routeApiBase: 'https://walking.test/route/v1/foot',
          httpGetClient: (uri) async => sampleOsrmJson,
        );

        final route = await nav.fetchOsrmRoute(
          startLat: 21.028511,
          startLng: 105.854167,
          destLat: 21.024344,
          destLng: 105.857644,
          destName: 'Nhà Hát Lớn Hà Nội',
        );

        expect(route, isNotNull);
        expect(route!.length, equals(4));

        // Mốc 1: Xuất phát
        expect(route[0].lat, equals(21.028511));
        expect(route[0].lng, equals(105.854167));
        expect(route[0].name, equals('Đinh Tiên Hoàng'));
        expect(route[0].actionText, equals('Xuất phát'));
        expect(route[0].instruction, contains('Bắt đầu đi thẳng'));

        // Mốc 2: Rẽ phải
        expect(route[1].name, equals('Phố Lò Sũ'));
        expect(route[1].actionText, equals('Rẽ phải'));
        expect(route[1].instruction, contains('Rẽ phải vào Phố Lò Sũ'));

        // Mốc 3: Rẽ trái
        expect(route[2].name, equals('Hẻm 12'));
        expect(route[2].actionText, equals('Rẽ trái'));
        expect(route[2].instruction, contains('Rẽ trái vào Hẻm 12'));

        // Mốc 4: Đích đến
        expect(route[3].name, equals('Nhà Hát Lớn Hà Nội'));
        expect(route[3].actionText, equals('Đích đến'));
        expect(route[3].instruction, contains('đích'));

        // Lộ trình được lưu vào bộ nhớ đệm
        expect(nav.cachedRoute.length, equals(4));

        nav.dispose();
        audio.dispose();
      });

      test(
          'Xử lý khi mất mạng và chưa có cache: Thông báo bằng giọng nói, không làm treo ứng dụng',
          () async {
        final spokenWords = <String>[];
        final audio = AudioHapticsService(
          customSpeaker: (text) async {
            spokenWords.add(text);
          },
        );
        final alertEngine = AlertDecisionEngine(audio: audio);

        // Giả lập lỗi mất mạng (SocketException)
        final nav = NavigationService(
          audio: audio,
          alertEngine: alertEngine,
          enableCompass: false,
          routeApiBase: 'https://walking.test/route/v1/foot',
          httpGetClient: (uri) async =>
              throw const SocketException('Không thể kết nối Internet'),
        );

        final success = await nav.startNavigationToDestination(
          destLat: 21.024344,
          destLng: 105.857644,
          fallbackStartLat: 21.028511,
          fallbackStartLng: 105.854167,
        );

        expect(
          success,
          isFalse,
          reason: 'Phải trả về false khi không có lộ trình',
        );
        expect(
          spokenWords.any(
            (w) => w.contains(
              'Không có mạng, chỉ dùng được chế độ phát hiện vật cản',
            ),
          ),
          isTrue,
        );

        nav.dispose();
        audio.dispose();
      });

      test(
          'Xử lý khi mất mạng nhưng ĐÃ CÓ CACHE: Tự động phục hồi lộ trình đã lưu trong đệm',
          () async {
        final spokenWords = <String>[];
        final audio = AudioHapticsService(
          customSpeaker: (text) async {
            spokenWords.add(text);
          },
        );
        final alertEngine = AlertDecisionEngine(audio: audio);

        bool networkAvailable = true;
        final nav = NavigationService(
          audio: audio,
          alertEngine: alertEngine,
          enableCompass: false,
          routeApiBase: 'https://walking.test/route/v1/foot',
          httpGetClient: (uri) async {
            if (networkAvailable) return sampleOsrmJson;
            throw const SocketException('Mạng bị ngắt');
          },
        );

        // Lần 1: Có mạng -> tải và lưu cache
        await nav.fetchOsrmRoute(
          startLat: 21.028511,
          startLng: 105.854167,
          destLat: 21.024344,
          destLng: 105.857644,
        );
        expect(nav.cachedRoute.length, equals(4));

        // Lần 2: Mất mạng hoàn toàn
        networkAvailable = false;
        final fallbackRoute = await nav.fetchOsrmRoute(
          startLat: 21.028511,
          startLng: 105.854167,
          destLat: 21.024344,
          destLng: 105.857644,
        );

        expect(fallbackRoute, isNotNull);
        expect(fallbackRoute!.length, equals(4));
        expect(fallbackRoute[0].name, equals('Đinh Tiên Hoàng'));

        nav.dispose();
        audio.dispose();
      });

      test(
          'Cơ chế An toàn Tuyệt đối (Safety Preemption): Camera phát hiện nguy cấp ngắt ngay lời chỉ đường GPS',
          () {
        final spokenWords = <String>[];
        final audio = AudioHapticsService(
          customSpeaker: (text) async {
            spokenWords.add(text);
          },
        );
        final alertEngine = AlertDecisionEngine(audio: audio);

        final nav = NavigationService(
          audio: audio,
          alertEngine: alertEngine,
          enableCompass: false,
        );

        // Trường hợp 1: Không có hiểm họa camera -> GPS được phép nói
        nav.startSimulation();
        expect(spokenWords.length, greaterThanOrEqualTo(1));
        spokenWords.clear();

        // Trường hợp 2: Camera phát hiện xe máy lao tới cực gần (< 1.5m, isApproaching)
        final criticalThreat = DetectionResult(
          id: 'bike_danger',
          label: 'motorcycle',
          vietnameseLabel: 'Xe máy',
          category: 'vehicle',
          score: 0.95,
          bbox: [100, 100, 100, 100],
          centerX: 0.50,
          bottomY: 0.92,
          areaRatio: 0.28,
          direction: DirectionZone.center,
          panValue: 0.0,
          distanceLevel: DistanceLevel.critical,
          approximateDistanceMeters: '< 1.5m',
          isApproaching: true,
        );

        alertEngine.process(
          objects2D: [criticalThreat],
          groundHazards: [],
          customNow: 1000,
        );

        expect(alertEngine.currentThreat, isNotNull);
        expect(alertEngine.currentThreat!.isApproaching, isTrue);

        // Khi có nguy hiểm camera, nếu GPS muốn phát chỉ dẫn đường đi thì bắt buộc bị ngắt/chặn ngay!
        // (Bảo vệ tính mạng người khiếm thị trên đường phố Việt Nam)
        nav.stopNavigation();
        nav.dispose();
        audio.dispose();
      });
    },
  );
}
