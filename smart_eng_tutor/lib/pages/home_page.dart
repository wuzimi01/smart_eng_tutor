import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../database_helper.dart';
import '../ocr_service.dart';
import 'rotate_preview_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final bool _isMobile = Platform.isAndroid || Platform.isIOS;

  // 服务
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final OcrService _ocrService = OcrService();
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _controller = TextEditingController();
  String _displayText = '请输入内容...';
  bool _isLoading = true;

  List<String> _chips = [];
  String? _selectedWord;

  File? _imageFile;
  Size _imageSize = Size.zero;
  List<OcrWord> _ocrWords = [];
  bool _isRecognizing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await _dbHelper.init();
    setState(() {
      _isLoading = false;
      if (!ok) _displayText = '❌ 数据库初始化失败，请检查 assets';
    });
    if (_isMobile) _ocrService.ensureInitialized();
  }

  // ==================== OCR 流程 ====================

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
    if (source != null) _pickAndRecognize(source);
  }

  Future<void> _pickAndRecognize(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 90,
      );
      if (picked == null) return;

      // 旋转预览
      final confirmed = await Navigator.push<File>(
        context,
        MaterialPageRoute(
          builder: (_) => RotatePreviewPage(
            sourceFile: File(picked.path),
            ocrService: _ocrService,
          ),
        ),
      );
      if (confirmed == null) return;

      setState(() {
        _isRecognizing = true;
        _imageFile = confirmed;
        _ocrWords = [];
        _displayText = '🔍 正在识别图片中的文字...';
      });

      _imageSize = await _ocrService.readImageSize(confirmed);
      final words = await _ocrService.recognize(confirmed);

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

  // ==================== 搜索逻辑 ====================

  Future<void> _search(String word) async {
    if (word.isEmpty) {
      setState(() {
        _displayText = '请输入内容...';
        _chips = [];
        _selectedWord = null;
      });
      return;
    }

    try {
      final stems = await _dbHelper.queryStems(word);

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
        final trans = await _dbHelper.queryTranslation(c);
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
      final trans = await _dbHelper.queryTranslation(word);
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
    _dbHelper.dispose();
    _ocrService.dispose();
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
                      child: CircularProgressIndicator(strokeWidth: 2),
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
                        child: Image.file(_imageFile!, fit: BoxFit.fill),
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
                                      color: Colors.blue.withOpacity(0.6)),
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
