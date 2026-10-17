import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../common/app_theme.dart';
import '../models/film_models.dart';
import '../utils/format_util.dart';
import '../utils/nav_util.dart';
import '../utils/server_config_manager.dart';
import '../utils/favorite_manager.dart';

/// 搜索结果横向图文卡片组件
class SearchResultItem extends StatelessWidget {
  final MovieBasicInfo film;
  final void Function(MovieBasicInfo film)? onSelect;
  final bool highlighted;

  const SearchResultItem({
    super.key,
    required this.film,
    this.onSelect,
    this.highlighted = false,
  });

  String _resolvedPosterUrl() {
    final raw = FormatUtil.poster(film);
    return ServerConfigManager.instance.resolveMediaUrl(raw);
  }

  void _handleClick(BuildContext context) {
    if (onSelect != null) {
      onSelect!(film);
      return;
    }
    final filmId = FormatUtil.filmId(film);
    NavUtil.openPlay(
      context,
      filmId,
      sourceId: film.sourceId,
      sourceMid: film.sourceMid > 0 ? '${film.sourceMid}' : '',
      title: film.name,
    );
  }

  Widget _buildFavoriteTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xE60A0B10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0x66FA8C16), width: 0.5),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_rounded,
            size: 10,
            color: Color(0xFFFA8C16),
          ),
          SizedBox(width: 2),
          Text(
            '已收藏',
            style: TextStyle(
              fontSize: 9,
              color: Color(0xFFFA8C16),
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final posterUrl = _resolvedPosterUrl();

    return InkWell(
      onTap: () => _handleClick(context),
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        decoration: highlighted
            ? BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.45)),
              )
            : null,
        padding: EdgeInsets.symmetric(vertical: 6, horizontal: highlighted ? 6 : 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              child: SizedBox(
                width: 86,
                height: 128,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (posterUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: posterUrl,
                        httpHeaders: FormatUtil.imageHeaders(posterUrl),
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: AppTheme.bgCard),
                        errorWidget: (context, url, error) => _buildPlaceholder(),
                      )
                    else
                      _buildPlaceholder(),
                    Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0x8C000000),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      left: 4,
                      child: ValueListenableBuilder<int>(
                        valueListenable: FavoriteManager.favoriteVersion,
                        builder: (context, _, child) {
                          final isFav = FavoriteManager.isFavoriteSync(FormatUtil.filmId(film));
                          if (!isFav) return const SizedBox.shrink();
                          return _buildFavoriteTag();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spaceMd),
            Expanded(
              child: ClipRect(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      film.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      FormatUtil.joinMeta([film.cName, film.year, film.area, film.remarks]),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '导演 ${film.director.isNotEmpty ? film.director : '未知'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '主演 ${film.actor.isNotEmpty ? film.actor : '未知'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      film.blurb.isNotEmpty ? film.blurb : '暂无简介',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppTheme.bgCard,
      child: Center(
        child: Text(
          film.name.isNotEmpty ? film.name.substring(0, 1) : '影',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
