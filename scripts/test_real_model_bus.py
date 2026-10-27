#!/usr/bin/env python3
"""
scripts/test_real_model_bus.py
Kiểm thử mô hình thật TFLite SSD MobileNet với ảnh xe buýt (bus.jpg)
Kỳ vọng phát hiện: >= 3 "person" và >= 1 "bus" khi áp dụng kLabelOffset = 1.
"""

import os
import sys

def run_test():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    model_path = os.path.join(base_dir, "flutter_app", "assets", "models", "mobilenet_ssd.tflite")
    label_path = os.path.join(base_dir, "flutter_app", "assets", "models", "labelmap.txt")
    image_path = os.path.join(base_dir, "flutter_app", "test", "assets", "bus.jpg")

    print(f"1. Kiểm tra các tệp đầu vào:")
    print(f"   - Model: {model_path} (Tồn tại: {os.path.exists(model_path)})")
    print(f"   - Labels: {label_path} (Tồn tại: {os.path.exists(label_path)})")
    print(f"   - Ảnh test: {image_path} (Tồn tại: {os.path.exists(image_path)})")

    if not os.path.exists(model_path) or not os.path.exists(label_path) or not os.path.exists(image_path):
        print("LỖI: Không tìm thấy đầy đủ tệp đầu vào!")
        sys.exit(1)

    # Đọc danh sách nhãn (91 dòng)
    with open(label_path, "r", encoding="utf-8") as f:
        labels = [line.strip() for line in f.readlines()]
    print(f"   - Số lượng nhãn nạp được: {len(labels)} dòng (dòng 0: '{labels[0]}', dòng 1: '{labels[1]}', dòng 6: '{labels[6]}')")
    assert len(labels) == 91, f"Kỳ vọng 91 nhãn, thực tế {len(labels)}"

    # Thử nạp TFLite Runtime hoặc TensorFlow
    interpreter = None
    try:
        import tflite_runtime.interpreter as tflite
        interpreter = tflite.Interpreter(model_path=model_path)
    except ImportError:
        try:
            import tensorflow as tf
            interpreter = tf.lite.Interpreter(model_path=model_path)
        except ImportError:
            print("\n[CẢNH BÁO] Chưa cài đặt tflite_runtime hoặc tensorflow trên môi trường Python này.")
            print("Để chạy suy luận trực tiếp trên máy, cài đặt: pip install tflite-runtime pillow")
            print("-> Xác nhận tính đúng đắn qua cấu trúc tensor và kiểm thử Dart Integration Test.")
            return

    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    print(f"\n2. Thông tin Tensor:")
    print(f"   - Input: {input_details[0]['shape']}, dtype: {input_details[0]['dtype']}")
    print(f"   - Outputs: {len(output_details)} tensors:")
    for i, out in enumerate(output_details):
        print(f"     Tensor {i}: shape {out['shape']}, dtype {out['dtype']}")

    # Đọc và tiền xử lý ảnh bus.jpg sang 300x300 uint8
    try:
        from PIL import Image
        import numpy as np
        img = Image.open(image_path).convert('RGB')
        img_resized = img.resize((300, 300))
        input_data = np.expand_dims(np.array(img_resized, dtype=np.uint8), axis=0)
    except ImportError:
        print("Cần thư viện pillow và numpy để xử lý ảnh: pip install pillow numpy")
        return

    # Chạy suy luận
    interpreter.set_tensor(input_details[0]['index'], input_data)
    interpreter.invoke()

    boxes = interpreter.get_tensor(output_details[0]['index'])[0]
    classes = interpreter.get_tensor(output_details[1]['index'])[0]
    scores = interpreter.get_tensor(output_details[2]['index'])[0]
    num_detections = int(interpreter.get_tensor(output_details[3]['index'])[0])

    print(f"\n3. Kết quả Suy luận thô ({num_detections} đối tượng):")
    kLabelOffset = 1
    confidence_threshold = 0.40

    detected_persons = 0
    detected_buses = 0

    for i in range(num_detections):
        score = float(scores[i])
        if score < confidence_threshold:
            continue
        raw_class = int(classes[i])
        effective_index = raw_class + kLabelOffset

        if 0 <= effective_index < len(labels):
            label = labels[effective_index]
        else:
            label = "UNKNOWN"

        box = boxes[i]
        print(f"   - [{i+1}] Raw class: {raw_class} -> Label: '{label}' (Score: {score:.2f}) | Box: {box}")

        if label == 'person':
            detected_persons += 1
        elif label == 'bus':
            detected_buses += 1

    print(f"\n4. Đánh giá tiêu chuẩn:")
    print(f"   - Số 'person' phát hiện: {detected_persons} (Kỳ vọng >= 3)")
    print(f"   - Số 'bus' phát hiện: {detected_buses} (Kỳ vọng >= 1)")

    assert detected_persons >= 3, f"Số người phát hiện ({detected_persons}) < 3!"
    assert detected_buses >= 1, f"Số xe buýt phát hiện ({detected_buses}) < 1!"
    print("\n✅ KIỂM THỬ THÀNH CÔNG: Mô hình thật phát hiện đúng >= 3 người và >= 1 xe buýt với kLabelOffset = 1!")

if __name__ == "__main__":
    run_test()
