import 'package:flutter/material.dart';
import '../common/app_theme.dart';
import '../models/film_models.dart';
import '../utils/breakpoint.dart';
import 'film_card.dart';

/// 首页分类横向影片展示行
class FilmRow extends StatelessWidget {
  final String title;
  final List<MovieBasicInfo> films;
  final String moreText;
  final int pid;
  final int? maxItems;
  final List<CategoryItem> subCategories;
  final VoidCallback? onMore;
  final void Function(int categoryId)? onSubCategory;
  final double? leftInset;
  final double? rightInset;

  const FilmRow({
    super.key,
    required this.title,
    required this.films,
    this.moreText = '查看全部',
    this.pid = 0,
    this.maxItems,
    this.subCategories = const [],
    this.onMore,
    this.onSubCategory,
    this.leftInset,
    this.rightInset,
  });

  void _openMore(BuildContext context) {
    if (onMore != null) {
      onMore!();
    } else if (pid > 0) {
      Navigator.pushNamed(context, '/filter', arguments: {'Pid': '$pid'});
    }
  }

  List<MovieBasicInfo> get _displayFilms {
    if (maxItems == null || maxItems! <= 0 || films.length <= maxItems!) {
      return films;
    }
    return films.sublist(0, maxItems!);
  }

  @override
  Widget build(BuildContext context) {
    final display = _displayFilms;
    if (display.isEmpty) {
      return const SizedBox.shrink();
    }
    final padding = MediaQuery.paddingOf(context);
    final left = leftInset ?? padding.left;
    final right = rightInset ?? padding.right;
    final windowWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = (AppTheme.spaceLg * 2) + left + right;
    final cardW = Breakpoint.cardWidthOf(
      windowWidth,
      horizontalPadding: horizontalPadding,
    );
    // 海报 2:3 + 标题上距 6 / 高 18 + 副标上距 2 / 高 15
    final rowHeight = cardW * 1.5 + 41;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppTheme.spaceSm),
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceMd),
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(
          bottom: BorderSide(color: Color(0x0DFFFFFF), width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppTheme.spaceLg + left,
              0,
              AppTheme.spaceLg + right,
              AppTheme.spaceMd,
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openMore(context),
                    child: Row(
                      children: [
                        Container(
                          width: 3.5,
                          height: 15,
                          decoration: BoxDecoration(
                            color: AppTheme.accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _openMore(context),
                  child: Padding(
                    padding: const EdgeInsets.only(left: AppTheme.spaceSm),
                    child: SizedBox(
                      height: 28,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            moreText,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 14,
                            color: AppTheme.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (subCategories.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                left: AppTheme.spaceLg + left,
                right: AppTheme.spaceLg + right,
                bottom: AppTheme.spaceSm,
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: subCategories.take(6).map((child) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(child.name),
                        onPressed: () {
                          if (onSubCategory != null) {
                            onSubCategory!(child.id);
                          } else if (pid > 0) {
                            Navigator.pushNamed(
                              context,
                              '/filter',
                              arguments: {
                                'Pid': '$pid',
                                'Category': '${child.id}',
                              },
                            );
                          }
                        },
                        backgroundColor: AppTheme.bgElevated,
                        labelStyle: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          SizedBox(
            height: rowHeight,
            child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.only(
                  left: AppTheme.spaceLg + left,
                  right: AppTheme.spaceLg + right,
                ),
                itemCount: display.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: AppTheme.spaceSm),
                itemBuilder: (context, index) {
                  return FilmCard(
                    film: display[index],
                    cardWidth: cardW,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
