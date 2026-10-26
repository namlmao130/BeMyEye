/**
 * detector.js
 * Quản lý khởi tạo mô hình TensorFlow.js COCO-SSD và thực thi suy luận trên từng frame camera.
 * 
 * Ánh xạ các nhãn COCO sang tiếng Việt và phân loại mức độ nguy hiểm đối với người khiếm thị.
 */

class ObjectDetector {
  constructor() {
    this.model = null;
    this.isModelLoaded = false;
    this.confidenceThreshold = 0.45;

    // Từ điển nhãn COCO sang tiếng Việt
    this.CLASS_MAPPINGS = {
      // Phương tiện giao thông (Mức độ ưu tiên cao nhất)
      'motorcycle': { vi: 'Xe máy', category: 'vehicle', priority: 1 },
      'car': { vi: 'Ô tô', category: 'vehicle', priority: 2 },
      'bicycle': { vi: 'Xe đạp', category: 'vehicle', priority: 3 },
      'bus': { vi: 'Xe buýt', category: 'vehicle', priority: 1 },
      'truck': { vi: 'Xe tải', category: 'vehicle', priority: 1 },

      // Người đi bộ
      'person': { vi: 'Người', category: 'pedestrian', priority: 4 },

      // Vật cản tĩnh chiếm lối đi thường gặp trên đường phố Việt Nam
      'chair': { vi: 'Ghế quán cóc', category: 'obstacle', priority: 5 },
      'bench': { vi: 'Ghế dài', category: 'obstacle', priority: 5 },
      'potted plant': { vi: 'Chậu cây', category: 'obstacle', priority: 6 },
      'fire hydrant': { vi: 'Trụ nước', category: 'obstacle', priority: 5 },
      'stop sign': { vi: 'Biển báo', category: 'obstacle', priority: 5 },
      'traffic light': { vi: 'Đèn giao thông', category: 'obstacle', priority: 6 },
      'umbrella': { vi: 'Dù bạt che', category: 'obstacle', priority: 4 },

      // Động vật
      'dog': { vi: 'Chó', category: 'animal', priority: 3 },
      'cat': { vi: 'Mèo', category: 'animal', priority: 7 }
    };
  }

  /**
   * Tải mô hình MobileNet COCO-SSD
   * @param {Function} onProgressCallback - Callback thông báo tiến độ tải
   */
  async loadModel(onProgressCallback = null) {
    if (this.isModelLoaded) return;

    if (onProgressCallback) onProgressCallback('Đang tải mô hình thị giác AI (MobileNet SSD)...');

    try {
      // Đặt backend ưu tiên WebGL để tăng tốc phần cứng GPU di động
      if (window.tf) {
        await tf.setBackend('webgl');
        await tf.ready();
      }

      // Tải mô hình COCO-SSD bản lite để đảm bảo đạt >= 15-20 FPS trên di động
      this.model = await cocoSsd.load({
        base: 'lite_mobilenet_v2' // Rất nhẹ và tối ưu cho mobile browser
      });

      this.isModelLoaded = true;
      if (onProgressCallback) onProgressCallback('Mô hình AI đã sẵn sàng.');
    } catch (err) {
      console.error('Lỗi khi tải mô hình TensorFlow.js:', err);
      // Thử fallback sang cpu backend nếu webgl lỗi
      if (window.tf) {
        await tf.setBackend('cpu');
        this.model = await cocoSsd.load({ base: 'lite_mobilenet_v2' });
        this.isModelLoaded = true;
      } else {
        throw new Error('Không thể tải TensorFlow.js: ' + err.message);
      }
    }
  }

  /**
   * Nhận diện các vật thể trong frame hình ảnh / video
   * @param {HTMLVideoElement|HTMLImageElement|HTMLCanvasElement} inputElement
   * @returns {Promise<Array>} Danh sách vật thể phát hiện được
   */
  async detect(inputElement) {
    if (!this.isModelLoaded || !this.model) {
      return [];
    }

    try {
      // Dự đoán đối tượng
      const predictions = await this.model.detect(inputElement, 15, this.confidenceThreshold);

      // Lọc và ánh xạ các nhãn liên quan
      const filtered = [];
      for (const pred of predictions) {
        const clsLower = pred.class.toLowerCase();
        const mapping = this.CLASS_MAPPINGS[clsLower];

        // Nếu vật thể nằm trong danh sách quan sát hoặc có độ tin cậy cao
        if (mapping) {
          filtered.push({
            class: clsLower,
            vietnameseClass: mapping.vi,
            category: mapping.category,
            priority: mapping.priority,
            score: pred.score,
            bbox: pred.bbox // [x, y, width, height]
          });
        }
      }

      // Sắp xếp theo mức độ ưu tiên nguy hiểm (priority nhỏ hơn = nguy hiểm hơn)
      filtered.sort((a, b) => a.priority - b.priority);

      return filtered;
    } catch (err) {
      console.warn('Lỗi thực thi suy luận frame:', err);
      return [];
    }
  }

  setConfidenceThreshold(val) {
    this.confidenceThreshold = Math.max(0.2, Math.min(0.9, val));
  }
}

window.ObjectDetector = ObjectDetector;
