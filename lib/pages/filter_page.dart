import 'package:flutter/material.dart';
import '../common/app_theme.dart';
import '../models/film_models.dart';
import '../api/film_api.dart';
import '../api/http_client.dart';
import '../utils/source_guard.dart';
import '../utils/collect_source_scope.dart';
import '../utils/favorite_manager.dart';
import '../utils/breakpoint.dart';
import '../components/film_card.dart';
import '../components/loading_view.dart';
import '../components/empty_state.dart';
import '../components/scroll_fab.dart';
import '../components/filter_bar.dart';
import '../components/sticky_appbar.dart';
import '../components/dynamic_sliver_appbar.dart';
import '../components/adaptive_content.dart';

const int _pageSize = 21;

/// 片库分类筛选。布局参考 EcoTV `views/filter`，逻辑对齐 OHOS `FilterPage.ets`。
class FilterPage extends StatefulWidget {
  final String pid;
  final String category;
  final String sort;

  const FilterPage({
    super.key,
    required this.pid,
    this.category = '',
    this.sort = '',
  });

  @override
  State<FilterPage> createState() => _FilterPageState();
}

class _FilterPageState extends State<FilterPage> {
  static const _verticalPhysics = AlwaysScrollableScrollPhysics(
    parent: ClampingScrollPhysics(),
  );

  String _pid = '';
  String _titleName = '片库';
  List<MovieBasicInfo> _films = [];
  int _total = 0, _current = 1, _pageCount = 1;
  bool _loading = true, _listLoading = false, _loadingMore = false, _fetchLock = false;
  String _errorText = '';

  List<String> _sortList = [], _titleKeys = [], _titles = [], _tagKeys = [];
  List<List<String>> _tagNames = [], _tagValues = [];
  List<ClassifySubNavItem> _subNav = [];

  final Map<String, String> _selected = {};
  final _sourceScope = CollectSourceScope.instance;
  final ScrollController _scrollController = ScrollController();
  bool _showTopFab = false;

  @override
  void initState() {
    super.initState();
    FavoriteManager.preload();
    _pid = widget.pid;
    HttpClient.instance.trackView('classify', _pid, 'FilterPage', '', widget.category);
    if (widget.category.isNotEmpty) _selected['Category'] = widget.category;
    if (widget.sort.isNotEmpty) _selected['Sort'] = widget.sort;
    _scrollController.addListener(_onScroll);
    SourceGuard.onReconnect(_onReconnect);
    _loadData(true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    SourceGuard.offReconnect(_onReconnect);
    super.dispose();
  }

  void _onReconnect() => _loadData(true);

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final y = _scrollController.offset;
    final viewH = _scrollController.position.viewportDimension;
    final showFab = viewH > 0 && y > viewH;
    if (showFab != _showTopFab) {
      setState(() => _showTopFab = showFab);
    }
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_loadingMore && _current < _pageCount) {
        _loadData(false);
      }
    }
  }

  Map<String, dynamic> _buildQuery(int page) {
    final query = <String, dynamic>{
      'Pid': _pid,
      'current': page,
      'pageSize': _pageSize,
    };
    _selected.forEach((k, v) {
      if (v.isNotEmpty) query[k] = v;
    });
    final sid = _sourceScope.activeId.trim();
    if (sid.isNotEmpty) {
      query['source'] = sid;
    }
    return query;
  }

  String _selectedOf(String key) => _selected[key] ?? '';

  String _selectedFor(String key) {
    final value = _selectedOf(key);
    return (key == 'Sort' && value.isEmpty) ? 'update_stamp' : value;
  }

  bool _isChipOn(String key, String value) => _selectedFor(key) == value;

  void _pick(String key, String value) {
    if (_isChipOn(key, value) || _fetchLock) return;
    setState(() => _selected[key] = value);
    if (key == 'Category') {
      HttpClient.instance.trackView('classify', _pid, 'FilterPage', '', value);
    }
    _loadData(true);
    _scrollToTop();
  }

  void _scrollToTop() {
    setState(() => _showTopFab = false);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _applyParams(List<String> keys, List<String> values) {
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      final v = i < values.length ? values[i] : '';
      if (v.isEmpty) continue;
      _selected[k] = v;
    }
  }

  Future<void> _loadData(bool reset, {bool fromPull = false}) async {
    if (_pid.isEmpty) {
      setState(() {
        _errorText = '缺少分类信息';
        _loading = false;
        _listLoading = false;
      });
      return;
    }
    final page = reset ? 1 : _current + 1;
    if ((!reset && (_loadingMore || page > _pageCount)) || _fetchLock) return;

    _fetchLock = true;
    if (reset) {
      if (fromPull) {
        setState(() => _listLoading = false);
      } else if (_sortList.isEmpty) {
        setState(() { _films = []; _loading = true; _listLoading = false; _errorText = ''; });
      } else {
        setState(() { _listLoading = true; _loading = false; _errorText = ''; });
      }
    } else {
      setState(() => _loadingMore = true);
    }

    var ok = false;
    try {
      final res = await FilmApi.getFilter(
        _buildQuery(page),
        sourceId: _sourceScope.activeId,
      );
      if (!mounted) return;
      final resolved = res.resolvedPid > 0 ? '${res.resolvedPid}' : '';
      if (reset && resolved.isNotEmpty && resolved != _pid) {
        _pid = resolved;
        _fetchLock = false;
        await _loadData(true, fromPull: fromPull);
        return;
      }
      setState(() {
        _titleName = res.titleName.isNotEmpty ? res.titleName : '片库';
        _subNav = res.subNav;
        _total = res.page.total;
        _current = res.page.current;
        _pageCount = res.page.pageCount;
        _films = reset ? res.list : [..._films, ...res.list];
        _sortList = res.search.sortList;
        _titleKeys = res.search.titleKeys;
        _titles = res.search.titles;
        _tagKeys = res.search.tagKeys;
        _tagNames = res.search.tagNames;
        _tagValues = res.search.tagValues;
        if (reset) _applyParams(res.paramKeys, res.params);
        _errorText = res.titleName.isNotEmpty ? '' : '当前分类已失效，请从首页重新进入';
        ok = _errorText.isEmpty;
      });
      if (reset) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) _scrollController.jumpTo(0);
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (reset) {
        setState(() => _errorText = '$e');
      }
    } finally {
      _fetchLock = false;
      if (mounted) {
        setState(() {
          _loading = false;
          _listLoading = false;
          _loadingMore = false;
        });
      }
      if (fromPull && ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已更新')),
        );
      }
    }
  }

  String _titleOf(String key) {
    final index = _titleKeys.indexOf(key);
    return index >= 0 ? _titles[index] : key;
  }

  List<String> _namesOf(String key) {
    final index = _tagKeys.indexOf(key);
    return index >= 0 ? _tagNames[index] : [];
  }

  List<String> _valuesOf(String key) {
    final index = _tagKeys.indexOf(key);
    return index >= 0 ? _tagValues[index] : [];
  }

  String _labelOf(String key, String value) {
    if (value.isEmpty) return '';
    final values = _valuesOf(key);
    final names = _namesOf(key);
    final index = values.indexOf(value);
    if (index >= 0 && index < names.length) return names[index];
    return value;
  }

  List<String> _selectedTagKeys() {
    final keys = <String>[];
    for (final key in _sortList) {
      final label = _labelOf(key, _selectedFor(key));
      if (label.isNotEmpty && label != '全部') keys.add(key);
    }
    return keys;
  }

  /// 行顺序：sortList，再补 tags 里有选项但 sortList 没列的键（类型/剧情/地区等）。
  List<String> _rowKeys() {
    final available = {for (final k in [..._tagKeys, ..._sortList]) if (_namesOf(k).isNotEmpty) k};
    final keys = <String>[];
    void add(String k) { if (available.contains(k) && !keys.contains(k)) keys.add(k); }
    for (final k in [..._sortList, 'Category', 'Plot', 'Area', 'Language', 'Year', 'Sort', ...available]) {
      add(k);
    }
    return keys;
  }

  @override
  Widget build(BuildContext context) {
    final rowKeys = _rowKeys();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: AdaptiveContent(
        child: SafeArea(
          child: _loading
            ? Column(
                children: [
                  _navBar(showPills: false),
                  const Expanded(child: LoadingView(label: '加载中')),
                ],
              )
            : Stack(
                alignment: Alignment.bottomRight,
                children: [
                  RefreshIndicator(
                    notificationPredicate: (n) => n.depth == 0 && _errorText.isEmpty,
                    onRefresh: () async {
                      if (_fetchLock || _errorText.isNotEmpty) return;
                      await _loadData(true, fromPull: true);
                    },
                    color: AppTheme.accent,
                    backgroundColor: AppTheme.bgCard,
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: _verticalPhysics,
                      slivers: [
                        if (rowKeys.isNotEmpty)
                          DynamicSliverAppBar(
                            maxHeight: MediaQuery.sizeOf(context).height,
                            child: FilterBar(
                              keys: rowKeys,
                              titleOf: _titleOf,
                              namesOf: _namesOf,
                              valuesOf: _valuesOf,
                              selectedOf: _selectedFor,
                              onPick: _pick,
                            ),
                          ),
                        SliverPersistentHeader(
                          pinned: true,
                          floating: true,
                          delegate: StickyAppbar(child: _navBar(showPills: true)),
                        ),
                        if (_subNav.isNotEmpty) SliverToBoxAdapter(child: _subNavBar()),
                        ..._bodySlivers(),
                      ],
                    ),
                  ),
                  ScrollFab(visible: _showTopFab, onClickFab: _scrollToTop),
                ],
              ),
        ),
      ),
    );
  }

  List<Widget> _bodySlivers() {
    if (_listLoading) {
      return const [
        SliverFillRemaining(child: LoadingView(label: '列表加载中')),
      ];
    }
    if (_errorText.isNotEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            title: '加载失败',
            subtitle: _errorText,
            icon: Icons.info_outline_rounded,
            action: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionPill(icon: Icons.link_rounded, label: '更换服务端', accent: true, onTap: () => Navigator.pushNamed(context, '/server_config')),
                const SizedBox(height: 12),
                _ActionPill(icon: Icons.refresh_rounded, label: '刷新', accent: false, onTap: () => _loadData(true)),
              ],
            ),
          ),
        ),
      ];
    }
    if (_films.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(title: '没有符合条件的影片'),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(AppTheme.spaceMd, 0, AppTheme.spaceMd, AppTheme.spaceMd),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: Breakpoint.gridColsOf(MediaQuery.sizeOf(context).width),
            childAspectRatio: Breakpoint.gridAspectRatio(
              width: MediaQuery.sizeOf(context).width,
              columns: Breakpoint.gridColsOf(MediaQuery.sizeOf(context).width),
              horizontalPadding: AppTheme.spaceMd * 2,
            ),
            crossAxisSpacing: AppTheme.spaceSm,
            mainAxisSpacing: AppTheme.spaceMd,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => FilmCard(film: _films[index]),
            childCount: _films.length,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              _loadingMore ? '加载中...' : (_current >= _pageCount ? '没有更多了' : ''),
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _subNavBar() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceMd),
        itemCount: _subNav.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = _subNav[index];
          final active = _selectedOf('Category') == '${item.id}';
          return ChoiceChip(
            label: Text(item.name),
            selected: active,
            onSelected: (_) => _pick('Category', '${item.id}'),
            selectedColor: AppTheme.accent.withValues(alpha: 0.35),
            backgroundColor: AppTheme.bgCard,
            labelStyle: TextStyle(
              fontSize: 12,
              color: active ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          );
        },
      ),
    );
  }

  Widget _navBar({required bool showPills}) {
    final keys = showPills ? _selectedTagKeys() : const <String>[];
    return ColoredBox(
      color: AppTheme.bg,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.only(left: AppTheme.spaceSm, right: AppTheme.spaceLg),
          child: Row(
            children: [
              const _BackBtn(),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: AppTheme.spaceXs),
                  itemCount: keys.length,
                  separatorBuilder: (context, index) => const SizedBox(width: AppTheme.spaceSm),
                  itemBuilder: (context, index) {
                    final key = keys[index];
                    return Center(
                      child: _FilterPill(label: _labelOf(key, _selectedFor(key))),
                    );
                  },
                ),
              ),
              if (showPills && _total > 0)
                Padding(
                  padding: const EdgeInsets.only(left: AppTheme.spaceSm),
                  child: Text(
                    '共 $_total 部',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackBtn extends StatelessWidget {
  const _BackBtn();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 24, color: AppTheme.textPrimary),
        onPressed: () => Navigator.maybePop(context),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  const _FilterPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceMd),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: AppTheme.accent),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.accent, height: 1)),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;
  final VoidCallback onTap;
  const _ActionPill({required this.icon, required this.label, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: Container(
        width: 148,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent ? AppTheme.accent : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppTheme.textPrimary),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
          ],
        ),
      ),
    );
  }
}
