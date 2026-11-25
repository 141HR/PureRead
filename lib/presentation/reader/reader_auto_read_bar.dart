import 'package:flutter/material.dart';

import '../../application/reader/auto_read_state.dart';

/// Compact theme-aware floating bottom control bar for Auto-Read playback,
/// mode switching, speed adjustment, and stopping.
class ReaderAutoReadBar extends StatelessWidget {
  const ReaderAutoReadBar({
    super.key,
    required this.state,
    required this.onTogglePause,
    required this.onModeChanged,
    required this.onCurtainSecondsChanged,
    required this.onTurnSecondsChanged,
    required this.onStop,
    this.backgroundColor,
    this.textColor,
    this.accentColor,
    this.borderColor,
  });

  final AutoReadState state;
  final VoidCallback onTogglePause;
  final ValueChanged<AutoReadMode> onModeChanged;
  final ValueChanged<int> onCurtainSecondsChanged;
  final ValueChanged<int> onTurnSecondsChanged;
  final VoidCallback onStop;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? accentColor;
  final Color? borderColor;

  void _updateActiveSeconds(int nextSeconds) {
    if (state.mode == AutoReadMode.curtain) {
      onCurtainSecondsChanged(AutoReadState.clampCurtainSeconds(nextSeconds));
    } else {
      onTurnSecondsChanged(AutoReadState.clampTurnSeconds(nextSeconds));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!state.isActive || !state.showControls) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final surfaceColor = backgroundColor ?? colorScheme.surface.withAlpha(245);
    final fgColor = textColor ?? colorScheme.onSurface;
    final primaryColor = accentColor ?? colorScheme.primary;
    final outlineColor = borderColor ?? fgColor.withAlpha(38);

    final minSeconds = state.minActiveSeconds;
    final maxSeconds = state.maxActiveSeconds;
    final currentSeconds = state.activeSeconds.clamp(minSeconds, maxSeconds);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Material(
          key: const ValueKey<String>('auto_read_control_bar'),
          elevation: 8,
          shadowColor: Colors.black38,
          color: surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: outlineColor),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: state.isPaused ? '继续自动阅读' : '暂停自动阅读',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      padding: EdgeInsets.zero,
                      color: primaryColor,
                      onPressed: onTogglePause,
                      icon: Icon(
                        state.isPaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SegmentedButton<AutoReadMode>(
                          showSelectedIcon: false,
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            minimumSize: const WidgetStatePropertyAll<Size>(
                              Size(0, 34),
                            ),
                            padding:
                                const WidgetStatePropertyAll<EdgeInsets>(
                                  EdgeInsets.symmetric(horizontal: 10),
                                ),
                            textStyle: WidgetStatePropertyAll<TextStyle?>(
                              theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            foregroundColor:
                                WidgetStateProperty.resolveWith<Color?>((
                                  states,
                                ) {
                                  if (states.contains(WidgetState.selected)) {
                                    return primaryColor;
                                  }
                                  return fgColor.withAlpha(210);
                                }),
                            backgroundColor:
                                WidgetStateProperty.resolveWith<Color?>((
                                  states,
                                ) {
                                  if (states.contains(WidgetState.selected)) {
                                    return primaryColor.withAlpha(32);
                                  }
                                  return Colors.transparent;
                                }),
                            side: WidgetStatePropertyAll<BorderSide>(
                              BorderSide(color: outlineColor),
                            ),
                          ),
                          segments: const <ButtonSegment<AutoReadMode>>[
                            ButtonSegment<AutoReadMode>(
                              value: AutoReadMode.curtain,
                              label: Text(
                                '滚幕覆盖',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            ButtonSegment<AutoReadMode>(
                              value: AutoReadMode.timedTurn,
                              label: Text(
                                '定时翻页',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          selected: <AutoReadMode>{state.mode},
                          onSelectionChanged: (selected) {
                            if (selected.isNotEmpty) {
                              onModeChanged(selected.first);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: fgColor,
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: onStop,
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      label: const Text(
                        '停止',
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    IconButton(
                      tooltip: '减少每页秒数',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      color: fgColor,
                      onPressed: currentSeconds > minSeconds
                          ? () => _updateActiveSeconds(currentSeconds - 1)
                          : null,
                      icon: const Icon(Icons.remove_rounded, size: 18),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          activeTrackColor: primaryColor,
                          inactiveTrackColor: outlineColor,
                          thumbColor: primaryColor,
                          overlayColor: primaryColor.withAlpha(32),
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                        ),
                        child: Slider(
                          value: currentSeconds.toDouble(),
                          min: minSeconds.toDouble(),
                          max: maxSeconds.toDouble(),
                          divisions: maxSeconds - minSeconds,
                          onChanged: (value) =>
                              _updateActiveSeconds(value.round()),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '增加每页秒数',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      color: fgColor,
                      onPressed: currentSeconds < maxSeconds
                          ? () => _updateActiveSeconds(currentSeconds + 1)
                          : null,
                      icon: const Icon(Icons.add_rounded, size: 18),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 52,
                      child: Text(
                        '${currentSeconds}s/页',
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        softWrap: false,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: fgColor,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
