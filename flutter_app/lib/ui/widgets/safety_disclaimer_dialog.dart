import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/audio_haptics_service.dart';

/// safety_disclaimer_dialog.dart
/// Hộp thoại Điều khoản An toàn Bắt buộc - Đọc to bằng VoiceOver/TalkBack & TTS

class SafetyDisclaimerDialog extends StatelessWidget {
  final AudioHapticsService audio;
  final VoidCallback onAccepted;

  const SafetyDisclaimerDialog({
    Key? key,
    required this.audio,
    required this.onAccepted,
  }) : super(key: key);

  static Future<bool> checkAndShow(
    BuildContext context,
    AudioHapticsService audio, {
    bool forceShow = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool('bemyeye_disclaimer_accepted') ?? false;

    if (accepted && !forceShow) return true;
    if (!context.mounted) return false;

    // Đọc to tóm tắt điều khoản an toàn sau khi hộp thoại đã xuất hiện.
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (!context.mounted) return;
        audio.speakVietnamese(
          'Chào mừng bạn đến với Be My Eyes Việt Nam. Xin lưu ý: Ứng dụng này chỉ là công cụ bổ trợ, tuyệt đối không thay thế gậy trắng hay người dẫn đường. Chạm nút dưới cùng để đồng ý.',
          force: true,
        );
      }),
    );

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SafetyDisclaimerDialog(
        audio: audio,
        onAccepted: () async {
          final saved = await prefs.setBool(
            'bemyeye_disclaimer_accepted',
            true,
          );
          if (!saved) return;
          if (ctx.mounted) Navigator.of(ctx).pop(true);
          audio.speakVietnamese(
            'Bạn đã đồng ý với điều khoản an toàn. Chúc bạn có chuyến đi an toàn.',
            force: true,
          );
        },
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFFACC15), width: 3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ĐIỀU KHOẢN AN TOÀN BẮT BUỘC',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFFACC15),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildBulletPoint(
                'Không thay thế gậy trắng:',
                'Ứng dụng chỉ là công cụ bổ trợ tầm xa và tầm cao. Bạn bắt buộc phải dùng gậy trắng để dò mặt đất.',
              ),
              _buildBulletPoint(
                'Không bao giờ che tai:',
                'Bắt buộc dùng tai nghe truyền xương, tai nghe hở (open-ear) hoặc loa ngoài để nghe tiếng xe thật phía sau.',
              ),
              _buildBulletPoint(
                'Giới hạn kỹ thuật:',
                'Camera điện thoại không thể đảm bảo 100% trong việc phát hiện hố ga mất nắp, rãnh cống hoặc vật cản khi ngược sáng.',
              ),
              _buildBulletPoint(
                'Ứng dụng không bao giờ nói "Đường an toàn":',
                'App im lặng chỉ có nghĩa cảm biến chưa phát hiện thấy vật cản, không cam kết đường hoàn toàn thông thoáng.',
              ),
              const SizedBox(height: 20),
              Semantics(
                button: true,
                label: 'Tôi hiểu rõ và đồng ý với điều khoản an toàn',
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFACC15),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onAccepted,
                    child: const Text(
                      'TÔI HIỂU RÕ VÀ ĐỒNG Ý',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBulletPoint(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚠️ ', style: TextStyle(fontSize: 14)),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: '$title ',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFACC15),
                    ),
                  ),
                  TextSpan(text: desc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
