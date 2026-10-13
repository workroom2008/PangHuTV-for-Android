import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../common/app_theme.dart';
import '../models/film_models.dart';
import '../utils/format_util.dart';
import '../utils/history_manager.dart';
import '../utils/server_config_manager.dart';
import '../utils/source_guard.dart';
import '../utils/nav_util.dart';
import '../components/page_header.dart';
import '../components/empty_state.dart';

/// 观看历史页面
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HistoryItem> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SourceGuard.onReconnect(_onReconnect);
    _reload();
  }

  @override
  void dispose() {
    SourceGuard.offReconnect(_onReconnect);
    super.dispose();
  }

  void _onReconnect() {
    _reload();
  }

  Future<void> _reload() async {
    final list = await HistoryManager.list();
    if (mounted) {
      setState(() {
        _list = list;
        _loading = false;
      });
    }
  }

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        title: const Text('清空观看历史', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: const Text('确定删除当前服务端的全部观看记录吗？', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('取消', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await HistoryManager.clear();
              await _reload();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已清空观看历史')),
                );
              }
            },
            child: const Text('清空', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(HistoryItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        title: const Text('删除记录', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text('确定删除「${item.name}」吗？', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              HistoryManager.remove(item.id).then((_) => _reload());
            },
            child: const Text('删除', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openPlay(HistoryItem item) {
    NavUtil.openPlay(
      context,
      item.id,
      sourceId: item.sourceId,
      episodeIndex: item.episodeIndex,
      currentTime: item.currentTime,
      title: item.name,
    ).then((_) => _reload());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            PageHeader(
              title: '观看历史',
              rightText: _list.isNotEmpty ? '清空' : '',
              rightTextColor: AppTheme.danger,
              onRight: _confirmClear,
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                  : _list.isEmpty
                      ? const EmptyState(
                          title: '暂无观看记录',
                          subtitle: '播放影片后会显示在这里',
                          icon: Icons.history_rounded,
                        )
                      : RefreshIndicator(
                          onRefresh: _reload,
                          color: AppTheme.accent,
                          backgroundColor: AppTheme.bgCard,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceLg, vertical: 8),
                            itemCount: _list.length,
                            itemBuilder: (context, index) {
                              final item = _list[index];
                              final posterUrl = ServerConfigManager.instance.resolveMediaUrl(item.picture);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.bgCard,
                                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Poster
                                    GestureDetector(
                                      onTap: () => _openPlay(item),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                                        child: SizedBox(
                                          width: 80,
                                          height: 116,
                                          child: posterUrl.isNotEmpty
                                              ? CachedNetworkImage(
                                                  imageUrl: posterUrl,
                                                  httpHeaders: FormatUtil.imageHeaders(posterUrl),
                                                  fit: BoxFit.cover,
                                                  errorWidget: (context, url, error) => _buildPosterPlaceholder(item.name),
                                                )
                                              : _buildPosterPlaceholder(item.name),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: AppTheme.spaceMd),

                                    // Info
                                    Expanded(
                                      child: SizedBox(
                                        height: 116,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            GestureDetector(
                                              onTap: () => _openPlay(item),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    item.name,
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppTheme.textPrimary,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '${item.sourceName} · ${item.episode}',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: AppTheme.textSecondary,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.access_time_rounded, size: 11, color: AppTheme.textMuted),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        FormatUtil.dateTime(item.timeStamp),
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: AppTheme.textMuted,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Progress & Delete
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: GestureDetector(
                                                    onTap: () => _openPlay(item),
                                                    child: Text(
                                                      FormatUtil.progress(item.currentTime, item.duration),
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                        color: AppTheme.accent,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                                InkWell(
                                                  onTap: () => _confirmDelete(item),
                                                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: AppTheme.dangerSoft,
                                                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                                                    ),
                                                    child: const Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.delete_outline_rounded, size: 12, color: AppTheme.danger),
                                                        SizedBox(width: 2),
                                                        Text(
                                                          '删除',
                                                          style: TextStyle(fontSize: 11, color: AppTheme.danger),
                                                        ),
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
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPosterPlaceholder(String name) {
    return Container(
      color: AppTheme.bgElevated,
      child: Center(
        child: Text(
          name.isNotEmpty ? name.substring(0, 1) : '影',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}
