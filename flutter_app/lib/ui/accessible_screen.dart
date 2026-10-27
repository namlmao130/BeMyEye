import 'package:flutter/material.dart';
import '../../config/thresholds.dart';
import '../../services/audio_haptics_service.dart';
import '../../services/alert_decision_engine.dart';
import '../../services/navigation_service.dart';
import '../../services/detector_service.dart';
import '../../services/camera_pipeline_service.dart';
import 'developer_hud_screen.dart';
import 'widgets/safety_disclaimer_dialog.dart';

/// accessible_screen.dart
/// Giao diện tiếp cận chính (Accessibility First) dành cho người khiếm thị
/// Nút bấm xúc giác khổng lồ, hỗ trợ tuyệt đối VoiceOver (iOS) & TalkBack (Android)
/// Khóa an toàn nếu mô hình AI gặp sự cố.

class AccessibleScreen extends StatefulWidget {
  final AudioHapticsService audio;
  final AlertDecisionEngine alertEngine;
  final NavigationService navService;
  final DetectorService detectorService;
  final CameraPipelineService? pipelineService;
  final bool isAppActive;
  final VoidCallback onToggleApp;

  const AccessibleScreen({
    Key? key,
    required this.audio,
    required this.alertEngine,
    required this.navService,
    required this.detectorService,
    this.pipelineService,
    required this.isAppActive,
    required this.onToggleApp,
  }) : super(key: key);

  @override
  State<AccessibleScreen> createState() => _AccessibleScreenState();
}

class _AccessibleScreenState extends State<AccessibleScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SafetyDisclaimerDialog.checkAndShow(context, widget.audio);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasModelError = widget.detectorService.loadError != null;

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
              // CẢNH BÁO LỖI MÔ HÌNH HOẶC BẢN THỬ NGHIỆM
              if (hasModelError)
                Semantics(
                  liveRegion: true,
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7F1D1D), // Đỏ đậm cảnh báo lỗi
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEF4444), width: 2),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Color(0xFFFACC15), size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'LỖI MÔ HÌNH: ${widget.detectorService.loadError}\nĐừng dùng ứng dụng để dẫn đường!',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (widget.pipelineService?.status == PipelineStatus.failed)
                Semantics(
                  liveRegion: true,
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7F1D1D), // Đỏ đậm cảnh báo lỗi
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEF4444), width: 2),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 28),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'LỖI CAMERA: ĐÃ KHÓA DẪN ĐƯỜNG\nMất tín hiệu hoặc không thể khởi động camera!',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (widget.pipelineService?.status == PipelineStatus.demo)
                Semantics(
                  liveRegion: true,
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7F1D1D), // Đỏ đậm cảnh báo
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEF4444), width: 2),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Color(0xFFFACC15), size: 28),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'BẢN DEMO – CHƯA NHẬN DIỆN CAMERA\nKhông dùng để dẫn đường thực tế!',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Thanh thông báo hướng dẫn
              Semantics(
                liveRegion: true,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasModelError ? const Color(0xFFEF4444) : const Color(0xFF333333),
                    ),
                  ),
                  child: Text(
                    hasModelError
                        ? 'Không tải được mô hình nhận diện. Đừng dùng ứng dụng để dẫn đường.'
                        : widget.isAppActive
                            ? 'Trợ lý đang quan sát phía trước. Chạm nút to để dừng lại.'
                            : 'Hệ thống đã sẵn sàng. Chạm nút to giữa màn hình để bắt đầu.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: hasModelError ? const Color(0xFFEF4444) : const Color(0xFFFACC15),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              // NÚT BẤM KHỔNG LỒ CHIẾM TRỌN TRUNG TÂM (KHÓA KHI CÓ LỖI)
              Expanded(
                child: Center(
                  child: Semantics(
                    button: true,
                    enabled: widget.detectorService.isReady,
                    label: hasModelError
                        ? 'Chế độ dẫn đường bị khóa do lỗi tải mô hình'
                        : widget.isAppActive
                            ? 'Dừng dẫn đường thời gian thực'
                            : 'Bắt đầu dẫn đường thời gian thực',
                    child: SizedBox(
                      width: double.infinity,
                      height: 220,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hasModelError
                              ? const Color(0xFF374151) // Xám chì khóa khi lỗi
                              : widget.isAppActive
                                  ? const Color(0xFFEF4444) // Đỏ khi đang bật
                                  : const Color(0xFFFACC15), // Vàng khi đang dừng
                          foregroundColor: hasModelError
                              ? const Color(0xFF9CA3AF)
                              : widget.isAppActive
                                  ? Colors.white
                                  : Colors.black,
                          elevation: hasModelError ? 0 : 12,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(32),
                            side: BorderSide(
                              color: hasModelError ? const Color(0xFFEF4444) : Colors.white,
                              width: 4,
                            ),
                          ),
                        ),
                        onPressed: widget.detectorService.isReady ? widget.onToggleApp : null,
                        child: Text(
                          hasModelError
                              ? 'KHÓA DẪN ĐƯỜNG\n(LỖI MÔ HÌNH)'
                              : widget.isAppActive
                                  ? 'DỪNG LẠI'
                                  : 'BẮT ĐẦU\nDẪN ĐƯỜNG',
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
                              detectorService: widget.detectorService,
                              pipelineService: widget.pipelineService,
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
