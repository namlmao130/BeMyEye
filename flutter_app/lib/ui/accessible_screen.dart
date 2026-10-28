import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/alert_decision_engine.dart';
import '../services/audio_haptics_service.dart';
import '../services/camera_pipeline_service.dart';
import '../services/detector_service.dart';
import '../services/navigation_service.dart';
import 'developer_hud_screen.dart';
import 'widgets/safety_disclaimer_dialog.dart';

/// Readiness follows successful camera inference, never just a start request.
class AccessibleScreen extends StatefulWidget {
  final AudioHapticsService audio;
  final AlertDecisionEngine alertEngine;
  final NavigationService navService;
  final DetectorService detectorService;
  final CameraPipelineService? pipelineService;
  final bool isAppActive;
  final bool isTransitioning;
  final VoidCallback onToggleApp;
  final VoidCallback? onRetryModel;

  static const channelsSwappedPreference = 'bemyeye_channels_swapped';

  const AccessibleScreen({
    super.key,
    required this.audio,
    required this.alertEngine,
    required this.navService,
    required this.detectorService,
    this.pipelineService,
    required this.isAppActive,
    required this.onToggleApp,
    this.isTransitioning = false,
    this.onRetryModel,
  });

  @override
  State<AccessibleScreen> createState() => _AccessibleScreenState();
}

class _AccessibleScreenState extends State<AccessibleScreen> {
  static const _yellow = Color(0xFFFACC15);
  static const _muted = Color(0xFFCACACA);
  bool _termsAccepted = false;
  bool _checkingEarphones = false;
  bool _savingChannels = false;
  String? _earphoneMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_prepare()));
  }

  Future<void> _prepare() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      widget.audio.isChannelsSwapped =
          prefs.getBool(AccessibleScreen.channelsSwappedPreference) ?? false;
    } catch (error) {
      debugPrint('Không đọc được cài đặt tai nghe: $error');
    }
    if (!mounted) return;
    final accepted = await SafetyDisclaimerDialog.checkAndShow(
      context,
      widget.audio,
    );
    if (mounted) setState(() => _termsAccepted = accepted);
  }

  Future<void> _checkEarphones() async {
    if (_checkingEarphones || widget.isAppActive || widget.isTransitioning)
      return;
    setState(() {
      _checkingEarphones = true;
      _earphoneMessage = 'Đang kiểm tra tai nghe…';
    });
    try {
      await widget.audio.runEarphoneCheckSequence(
        onStepChange: (step) {
          if (!mounted) return;
          setState(() {
            _earphoneMessage = switch (step) {
              'left' => 'Âm kiểm tra: bên trái',
              'center' => 'Âm kiểm tra: ở giữa',
              'right' => 'Âm kiểm tra: bên phải',
              _ =>
                'Đã phát xong. Nếu nghe ngược bên, bật đảo kênh rồi thử lại.',
            };
          });
        },
      );
    } catch (error) {
      debugPrint('Không hoàn tất kiểm tra tai nghe: $error');
      if (mounted) {
        setState(() {
          _earphoneMessage =
              'Chưa hoàn tất kiểm tra. Hãy kiểm tra âm lượng và kết nối tai nghe.';
        });
      }
    } finally {
      if (mounted) setState(() => _checkingEarphones = false);
    }
  }

  Future<void> _setChannelsSwapped(bool swapped) async {
    setState(() => _savingChannels = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setBool(
        AccessibleScreen.channelsSwappedPreference,
        swapped,
      );
      if (!saved) throw StateError('Không lưu được tùy chọn đảo kênh');
      if (!mounted) return;
      setState(() {
        widget.audio.isChannelsSwapped = swapped;
        _earphoneMessage = 'Đã lưu cài đặt. Hãy kiểm tra lại trái, giữa, phải.';
      });
    } catch (error) {
      debugPrint('Không lưu được cài đặt tai nghe: $error');
      if (mounted) {
        setState(
          () => _earphoneMessage = 'Chưa lưu được cài đặt. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _savingChannels = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasModelError = widget.detectorService.loadError != null;
    final loadingModel = !widget.detectorService.isReady && !hasModelError;
    final status = widget.pipelineService?.status;
    final failed = status == PipelineStatus.failed;
    final running = widget.isAppActive && status == PipelineStatus.running;
    final starting = !failed && widget.isAppActive && !running;
    final canConfigure = _termsAccepted &&
        !widget.isAppActive &&
        !widget.isTransitioning &&
        !_checkingEarphones &&
        !_savingChannels;
    final canToggle = _termsAccepted &&
        !widget.isTransitioning &&
        !_checkingEarphones &&
        !_savingChannels &&
        (widget.isAppActive || widget.detectorService.isReady);

    final String statusTitle;
    final String statusDescription;
    final IconData statusIcon;
    final Color statusColor;
    if (hasModelError) {
      statusTitle = 'LỖI MÔ HÌNH';
      statusDescription =
          'Không tải được bộ nhận diện. Đừng dùng ứng dụng để dẫn đường. Bạn có thể thử tải lại.';
      statusIcon = Icons.error_outline;
      statusColor = const Color(0xFFFCA5A5);
    } else if (loadingModel) {
      statusTitle = 'ĐANG TẢI NHẬN DIỆN';
      statusDescription =
          'Vui lòng chờ. Camera chưa quan sát và chưa phát cảnh báo.';
      statusIcon = Icons.hourglass_top_rounded;
      statusColor = _yellow;
    } else if (failed) {
      statusTitle = 'ĐÃ DỪNG DO LỖI CAMERA';
      statusDescription =
          'Ứng dụng không còn quan sát. Hãy dừng ở vị trí phù hợp và kiểm tra quyền camera trước khi thử lại.';
      statusIcon = Icons.videocam_off_outlined;
      statusColor = const Color(0xFFFCA5A5);
    } else if (starting) {
      statusTitle = 'ĐANG MỞ CAMERA';
      statusDescription =
          'Đang chờ khung hình nhận diện đầu tiên. Chưa có cảnh báo vật cản.';
      statusIcon = Icons.hourglass_top_rounded;
      statusColor = _yellow;
    } else if (running) {
      statusTitle = 'ĐANG QUAN SÁT';
      statusDescription =
          'Cảnh báo âm thanh và rung đang bật. Im lặng không có nghĩa là không có vật cản.';
      statusIcon = Icons.visibility_outlined;
      statusColor = const Color(0xFF86EFAC);
    } else {
      statusTitle = 'ĐÃ TẠM DỪNG';
      statusDescription =
          'Camera chưa quan sát. Chạm Bắt đầu để mở trợ lý nhận diện vật cản.';
      statusIcon = Icons.pause_circle_outline_rounded;
      statusColor = _muted;
    }
    final actionLabel = widget.isAppActive
        ? 'DỪNG LẠI'
        : hasModelError
            ? 'KHÓA DẪN ĐƯỜNG'
            : loadingModel
                ? 'ĐANG TẢI…'
                : failed
                    ? 'THỬ LẠI CAMERA'
                    : 'BẮT ĐẦU';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: const Text(
                      'Be My Eye',
                      style: TextStyle(
                        color: _yellow,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Trợ lý nhận diện vật cản',
                    style: TextStyle(color: _muted, fontSize: 18),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    key: const Key('assistant-status'),
                    liveRegion: true,
                    label: '$statusTitle. $statusDescription',
                    excludeSemantics: true,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171717),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor, width: 2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(statusIcon, color: statusColor, size: 32),
                          const SizedBox(height: 12),
                          Text(
                            statusTitle,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            statusDescription,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    button: true,
                    enabled: canToggle,
                    excludeSemantics: true,
                    label: actionLabel,
                    hint: widget.isAppActive
                        ? 'Dừng camera và cảnh báo vật cản'
                        : 'Mở camera để nhận diện vật cản phía trước',
                    onTap: canToggle ? widget.onToggleApp : null,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 220),
                      child: ElevatedButton(
                        key: const Key('primary-action'),
                        onPressed: canToggle ? widget.onToggleApp : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.isAppActive
                              ? const Color(0xFF991B1B)
                              : _yellow,
                          foregroundColor:
                              widget.isAppActive ? Colors.white : Colors.black,
                          disabledBackgroundColor: const Color(0xFF262626),
                          disabledForegroundColor: _muted,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 32,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                            side: BorderSide(
                              color:
                                  canToggle ? _yellow : const Color(0xFF737373),
                              width: 4,
                            ),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.isAppActive
                                  ? Icons.stop_rounded
                                  : failed
                                      ? Icons.refresh_rounded
                                      : Icons.play_arrow_rounded,
                              size: 56,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              actionLabel,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (hasModelError && widget.onRetryModel != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: canConfigure ? widget.onRetryModel : null,
                      style: _secondaryButtonStyle,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Thử tải lại nhận diện'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Luôn dùng gậy trắng. Giữ tai nghe được âm thanh xung quanh.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, fontSize: 16, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  Semantics(
                    header: true,
                    child: const Text(
                      'Trước khi di chuyển',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('earphone-check'),
                    onPressed: canConfigure ? _checkEarphones : null,
                    style: _secondaryButtonStyle,
                    icon: const Icon(Icons.headphones_outlined),
                    label: Text(
                      _checkingEarphones
                          ? 'Đang kiểm tra tai nghe…'
                          : 'Kiểm tra tai nghe trái / phải',
                    ),
                  ),
                  if (widget.isAppActive)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Dừng trợ lý trước khi kiểm tra hoặc đổi kênh tai nghe.',
                        style: TextStyle(color: _muted, fontSize: 16),
                      ),
                    ),
                  if (_earphoneMessage != null)
                    Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _earphoneMessage!,
                          style: const TextStyle(
                            color: _yellow,
                            fontSize: 16,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  SwitchListTile.adaptive(
                    key: const Key('swap-channels'),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    title: const Text(
                      'Đảo kênh trái / phải',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    subtitle: const Text(
                      'Bật nếu âm bên trái phát ở tai phải.',
                      style: TextStyle(color: _muted, fontSize: 16),
                    ),
                    value: widget.audio.isChannelsSwapped,
                    onChanged: canConfigure ? _setChannelsSwapped : null,
                    activeThumbColor: _yellow,
                  ),
                  const Divider(color: Color(0xFF404040), height: 32),
                  TextButton.icon(
                    key: const Key('safety-terms'),
                    onPressed: canConfigure
                        ? () => SafetyDisclaimerDialog.checkAndShow(
                              context,
                              widget.audio,
                              forceShow: true,
                            )
                        : null,
                    style: _secondaryButtonStyle,
                    icon: const Icon(Icons.info_outline_rounded),
                    label: const Text('An toàn & giới hạn nhận diện'),
                  ),
                  TextButton.icon(
                    onPressed: _termsAccepted &&
                            !_checkingEarphones &&
                            !_savingChannels
                        ? () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => DeveloperHUDScreen(
                                  audio: widget.audio,
                                  alertEngine: widget.alertEngine,
                                  navService: widget.navService,
                                  detectorService: widget.detectorService,
                                  pipelineService: widget.pipelineService,
                                ),
                              ),
                            )
                        : null,
                    style: _secondaryButtonStyle.copyWith(
                      foregroundColor: const WidgetStatePropertyAll(_muted),
                    ),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Thông số kỹ thuật & đo đạc'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  ButtonStyle get _secondaryButtonStyle => OutlinedButton.styleFrom(
        foregroundColor: _yellow,
        disabledForegroundColor: const Color(0xFF888888),
        minimumSize: const Size.fromHeight(64),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        side: const BorderSide(color: Color(0xFF737373)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );
}
