import 'package:flutter/material.dart';
import '../common/app_theme.dart';
import '../models/film_models.dart';
import '../utils/breakpoint.dart';
import '../utils/format_util.dart';
import 'search_result_item.dart';
import 'empty_state.dart';

/// 搜索结果列表与底部加载指示器，对齐 OHOS `SearchResultList.ets`
class SearchResultList extends StatelessWidget {
  final List<MovieBasicInfo> list;
  final PageInfo page;
  final bool loadingMore;
  final String sourceError;
  final String submitted;
  final String sourceId;
  final ScrollController scrollController;
  final String? anchorFilmId;
  final void Function(MovieBasicInfo film)? onFilmTap;
  final Future<void> Function() onRefresh;

  const SearchResultList({
    super.key,
    required this.list,
    required this.page,
    required this.loadingMore,
    required this.sourceError,
    required this.submitted,
    this.sourceId = '',
    required this.scrollController,
    this.anchorFilmId,
    this.onFilmTap,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) {
      final hasError = sourceError.isNotEmpty;
      return RefreshIndicator(
        onRefresh: onRefresh,
        color: AppTheme.accent,
        backgroundColor: AppTheme.bgCard,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.only(top: 80, bottom: 40),
            child: EmptyState(
              title: hasError ? '该采集源搜索失败' : '未找到相关影片',
              subtitle: hasError
                  ? sourceError
                  : '未找到与「$submitted」相关的影片\n建议缩短或更换搜索词，也可以尝试切换其他采集源',
              icon: hasError ? Icons.error_outline_rounded : Icons.search_off_rounded,
            ),
          ),
        ),
      );
    }

    final lanes = Breakpoint.listLanesOf(MediaQuery.sizeOf(context).width);

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppTheme.accent,
      backgroundColor: AppTheme.bgCard,
      child: CustomScrollView(
        key: PageStorageKey<String>('search_list_${submitted}_$sourceId'),
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppTheme.spaceLg, 8, AppTheme.spaceLg, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                '共 ${page.total} 部与「$submitted」相关',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ),
          ),
          if (lanes <= 1)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceLg),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final film = list[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SearchResultItem(
                        film: film,
                        highlighted: anchorFilmId != null && FormatUtil.filmId(film) == anchorFilmId,
                        onSelect: onFilmTap,
                      ),
                    );
                  },
                  childCount: list.length,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceLg),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: lanes,
                  mainAxisExtent: 168,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 8,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final film = list[index];
                    return SearchResultItem(
                      film: film,
                      highlighted: anchorFilmId != null && FormatUtil.filmId(film) == anchorFilmId,
                      onSelect: onFilmTap,
                    );
                  },
                  childCount: list.length,
                ),
              ),
            ),
          // 底部上滑加载指示器与到底提示，对齐 OHOS SearchResultList.ets:73-80
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              height: 52,
              alignment: Alignment.center,
              child: loadingMore
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.accent,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          '正在加载更多...',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    )
                  : (page.current >= page.pageCount && list.isNotEmpty
                      ? const Text(
                          '没有更多了',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        )
                      : const SizedBox.shrink()),
            ),
          ),
        ],
      ),
    );
  }
}
