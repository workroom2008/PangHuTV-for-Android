import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../../common/app_theme.dart';

/// 音轨选择底栏弹窗（结构对齐 PlayerSpeedSheet）。
///
/// 只在 multiAudio=true 时由播放器调起；单轨源不显示入口按钮，
/// 因为这类源选轨没有意义，加了反而让人以为还有别的轨。
class PlayerTrackSheet extends StatelessWidget {
  final List<AudioTrack> tracks;
  final String currentId;
  final String Function(AudioTrack) labelOf;
  final ValueChanged<String> onSelectTrack;

  const PlayerTrackSheet({
    super.key,
    required this.tracks,
    required this.currentId,
    required this.labelOf,
    required this.onSelectTrack,
  });

  static void show(
    BuildContext context,
    List<AudioTrack> tracks,
    String currentId,
    String Function(AudioTrack) labelOf,
    ValueChanged<String> onSelectTrack,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (context) => PlayerTrackSheet(
        tracks: tracks,
        currentId: currentId,
        labelOf: labelOf,
        onSelectTrack: onSelectTrack,
      ),
    );
  }

  /// 次级信息：语言 / 编码 / 声道，拼成一行灰字。
  String _subtitleOf(AudioTrack t) {
    final parts = <String>[];
    final lang = (t.language ?? '').trim();
    if (lang.isNotEmpty && lang != 'und') parts.add(lang);
    final codec = (t.codec ?? '').trim();
    if (codec.isNotEmpty) parts.add(codec.toUpperCase());
    final channels = (t.channels ?? '').trim();
    if (channels.isNotEmpty) parts.add(channels);
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final landscape = media.size.height > 0 && media.size.height < 500;
    final maxHeight = media.size.height * 0.88;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: landscape ? AppTheme.spaceSm : AppTheme.spaceMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: landscape ? 4 : 8),
                child: const Text(
                  '音轨',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              const Divider(color: AppTheme.border),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: tracks.map((track) {
                      final active = track.id == currentId;
                      final sub = _subtitleOf(track);
                      return ListTile(
                        dense: landscape,
                        visualDensity: landscape ? VisualDensity.compact : VisualDensity.standard,
                        title: Text(
                          labelOf(track),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: active ? FontWeight.bold : FontWeight.normal,
                            color: active ? AppTheme.accent : AppTheme.textSecondary,
                          ),
                        ),
                        subtitle: sub.isEmpty
                            ? null
                            : Text(
                                sub,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                              ),
                        onTap: () {
                          onSelectTrack(track.id);
                          Navigator.pop(context);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
