import 'dart:async';
import 'package:flutter/material.dart';
import '../../api/download_api.dart';
import '../../common/app_theme.dart';
import '../../models/download_models.dart';
import '../../services/auth_session.dart';
import '../../services/front_download_service.dart';

/// 播放页「下载当前集」，对齐 Web 播放页 download 行。
class PlayDownloadRow extends StatefulWidget {
  final String filmId;
  final int episodeNo;

  const PlayDownloadRow({
    super.key,
    required this.filmId,
    required this.episodeNo,
  });

  @override
  State<PlayDownloadRow> createState() => _PlayDownloadRowState();
}

class _PlayDownloadRowState extends State<PlayDownloadRow> {
  bool _submitting = false;
  String _statusText = '';
  String _myTaskStatus = '';
  Timer? _pollTimer;

  bool get _downloadEnabled => FrontDownloadService.instance.enabled;

  @override
  void initState() {
    super.initState();
    FrontDownloadService.instance.addListener(_onSwitchChanged);
    _refreshTask();
  }

  @override
  void didUpdateWidget(covariant PlayDownloadRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filmId != widget.filmId || oldWidget.episodeNo != widget.episodeNo) {
      _refreshTask();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    FrontDownloadService.instance.removeListener(_onSwitchChanged);
    super.dispose();
  }

  void _onSwitchChanged() {
    if (mounted) {
      setState(() {});
      _refreshTask();
    }
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    if (!_downloadEnabled || !AuthSession.instance.isLoggedIn) return;
    if (!downloadActiveStatuses.contains(_myTaskStatus)) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshTask());
  }

  Future<void> _refreshTask() async {
    if (!mounted || !_downloadEnabled || !isDownloadableFilmId(widget.filmId)) {
      if (mounted) {
        setState(() {
          _statusText = '';
          _myTaskStatus = '';
        });
      }
      _pollTimer?.cancel();
      return;
    }
    if (!AuthSession.instance.isLoggedIn) {
      if (mounted) {
        setState(() {
          _myTaskStatus = '';
          if (_statusText != '已提交') _statusText = '';
        });
      }
      return;
    }
    try {
      final tasks = await DownloadApi.listMyTasks(mid: widget.filmId, limit: 20);
      if (!mounted) return;
      DownloadTaskItem? matched;
      for (final t in tasks) {
        if (t.episode == widget.episodeNo) {
          matched = t;
          break;
        }
      }
      matched ??= tasks.isNotEmpty ? tasks.first : null;
      if (matched == null || matched.status.isEmpty) {
        setState(() {
          _myTaskStatus = '';
          _statusText = '';
        });
        _pollTimer?.cancel();
        return;
      }
      setState(() {
        _myTaskStatus = matched!.status;
        _statusText = downloadStatusText(matched);
      });
      _schedulePoll();
    } catch (_) {
      if (mounted) {
        setState(() {
          _myTaskStatus = '';
          _statusText = '';
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_downloadEnabled) {
      _toast('请先在后台「系统设置 → 下载整理」开启总开关');
      return;
    }
    if (!isDownloadableFilmId(widget.filmId)) return;
    setState(() => _submitting = true);
    try {
      final res = await DownloadApi.submitTask(
        mid: widget.filmId,
        episode: widget.episodeNo,
      );
      if (!mounted) return;
      if (res.code == 0) {
        _toast(res.msg.isNotEmpty ? res.msg : '下载任务已提交');
        if (AuthSession.instance.isLoggedIn) {
          await _refreshTask();
        } else {
          setState(() => _statusText = '已提交');
        }
      } else {
        _toast(res.msg.isNotEmpty ? res.msg : '提交失败');
      }
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String msg) {
    if (!mounted || msg.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (!isDownloadableFilmId(widget.filmId)) {
      return const SizedBox.shrink();
    }

    final hint = !_downloadEnabled
        ? '后台未开启下载总开关'
        : (_statusText.isNotEmpty ? _statusText : '');

    return Material(
      color: AppTheme.bgElevated,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            TextButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined, size: 20),
              label: Text(_submitting ? '提交中...' : '下载当前集'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
            if (hint.isNotEmpty)
              Expanded(
                child: Text(
                  hint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
