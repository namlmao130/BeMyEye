/**
 * app.js
 * Tệp điều phối trung tâm (Main Orchestrator) - Giai đoạn 2
 * Hợp nhất: 2D Object Detection + Generic Depth Analyzer (Tầm đầu/ngực) + Ground Plane Analyzer (Bậc thềm/Lề đường)
 */

document.addEventListener('DOMContentLoaded', async () => {
  // DOM Elements
  const video = document.getElementById('camera-feed');
  const canvas = document.getElementById('debug-canvas');
  const btnToggleApp = document.getElementById('btn-toggle-app');
  const btnToggleAppDebug = document.getElementById('btn-toggle-app-debug');
  const btnToggleDebugMode = document.getElementById('btn-toggle-debug');
  const btnToggleDebugClose = document.getElementById('btn-toggle-debug-close');
  const statusBanner = document.getElementById('status-banner');
  const debugPanel = document.getElementById('debug-panel');
  const accessibleView = document.getElementById('accessible-view');

  // Debug HUD Elements
  const fpsDisplay = document.getElementById('fps-val');
  const latencyDisplay = document.getElementById('latency-val');
  const threatDisplay = document.getElementById('threat-val');
  const directionDisplay = document.getElementById('direction-val');
  const videoFileInput = document.getElementById('video-file-input');
  const btnUseCamera = document.getElementById('btn-use-camera');
  const confSlider = document.getElementById('conf-slider');
  const confValue = document.getElementById('conf-value');

  // Phase 2 Toggles
  const toggleHighPerf = document.getElementById('toggle-high-perf');
  const toggleGroundAnalysis = document.getElementById('toggle-ground-analysis');
  const toggleDepthAnalysis = document.getElementById('toggle-depth-analysis');

  // Metrics & Companion buttons
  const btnRecordMetrics = document.getElementById('btn-record-metrics');
  const btnMarkGood = document.getElementById('btn-mark-good');
  const btnMarkMiss = document.getElementById('btn-mark-miss');
  const btnMarkFalse = document.getElementById('btn-mark-false');
  const recordingStatus = document.getElementById('recording-status');

  // Khởi tạo các module
  const audioHaptics = new AudioHapticsEngine();
  const spatialAnalyzer = new SpatialAnalyzer();
  const alertEngine = new AlertDecisionEngine(audioHaptics);
  const metricsLogger = new MetricsLogger();
  const cameraManager = new CameraManager(video, canvas);
  const detector = new ObjectDetector();
  const groundAnalyzer = new GroundPlaneAnalyzer();
  const genericDepthAnalyzer = new GenericDepthAnalyzer();
  const navEngine = new NavigationEngine(audioHaptics, alertEngine);
  const batteryOptimizer = new BatteryThermalOptimizer();

  let isAppActive = false;
  let animationFrameId = null;
  let isDebugViewVisible = false;
  let enableGround = true;
  let enableDepth = true;

  // Hàng đợi xử lý bất đồng bộ (Decoupled Multi-rate Pipeline) để đạt 30-60 FPS
  let isDetecting = false;
  let cachedRawDetections = [];
  let cachedGenericObstacles = [];
  let cachedGroundHazards = [];
  let loopFrameCount = 0;

  // 1. Tải trước mô hình AI
  statusBanner.textContent = 'Đang nạp mô hình AI... Vui lòng đợi';
  try {
    await detector.loadModel((msg) => {
      statusBanner.textContent = msg;
    });
    statusBanner.textContent = 'Hệ thống đã sẵn sàng. Chạm để bắt đầu.';
  } catch (err) {
    statusBanner.textContent = 'Lỗi nạp mô hình AI: ' + err.message;
    console.error(err);
  }

  // 2. Chuyển đổi trạng thái Bật / Dừng ứng dụng
  async function toggleApp() {
    if (isAppActive) {
      stopApp();
    } else {
      await startApp();
    }
  }

  async function startApp() {
    audioHaptics.resumeContextIfNeeded();
    statusBanner.textContent = 'Đang khởi động Camera...';

    try {
      if (!cameraManager.isRunning) {
        await cameraManager.startCamera();
      }

      isAppActive = true;
      updateUIState(true);
      audioHaptics.speakVietnamese('Đã bật trợ lý dẫn đường', true);
      processFrameLoop();
    } catch (err) {
      statusBanner.textContent = 'Lỗi mở Camera. Đảm bảo dùng HTTPS hoặc localhost: ' + err.message;
      alert('Không thể mở Camera!\nLưu ý: Trình duyệt điện thoại chỉ cho phép dùng camera qua link HTTPS.');
      updateUIState(false);
    }
  }

  function stopApp() {
    isAppActive = false;
    if (animationFrameId) {
      cancelAnimationFrame(animationFrameId);
      animationFrameId = null;
    }
    cameraManager.stop();
    updateUIState(false);
    audioHaptics.speakVietnamese('Đã tạm dừng', true);
    statusBanner.textContent = 'Đã dừng. Chạm để bật lại.';
  }

  function updateUIState(active) {
    if (active) {
      btnToggleApp.textContent = 'DỪNG LẠI';
      btnToggleApp.classList.add('active');
      btnToggleApp.setAttribute('aria-label', 'Dừng dẫn đường thời gian thực');
      if (btnToggleAppDebug) {
        btnToggleAppDebug.textContent = 'Dừng camera';
        btnToggleAppDebug.classList.add('btn-danger');
      }
    } else {
      btnToggleApp.textContent = 'BẮT ĐẦU DẪN ĐƯỜNG';
      btnToggleApp.classList.remove('active');
      btnToggleApp.setAttribute('aria-label', 'Bắt đầu dẫn đường thời gian thực');
      if (btnToggleAppDebug) {
        btnToggleAppDebug.textContent = 'Bật camera';
        btnToggleAppDebug.classList.remove('btn-danger');
      }
    }
  }

  btnToggleApp.addEventListener('click', toggleApp);
  if (btnToggleAppDebug) {
    btnToggleAppDebug.addEventListener('click', toggleApp);
  }

  // 3. Vòng lặp suy luận thời gian thực SIÊU MƯỢT (Decoupled Async Pipeline - 30+ FPS)
  async function processFrameLoop() {
    if (!isAppActive) return;

    metricsLogger.tickFrame();
    const frameStartTime = performance.now();

    // Điều tiết FPS nếu bật chế độ tiết kiệm pin
    if (!batteryOptimizer.shouldProcessFrame(frameStartTime)) {
      animationFrameId = requestAnimationFrame(processFrameLoop);
      return;
    }

    if (navEngine.currentPosition) {
      batteryOptimizer.updateMovementState(navEngine.currentPosition.speed || 0);
    }

    if (video.readyState >= 2) {
      const frameWidth = canvas.width || video.videoWidth;
      const frameHeight = canvas.height || video.videoHeight;
      loopFrameCount++;

      // BƯỚC 1: SUY LUẬN AI BẤT ĐỒNG BỘ (Không bao giờ block Render Loop của trình duyệt)
      if (!isDetecting) {
        isDetecting = true;
        const inferStart = performance.now();
        detector.detect(video).then(raw => {
          cachedRawDetections = raw;
          isDetecting = false;
          const latencyMs = performance.now() - inferStart;
          metricsLogger.updateLatency(latencyMs);
        }).catch(() => {
          isDetecting = false;
        });
      }

      // BƯỚC 2: XOAY VÒNG PHÂN TÍCH MẶT ĐẤT & ĐỘ SÂU (Interleaved: 1 module / frame)
      // Giảm 60% tải getImageData() trên GPU
      if (loopFrameCount % 2 === 0) {
        if (enableGround) {
          const groundResult = groundAnalyzer.analyze(video);
          cachedGroundHazards = groundResult.hazards || [];
        }
      } else {
        if (enableDepth) {
          cachedGenericObstacles = genericDepthAnalyzer.detectGenericObstacles(video, cachedRawDetections);
        }
      }

      // BƯỚC 3: PHÂN TÍCH KHÔNG GIAN DỰA TRÊN DỮ LIỆU ĐÃ CACHE
      const analyzed2D = spatialAnalyzer.analyzeDetections(cachedRawDetections, frameWidth, frameHeight);

      // BƯỚC 4: BỘ QUYẾT ĐỊNH CẢNH BÁO
      const primaryThreat = alertEngine.process(analyzed2D, cachedGenericObstacles, cachedGroundHazards);
      metricsLogger.recordDetections(analyzed2D);

      // BƯỚC 5: VẼ TRỰC QUAN HÓA & HUD (Chạy mượt 30-60 FPS)
      if (isDebugViewVisible) {
        drawDebugCanvas(analyzed2D, cachedGenericObstacles, cachedGroundHazards, primaryThreat, frameWidth, frameHeight);
        updateDebugHUD(primaryThreat);
      }
    }

    animationFrameId = requestAnimationFrame(processFrameLoop);
  }

  // 4. Vẽ trực quan hóa trên Canvas Debug
  function drawDebugCanvas(objects2D, genericObstacles, groundHazards, primaryThreat, width, height) {
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, width, height);

    // 1. Vẽ 2 vạch phân chia 3 hành lang Trái - Giữa - Phải
    const leftX = width * spatialAnalyzer.LEFT_BOUNDARY;
    const rightX = width * spatialAnalyzer.RIGHT_BOUNDARY;

    ctx.strokeStyle = 'rgba(255, 255, 255, 0.35)';
    ctx.lineWidth = 2;
    ctx.setLineDash([6, 6]);

    ctx.beginPath();
    ctx.moveTo(leftX, 0);
    ctx.lineTo(leftX, height);
    ctx.stroke();

    ctx.beginPath();
    ctx.moveTo(rightX, 0);
    ctx.lineTo(rightX, height);
    ctx.stroke();
    ctx.setLineDash([]);

    // 2. Vẽ vùng quét chướng ngại vật tầm đầu / ngực (Head Frustum Box)
    const headTop = height * genericDepthAnalyzer.HEAD_CORRIDOR_TOP;
    const headBottom = height * genericDepthAnalyzer.HEAD_CORRIDOR_BOTTOM;

    ctx.strokeStyle = 'rgba(234, 179, 8, 0.4)';
    ctx.lineWidth = 1;
    ctx.setLineDash([3, 3]);
    ctx.strokeRect(width * 0.1, headTop, width * 0.8, headBottom - headTop);
    ctx.setLineDash([]);
    ctx.font = '10px sans-serif';
    ctx.fillStyle = 'rgba(234, 179, 8, 0.7)';
    ctx.fillText('HÀNH LANG TẦM ĐẦU / NGỰC (HEAD CLEARANCE)', width * 0.12, headTop + 14);

    // 3. Vẽ các Bậc thềm / Mép lề đường phát hiện được (Ground Hazards)
    for (const gh of groundHazards) {
      const lineY = height * gh.normalizedY;
      const isNegative = gh.isNegativeObstacle;
      const strokeColor = isNegative ? '#ec4899' : '#06b6d4'; // Hồng cánh sen: Bậc xuống; Xanh Cyan: Bậc lên

      ctx.strokeStyle = strokeColor;
      ctx.lineWidth = 4;
      ctx.beginPath();
      ctx.moveTo(width * 0.15, lineY);
      ctx.lineTo(width * 0.85, lineY);
      ctx.stroke();

      const label = `${gh.vietnameseName} | ${gh.distanceMeters}`;
      ctx.fillStyle = strokeColor;
      ctx.fillRect(width * 0.15, lineY - 18, ctx.measureText(label).width + 8, 18);
      ctx.fillStyle = '#000';
      ctx.font = 'bold 11px sans-serif';
      ctx.fillText(label, width * 0.15 + 4, lineY - 4);
    }

    // 4. Vẽ chướng ngại vật tầm đầu phát hiện được (Generic Obstacles)
    for (const go of genericObstacles) {
      const [nx, ny, nw, nh] = go.bbox;
      const gx = nx * width;
      const gy = ny * height;
      const gw = nw * width;
      const gh = nh * height;

      ctx.fillStyle = 'rgba(239, 68, 68, 0.25)';
      ctx.fillRect(gx, gy, gw, gh);
      ctx.strokeStyle = '#ef4444';
      ctx.lineWidth = 3;
      ctx.strokeRect(gx, gy, gw, gh);

      const label = `⚠️ ${go.vietnameseClass} (${go.direction.toUpperCase()}) | ${go.approximateDistanceMeters}`;
      ctx.fillStyle = '#ef4444';
      ctx.fillRect(gx, gy - 20, ctx.measureText(label).width + 8, 20);
      ctx.fillStyle = '#fff';
      ctx.font = 'bold 11px sans-serif';
      ctx.fillText(label, gx + 4, gy - 5);
    }

    // 5. Vẽ Bounding Box các vật thể 2D COCO
    for (const obj of objects2D) {
      const [x, y, w, h] = obj.bbox;
      const isTopThreat = (primaryThreat && primaryThreat.id === obj.id);

      let color = '#22c55e'; // Xanh lá: Xa
      if (obj.distanceLevel === 'critical' || obj.isApproaching) {
        color = '#ef4444'; // Đỏ: Rất gần hoặc đang lao tới
      } else if (obj.distanceLevel === 'near') {
        color = '#f59e0b'; // Vàng cam: Gần
      }

      ctx.strokeStyle = color;
      ctx.lineWidth = isTopThreat ? 4 : 2;
      ctx.strokeRect(x, y, w, h);

      const label = `${obj.vietnameseClass} ${Math.round(obj.score * 100)}% | ${obj.approximateDistanceMeters}${obj.isApproaching ? ' [ĐANG TỚI!]' : ''}`;
      ctx.fillStyle = color;
      ctx.fillRect(x, Math.max(0, y - 22), ctx.measureText(label).width + 10, 22);

      ctx.fillStyle = '#000000';
      ctx.font = 'bold 12px sans-serif';
      ctx.fillText(label, x + 5, Math.max(16, y - 6));
    }
  }

  // 5. Cập nhật bảng thông số HUD
  function updateDebugHUD(threat) {
    fpsDisplay.textContent = metricsLogger.fps;
    latencyDisplay.textContent = metricsLogger.latency + ' ms';

    if (threat) {
      threatDisplay.textContent = `${threat.vietnameseClass} (${threat.distanceLevel})`;
      threatDisplay.className = 'val ' + threat.distanceLevel;
      directionDisplay.textContent = threat.direction ? threat.direction.toUpperCase() : 'GIỮA';
    } else {
      threatDisplay.textContent = 'Không có vật cản';
      threatDisplay.className = 'val safe';
      directionDisplay.textContent = '--';
    }
  }

  // 6. Chuyển đổi giữa chế độ Người dùng & Chế độ Debug
  function setDebugView(show) {
    isDebugViewVisible = show;
    if (show) {
      debugPanel.style.display = 'block';
      accessibleView.style.display = 'none';
      btnToggleDebugMode.style.display = 'none';
    } else {
      debugPanel.style.display = 'none';
      accessibleView.style.display = 'flex';
      btnToggleDebugMode.style.display = 'block';
    }
  }

  btnToggleDebugMode.addEventListener('click', () => setDebugView(true));
  btnToggleDebugClose.addEventListener('click', () => setDebugView(false));

  // Toggles Hiệu Năng & Giai đoạn 2
  if (toggleHighPerf) {
    toggleHighPerf.addEventListener('change', (e) => {
      batteryOptimizer.setHighPerformance(e.target.checked);
    });
  }
  if (toggleGroundAnalysis) {
    toggleGroundAnalysis.addEventListener('change', (e) => {
      enableGround = e.target.checked;
    });
  }
  if (toggleDepthAnalysis) {
    toggleDepthAnalysis.addEventListener('change', (e) => {
      enableDepth = e.target.checked;
    });
  }

  // 7. Video kiểm thử & Camera
  videoFileInput.addEventListener('change', async (e) => {
    const file = e.target.files[0];
    if (file) {
      statusBanner.textContent = 'Đang phát video thử nghiệm: ' + file.name;
      await cameraManager.loadTestVideo(file);
      if (!isAppActive) {
        isAppActive = true;
        updateUIState(true);
        processFrameLoop();
      }
    }
  });

  btnUseCamera.addEventListener('click', async () => {
    statusBanner.textContent = 'Đang chuyển sang Camera sau...';
    await cameraManager.startCamera();
  });

  confSlider.addEventListener('input', (e) => {
    const val = parseFloat(e.target.value);
    confValue.textContent = Math.round(val * 100) + '%';
    detector.setConfidenceThreshold(val);
  });

  // 8. Đo đạc định lượng (Benchmarking)
  btnRecordMetrics.addEventListener('click', () => {
    if (!metricsLogger.isRecording) {
      metricsLogger.startRecording();
      btnRecordMetrics.textContent = 'Dừng & Xuất JSON Báo Cáo';
      btnRecordMetrics.classList.add('recording');
      recordingStatus.textContent = 'Đang ghi nhận số liệu từng frame...';
    } else {
      const report = metricsLogger.stopRecording();
      btnRecordMetrics.textContent = 'Bắt đầu ghi số liệu (Benchmarking)';
      btnRecordMetrics.classList.remove('recording');
      recordingStatus.textContent = `Đã lưu ${report.totalFrames} frames. Tải file JSON...`;

      const dataStr = 'data:text/json;charset=utf-8,' + encodeURIComponent(JSON.stringify(report, null, 2));
      const downloadAnchor = document.createElement('a');
      downloadAnchor.setAttribute('href', dataStr);
      downloadAnchor.setAttribute('download', `bemyeye_metrics_phase2_${Date.now()}.json`);
      document.body.appendChild(downloadAnchor);
      downloadAnchor.click();
      downloadAnchor.remove();
    }
  });

  if (btnMarkGood) {
    btnMarkGood.addEventListener('click', () => {
      const count = metricsLogger.markGoodAlert();
      btnMarkGood.textContent = `Cảnh báo tốt (${count})`;
    });
  }

  btnMarkMiss.addEventListener('click', () => {
    const count = metricsLogger.markMissedObstacle();
    btnMarkMiss.textContent = `Bỏ sót vật cản (${count})`;
  });

  btnMarkFalse.addEventListener('click', () => {
    const count = metricsLogger.markFalseAlarm();
    btnMarkFalse.textContent = `Báo nhầm (${count})`;
  });

  // Nút thử nghiệm âm thanh Stereo
  document.getElementById('btn-test-sound-left').addEventListener('click', () => {
    audioHaptics.playDirectionalBeep(-0.85, 600, 80);
  });
  document.getElementById('btn-test-sound-center').addEventListener('click', () => {
    audioHaptics.playDirectionalBeep(0.0, 750, 80);
  });
  document.getElementById('btn-test-sound-right').addEventListener('click', () => {
    audioHaptics.playDirectionalBeep(0.85, 900, 80);
  });

  // ====================================================
  // ĐIỀU KHIỂN DẪN ĐƯỜNG GPS & LA BÀN (GIAI ĐOẠN 4)
  // ====================================================
  const btnStartNavGPS = document.getElementById('btn-start-nav-gps');
  const btnStartNavSim = document.getElementById('btn-start-nav-sim');
  const btnStopNav = document.getElementById('btn-stop-nav');
  const btnRequestCompass = document.getElementById('btn-request-compass');

  const navStatusText = document.getElementById('nav-status-text');
  const navInstructionText = document.getElementById('nav-instruction-text');
  const navWaypointIdx = document.getElementById('nav-waypoint-idx');
  const navDistanceText = document.getElementById('nav-distance-text');
  const navAccuracyText = document.getElementById('nav-accuracy-text');
  const navCompassText = document.getElementById('nav-compass-text');

  if (btnStartNavGPS) {
    btnStartNavGPS.addEventListener('click', () => {
      audioHaptics.resumeContextIfNeeded();
      const started = navEngine.startNavigation();
      if (started) {
        navStatusText.textContent = 'Đang bắt GPS thật...';
        navStatusText.style.color = '#3b82f6';
      }
    });
  }

  if (btnStartNavSim) {
    btnStartNavSim.addEventListener('click', () => {
      audioHaptics.resumeContextIfNeeded();
      navEngine.startSimulation();
      navStatusText.textContent = 'Đang mô phỏng đi bộ...';
      navStatusText.style.color = '#10b981';
    });
  }

  if (btnStopNav) {
    btnStopNav.addEventListener('click', () => {
      navEngine.stopNavigation();
      navStatusText.textContent = 'Đã dừng dẫn đường';
      navStatusText.style.color = '#aaa';
      navInstructionText.textContent = '--';
    });
  }

  if (btnRequestCompass) {
    btnRequestCompass.addEventListener('click', async () => {
      const granted = await navEngine.requestCompassPermission();
      btnRequestCompass.textContent = granted ? 'Đã cấp quyền La bàn' : 'Không có quyền La bàn';
    });
  }

  // Cập nhật trạng thái Dẫn đường lên giao diện định kỳ (500ms)
  setInterval(() => {
    if (!navEngine) return;
    const st = navEngine.getCurrentStatus();

    if (st.status !== 'idle') {
      if (st.status === 'simulating') {
        navStatusText.textContent = 'Mô phỏng (Simulator)';
        navStatusText.style.color = '#10b981';
      } else {
        navStatusText.textContent = 'GPS Đang kích hoạt';
        navStatusText.style.color = '#3b82f6';
      }

      navInstructionText.textContent = st.lastInstruction || st.nextAction || 'Đang xác định lộ trình...';
      navWaypointIdx.textContent = `${st.currentWaypointIndex + 1}/${st.totalWaypoints}`;
      navDistanceText.textContent = `${st.distanceToTarget} m`;
      navAccuracyText.textContent = `±${st.gpsAccuracy} m`;
      navCompassText.textContent = `${st.compassHeading}°`;

      // Cập nhật thanh trạng thái đọc của người khiếm thị nếu không có hiểm họa khẩn cấp
      if (!alertEngine.currentThreat && isAppActive) {
        statusBanner.textContent = `Dẫn đường: ${st.lastInstruction || 'Đi thẳng'}`;
      }
    }
  }, 500);

  // ====================================================
  // MODAL ĐIỀU KHOẢN AN TOÀN BẮT BUỘC (GIAI ĐOẠN 5)
  // ====================================================
  const safetyModal = document.getElementById('safety-modal');
  const btnAgreeDisclaimer = document.getElementById('btn-agree-disclaimer');
  const btnReopenDisclaimer = document.getElementById('btn-reopen-disclaimer');

  function checkDisclaimer() {
    const accepted = localStorage.getItem('bemyeye_disclaimer_accepted');
    if (!accepted && safetyModal) {
      safetyModal.style.display = 'flex';
      setTimeout(() => {
        audioHaptics.speakVietnamese(
          'Chào mừng bạn đến với Be My Eyes Việt Nam. Ứng dụng là công cụ bổ trợ, tuyệt đối không thay thế gậy trắng. Bấm nút dưới cùng để đồng ý.',
          true
        );
      }, 800);
    }
  }

  if (btnAgreeDisclaimer) {
    btnAgreeDisclaimer.addEventListener('click', () => {
      localStorage.setItem('bemyeye_disclaimer_accepted', 'true');
      if (safetyModal) safetyModal.style.display = 'none';
      audioHaptics.speakVietnamese('Bạn đã đồng ý với điều khoản an toàn. Chúc bạn có chuyến đi an toàn.', true);
    });
  }

  if (btnReopenDisclaimer) {
    btnReopenDisclaimer.addEventListener('click', () => {
      if (safetyModal) safetyModal.style.display = 'flex';
    });
  }

  checkDisclaimer();
});
