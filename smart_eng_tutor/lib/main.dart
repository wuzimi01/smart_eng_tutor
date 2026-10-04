import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show sqfliteFfiInit, databaseFactoryFfi;
import 'package:path/path.dart' show join, dirname;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

void main() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: HomePage());
  }
}

class OcrWord {
  final String text;
  final Rect rect;
  OcrWord(this.text, this.rect);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final bool _isMobile = Platform.isAndroid || Platform.isIOS;

  final TextEditingController _controller = TextEditingController();
  String _displayText = '请输入内容...';
  Database? _lemmaDb;
  Database? _dictDb;
  bool _isLoading = true;

  List<String> _chips = [];
  String? _selectedWord;

  final ImagePicker _picker = ImagePicker();
  TextRecognizer? _textRecognizer;
  File? _imageFile;
  Size _imageSize = Size.zero;
  List<OcrWord> _ocrWords = [];
  bool _isRecognizing = false;

  @override
  void initState() {
    super.initState();
    if (_isMobile) {
      _textRecognizer =
          TextRecognizer(script: TextRecognitionScript.latin);
    }
    _initDatabases();
  }

  Future<void> _copyFromAssets(String assetPath, String dbPath) async {
    final dbDir = Directory(dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    final data = await rootBundle.load(assetPath);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await File(dbPath).writeAsBytes(bytes);
  }

  Future<void> _initDatabases() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();

      final lemmaPath = join(appDocDir.path, 'lemma.en.db');
      if (!await File(lemmaPath).exists()) {
        try {
          await _copyFromAssets('assets/lemma.en.db', lemmaPath);
        } catch (e) {
          setState(() {
            _displayText = '❌ 未找到 assets/lemma.en.db';
            _isLoading = false;
          });
          return;
        }
      }
      try {
        _lemmaDb = await openDatabase(lemmaPath);
      } catch (e) {
        setState(() {
          _displayText = '❌ 词根库打开失败: $e';
          _isLoading = false;
        });
        return;
      }

      final dictPath = join(appDocDir.path, 'stardict.db');
      if (!await File(dictPath).exists()) {
        try {
          await _copyFromAssets('assets/stardict.db', dictPath);
        } catch (e) {
          setState(() {
            _displayText = '❌ 未找到 assets/stardict.db';
            _isLoading = false;
          });
          return;
        }
      }
      try {
        _dictDb = await openDatabase(dictPath, readOnly: true);
      } catch (e) {
        setState(() {
          _displayText = '❌ 释义库打开失败: $e';
          _isLoading = false;
        });
        return;
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _displayText = '❌ 初始化异常: $e';
        _isLoading = false;
      });
    }
  }

  // ==================== 图片旋转工具 ====================

  /// 🔥 把图片按 quarterTurns 个 90° 顺时针旋转，写入临时 PNG 并返回
  Future<File> _rotateImageFile(File source, int quarterTurns) async {
    final q = quarterTurns % 4;
    if (q == 0) return source;

    final bytes = await source.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    switch (q) {
      case 1: // 90° 顺时针
        canvas.translate(img.height.toDouble(), 0);
        canvas.rotate(math.pi / 2);
        break;
      case 2: // 180°
        canvas.translate(img.width.toDouble(), img.height.toDouble());
        canvas.rotate(math.pi);
        break;
      case 3: // 270°
        canvas.translate(0, img.width.toDouble());
        canvas.rotate(3 * math.pi / 2);
        break;
    }
    canvas.drawImage(img, Offset.zero, Paint());
    final picture = recorder.endRecording();

    final newW = q.isOdd ? img.height : img.width;
    final newH = q.isOdd ? img.width : img.height;
    final out = await picture.toImage(newW, newH);
    final data =
        await out.toByteData(format: ui.ImageByteFormat.png);

    img.dispose();
    frame.image.dispose();
    codec.dispose();

    final tempDir = await getTemporaryDirectory();
    final file = File(join(tempDir.path,
        'rotated_${DateTime.now().millisecondsSinceEpoch}.png'));
    await file.writeAsBytes(data!.buffer.asUint8List());
    return file;
  }

  /// 🔥 打开旋转预览页，返回用户确认后的图片文件（可能已旋转）
  Future<File?> _openRotatePreview(File source) async {
    final result = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (_) => RotatePreviewPage(sourceFile: source),
      ),
    );
    return result;
  }

  // ==================== OCR ====================

  Future<void> _showImageSourceDialog() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) {
      _pickAndRecognize(source);
    }
  }

  Future<void> _pickAndRecognize(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 90,
      );
      if (picked == null) return;

      // 🔥 先进入旋转预览，用户可旋转后再确认
      final File? confirmed =
          await _openRotatePreview(File(picked.path));
      if (confirmed == null) return; // 用户取消

      final file = confirmed;

      // 读出图片实际尺寸（此时已是最终方向）
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
          frame.image.width.toDouble(), frame.image.height.toDouble());
      frame.image.dispose();
      codec.dispose();

      setState(() {
        _isRecognizing = true;
        _imageFile = file;
        _imageSize = size;
        _ocrWords = [];
        _displayText = '🔍 正在识别图片中的文字...';
      });

      final inputImage = InputImage.fromFilePath(file.path);
      final result = await _textRecognizer!.processImage(inputImage);

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

      setState(() {
        _isRecognizing = false;
        _ocrWords = words;
        _displayText = words.isEmpty
            ? '未识别到英文单词，请重试或检查图片清晰度'
            : '点击图片上的单词进行查询（共 ${words.length} 个）';
      });
    } catch (e) {
      setState(() {
        _isRecognizing = false;
        _displayText = '❌ OCR 识别失败: $e';
      });
    }
  }

  // ==================== 数据库查询 ====================

  Future<List<Map<String, Object?>>?> _queryTranslation(String word) async {
    if (_dictDb == null) return null;
    final results = await _dictDb!.query(
      'stardict',
      columns: ['word', 'translation'],
      where: 'word = ?',
      whereArgs: [word],
    );
    return results.isEmpty ? null : results;
  }

  Future<void> _search(String word) async {
    if (_lemmaDb == null || _dictDb == null) {
      setState(() => _displayText = '数据库未就绪...');
      return;
    }
    if (word.isEmpty) {
      setState(() {
        _displayText = '请输入内容...';
        _chips = [];
        _selectedWord = null;
      });
      return;
    }

    try {
      final stemRows = await _lemmaDb!.query(
        'word_stem',
        columns: ['stem'],
        where: 'word = ?',
        whereArgs: [word],
        orderBy: 'weight DESC',
      );
      final stems = stemRows.map((row) => row['stem'] as String).toList();

      final candidates = <String>[word, ...stems];
      final unique = <String>[];
      for (final c in candidates) {
        if (!unique.contains(c)) unique.add(c);
      }

      setState(() {
        _chips = unique;
        _selectedWord = null;
      });

      for (final c in unique) {
        final trans = await _queryTranslation(c);
        if (trans != null) {
          await _selectChip(c);
          return;
        }
      }

      setState(() {
        _selectedWord = null;
        _displayText = '未找到释义';
      });
    } catch (e) {
      setState(() => _displayText = '查询出错: $e');
    }
  }

  Future<void> _selectChip(String word) async {
    setState(() => _selectedWord = word);
    try {
      final trans = await _queryTranslation(word);
      if (trans == null) {
        setState(() => _displayText = '「$word」没有释义');
        return;
      }
      final buffer = StringBuffer();
      for (final row in trans) {
        buffer.writeln(row['word']);
        buffer.writeln(row['translation']);
      }
      setState(() => _displayText = buffer.toString().trim());
    } catch (e) {
      setState(() => _displayText = '查询出错: $e');
    }
  }

  Future<void> _onTapOcrWord(String word) async {
    _controller.text = word;
    await _search(word);
  }

  @override
  void dispose() {
    _controller.dispose();
    _lemmaDb?.close();
    _dictDb?.close();
    _textRecognizer?.close();
    super.dispose();
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _controller,
              onChanged: (value) => _search(value.trim()),
              decoration: InputDecoration(
                hintText: '输入你想搜索的内容…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
          ),

          if (_chips.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _chips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final word = _chips[index];
                  final selected = word == _selectedWord;
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _selectChip(word),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.blue
                            : Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        word,
                        style: TextStyle(
                          fontSize: 16,
                          color: selected ? Colors.white : Colors.blue,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          if (_isMobile && _imageFile != null) _buildImageWithWords(),

          Expanded(
            child: Center(
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isRecognizing)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          Text(
                            _displayText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              color: _displayText == '请输入内容...'
                                  ? Colors.grey
                                  : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );

    if (_isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Smart English Tutor'),
          actions: [
            IconButton(
              icon: _isRecognizing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.photo_camera),
              tooltip: '拍照选词',
              onPressed: _isRecognizing ? null : _showImageSourceDialog,
            ),
          ],
        ),
        body: body,
      );
    }

    return Scaffold(body: body);
  }

  /// 🔥 照片 + 单词按钮 + 双指缩放
  Widget _buildImageWithWords() {
    return Expanded(
      flex: 3,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_imageSize == Size.zero) {
              return const Center(child: CircularProgressIndicator());
            }
            final scaleX = constraints.maxWidth / _imageSize.width;
            final scaleY = constraints.maxHeight / _imageSize.height;
            final scale = scaleX < scaleY ? scaleX : scaleY;
            final displayW = _imageSize.width * scale;
            final displayH = _imageSize.height * scale;

            return Center(
              // 🔥 InteractiveViewer：双指缩放 + 拖动，图片和按钮一起变换
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
                          _imageFile!,
                          fit: BoxFit.fill, // SizedBox 已按宽高比定好尺寸
                        ),
                      ),
                      ..._ocrWords.map((w) {
                        return Positioned(
                          left: w.rect.left * scale,
                          top: w.rect.top * scale,
                          width: w.rect.width * scale,
                          height: w.rect.height * scale,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _onTapOcrWord(w.text),
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.blue.withOpacity(0.6),
                                    width: 1,
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

/// 🔥 旋转预览页：导入照片后先到这里，可旋转，确认后返回
class RotatePreviewPage extends StatefulWidget {
  final File sourceFile;
  const RotatePreviewPage({super.key, required this.sourceFile});

  @override
  State<RotatePreviewPage> createState() => _RotatePreviewPageState();
}

class _RotatePreviewPageState extends State<RotatePreviewPage> {
  int _quarterTurns = 0; // 已旋转的 90° 次数
  bool _saving = false;

  Future<void> _confirm() async {
    if (_quarterTurns % 4 == 0) {
      // 没旋转，直接返回原图
      Navigator.pop(context, widget.sourceFile);
      return;
    }
    setState(() => _saving = true);
    try {
      final bytes = await widget.sourceFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final q = _quarterTurns % 4;
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
      final file = File(join(tempDir.path,
          'rotated_${DateTime.now().millisecondsSinceEpoch}.png'));
      await file.writeAsBytes(data!.buffer.asUint8List());

      if (mounted) Navigator.pop(context, file);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('旋转失败: $e')),
        );
      }
    }
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
            onPressed: _saving ? null : _confirm,
          ),
        ],
      ),
      body: _saving
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
                        // 逆时针
                        IconButton.outlined(
                          icon: const Icon(Icons.rotate_left),
                          iconSize: 32,
                          onPressed: () => setState(
                              () => _quarterTurns = (_quarterTurns + 3) % 4),
                        ),
                        const SizedBox(width: 24),
                        Text(
                          '${(_quarterTurns % 4) * 90}°',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(width: 24),
                        // 顺时针
                        IconButton.outlined(
                          icon: const Icon(Icons.rotate_right),
                          iconSize: 32,
                          onPressed: () => setState(
                              () => _quarterTurns = (_quarterTurns + 1) % 4),
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
