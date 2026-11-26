import 'package:flutter/material.dart';

import '../../application/reader/tts_state.dart';
import '../../domain/domain.dart';

/// Floating, reader-theme-aware bottom TTS playback bar supporting collapsed
/// pill mode, expanded playback controls, detached browsing (`回到朗读处`)
/// jump-back chip, sleep countdown badge, and narrow 360dp layouts.
class ReaderTtsBar extends StatelessWidget {
  const ReaderTtsBar({
    super.key,
    required this.state,
    this.readerTheme,
    required this.onTogglePlayPause,
    required this.onPrevSentence,
    required this.onNextSentence,
    required this.onOpenSettings,
    required this.onStop,
    this.onJumpBack,
    this.onToggleCollapse,
    this.onSpeedTap,
  });

  final TtsState state;
  final ReaderTheme? readerTheme;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onPrevSentence;
  final VoidCallback onNextSentence;
  final VoidCallback onOpenSettings;
  final VoidCallback onStop;
  final VoidCallback? onJumpBack;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onSpeedTap;

  static String formatSpeechRate(double rate) {
    final scaled = rate * 10;
    if ((scaled.roundToDouble() - scaled).abs() < 0.001) {
      return '${rate.toStringAsFixed(1)}x';
    }
    return '${rate.toStringAsFixed(2)}x';
  }

  static String? formatSleepBadge(TtsState state) {
    final remaining = state.sleepRemainingSeconds;
    if (remaining != null) {
      final mins = (remaining ~/ 60).toString().padLeft(2, '0');
      final secs = (remaining % 60).toString().padLeft(2, '0');
      return '$mins:$secs';
    }
    if (state.sleepTimerMode == TtsSleepTimerMode.endOfChapter) {
      return '本章后停';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (state.status == TtsStatus.idle) {
      return const SizedBox.shrink();
    }

    final palette = _resolvePalette(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: state.isBarCollapsed
                ? _buildCollapsedPill(context, palette)
                : _buildExpandedCard(context, palette),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedPill(BuildContext context, _TtsBarPalette palette) {
    final sleepBadge = formatSleepBadge(state);
    final statusLabel = switch (state.status) {
      TtsStatus.playing => '朗读中',
      TtsStatus.paused => '已暂停',
      TtsStatus.loading => '加载中',
      TtsStatus.error => '朗读异常',
      TtsStatus.idle => '',
    };

    return Material(
      elevation: 6,
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: state.isPlaying ? '暂停朗读' : '继续朗读',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
              padding: EdgeInsets.zero,
              color: palette.accent,
              onPressed: state.status == TtsStatus.loading
                  ? null
                  : onTogglePlayPause,
              icon: Icon(
                state.isPlaying
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_filled_rounded,
                size: 26,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                sleepBadge != null ? '$statusLabel · $sleepBadge' : statusLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.primaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (state.isDetached) ...[
              const SizedBox(width: 8),
              ActionChip(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                avatar: Icon(Icons.my_location, size: 15, color: palette.accent),
                label: Text(
                  '回到朗读处',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.accent,
                  ),
                ),
                backgroundColor: palette.accentTint,
                side: BorderSide(color: palette.accent.withAlpha(90)),
                onPressed: onJumpBack,
              ),
            ],
            if (onToggleCollapse != null)
              IconButton(
                tooltip: '展开朗读控制栏',
                visualDensity: VisualDensity.compact,
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 32),
                padding: EdgeInsets.zero,
                color: palette.secondaryText,
                onPressed: onToggleCollapse,
                icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
              ),
            IconButton(
              tooltip: '停止朗读',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
              color: palette.secondaryText,
              onPressed: onStop,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedCard(BuildContext context, _TtsBarPalette palette) {
    final sleepBadge = formatSleepBadge(state);
    final total = state.utterances.length;
    final current = total > 0
        ? (state.currentUtteranceIndex + 1).clamp(1, total)
        : 0;
    final chapterTitle = state.speakingChapterTitle.isNotEmpty
        ? state.speakingChapterTitle
        : (state.bookTitle ?? '正在朗读');
    final progressLabel =
        total > 0 ? '$chapterTitle · $current/$total句' : chapterTitle;

    return Material(
      elevation: 8,
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.isDetached) ...[
              _buildDetachedBanner(palette),
              const SizedBox(height: 6),
            ],
            if (state.status == TtsStatus.error &&
                state.errorMessage != null &&
                state.errorMessage!.isNotEmpty) ...[
              Text(
                state.errorMessage!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                Icon(
                  Icons.record_voice_over_outlined,
                  size: 15,
                  color: palette.secondaryText,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    progressLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.secondaryText,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (sleepBadge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: palette.accentTint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      sleepBadge,
                      style: TextStyle(
                        color: palette.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (onToggleCollapse != null)
                  IconButton(
                    tooltip: '收起朗读控制栏',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 28,
                    ),
                    padding: EdgeInsets.zero,
                    color: palette.secondaryText,
                    onPressed: onToggleCollapse,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSpeedPill(palette),
                IconButton(
                  tooltip: '上一句',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 38,
                    height: 38,
                  ),
                  padding: EdgeInsets.zero,
                  color: palette.primaryText,
                  onPressed: onPrevSentence,
                  icon: const Icon(Icons.skip_previous_rounded, size: 24),
                ),
                _buildPlayPauseButton(context, palette),
                IconButton(
                  tooltip: '下一句',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 38,
                    height: 38,
                  ),
                  padding: EdgeInsets.zero,
                  color: palette.primaryText,
                  onPressed: onNextSentence,
                  icon: const Icon(Icons.skip_next_rounded, size: 24),
                ),
                IconButton(
                  tooltip: '朗读设置',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 38,
                    height: 38,
                  ),
                  padding: EdgeInsets.zero,
                  color: palette.primaryText,
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.tune_rounded, size: 20),
                ),
                IconButton(
                  tooltip: '停止朗读',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 38,
                    height: 38,
                  ),
                  padding: EdgeInsets.zero,
                  color: palette.secondaryText,
                  onPressed: onStop,
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetachedBanner(_TtsBarPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.accentTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.accent.withAlpha(70)),
      ),
      child: Row(
        children: [
          Icon(Icons.explore_outlined, size: 16, color: palette.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '已脱离朗读位置',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.primaryText,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onJumpBack,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: palette.accent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.my_location,
                    size: 13,
                    color: palette.onAccent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '回到朗读处',
                    style: TextStyle(
                      color: palette.onAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedPill(_TtsBarPalette palette) {
    return Tooltip(
      message: '语速',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onSpeedTap ?? onOpenSettings,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: Text(
            formatSpeechRate(state.speechRate),
            style: TextStyle(
              color: palette.primaryText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayPauseButton(BuildContext context, _TtsBarPalette palette) {
    if (state.status == TtsStatus.loading) {
      return SizedBox(
        width: 42,
        height: 42,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: palette.accent,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 42,
      height: 42,
      child: Material(
        color: palette.accent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTogglePlayPause,
          child: Tooltip(
            message: state.isPlaying ? '暂停' : '继续',
            child: Icon(
              state.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: palette.onAccent,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }

  _TtsBarPalette _resolvePalette(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = readerTheme;
    if (theme == null) {
      return _TtsBarPalette(
        surface: scheme.surfaceContainerHigh.withAlpha(246),
        border: scheme.outlineVariant,
        primaryText: scheme.onSurface,
        secondaryText: scheme.onSurfaceVariant,
        accent: scheme.primary,
        onAccent: scheme.onPrimary,
        accentTint: scheme.primaryContainer.withAlpha(150),
      );
    }

    final bg = Color(theme.bgColor);
    final fg = Color(theme.textColor);
    final secondary = Color(theme.secondaryTextColor);
    final surface = theme.isDark
        ? Color.alphaBlend(Colors.white.withAlpha(20), bg)
        : Color.alphaBlend(Colors.black.withAlpha(10), bg);
    final border = theme.isDark
        ? Colors.white.withAlpha(36)
        : Colors.black.withAlpha(28);

    return _TtsBarPalette(
      surface: surface.withAlpha(248),
      border: border,
      primaryText: fg,
      secondaryText: secondary,
      accent: scheme.primary,
      onAccent: scheme.onPrimary,
      accentTint: scheme.primary.withAlpha(theme.isDark ? 48 : 28),
    );
  }
}

class _TtsBarPalette {
  const _TtsBarPalette({
    required this.surface,
    required this.border,
    required this.primaryText,
    required this.secondaryText,
    required this.accent,
    required this.onAccent,
    required this.accentTint,
  });

  final Color surface;
  final Color border;
  final Color primaryText;
  final Color secondaryText;
  final Color accent;
  final Color onAccent;
  final Color accentTint;
}
