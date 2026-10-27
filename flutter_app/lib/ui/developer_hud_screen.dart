import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/thresholds.dart';
import '../../models/detection_result.dart';
import '../../services/audio_haptics_service.dart';
import '../../services/alert_decision_engine.dart';
import '../../services/navigation_service.dart';
import '../../services/detector_service.dart';
import '../../services/camera_pipeline_service.dart';

/// developer_hud_screen.dart
/// Màn hình kỹ thuật dành cho Nhà phát triển (Developer HUD)
/// Hiển thị trực tiếp luồng CameraPreview, vẽ Bounding Boxes, hiển thị độ trễ từng giai đoạn,
/// và công cụ xuất file log CSV để đo đạc thực địa.

class DeveloperHUDScreen extends StatefulWidget {
  final AudioHapticsService audio;
  final AlertDecisionEngine alertEngine;
  final NavigationService navService;
  final DetectorService detectorService;
  final CameraPipelineService? pipelineService;

  const DeveloperHUDScreen({
    Key? key,
    required this.audio,
    required this.alertEngine,
    required this.navService,
    required this.detectorService,
    this.pipelineService,
  }) : super(key: key);

  @override
  State<DeveloperHUDScreen> createState() => _DeveloperHUDScreenState();
}

class _DeveloperHUDScreenState extends State<DeveloperHUDScreen> {
  @override
  void initState() {
    super.initState();
    widget.pipelineService?.onFrameProcessed = _onPipelineUpdate;
  }

  void _onPipelineUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    if (widget.pipelineService?.onFrameProcessed == _onPipelineUpdate) {
      widget.pipelineService?.onFrameProcessed = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navStatus = widget.navService.getStatus();
    final currentThreat = widget.alertEngine.currentThreat;
    final det = widget.detectorService;
    final pipeline = widget.pipelineService;

    final fpsText = (pipeline != null && pipeline.currentFps > 0)
        ? pipeline.currentFps.toStringAsFixed(1)
        : (pipeline?.status == PipelineStatus.running ? '--' : 'Chưa chạy');

    final latencyText = (pipeline != null && pipeline.latencyTotalMs > 0)
        ? '${pipeline.latencyTotalMs} ms'
        : (pipeline?.status == PipelineStatus.running ? '--' : 'Chưa chạy');

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
                _buildHUDCard('FPS', fpsText, Colors.white),
                const SizedBox(width: 8),
                _buildHUDCard('Độ trễ tổng', latencyText, Colors.white),
                const SizedBox(width: 8),
                _buildHUDCard(
                  'Delegate',
                  det.activeDelegate,
                  det.activeDelegate == 'LỖI'
                      ? const Color(0xFFEF4444)
                      : (det.activeDelegate == 'GPU' || det.activeDelegate == 'XNNPACK' || det.activeDelegate == 'NNAPI')
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFFACC15),
                ),
                const SizedBox(width: 8),
                _buildHUDCard(
                  'Mô hình',
                  det.isReady ? '${det.labels.length} nhãn' : 'LỖI',
                  det.isReady ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              children: [
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
                const SizedBox(width: 8),
                _buildHUDCard(
                  'Số vật thể',
                  '${pipeline?.latestDetections.length ?? 0}',
                  const Color(0xFF38BDF8),
                ),
                const SizedBox(width: 8),
                _buildHUDCard(
                  'Tin cậy AI',
                  '${(det.confidenceThreshold * 100).toInt()}%',
                  const Color(0xFFFACC15),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                _buildHUDCard(
                  'Mức Pin',
                  '${pipeline?.batteryOptimizer.batteryLevel ?? 100}%',
                  (pipeline?.batteryOptimizer.isLowBattery ?? false)
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF22C55E),
                ),
                const SizedBox(width: 8),
                _buildHUDCard(
                  'Nhiệt độ máy',
                  pipeline?.healthService?.thermalStatusText ?? 'Bình thường',
                  (pipeline?.batteryOptimizer.isOverheated ?? false)
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF38BDF8),
                ),
                const SizedBox(width: 8),
                _buildHUDCard(
                  'FPS Mục tiêu',
                  '${pipeline?.batteryOptimizer.targetFPS ?? 22} fps',
                  const Color(0xFFFACC15),
                ),
                const SizedBox(width: 8),
                _buildHUDCard(
                  'Chế độ tải',
                  (pipeline?.batteryOptimizer.isOverheated ?? false)
                      ? 'QUÁ NHIỆT'
                      : (pipeline?.batteryOptimizer.isLowBattery ?? false)
                          ? 'TIẾT KIỆM'
                          : (pipeline?.batteryOptimizer.userMovementState == 'standing' ? 'ĐỨNG YÊN' : 'BƯỚC ĐI'),
                  (pipeline?.batteryOptimizer.isOverheated ?? false)
                      ? const Color(0xFFEF4444)
                      : (pipeline?.batteryOptimizer.isLowBattery ?? false)
                          ? const Color(0xFFFACC15)
                          : const Color(0xFF22C55E),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Chi tiết độ trễ từng chặng (Preprocess / Inference / Analysis)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text(
                    'Tiền xử lý: ${pipeline?.latencyPreprocessMs ?? 0}ms',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12),
                  ),
                  Text(
                    'Suy luận AI: ${pipeline?.latencyInferenceMs ?? 0}ms',
                    style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 12),
                  ),
                  Text(
                    'Phân tích: ${pipeline?.latencyAnalysisMs ?? 0}ms',
                    style: const TextStyle(color: Color(0xFFFACC15), fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Khung Camera thật (CameraPreview) + Vẽ Bounding Box & 3 hành lang
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF333333)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (pipeline?.controller != null &&
                        pipeline!.controller!.value.isInitialized)
                      CameraPreview(pipeline.controller!)
                    else
                      Center(
                        child: Text(
                          pipeline != null && pipeline.isStreaming
                              ? 'Đang khởi động Camera...'
                              : 'Camera đang tắt\n(Nhấn "BẮT ĐẦU DẪN ĐƯỜNG" ở màn hình chính để kích hoạt luồng camera)',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),

                    // Vẽ đường phân chia 3 hành lang (Trái 35% - Giữa 30% - Phải 35%)
                    CustomPaint(
                      painter: CorridorOverlayPainter(),
                    ),

                    // Vẽ các hộp nhận diện (Bounding Boxes) từ mô hình AI
                    if (pipeline != null && pipeline.latestDetections.isNotEmpty)
                      CustomPaint(
                        painter: BoundingBoxPainter(detections: pipeline.latestDetections),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Chi tiết độ trễ từng giai đoạn (Latency Breakdown)
            if (pipeline != null && pipeline.latencyTotalMs > 0)
              _buildSection(
                title: 'Chi tiết thời gian xử lý (Latency Breakdown)',
                child: Column(
                  children: [
                    _buildLatencyRow('1. Tiền xử lý (YUV420 → RGB/Luma Isolate)', '${pipeline.latencyPreprocessMs} ms'),
                    _buildLatencyRow('2. Suy luận TFLite SSD MobileNet on-device', '${pipeline.latencyInferenceMs} ms'),
                    _buildLatencyRow('3. Phân tích Không gian & Bậc thềm', '${pipeline.latencyAnalysisMs} ms'),
                    const Divider(color: Color(0xFF333333)),
                    _buildLatencyRow('Tổng độ trễ mỗi khung hình (End-to-End)', '${pipeline.latencyTotalMs} ms', isTotal: true),
                  ],
                ),
              ),
            const SizedBox(height: 14),

            // Công cụ ghi log CSV đo đạc thực địa
            _buildSection(
              title: 'Công cụ Đo đạc Thực địa & Benchmark 3 Phút',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'LƯU Ý TRUNG THỰC: Số liệu hiệu năng CẦN ĐO TRÊN MÁY THẬT. '
                            'Không khẳng định kết quả khi chưa có file log CSV thực địa.',
                            style: TextStyle(color: Color(0xFFFDE68A), fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Số bản ghi CSV hiện có: ${pipeline?.csvLogger.rowCount ?? 0} dòng',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  // Nút Benchmark 3 phút
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (pipeline?.csvLogger.isBenchmarkRunning ?? false)
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF059669),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      icon: Icon(
                        (pipeline?.csvLogger.isBenchmarkRunning ?? false)
                            ? Icons.timer
                            : Icons.speed,
                        size: 20,
                      ),
                      label: Text(
                        (pipeline?.csvLogger.isBenchmarkRunning ?? false)
                            ? 'Đang đo benchmark: còn ${pipeline?.csvLogger.benchmarkRemainingSeconds}s (Bấm để dừng)'
                            : 'Bắt đầu đo hiệu năng 3 phút (Xuất CSV)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        if (pipeline == null) return;
                        if (pipeline.csvLogger.isBenchmarkRunning) {
                          pipeline.csvLogger.stopBenchmark();
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Đã dừng phiên benchmark đo hiệu năng.')),
                          );
                        } else {
                          pipeline.csvLogger.startBenchmark(
                            durationSeconds: 180,
                            onComplete: (csvData) {
                              Clipboard.setData(ClipboardData(text: csvData));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Đã hoàn thành benchmark 3 phút! Đã sao chép CSV vào bộ nhớ tạm.'),
                                    backgroundColor: Color(0xFF15803D),
                                    duration: Duration(seconds: 4),
                                  ),
                                );
                              }
                            },
                          );
                          setState(() {});
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Sao chép CSV'),
                          onPressed: () {
                            if (pipeline == null || pipeline.csvLogger.rowCount == 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Chưa có dữ liệu CSV nào được ghi!')),
                              );
                              return;
                            }
                            final csvText = pipeline.csvLogger.exportCsv();
                            Clipboard.setData(ClipboardData(text: csvText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Đã sao chép ${pipeline.csvLogger.rowCount} dòng CSV vào bộ nhớ tạm để gửi lại!'),
                                backgroundColor: const Color(0xFF15803D),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(color: Color(0xFFEF4444)),
                        ),
                        onPressed: () {
                          pipeline?.csvLogger.clear();
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Đã xóa bộ nhớ log CSV.')),
                          );
                        },
                        child: const Text('Xóa Log'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Cấu hình mô hình AI & Thanh trượt Confidence
            _buildSection(
              title: 'Cấu hình Mô hình Thị giác AI (SSD MobileNet)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trạng thái: ${det.isReady ? "Sẵn sàng hoạt động" : "Lỗi nạp mô hình"}',
                    style: TextStyle(
                      color: det.isReady ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (det.loadError != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Chi tiết lỗi: ${det.loadError}',
                      style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'Bộ tăng tốc phần cứng (Delegate): ${det.activeDelegate} (Tự động fallback: GPU → NNAPI → CPU)',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tổng số nhãn nạp được: ${det.labels.length} nhãn (COCO SSD 91 dòng)',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        'Ngưỡng tin cậy (Confidence): ${(det.confidenceThreshold * 100).toInt()}%',
                        style: const TextStyle(color: Color(0xFFFACC15), fontSize: 13),
                      ),
                      Expanded(
                        child: Slider(
                          value: det.confidenceThreshold,
                          min: 0.20,
                          max: 0.90,
                          divisions: 14,
                          label: '${(det.confidenceThreshold * 100).toInt()}%',
                          activeColor: const Color(0xFFFACC15),
                          onChanged: (val) {
                            setState(() {
                              det.confidenceThreshold = val;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Hiệu chuẩn Góc nghiêng & Chiều cao đeo (NV6)
            _buildSection(
              title: 'Hiệu chuẩn Góc nghiêng & Khoảng cách (NV6)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Góc nghiêng ngực: ${(pipeline?.tiltService?.effectiveTiltDeg ?? 0.0).toStringAsFixed(1)}°',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                        icon: const Icon(Icons.screen_rotation, size: 16),
                        label: const Text('Hiệu chuẩn góc 0°'),
                        onPressed: () {
                          pipeline?.tiltService?.calibrateNeutral();
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Đã hiệu chuẩn góc đeo ngực hiện tại làm mốc 0°!')),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        'Chiều cao đeo: ${kDefaultMountHeightMeters.toStringAsFixed(2)}m',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      Expanded(
                        child: Slider(
                          value: kDefaultMountHeightMeters,
                          min: 1.10,
                          max: 1.85,
                          divisions: 15,
                          label: '${kDefaultMountHeightMeters.toStringAsFixed(2)}m',
                          activeColor: const Color(0xFF38BDF8),
                          onChanged: (val) {
                            setState(() {
                              kDefaultMountHeightMeters = val;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        'Ngưỡng Nguy cấp: ${kCriticalBottomY.toStringAsFixed(2)}',
                        style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
                      ),
                      Expanded(
                        child: Slider(
                          value: kCriticalBottomY,
                          min: 0.70,
                          max: 0.95,
                          divisions: 25,
                          label: kCriticalBottomY.toStringAsFixed(2),
                          activeColor: const Color(0xFFEF4444),
                          onChanged: (val) {
                            setState(() {
                              kCriticalBottomY = val;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Hiệu chuẩn Năng lượng & Quá nhiệt thực tế (NV9)
            _buildSection(
              title: 'Điều tiết Năng lượng & Nhiệt độ thực tế (NV9)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trạng thái pin: ${pipeline?.batteryOptimizer.batteryLevel ?? 100}% | Nhiệt độ: ${pipeline?.healthService?.thermalStatusText ?? "Bình thường"}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Mô phỏng mức Pin để kiểm tra điều tiết FPS (< 20% -> 10 FPS):',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  Row(
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                        onPressed: () {
                          pipeline?.healthService?.setMockHealth(batteryLevel: 15);
                          pipeline?.batteryOptimizer.updateBatteryAndThermal(
                            batteryLevel: 15,
                            thermalStatus: pipeline.batteryOptimizer.thermalStatus,
                          );
                          setState(() {});
                        },
                        child: const Text('Pin 15% (Yếu)'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                        onPressed: () {
                          pipeline?.healthService?.setMockHealth(batteryLevel: 85);
                          pipeline?.batteryOptimizer.updateBatteryAndThermal(
                            batteryLevel: 85,
                            thermalStatus: pipeline.batteryOptimizer.thermalStatus,
                          );
                          setState(() {});
                        },
                        child: const Text('Pin 85% (Bình thường)'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Mô phỏng Quá nhiệt để kiểm tra Throttling (Severe >= 3 -> 8 FPS + Cảnh báo):',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  Row(
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                        onPressed: () {
                          pipeline?.healthService?.setMockHealth(thermalStatus: 3);
                          pipeline?.batteryOptimizer.updateBatteryAndThermal(
                            batteryLevel: pipeline.batteryOptimizer.batteryLevel,
                            thermalStatus: 3,
                          );
                          setState(() {});
                          if (pipeline?.batteryOptimizer.shouldAnnounceThermalWarning(DateTime.now().millisecondsSinceEpoch) == true) {
                            widget.audio.speakVietnamese('Thiết bị quá nhiệt, giảm tốc độ xử lý', force: true, priority: 250);
                          }
                        },
                        child: const Text('Quá nhiệt (Severe 3)'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                        onPressed: () {
                          pipeline?.healthService?.setMockHealth(thermalStatus: 0);
                          pipeline?.batteryOptimizer.updateBatteryAndThermal(
                            batteryLevel: pipeline.batteryOptimizer.batteryLevel,
                            thermalStatus: 0,
                          );
                          setState(() {});
                        },
                        child: const Text('Mát mẻ (None 0)'),
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
                  const SizedBox(height: 8),
                  const Text(
                    'Tải tuyến đi bộ OpenStreetMap (OSRM Foot Profile - NV11):',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đang tải tuyến đi bộ OSRM: Hồ Gươm -> Nhà Hát Lớn...')),
                            );
                            final ok = await widget.navService.startNavigationToDestination(
                              destLat: NavigationService.hanoiDestLat,
                              destLng: NavigationService.hanoiDestLng,
                              destName: 'Nhà Hát Lớn Hà Nội',
                              fallbackStartLat: NavigationService.hanoiStartLat,
                              fallbackStartLng: NavigationService.hanoiStartLng,
                            );
                            setState(() {});
                            if (ok && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Đã nạp ${widget.navService.activeRoute.length} mốc OSRM Hà Nội!')),
                              );
                            }
                          },
                          child: const Text('OSRM Hà Nội', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đang tải tuyến đi bộ OSRM: Nguyễn Huệ -> Bến Thành...')),
                            );
                            final ok = await widget.navService.startNavigationToDestination(
                              destLat: NavigationService.hcmcDestLat,
                              destLng: NavigationService.hcmcDestLng,
                              destName: 'Chợ Bến Thành',
                              fallbackStartLat: NavigationService.hcmcStartLat,
                              fallbackStartLng: NavigationService.hcmcStartLng,
                            );
                            setState(() {});
                            if (ok && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Đã nạp ${widget.navService.activeRoute.length} mốc OSRM TP.HCM!')),
                              );
                            }
                          },
                          child: const Text('OSRM TP.HCM', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Thử nghiệm & Kiểm tra âm thanh Stereo Pan (NV8 - Lỗi 7)
            _buildSection(
              title: 'Kiểm tra Tai nghe & Âm thanh Định hướng (NV8)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Đảo kênh L/R (khi đeo ngược tai):',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      Switch(
                        value: widget.audio.isChannelsSwapped,
                        activeColor: const Color(0xFF38BDF8),
                        onChanged: (val) {
                          setState(() {
                            widget.audio.isChannelsSwapped = val;
                          });
                        },
                      ),
                    ],
                  ),
                  if (widget.audio.lastPlayedAsset.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'File âm thanh vừa phát: ${widget.audio.lastPlayedAsset}',
                        style: const TextStyle(color: Color(0xFFFACC15), fontSize: 11),
                      ),
                    ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      minimumSize: const Size.fromHeight(40),
                    ),
                    icon: const Icon(Icons.headphones, size: 18),
                    label: const Text('Quy trình Kiểm tra Tai nghe (L -> Center -> R)'),
                    onPressed: () {
                      widget.audio.runEarphoneCheckSequence();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Đang phát chu kỳ kiểm tra tai nghe Trái/Giữa/Phải...')),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            widget.audio.playDirectionalBeep(
                              pan: -1.0,
                              pitch: 500,
                              direction: DirectionZone.left,
                            );
                            setState(() {});
                          },
                          child: const Text('Trái (500Hz)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            widget.audio.playDirectionalBeep(
                              pan: 0.0,
                              pitch: 750,
                              direction: DirectionZone.center,
                            );
                            setState(() {});
                          },
                          child: const Text('Giữa (750Hz)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            widget.audio.playDirectionalBeep(
                              pan: 1.0,
                              pitch: 1000,
                              direction: DirectionZone.right,
                            );
                            setState(() {});
                          },
                          child: const Text('Phải (1000Hz)'),
                        ),
                      ),
                    ],
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

  Widget _buildLatencyRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isTotal ? const Color(0xFFFACC15) : Colors.white70,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isTotal ? const Color(0xFF22C55E) : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
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

/// Vẽ 3 hành lang di chuyển (Trái 35% | Giữa 30% | Phải 35%)
class CorridorOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(size.width * 0.35, 0), Offset(size.width * 0.35, size.height), paint);
    canvas.drawLine(Offset(size.width * 0.65, 0), Offset(size.width * 0.65, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Vẽ các hộp Bounding Box và tên vật thể lên khung Camera
class BoundingBoxPainter extends CustomPainter {
  final List<DetectionResult> detections;

  BoundingBoxPainter({required this.detections});

  @override
  void paint(Canvas canvas, Size size) {
    for (final det in detections) {
      final bbox = det.bbox;
      // bbox tọa độ trên khung chuẩn 300x300, scale sang kích thước size thực tế của container
      final double scaleX = size.width / 300.0;
      final double scaleY = size.height / 300.0;

      final double x = bbox[0] * scaleX;
      final double y = bbox[1] * scaleY;
      final double w = bbox[2] * scaleX;
      final double h = bbox[3] * scaleY;

      Color boxColor = const Color(0xFF38BDF8); // Mặc định xanh dương
      if (det.distanceLevel == DistanceLevel.critical) {
        boxColor = const Color(0xFFEF4444); // Đỏ nguy cấp
      } else if (det.distanceLevel == DistanceLevel.near) {
        boxColor = const Color(0xFFF59E0B); // Vàng/cam gần
      }

      final boxPaint = Paint()
        ..color = boxColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;

      final rect = Rect.fromLTWH(x, y, w, h);
      canvas.drawRect(rect, boxPaint);

      // Nhãn chữ
      final textSpan = TextSpan(
        text: '${det.vietnameseLabel} (${(det.score * 100).toInt()}%)',
        style: TextStyle(
          color: Colors.white,
          backgroundColor: boxColor.withOpacity(0.85),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, Offset(x, (y - 14).clamp(0, size.height - 14)));
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) => true;
}
