import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smart_eng_tutor/services/ocr/ocr_models.dart';
import 'package:smart_eng_tutor/services/ocr/ocr_recognizer.dart';
import 'package:smart_eng_tutor/pages/rotate_preview_page.dart';

/// OCR 流程的最终产物
class OcrFlowResult {
  final File imageFile;      // 预处理增强图
  final Size imageSize;      // 增强图尺寸
  final List<OcrWord> words; // 词框（与增强图同一坐标系）

  const OcrFlowResult(this.imageFile, this.imageSize, this.words);
}

/// OCR 流程编排：选图 → 旋转校正 → 预处理 → 识别
class OcrService {
  final OcrRecognizer ocrRecognizer;
  final ImagePicker _picker = ImagePicker();

  OcrService(this.ocrRecognizer);

  /// 完整流程。用户取消返回 null；处理出错抛异常（由调用方 catch）
  Future<OcrFlowResult?> run(BuildContext context, ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 100,
      maxWidth: 8192,
    );
    if (picked == null) return null;
    if (!context.mounted) return null;   // ← gap 后先确认活着

    final result = await Navigator.push<(File, int)>(
      context,
      MaterialPageRoute(
        builder: (_) => RotatePreviewPage(
          sourceFile: File(picked.path),
          ocrRecognizer: ocrRecognizer,
        ),
      ),
    );
    if (result == null) return null;
    if (!context.mounted) return null;   // ← 第二个 gap 后再确认一次

    final (file, turns) = result;
    final prep = await ocrRecognizer.preprocessImage(file, quarterTurns: turns);
    final words = await ocrRecognizer.recognize(prep.file);
    final size = await ocrRecognizer.readImageSize(prep.file);

    return OcrFlowResult(prep.file, size, words);
  }
}
