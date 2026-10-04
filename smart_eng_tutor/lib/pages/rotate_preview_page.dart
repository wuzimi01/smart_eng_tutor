import 'dart:io';
import 'package:flutter/material.dart';
import '../services/ocr_service.dart';

class RotatePreviewPage extends StatefulWidget {
  final File sourceFile;
  final OcrService ocrService;

  const RotatePreviewPage({
    super.key,
    required this.sourceFile,
    required this.ocrService,
  });

  @override
  State<RotatePreviewPage> createState() => _RotatePreviewPageState();
}

class _RotatePreviewPageState extends State<RotatePreviewPage> {
  int _quarterTurns = 0;

  /// 确认：不再在此生成旋转文件，把 (原图, 转数) 交回主页，
  /// 由 preprocessImage 统一做旋转 + 增强
  void _confirm() {
    Navigator.pop(context, (widget.sourceFile, _quarterTurns)); // Dart 3 record
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('旋转图片'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done),
            tooltip: '确认',
            onPressed: _confirm,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: RotatedBox(
                quarterTurns: _quarterTurns,
                child: Image.file(widget.sourceFile),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.outlined(
                    icon: const Icon(Icons.rotate_left),
                    iconSize: 32,
                    onPressed: () =>
                        setState(() => _quarterTurns = (_quarterTurns + 3) % 4),
                  ),
                  const SizedBox(width: 24),
                  Text('${(_quarterTurns % 4) * 90}°',
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 24),
                  IconButton.outlined(
                    icon: const Icon(Icons.rotate_right),
                    iconSize: 32,
                    onPressed: () =>
                        setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
