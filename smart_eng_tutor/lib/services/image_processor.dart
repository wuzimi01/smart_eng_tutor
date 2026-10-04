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
    image = _removeMarks(image, red: true, blue: true);

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
  /// 去笔迹批改：红笔/蓝青笔像素置白（HSV 色相判断，可覆盖青色、浅蓝）
  img.Image _removeMarks(
    img.Image image, {
    bool red = true,
    bool blue = true,
  }) {
    final w = image.width;
    final h = image.height;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        final r = p.r / 255.0;
        final g = p.g / 255.0;
        final b = p.b / 255.0;

        final max = [r, g, b].reduce((a, b2) => a > b2 ? a : b2);
        final min = [r, g, b].reduce((a, b2) => a < b2 ? a : b2);
        final delta = max - min;
        // 饱和度过低 → 灰/白/黑，跳过（保护印刷内容）
        if (max < 0.1 || delta / max < 0.15) continue;

        // 计算色相 (0~360)
        double hue;
        if (max == r) {
          hue = 60 * (((g - b) / delta) % 6);
        } else if (max == g) {
          hue = 60 * ((b - r) / delta + 2);
        } else {
          hue = 60 * ((r - g) / delta + 4);
        }
        if (hue < 0) hue += 360;

        final isRed = red && (hue >= 330 || hue <= 20) && max > 0.25;
        // 170~260 覆盖 青(180)、天蓝(200)、蓝(240)
        final isBlue = blue && hue >= 170 && hue <= 260 && max > 0.25;

        if (isRed || isBlue) {
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
