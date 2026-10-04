import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/painting.dart'; // Rect / Size / Paint
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class OcrService {
  TextRecognizer? _recognizer;

  bool get isSupported => !(
      // ML Kit 只在移动端可用
      false);

  void ensureInitialized() {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
  }

  /// 识别图片，返回带坐标的单词列表
  Future<List<OcrWord>> recognize(File imageFile) async {
    ensureInitialized();
    final inputImage = InputImage.fromFilePath(imageFile.path);
    final result = await _recognizer!.processImage(inputImage);

    final words = <OcrWord>[];
    final wordRegex = RegExp(r"^[A-Za-z'’-]+$");
    for (final block in result.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final bbox = element.boundingBox;
          if (bbox == null) continue;
          final tokens = element.text
              .split(RegExp(r'[\s,.:;!?()"“”]+'))
              .where((t) => t.trim().isNotEmpty)
              .toList();
          if (tokens.isEmpty) continue;

          final totalLen = element.text.length;
          int offset = 0;
          for (final t in tokens) {
            final start = element.text.indexOf(t, offset);
            final end = start + t.length;
            offset = end;
            final w = t.trim();
            if (!wordRegex.hasMatch(w)) continue;

            final scaleW = bbox.width / totalLen;
            final sub = Rect.fromLTRB(
              bbox.left + start * scaleW,
              bbox.top,
              bbox.left + end * scaleW,
              bbox.bottom,
            );
            words.add(OcrWord(w.toLowerCase(), sub));
          }
        }
      }
    }
    return words;
  }

  /// 读取图片尺寸
  Future<Size> readImageSize(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size =
        Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    frame.image.dispose();
    codec.dispose();
    return size;
  }

  /// 像素级旋转图片（quarterTurns: 1=90°顺时针, 2=180°, 3=270°）
  Future<File> rotateImage(File source, int quarterTurns) async {
    final q = quarterTurns % 4;
    if (q == 0) return source;

    final bytes = await source.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    switch (q) {
      case 1:
        canvas.translate(img.height.toDouble(), 0);
        canvas.rotate(math.pi / 2);
        break;
      case 2:
        canvas.translate(img.width.toDouble(), img.height.toDouble());
        canvas.rotate(math.pi);
        break;
      case 3:
        canvas.translate(0, img.width.toDouble());
        canvas.rotate(3 * math.pi / 2);
        break;
    }
    canvas.drawImage(img, Offset.zero, Paint());
    final picture = recorder.endRecording();

    final newW = q.isOdd ? img.height : img.width;
    final newH = q.isOdd ? img.width : img.height;
    final out = await picture.toImage(newW, newH);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);

    img.dispose();
    codec.dispose();

    final tempDir = await getTemporaryDirectory();
    final file = File(join(
        tempDir.path, 'rotated_${DateTime.now().millisecondsSinceEpoch}.png'));
    await file.writeAsBytes(data!.buffer.asUint8List());
    return file;
  }

  void dispose() {
    _recognizer?.close();
  }
}
