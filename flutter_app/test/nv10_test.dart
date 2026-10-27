import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NV10 - Quyền hạn, Bảo mật và Dọn dẹp Repo', () {
    test('AndroidManifest.xml chỉ chứa các quyền tối giản cần thiết, không xin quyền thừa', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue, reason: 'AndroidManifest.xml phải tồn tại');

      final content = manifestFile.readAsStringSync();

      // Các quyền bắt buộc phải có cho tính năng dẫn đường & thị giác
      expect(content, contains('android.permission.CAMERA'));
      expect(content, contains('android.permission.VIBRATE'));
      expect(content, contains('android.permission.ACCESS_FINE_LOCATION'));
      expect(content, contains('android.permission.ACCESS_COARSE_LOCATION'));
      expect(content, contains('android.permission.INTERNET'));
      expect(content, contains('android.permission.WAKE_LOCK'));

      // Các quyền nhạy cảm KHÔNG ĐƯỢC phép có (đảm bảo quyền riêng tư người khiếm thị)
      expect(content.contains('android.permission.RECORD_AUDIO'), isFalse,
          reason: 'Không được xin quyền ghi âm Microphone');
      expect(content.contains('android.permission.READ_CONTACTS'), isFalse,
          reason: 'Không được xin quyền đọc danh bạ');
      expect(content.contains('android.permission.READ_CALL_LOG'), isFalse,
          reason: 'Không được xin quyền nhật ký cuộc gọi');
      expect(content.contains('android.permission.READ_EXTERNAL_STORAGE'), isFalse,
          reason: 'Không được xin quyền đọc bộ nhớ ngoài');
      expect(content.contains('android.permission.WRITE_EXTERNAL_STORAGE'), isFalse,
          reason: 'Không được xin quyền ghi bộ nhớ ngoài');
    });

    test('Các cảm biến phần cứng đặt required="false" để máy tầm trung / giá rẻ cài được', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      final content = manifestFile.readAsStringSync();

      // La bàn và gia tốc kế không được bắt buộc cứng required="true"
      expect(content, contains('android.hardware.sensor.compass" android:required="false"'));
      expect(content, contains('android.hardware.sensor.accelerometer" android:required="false"'));
    });

    test('.gitignore bao quát đầy đủ các loại khóa bí mật, chứng chỉ và file nhạy cảm', () {
      final gitignoreFile = File('../.gitignore');
      if (gitignoreFile.existsSync()) {
        final content = gitignoreFile.readAsStringSync();

        expect(content, contains('*.pem'));
        expect(content, contains('*.key'));
        expect(content, contains('*.jks'));
        expect(content, contains('*.keystore'));
        expect(content, contains('*.env'));
        expect(content, contains('certs/'));
      }
    });

    test('Không có file chứng chỉ hay private key nào bị commit trong kho lưu trữ', () {
      final certsDir = Directory('../certs');
      if (certsDir.existsSync()) {
        final pemFiles = certsDir.listSync().where((f) => f.path.endsWith('.pem') || f.path.endsWith('.key'));
        expect(pemFiles, isEmpty, reason: 'Thư mục certs không được chứa tệp khóa bí mật .pem/.key');
      }
    });
  });
}
