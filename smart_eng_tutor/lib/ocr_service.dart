import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart'; // Rect / Size
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'image_processor.dart'; // PreprocessResult
import 'models.dart';

class OcrService {
  TextRecognizer? _recognizer;
  final ImageProcessor _processor = ImageProcessor(); // ← 委托预处理

  bool get isSupported => true;

  void ensureInitialized() {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
  }

  /// 识别图片，返回带坐标的单词列表（传入的是预处理增强图）
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
    final size = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    frame.image.dispose();
    codec.dispose();
    return size;
  }

  /// 预处理：委托给 ImageProcessor
  Future<PreprocessResult> preprocessImage(
    File source, {
    int quarterTurns = 0,
  }) {
    return _processor.process(source, quarterTurns: quarterTurns);
  }

  void dispose() {
    _recognizer?.close();
  }
}
