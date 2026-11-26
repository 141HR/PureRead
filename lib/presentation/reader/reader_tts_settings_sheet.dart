import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/reader/tts_controller.dart';
import '../../application/reader/tts_state.dart';
import '../../infrastructure/tts/tts.dart';
import 'reader_tts_bar.dart';

/// Modal bottom sheet for configuring TTS speech rate, pitch, sleep timer,
/// native TTS engine, and filterable voice selection.
class ReaderTtsSettingsSheet extends StatefulWidget {
  const ReaderTtsSettingsSheet({
    super.key,
    required this.state,
    required this.onSpeechRateChanged,
    required this.onPitchChanged,
    required this.onSelectEngine,
    required this.onSelectVoice,
    required this.onSelectSleepTimer,
  });

  final TtsState state;
  final ValueChanged<double> onSpeechRateChanged;
  final ValueChanged<double> onPitchChanged;
  final ValueChanged<String> onSelectEngine;
  final ValueChanged<String> onSelectVoice;
  final ValueChanged<TtsSleepTimerMode> onSelectSleepTimer;

  /// Opens [ReaderTtsSettingsSheet] wired to [ttsControllerProvider].
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => Consumer(
        builder: (sheetContext, ref, _) {
          final state = ref.watch(ttsControllerProvider);
          final controller = ref.read(ttsControllerProvider.notifier);
          return ReaderTtsSettingsSheet(
            state: state,
            onSpeechRateChanged: controller.setSpeechRate,
            onPitchChanged: controller.setPitch,
            onSelectEngine: controller.setEngine,
            onSelectVoice: controller.setVoice,
            onSelectSleepTimer: controller.setSleepTimer,
          );
        },
      ),
    );
  }

  @override
  State<ReaderTtsSettingsSheet> createState() => _ReaderTtsSettingsSheetState();
}

class _ReaderTtsSettingsSheetState extends State<ReaderTtsSettingsSheet> {
  final TextEditingController _voiceFilterController = TextEditingController();
  String _voiceFilter = '';

  @override
  void dispose() {
    _voiceFilterController.dispose();
    super.dispose();
  }

  List<TtsVoiceInfo> _filteredVoices() {
    final sorted = TtsController.sortVoicesZhFirst(widget.state.voices);
    final query = _voiceFilter.trim().toLowerCase();
    if (query.isEmpty) return sorted;
    return sorted
        .where(
          (v) =>
              v.name.toLowerCase().contains(query) ||
              v.locale.toLowerCase().contains(query) ||
              v.id.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final filteredVoices = _filteredVoices();
    final sleepBadge = ReaderTtsBar.formatSleepBadge(state);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.record_voice_over_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '朗读设置',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildSliderRow(
                context,
                label: '语速',
                valueText: ReaderTtsBar.formatSpeechRate(state.speechRate),
                value: state.speechRate.clamp(
                  TtsState.minSpeechRate,
                  TtsState.maxSpeechRate,
                ),
                min: TtsState.minSpeechRate,
                max: TtsState.maxSpeechRate,
                divisions: 20,
                onChanged: (v) => widget.onSpeechRateChanged(
                  double.parse(v.toStringAsFixed(2)),
                ),
              ),
              _buildSliderRow(
                context,
                label: '音调',
                valueText: state.pitch.toStringAsFixed(2),
                value: state.pitch.clamp(TtsState.minPitch, TtsState.maxPitch),
                min: TtsState.minPitch,
                max: TtsState.maxPitch,
                divisions: 15,
                onChanged: (v) =>
                    widget.onPitchChanged(double.parse(v.toStringAsFixed(2))),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('定时关闭', style: theme.textTheme.labelLarge),
                  if (sleepBadge != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      sleepBadge,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in TtsSleepTimerMode.values)
                    ChoiceChip(
                      label: Text(mode.label),
                      selected: state.sleepTimerMode == mode,
                      onSelected: (_) => widget.onSelectSleepTimer(mode),
                    ),
                ],
              ),
              if (state.engines.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('朗读引擎', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final engine in state.engines)
                      ChoiceChip(
                        label: Text(
                          engine.isDefault
                              ? '${engine.label} (默认)'
                              : engine.label,
                        ),
                        selected: state.engineId == engine.id,
                        onSelected: (_) => widget.onSelectEngine(engine.id),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text('发音人', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              if (state.voices.isNotEmpty) ...[
                TextField(
                  controller: _voiceFilterController,
                  decoration: InputDecoration(
                    hintText: '搜索发音人或语言 (如 zh / en)...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _voiceFilter.isNotEmpty
                        ? IconButton(
                            tooltip: '清空',
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _voiceFilterController.clear();
                              setState(() => _voiceFilter = '');
                            },
                          )
                        : null,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _voiceFilter = value),
                ),
                const SizedBox(height: 8),
              ],
              _buildVoiceList(context, theme, state, filteredVoices),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceList(
    BuildContext context,
    ThemeData theme,
    TtsState state,
    List<TtsVoiceInfo> voices,
  ) {
    if (state.voices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '当前引擎未提供可选发音人，将使用系统默认语音',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (voices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '未找到匹配“$_voiceFilter”的发音人',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: voices.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final voice = voices[index];
            final selected = state.voiceId == voice.id;
            return ListTile(
              dense: true,
              selected: selected,
              title: Text(
                voice.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: voice.locale.isNotEmpty
                  ? Text(
                      voice.locale,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
              trailing: selected
                  ? Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    )
                  : null,
              onTap: () => widget.onSelectVoice(voice.id),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSliderRow(
    BuildContext context, {
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            valueText,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
