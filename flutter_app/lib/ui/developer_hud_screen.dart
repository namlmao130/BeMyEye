import 'package:flutter/material.dart';
import '../../services/audio_haptics_service.dart';
import '../../services/alert_decision_engine.dart';
import '../../services/navigation_service.dart';

/// developer_hud_screen.dart
/// Màn hình kỹ thuật dành cho Nhà phát triển & Người bảo hộ đi cùng (Sighted Companion Toolbar)

class DeveloperHUDScreen extends StatefulWidget {
  final AudioHapticsService audio;
  final AlertDecisionEngine alertEngine;
  final NavigationService navService;

  const DeveloperHUDScreen({
    Key? key,
    required this.audio,
    required this.alertEngine,
    required this.navService,
  }) : super(key: key);

  @override
  State<DeveloperHUDScreen> createState() => _DeveloperHUDScreenState();
}

class _DeveloperHUDScreenState extends State<DeveloperHUDScreen> {
  int goodAlerts = 0;
  int missedObstacles = 0;
  int falseAlarms = 0;

  @override
  Widget build(BuildContext context) {
    final navStatus = widget.navService.getStatus();
    final currentThreat = widget.alertEngine.currentThreat;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Màn hình Kỹ thuật & Đo lường'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Bảng HUD thông số thời gian thực
            Row(
              children: [
                _buildHUDCard('FPS', '21.4', Colors.white),
                const SizedBox(width: 8),
                _buildHUDCard('Độ trễ', '42 ms', Colors.white),
                const SizedBox(width: 8),
                _buildHUDCard(
                  'Mối nguy',
                  currentThreat?.vietnameseLabel ?? '--',
                  currentThreat != null ? const Color(0xFFEF4444) : Colors.grey,
                ),
                const SizedBox(width: 8),
                _buildHUDCard(
                  'Hướng',
                  currentThreat?.direction.name.toUpperCase() ?? '--',
                  Colors.white,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Khung Camera mô phỏng
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF333333)),
              ),
              child: Stack(
                children: [
                  const Center(
                    child: Text(
                      'Luồng Camera On-Device (TFLite YOLO/SSD)',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ),
                  // Đường kẻ phân chia 3 hành lang Trái - Giữa - Phải
                  Positioned.fill(
                    child: CustomPaint(
                      painter: CorridorOverlayPainter(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Thanh công cụ Người bảo hộ đi kèm (Field Testing Toolbar)
            _buildSection(
              title: 'Thanh công cụ Người bảo hộ đi kèm',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF15803D)),
                          onPressed: () => setState(() => goodAlerts++),
                          child: Text('Cảnh báo tốt ($goodAlerts)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                          onPressed: () => setState(() => missedObstacles++),
                          child: Text('Bỏ sót ($missedObstacles)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB45309)),
                          onPressed: () => setState(() => falseAlarms++),
                          child: Text('Báo nhầm ($falseAlarms)'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Dẫn đường GPS từng bước
            _buildSection(
              title: 'Dẫn đường từng bước (Turn-by-Turn GPS)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trạng thái: ${navStatus.isSimulating ? "Mô phỏng (Simulator)" : navStatus.isNavigating ? "Đang bật GPS thật" : "Chưa kích hoạt"}',
                    style: const TextStyle(color: Color(0xFFFACC15), fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Chỉ dẫn: ${navStatus.lastInstruction.isNotEmpty ? navStatus.lastInstruction : "--"}',
                    style: const TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Mốc: ${navStatus.currentWaypointIndex + 1}/${navStatus.totalWaypoints} | Cự ly: ${navStatus.distanceMeters}m | Sai số GPS: ±${navStatus.gpsAccuracy}m | La bàn: ${navStatus.compassHeading}°',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1D4ED8)),
                          onPressed: () => widget.navService.startNavigation(),
                          child: const Text('Bật GPS thật'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF047857)),
                          onPressed: () => widget.navService.startSimulation(),
                          child: const Text('Mô phỏng'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF333333)),
                          onPressed: () => widget.navService.stopNavigation(),
                          child: const Text('Dừng'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Thử nghiệm âm thanh Stereo Pan
            _buildSection(
              title: 'Thử nghiệm âm thanh Stereo Pan',
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => widget.audio.playDirectionalBeep(pan: -0.85, pitch: 600),
                      child: const Text('Bíp Trái'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => widget.audio.playDirectionalBeep(pan: 0.0, pitch: 750),
                      child: const Text('Bíp Giữa'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => widget.audio.playDirectionalBeep(pan: 0.85, pitch: 900),
                      child: const Text('Bíp Phải'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHUDCard(String label, String value, Color valColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: valColor, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Color(0xFFFACC15), fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class CorridorOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Vạch trái (35%)
    canvas.drawLine(Offset(size.width * 0.35, 0), Offset(size.width * 0.35, size.height), paint);
    // Vạch phải (65%)
    canvas.drawLine(Offset(size.width * 0.65, 0), Offset(size.width * 0.65, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
