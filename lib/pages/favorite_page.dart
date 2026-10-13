import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../common/app_theme.dart';
import '../models/film_models.dart';
import '../utils/breakpoint.dart';
import '../utils/format_util.dart';
import '../utils/favorite_manager.dart';
import '../utils/server_config_manager.dart';
import '../utils/source_guard.dart';
import '../utils/nav_util.dart';
import '../components/page_header.dart';
import '../components/empty_state.dart';

/// 我的收藏，对齐 OHOS `FavoritePage.ets`
class FavoritePage extends StatefulWidget {
  const FavoritePage({super.key});

  @override
  State<FavoritePage> createState() => _FavoritePageState();
}

class _FavoritePageState extends State<FavoritePage> {
  List<FavoriteItem> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SourceGuard.onReconnect(_reload);
    FavoriteManager.onFavoriteChange(_reload);
    _reload();
  }

  @override
  void dispose() {
    SourceGuard.offReconnect(_reload);
    FavoriteManager.offFavoriteChange(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await FavoriteManager.list();
    if (mounted) {
      setState(() {
        _list = list;
        _loading = false;
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        title: const Text('清空收藏', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: const Text('确定清空当前服务端的所有收藏记录吗？', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('取消', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await FavoriteManager.clear();
              await _reload();
              _toast('已清空收藏');
            },
            child: const Text('清空', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _subInfo(FavoriteItem item) {
    final parts = <String>[];
    if (item.cName.isNotEmpty) parts.add(item.cName);
    if (item.year.isNotEmpty) parts.add(item.year);
    if (item.area.isNotEmpty) parts.add(item.area);
    if (parts.isNotEmpty) return parts.join(' · ');
    return item.subTitle.isNotEmpty ? item.subTitle : '未知';
  }

  Widget _poster(FavoriteItem item) {
    final url = ServerConfigManager.instance.resolveMediaUrl(item.picture);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: SizedBox(
        width: 80,
        height: 116,
        child: url.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url,
                httpHeaders: FormatUtil.imageHeaders(url),
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => const ColoredBox(color: AppTheme.bgElevated),
              )
            : const ColoredBox(color: AppTheme.bgElevated),
      ),
    );
  }

  Widget _itemCard(FavoriteItem item) {
    return Dismissible(
      key: ValueKey('fav_${item.id}_${item.createdAt}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.danger,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 20),
            SizedBox(height: 4),
            Text('删除', style: TextStyle(fontSize: 12, color: Colors.white)),
          ],
        ),
      ),
      onDismissed: (_) async {
        await FavoriteManager.remove(item.id);
        _toast('已取消收藏');
      },
      child: Material(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: InkWell(
          onTap: () {
            NavUtil.openPlay(context, item.id, title: item.name).then((_) => _reload());
          },
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _poster(item),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 116,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _subInfo(item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                            if (item.remarks.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                item.remarks,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: AppTheme.accent),
                              ),
                            ],
                          ],
                        ),
                        Row(
                          children: [
                            const Icon(Icons.access_time_filled_rounded, size: 11, color: AppTheme.textMuted),
                            const SizedBox(width: 4),
                            Text(
                              '收藏于 ${FormatUtil.dateTime(item.createdAt)}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lanes = Breakpoint.listLanesOf(MediaQuery.sizeOf(context).width);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            PageHeader(
              title: '我的收藏',
              rightText: _list.isNotEmpty ? '清空' : '',
              rightTextColor: AppTheme.danger,
              onRight: _confirmClear,
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                  : RefreshIndicator(
                      onRefresh: _reload,
                      color: AppTheme.accent,
                      backgroundColor: AppTheme.bgCard,
                      child: _list.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 48),
                                EmptyState(
                                  title: '暂无收藏',
                                  subtitle: '在播放页点击收藏后会显示在这里',
                                  icon: Icons.star_rounded,
                                ),
                              ],
                            )
                          : GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: lanes,
                                mainAxisExtent: 140,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: _list.length,
                              itemBuilder: (context, index) => _itemCard(_list[index]),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
