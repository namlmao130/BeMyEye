import 'package:flutter/material.dart';
import '../../services/audio_haptics_service.dart';
import '../../services/alert_decision_engine.dart';
import '../../services/navigation_service.dart';
import 'developer_hud_screen.dart';
import 'widgets/safety_disclaimer_dialog.dart';

/// accessible_screen.dart
/// Giao diện tiếp cận chính (Accessibility First) dành cho người khiếm thị
/// Nút bấm xúc giác khổng lồ, hỗ trợ tuyệt đối VoiceOver (iOS) & TalkBack (Android)

class AccessibleScreen extends StatefulWidget {
  final AudioHapticsService audio;
  final AlertDecisionEngine alertEngine;
  final NavigationService navService;
  final bool isAppActive;
  final VoidCallback onToggleApp;

  const AccessibleScreen({
    Key? key,
    required this.audio,
    required this.alertEngine,
    required this.navService,
    required this.isAppActive,
    required this.onToggleApp,
  }) : super(key: key);

  @override
  State<AccessibleScreen> createState() => _AccessibleScreenState();
}

class _AccessibleScreenState extends State<AccessibleScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000), // OLED Pure Black tiết kiệm pin
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        centerTitle: true,
        title: const Text(
          'Be My Eyes VN',
          style: TextStyle(color: Color(0xFFFACC15), fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Thanh thông báo hướng dẫn
              Semantics(
                liveRegion: true,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF333333)),
                  ),
                  child: Text(
                    widget.isAppActive
                        ? 'Trợ lý đang quan sát phía trước. Chạm nút to để dừng lại.'
                        : 'Hệ thống đã sẵn sàng. Chạm nút to giữa màn hình để bắt đầu.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFACC15),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              // NÚT BẤM KHỔNG LỒ CHIẾM TRỌN TRUNG TÂM
              Expanded(
                child: Center(
                  child: Semantics(
                    button: true,
                    label: widget.isAppActive
                        ? 'Dừng dẫn đường thời gian thực'
                        : 'Bắt đầu dẫn đường thời gian thực',
                    child: SizedBox(
                      width: double.infinity,
                      height: 220,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.isAppActive
                              ? const Color(0xFFEF4444) // Đỏ khi đang bật
                              : const Color(0xFFFACC15), // Vàng khi đang dừng
                          foregroundColor: widget.isAppActive ? Colors.white : Colors.black,
                          elevation: 12,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(32),
                            side: const BorderSide(color: Colors.white, width: 4),
                          ),
                        ),
                        onPressed: widget.onToggleApp,
                        child: Text(
                          widget.isAppActive ? 'DỪNG LẠI' : 'BẮT ĐẦU\nDẪN ĐƯỜNG',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Các nút phụ bên dưới
              Column(
                children: [
                  Semantics(
                    button: true,
                    label: 'Mở màn hình kỹ thuật và đo đạc cho nhà phát triển',
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFA3A3A3),
                        side: const BorderSide(color: Color(0xFF444444)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (ctx) => DeveloperHUDScreen(
                              audio: widget.audio,
                              alertEngine: widget.alertEngine,
                              navService: widget.navService,
                            ),
                          ),
                        );
                      },
                      icon: const Text('🛠️'),
                      label: const Text('Màn hình Kỹ thuật & Đo đạc'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      SafetyDisclaimerDialog.checkAndShow(context, widget.audio);
                    },
                    child: const Text(
                      '📜 Điều khoản an toàn & Giới hạn kỹ thuật',
                      style: TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
