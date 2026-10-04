import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/models.dart';
import '../services/database_helper.dart';
import '../services/ocr_service.dart';
import '../services/word_lookup.dart';
import '../services/ocr_flow.dart';
import '../services/wordbook_service.dart';
import 'widgets/ocr_image_view.dart';
import 'widgets/chip_list.dart';
import 'wordbook_list_page.dart';

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
  late final WordLookup _lookup = WordLookup(_dbHelper);
  late final OcrFlow _ocrFlow = OcrFlow(_ocrService);
  final TextEditingController _controller = TextEditingController();

  String _displayText = '请输入内容...';
  bool _isLoading = true;

  List<String> _chips = [];
  String? _selectedWord;
  bool _isFavorited = false;

  File? _imageFile;
  Size _imageSize = Size.zero;
  List<OcrWord> _ocrWords = [];
  bool _isRecognizing = false;

  late final WordbookService _wordbook = WordbookService(_dbHelper);

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

  // ==================== 提示条 ====================
  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1800),
        ),
      );
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
    setState(() => _isRecognizing = true);
    try {
      final r = await _ocrFlow.run(context, source);
      if (!mounted) return;
      setState(() => _isRecognizing = false);
      if (r == null) return;
      setState(() {
        _imageFile = r.imageFile;
        _imageSize = r.imageSize;
        _ocrWords = r.words;
        _displayText = r.words.isEmpty
            ? '未识别到英文单词，请重试或检查图片清晰度'
            : '点击图片上的单词进行查询（共 ${r.words.length} 个）';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRecognizing = false);
      _showSnack('❌ OCR 识别失败: $e');
    }
  }

  // ==================== 搜索逻辑 ====================
    Future<void> _search(String word) async {
    if (word.isEmpty) {
      setState(() {
        _displayText = '请输入内容...';
        _chips = [];
        _selectedWord = null;
        _isFavorited = false;   // 清空时熄灭星星
      });
      return;
    }
    try {
      final r = await _lookup.search(word);
      if (!mounted) return;
      final fav = r.selected != null
          ? await _wordbook.isFavorited(r.selected!)
          : false;
      if (!mounted) return;
      setState(() {
        _chips = r.chips;
        _selectedWord = r.selected;
        _displayText = r.displayText;
        _isFavorited = fav;
      });
    } catch (e) {
      _showSnack('查询出错: $e');
    }
  }


      Future<void> _selectChip(String word) async {
    try {
      final r = await _lookup.select(word);
      if (!mounted) return;
      // 先查收藏状态，再一次性 setState —— 星星和释义同帧更新
      final fav = r.selected != null
          ? await _wordbook.isFavorited(r.selected!)
          : false;
      if (!mounted) return;
      setState(() {
        _selectedWord = r.selected;
        _displayText = r.displayText;
        _isFavorited = fav;
      });
    } catch (e) {
      _showSnack('查询出错: $e');
    }
  }



    Future<void> _toggleFavorite() async {
    final word = _selectedWord;
    if (word == null) return;
    try {
            final r = await _wordbook.toggle(word);
      if (!mounted) return;
      // 以数据库的真实状态为准，而不是假设翻转成功
      final real = await _wordbook.isFavorited(word);
      if (!mounted) return;                       // ← 补这个：第二次 await 之后
      setState(() => _isFavorited = real);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(r.message),
            duration: const Duration(milliseconds: 1200),
            behavior: SnackBarBehavior.floating,
            width: 260,
            action: real
                ? SnackBarAction(
                    label: '撤销',
                    onPressed: () async {
                      await _wordbook.toggle(word);
                      if (mounted) {              // 撤销回调里已有，保留
                        final still = await _wordbook.isFavorited(word);
                        if (mounted) setState(() => _isFavorited = still);
                      }
                    },
                  )
                : null,
          ),
        );

    } catch (e) {
      _showSnack('收藏出错: $e');
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
            ChipList(
              chips: _chips,
              selectedWord: _selectedWord,
              onSelect: _selectChip,
            ),
          if (_isMobile && _imageFile != null)
            OcrImageView(
              imageFile: _imageFile!,
              imageSize: _imageSize,
              words: _ocrWords,
              onWordTap: _onTapOcrWord,
            ),
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
                          // 收藏按钮：单词 chips 下方、释义上方
                          if (_selectedWord != null && !_isRecognizing)
                            IconButton(
                              icon: Icon(
                                _isFavorited ? Icons.star : Icons.star_border,
                                color:
                                    _isFavorited ? Colors.amber : Colors.grey,
                              ),
                              iconSize: 28,
                              tooltip: _isFavorited ? '取消收藏' : '收藏到词库',
                              onPressed: _toggleFavorite,
                            ),
                          // 释义文本（只承载正常提示/结果，错误走 SnackBar）
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart English Tutor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book),
            tooltip: '我的词库',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WordbookListPage(dbHelper: _dbHelper),
                ),
              );
              // 返回后按当前选中词刷新星星
              final w = _selectedWord;
              if (w != null && mounted) {
                final fav = await _wordbook.isFavorited(w);
                if (mounted) setState(() => _isFavorited = fav);
              }
            },
          ),
          if (_isMobile) ...[
            IconButton(
              icon: _isRecognizing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.photo_camera),
              tooltip: '拍照选词',
              onPressed: _isRecognizing ? null : _showImageSourceDialog,
            ),
          ],
        ],
      ),
      body: body,
    );
  }
}
