import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/models.dart';

/// 图片取词区：显示预处理图 + 单词点击框叠加层
///
/// 纯展示组件：
/// - 输入：图片文件、真实尺寸、词框列表
/// - 输出：点击单词时回调 onWordTap
class OcrImageView extends StatelessWidget {
  final File imageFile;
  final Size imageSize;
  final List<OcrWord> words;
  final ValueChanged<String> onWordTap;

  const OcrImageView({
    super.key,
    required this.imageFile,
    required this.imageSize,
    required this.words,
    required this.onWordTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 3,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (imageSize == Size.zero) {
              return const Center(child: CircularProgressIndicator());
            }

            final scaleX = constraints.maxWidth / imageSize.width;
            final scaleY = constraints.maxHeight / imageSize.height;
            final scale = scaleX < scaleY ? scaleX : scaleY;
            final displayW = imageSize.width * scale;
            final displayH = imageSize.height * scale;

            return Center(
              child: InteractiveViewer(
                panEnabled: true,
                scaleEnabled: true,
                minScale: 1.0,
                maxScale: 5.0,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: SizedBox(
                  width: displayW,
                  height: displayH,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.file(
                          imageFile,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      ...words.map((w) {
                        return Positioned(
                          left: w.rect.left * scale,
                          top: w.rect.top * scale,
                          width: w.rect.width * scale,
                          height: w.rect.height * scale,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => onWordTap(w.text),
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.blue.withValues(alpha: 0.6),
                                  ),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    w.text,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
