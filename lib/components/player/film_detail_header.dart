import 'package:flutter/material.dart';
import '../../common/app_theme.dart';
import '../../models/film_models.dart';
import '../../utils/favorite_manager.dart';
import '../../utils/format_util.dart';
import '../film_detail_dialog.dart';

/// 播放页影片详情头部，对齐 OHOS `FilmDetailHeader`
class FilmDetailHeader extends StatefulWidget {
  final String filmId;
  final String picture;
  final String name;
  final String subTitle;
  final String actor;
  final String plot;
  final String sourceName;
  final String sourceId;
  final MovieDescriptor? descriptor;
  final double rightInset;

  const FilmDetailHeader({
    super.key,
    required this.filmId,
    this.picture = '',
    required this.name,
    this.subTitle = '',
    this.actor = '',
    this.plot = '',
    this.sourceName = '',
    this.sourceId = '',
    this.descriptor,
    this.rightInset = 0,
  });

  @override
  State<FilmDetailHeader> createState() => _FilmDetailHeaderState();
}

class _FilmDetailHeaderState extends State<FilmDetailHeader> {
  bool _isFav = false;

  @override
  void initState() {
    super.initState();
    FavoriteManager.onFavoriteChange(_syncFav);
    _syncFav();
  }

  @override
  void didUpdateWidget(covariant FilmDetailHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filmId != widget.filmId) {
      _syncFav();
    }
  }

  @override
  void dispose() {
    FavoriteManager.offFavoriteChange(_syncFav);
    super.dispose();
  }

  Future<void> _syncFav() async {
    final id = widget.filmId;
    if (id.isEmpty) {
      if (mounted) setState(() => _isFav = false);
      return;
    }
    final fav = await FavoriteManager.isFavorite(id);
    if (mounted && widget.filmId == id) {
      setState(() => _isFav = fav);
    }
  }

  String _scoreText() {
    final s = widget.descriptor?.dbScore.trim() ?? '';
    if (s.isEmpty || s == '0' || s == '0.0') return '';
    return s;
  }

  String _cleanPlot() {
    final raw = widget.plot.isNotEmpty
        ? widget.plot
        : (widget.descriptor?.content.isNotEmpty == true
            ? widget.descriptor!.content
            : (widget.descriptor?.blurb ?? ''));
    return FormatUtil.cleanPlot(raw);
  }

  String _briefMetaText() {
    final parts = <String>[];
    final year = widget.descriptor?.year.trim() ?? '';
    if (year.isNotEmpty) parts.add(year);
    final cat = (widget.descriptor?.classTag.isNotEmpty == true)
        ? widget.descriptor!.classTag
        : (widget.descriptor?.cName ?? '');
    if (cat.trim().isNotEmpty) {
      final firstCat = cat.trim().split(RegExp(r'[,/，\s]+'))[0].trim();
      if (firstCat.isNotEmpty) parts.add(firstCat);
    }
    final rawArea = (widget.descriptor?.area.isNotEmpty == true)
        ? widget.descriptor!.area
        : (widget.descriptor?.language ?? '');
    if (rawArea.trim().isNotEmpty) {
      final firstArea = rawArea.trim().split(RegExp(r'[,/，\s]+'))[0].trim();
      if (firstArea.isNotEmpty) parts.add(firstArea);
    }
    return parts.join(' · ');
  }

  List<String> _metaTags() {
    final tags = <String>[];
    final year = widget.descriptor?.year.trim() ?? '';
    if (year.isNotEmpty) tags.add(year);
    final cat = (widget.descriptor?.classTag.isNotEmpty == true)
        ? widget.descriptor!.classTag
        : (widget.descriptor?.cName ?? '');
    if (cat.trim().isNotEmpty) {
      for (final part in cat.trim().split(RegExp(r'[,/，\s]+'))) {
        final p = part.trim();
        if (p.isNotEmpty && !tags.contains(p) && tags.length < 5) tags.add(p);
      }
    }
    final area = widget.descriptor?.area.trim() ?? '';
    if (area.isNotEmpty && !tags.contains(area)) tags.add(area);
    final lang = widget.descriptor?.language.trim() ?? '';
    if (lang.isNotEmpty && !tags.contains(lang)) tags.add(lang);
    return tags;
  }

  String _directorText() {
    final raw = widget.descriptor?.director.trim() ?? '';
    if (raw.isEmpty) return '';
    return raw.replaceAll(RegExp(r'\s*[，,、]\s*'), ' / ');
  }

  String _actorText() {
    final raw = (widget.descriptor?.actor.isNotEmpty == true)
        ? widget.descriptor!.actor.trim()
        : widget.actor.trim();
    if (raw.isEmpty) return '';
    return raw.replaceAll(RegExp(r'\s*[，,、]\s*'), ' / ');
  }

  // ignore: unused_element
  bool _hasDetailInfo() {
    return _directorText().isNotEmpty || _actorText().isNotEmpty || _cleanPlot().isNotEmpty;
  }

  // ignore: unused_element
  String _snippet() {
    final actor = _actorText();
    if (actor.isNotEmpty) return '主演：$actor';
    final director = _directorText();
    if (director.isNotEmpty) return '导演：$director';
    final plot = _cleanPlot();
    if (plot.isNotEmpty) return '简介：${plot.replaceAll(RegExp(r'\n+'), ' ')}';
    return '查看简介 / 主演 / 导演';
  }

  Future<void> _toggleFavorite() async {
    if (widget.filmId.isEmpty || widget.name.isEmpty) return;
    final desc = widget.descriptor;
    final next = await FavoriteManager.toggle(FavoriteItem(
      id: widget.filmId,
      name: widget.name,
      picture: widget.picture,
      cName: desc?.cName ?? '',
      remarks: desc?.remarks ?? '',
      year: desc?.year ?? '',
      area: desc?.area ?? '',
      subTitle: widget.subTitle,
      actor: widget.actor,
      director: desc?.director ?? '',
      sourceId: widget.sourceId,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    if (!mounted) return;
    setState(() => _isFav = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(next ? '已加入收藏' : '已取消收藏')),
    );
  }

  void _openDialog() {
    FilmDetailDialog.show(
      context,
      name: widget.name,
      scoreText: _scoreText(),
      sourceName: widget.sourceName,
      tags: _metaTags(),
      director: _directorText(),
      actor: _actorText(),
      plot: _cleanPlot(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final score = _scoreText();
    final metaText = _briefMetaText();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 片名与收藏行（左侧片名最多2行后省略；右上角常驻唯一收藏胶囊，平衡短片名与长片名的视觉重心）
        Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12 + widget.rightInset, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    height: 24 / 18,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              // 收藏按钮（右上角唯一的实体胶囊，26vp 精致尺寸，顶部对齐）
              InkWell(
                onTap: _toggleFavorite,
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                child: Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: _isFav ? const Color(0x24FA8C16) : AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    border: Border.all(
                      width: 0.5,
                      color: _isFav ? const Color(0x59FA8C16) : AppTheme.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 13,
                        color: _isFav ? AppTheme.accent : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _isFav ? '已收藏' : '收藏',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _isFav ? AppTheme.accent : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 2. 元数据与详情行（左侧排列采集源、评分、信息摘要与更多入口）
        Padding(
          padding: EdgeInsets.fromLTRB(12, 2, 12 + widget.rightInset, 8),
          child: InkWell(
            onTap: _openDialog,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            child: Row(
              children: [
                // 评分微标（如有）
                if (score.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentSoft,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('★', style: TextStyle(fontSize: 10, color: AppTheme.accent)),
                        const SizedBox(width: 2),
                        Text(
                          score,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accent,
                          ),
                        ),
                        const SizedBox(width: 1),
                        const Text('分', style: TextStyle(fontSize: 9, color: AppTheme.accent)),
                      ],
                    ),
                  ),

                // 核心信息摘要（年份 · 分类 · 地区）
                if (metaText.isNotEmpty)
                  Flexible(
                    child: Text(
                      metaText,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                // 紧贴左侧的纯文字更多入口（主题高亮色链接，无按钮底色）
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (metaText.isNotEmpty)
                      const Text(
                        ' · ',
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    const Text(
                      '更多',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.accent,
                      ),
                    ),
                    const SizedBox(width: 1),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 10,
                      color: AppTheme.accent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
