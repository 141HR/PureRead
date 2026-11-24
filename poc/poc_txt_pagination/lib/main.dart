import 'package:flutter/material.dart';

import 'pagination/incremental_paginator.dart';
import 'pagination/page_painter.dart';
import 'pagination/pagination_models.dart';

void main() {
  runApp(const PureReadPaginationPocApp());
}

/// Interactive PoC preview app demonstrating single/two-column logical page
/// reuse and charOffset-anchored live font/viewport reflow.
class PureReadPaginationPocApp extends StatelessWidget {
  const PureReadPaginationPocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PureRead TXT Pagination PoC',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4A6B5D),
        useMaterial3: true,
      ),
      home: const ReaderPocScreen(),
    );
  }
}

class ReaderPocScreen extends StatefulWidget {
  const ReaderPocScreen({
    super.key,
    this.initialChapterText = defaultSampleChapterText,
  });

  final String initialChapterText;

  static const String defaultSampleChapterText =
      '第1章 青云初雪\n'
      '夜色微凉，沈砚合上桌上的《山海残卷》，抬头望向窗外闪烁的霓虹灯光。终端屏幕上的 PureRead v3.13 引擎仍在静默运行，日志里不断刷新着 1024 与 4096 的字节偏移刻度。「你确定要在今晚测试这套分页算法吗？」林清音端着热茶走近，「如果出现半个汉字乱码怎么办？」\n'
      '他轻轻一笑，在键盘上敲下几行 Flutter 测试命令：第1步校验编码，第2步构建章节索引，第3步统计字符守恒。窗外细雨淅沥，石板路上的积水倒映着古老牌坊与现代路灯，仿佛两个时代在此交汇！无论是「行首避头」还是「行尾避尾」，排版细节都决定了长篇阅读的呼吸感。\n'
      '“这已经是第7次压测了，数据流依然稳如磐石。”苏牧把玩着手中的青铜令牌（编号 A-2026），仔细核对清单上的条目：墨水屏适配、双栏布局、UTF-8 与 GB18030 流式识别、以及 RandomAccessFile 随机读取。远处的钟楼敲响了午夜十二点的钟声，第一缕山风穿过回廊，吹动了案头的书页……\n';

  @override
  State<ReaderPocScreen> createState() => _ReaderPocScreenState();
}

class _ReaderPocScreenState extends State<ReaderPocScreen> {
  final IncrementalTextPaginator _paginator = IncrementalTextPaginator();
  double _fontSize = 18.0;
  bool _forceTwoColumns = false;
  int _anchorCharOffset = 0;
  Size? _lastViewportSize;
  PaginationConfig? _lastConfig;
  List<PageSlice> _pages = const <PageSlice>[];

  void _ensurePaginated(Size viewportSize) {
    final columnCount = (_forceTwoColumns || viewportSize.width >= 760) ? 2 : 1;
    final config = PaginationConfig.fromViewport(
      viewportWidth: viewportSize.width,
      viewportHeight: viewportSize.height,
      columnCount: columnCount,
      fontSize: _fontSize,
    );

    if (_lastViewportSize == viewportSize &&
        _lastConfig?.fontSize == config.fontSize &&
        _lastConfig?.columnCount == config.columnCount &&
        _pages.isNotEmpty) {
      return;
    }

    _lastViewportSize = viewportSize;
    _lastConfig = config;
    _pages = _paginator.paginateChapterSync(
      chapterIndex: 0,
      sanitizedText: widget.initialChapterText,
      config: config,
      treatFirstLineAsTitle: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F1E7),
      appBar: AppBar(
        title: const Text('PureRead Pagination PoC'),
        actions: [
          IconButton(
            tooltip: 'Decrease font size',
            onPressed: () => setState(() {
              _fontSize = (_fontSize - 2).clamp(12.0, 32.0);
            }),
            icon: const Icon(Icons.text_decrease),
          ),
          IconButton(
            tooltip: 'Increase font size',
            onPressed: () => setState(() {
              _fontSize = (_fontSize + 2).clamp(12.0, 32.0);
            }),
            icon: const Icon(Icons.text_increase),
          ),
          IconButton(
            tooltip: 'Toggle single/two-column',
            onPressed: () => setState(() {
              _forceTwoColumns = !_forceTwoColumns;
            }),
            icon: Icon(_forceTwoColumns ? Icons.menu_book : Icons.article),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          _ensurePaginated(size);
          final config = _lastConfig!;
          final activePageIndex = IncrementalTextPaginator.findPageIndexForOffset(
            _pages,
            _anchorCharOffset,
          );

          final PageSlice leftPage;
          final PageSlice? rightPage;
          final int step;

          if (config.columnCount == 2) {
            final spreadIdx = activePageIndex >> 1;
            final leftIdx = spreadIdx * 2;
            leftPage = _pages[leftIdx];
            rightPage = leftIdx + 1 < _pages.length ? _pages[leftIdx + 1] : null;
            step = 2;
          } else {
            leftPage = _pages[activePageIndex];
            rightPage = null;
            step = 1;
          }

          return Column(
            children: [
              Expanded(
                child: CustomPaint(
                  size: size,
                  painter: ReaderPagePainter(
                    chapterText: widget.initialChapterText,
                    config: config,
                    metricsCache: _paginator.metricsFor(config),
                    leftPage: leftPage,
                    rightPage: rightPage,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: leftPage.pageIndex - step >= 0
                          ? () => setState(() {
                                _anchorCharOffset =
                                    _pages[leftPage.pageIndex - step].startCharOffset;
                              })
                          : null,
                      child: const Text('Prev'),
                    ),
                    Flexible(
                      child: Text(
                        'Page ${activePageIndex + 1}/${_pages.length} '
                        '(offset=$_anchorCharOffset, cols=${config.columnCount})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: (leftPage.pageIndex + step) < _pages.length
                          ? () => setState(() {
                                _anchorCharOffset =
                                    _pages[leftPage.pageIndex + step].startCharOffset;
                              })
                          : null,
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
