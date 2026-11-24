import '../../domain/domain.dart';

/// Built-in demo book and chapters used exclusively when opening `/reader/demo`
/// with no `'demo'` entry persisted in [BookRepository].
abstract final class DemoBookContent {
  static Book buildDemoBook() {
    final now = DateTime.utc(2026, 11, 24);
    return Book(
      id: 'demo',
      providerType: ProviderType.localTxt,
      title: '阅读器 (demo)',
      author: 'PureRead 净读',
      intro: 'PureRead 双端自适应阅读排版预览样本，演示 charOffset 锚点、中文避头尾禁则与单/双栏自适应排版。',
      totalChapters: chapters.length,
      lastChapterTitle: chapters.first.title,
      createdAt: now,
      updatedAt: now,
    );
  }

  static final List<ChapterMeta> chapters = <ChapterMeta>[
    ChapterMeta(
      bookId: 'demo',
      chapterIndex: 0,
      title: '第一章 净读初见：基于 charOffset 的排版引擎',
      wordCount: 980,
      updatedAt: DateTime.utc(2026, 11, 24),
    ),
    ChapterMeta(
      bookId: 'demo',
      chapterIndex: 1,
      title: '第二章 双栏流韵：桌面宽屏与移动沉浸体验',
      wordCount: 920,
      updatedAt: DateTime.utc(2026, 11, 24),
    ),
  ];

  static String chapterText(int chapterIndex) {
    if (chapterIndex == 1) {
      return _chapter2;
    }
    return _chapter1;
  }

  static const String _chapter1 = '''第一章 净读初见：基于 charOffset 的排版引擎
夜雨微凉，桌面台灯洒下一圈柔和的暖光。PureRead（净读）以纯本地极致阅读体验为核心，摒弃一切冗杂干扰，让文字回归纸面般的安静与克制。
传统阅读器往往依赖脆弱的固定页码记录进度：一旦你放大字号、调节行距，或者在 Windows 宽屏桌面与 Android 手机之间拖拽缩放窗口，原本正在读的那一段就会悄然漂移，甚至出现丢字或重字。
PureRead 在领域层引入了唯一的真实进度锚点——ReadingAnchor（chapterIndex + charOffset）。无论页面如何重新排版、从单栏居中切换为双栏仿真书页（P2k 与 P2k+1），系统始终锁定你当前视线起始处的精确字符偏移量，实现零丢字、零重字的丝滑重锚。
在中文排版细节上，引擎原生支持行尾标点避头尾禁则（如逗号、句号、感叹号、右书名号《》」不孤立出现在行首或行尾），同时在中英文与数字（如 Flutter 3.47 与 UTF-8 编码）混排边界自动插入 0.2em 呼吸微距，让长篇小说与技术读物都赏心悦目。
你可以尝试点击画面中央呼出控制栏，切换「米白护眼」「羊皮纸感」「静谧暗灰」「OLED 纯黑」主题，或拖动阅读进度条后点击「撤回跳转」一键回到原位。''';

  static const String _chapter2 = '''第二章 双栏流韵：桌面宽屏与移动沉浸体验
当窗口宽度达到 840px 以上时，PureRead 的逻辑单页复用模型会自动将单页切片序列 [P0, P1, P2, ...] 配对铺展为左右双栏仿真书页，如同一本摊开的精装实体书。
左栏读毕，视线自然顺延至右栏首字；按下键盘方向键、Space、PageDown，或轻拨鼠标滚轮，即可成对翻页；按 F11 可一键进入无边框全屏沉浸模式，按 Ctrl+H 则可立即触发老板键最小化隐藏。
而在 Android 移动端单手阅读场景下，你可以自由切换「无动画」「左右平移」「覆盖翻页」与「上下连续滚动」四种翻页模式，并在阅读设置中开启音量键翻页与屏幕常亮。
若想读本地长篇 TXT，回到书架点击「导入本地 TXT」，即可体验后台 Isolate 毫秒级编码探测与流式分章。祝你在 PureRead 中享有一段专注而纯粹的阅读时光！''';
}
