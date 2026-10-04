import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';

/// 图像预处理结果
class PreprocessResult {
  final File file;      // 送 OCR 的增强图
  const PreprocessResult(this.file);
}

/// 图像处理器：负责预处理流水线（与 OCR 识别解耦）
class ImageProcessor {
  /// 流水线：旋转 → 小图放大 → 去红笔批改 → 灰度 → 对比度增强 → Bradley 自适应二值化
  Future<PreprocessResult> process(
    File source, {
    int quarterTurns = 0,
  }) async {
    final bytes = await source.readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('无法解码图片');

    // ---- 1. 旋转（quarterTurns: 1=90°顺时针, 2=180°, 3=270°）----
    final q = quarterTurns % 4;
    if (q != 0) {
      // image 4.x：angle 单位为度
      image = img.copyRotate(image, angle: q * 90);
    }
    // if (image.width < 1400) {
    //   image = img.copyResize(
    //     image,
    //     width: 1400,
    //     interpolation: img.Interpolation.cubic,
    //   );
    // }

    // ---- 3. 去红笔批改：红笔像素置白 ----
    image = _removeRedMarks(image);

    // ---- 4. 灰度 + 对比度增强 ----
    image = img.grayscale(image);
    image = img.adjustColor(image, contrast: 1.3);

    // ---- 5. Bradley 自适应二值化 ----
    image = _bradleyThreshold(image);

    // ---- 6. 导出 ----
    final tempDir = await getTemporaryDirectory();
    final out = File(join(tempDir.path,
        'prep_${DateTime.now().millisecondsSinceEpoch}.png'));
    final pngBytes = img.encodePng(image);
    await out.writeAsBytes(Uint8List.fromList(pngBytes));
    
    return PreprocessResult(out);
  }

  /// 去红笔批改：红笔像素（R 明显高于 G、B）置白
  img.Image _removeRedMarks(img.Image image) {
    final w = image.width;
    final h = image.height;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();
        if (r > 90 && r > g * 1.5 && r > b * 1.5) {
          image.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
    }
    return image;
  }

  /// Bradley 自适应阈值二值化（image 包无内置，手写实现）
  img.Image _bradleyThreshold(img.Image src, {double t = 0.15}) {
    final w = src.width;
    final h = src.height;

    // 灰度数组
    final gray = List<int>.filled(w * h, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        gray[y * w + x] = src.getPixel(x, y).luminance.toInt();
      }
    }

    // 积分图
    final iw = w + 1;
    final integral = List<int>.filled(iw * (h + 1), 0);
    for (int y = 0; y < h; y++) {
      int rowSum = 0;
      for (int x = 0; x < w; x++) {
        rowSum += gray[y * w + x];
        integral[(y + 1) * iw + (x + 1)] = integral[y * iw + (x + 1)] + rowSum;
      }
    }

    // 阈值化
    final dst = img.Image.from(src);
    const s = 24; // 窗口半径，可调
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final x1 = (x - s).clamp(0, w - 1);
        final y1 = (y - s).clamp(0, h - 1);
        final x2 = (x + s).clamp(0, w - 1);
        final y2 = (y + s).clamp(0, h - 1);
        final count = (x2 - x1 + 1) * (y2 - y1 + 1);
        final sum = integral[(y2 + 1) * iw + x2 + 1] -
            integral[y1 * iw + x2 + 1] -
            integral[(y2 + 1) * iw + x1] +
            integral[y1 * iw + x1];
        final v = gray[y * w + x] < sum / count * (1 - t) ? 0 : 255;
        dst.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return dst;
  }
}
