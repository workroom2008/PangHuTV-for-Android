import 'package:flutter/material.dart';
import '../common/app_theme.dart';
import '../models/film_models.dart';
import '../api/film_api.dart';
import '../api/http_client.dart';
import '../utils/search_history_manager.dart';
import '../utils/source_guard.dart';
import '../utils/favorite_manager.dart';
import '../utils/format_util.dart';
import '../utils/nav_util.dart';
import '../components/search_source_tabs.dart';
import '../components/search_suggest_pane.dart';
import '../components/search_result_list.dart';
import '../components/loading_view.dart';
import '../components/adaptive_content.dart';

const List<String> _defaultHotKeywords = [
  '凡人修仙传', '庆余年', '仙逆', '吞噬星空', '遮天', '斗破苍穹', '白夜破晓', '大奉打更人'
];

/// 影片搜索页面
class SearchPage extends StatefulWidget {
  final String initialKeyword;

  const SearchPage({super.key, this.initialKeyword = ''});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _submitted = '';
  List<MovieBasicInfo> _list = [];
  List<SearchSourceTab> _sources = [];
  String _source = '';
  PageInfo _page = PageInfo(pageSize: 10, current: 1, pageCount: 0, total: 0);
  bool _loading = false;
  bool _loadingMore = false;
  List<String> _searchHistory = [];
  List<String> _hotKeywords = [];
  final ScrollController _scrollController = ScrollController();
  final Map<String, _CachedSource> _cache = {};
  int _searchGen = 0;
  String _sourceError = '';
  String? _anchorFilmId;
  double? _pendingRestoreOffset;

  @override
  void initState() {
    super.initState();
    FavoriteManager.preload();
    _loadHistory();
    _loadHotKeywords();
    SourceGuard.onReconnect(_onReconnect);
    _scrollController.addListener(_onScroll);

    if (widget.initialKeyword.isNotEmpty) {
      _inputController.text = widget.initialKeyword;
      _doSearch(true);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _submitted.isEmpty) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _focusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    SourceGuard.offReconnect(_onReconnect);
    super.dispose();
  }

  void _onReconnect() {
    FavoriteManager.preload();
    _loadHistory();
    _loadHotKeywords();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_loadingMore && _page.current < _page.pageCount) {
        _doSearch(false);
      }
    }
  }

  Future<void> _loadHistory() async {
    final list = await SearchHistoryManager.list();
    if (mounted) {
      setState(() {
        _searchHistory = list;
      });
    }
  }

  Future<void> _loadHotKeywords() async {
    try {
      final list = await FilmApi.getHotKeywords();
      if (mounted && list.isNotEmpty) {
        setState(() {
          _hotKeywords = list;
        });
        return;
      }
    } catch (_) {}
    if (mounted && _hotKeywords.isEmpty) {
      setState(() {
        _hotKeywords = List.from(_defaultHotKeywords);
      });
    }
  }

  String _getSearchPlaceholder() {
    if (_hotKeywords.isNotEmpty) {
      return '大家都在搜：${_hotKeywords.first}';
    }
    return '搜索电影、剧集、动漫';
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        title: const Text('清空搜索历史', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: const Text('确定要清空全部搜索记录吗？', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('取消', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await SearchHistoryManager.clear();
              await _loadHistory();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已清空搜索历史')),
                );
              }
            },
            child: const Text('清空', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _applySource(String id) {
    final hit = _cache[id];
    if (hit != null) {
      _list = hit.list;
      _page = hit.page;
      _sourceError = hit.error;
      _loading = false;
      return;
    }
    _list = [];
    _sourceError = '';
    _loading = true;
    if (_submitted.isNotEmpty && id.isNotEmpty) {
      _fetchSource(_searchGen, _submitted, id);
    }
  }

  void _patchTab(String id, {int? count, bool? loading}) {
    _sources = [
      for (final tab in _sources)
        if (tab.id == id)
          SearchSourceTab(
            id: tab.id,
            name: tab.name,
            count: count ?? tab.count,
            loading: loading ?? tab.loading,
          )
        else
          tab,
    ];
  }

  Future<void> _fetchSource(int gen, String kw, String id) async {
    var list = <MovieBasicInfo>[];
    var page = PageInfo(pageSize: 12, current: 1, pageCount: 0, total: 0);
    var err = '';
    try {
      final res = await FilmApi.searchFilm(kw, current: 1, source: id);
      list = res.list;
      page = res.page;
      err = res.error;
    } catch (_) {
      err = '源站搜索失败';
    }
    if (!mounted || gen != _searchGen) return;
    setState(() {
      _cache[id] = _CachedSource(list: list, page: page, error: err);
      _patchTab(id, count: page.total, loading: false);
      if (_source == id) {
        _list = list;
        _page = page;
        _sourceError = err;
        _loading = false;
      }
    });
  }

  Future<void> _openPlayFromSearch(MovieBasicInfo film) async {
    if (_scrollController.hasClients) {
      _pendingRestoreOffset = _scrollController.offset;
    }
    final filmId = FormatUtil.filmId(film);
    _anchorFilmId = filmId;
    await NavUtil.openPlay(
      context,
      filmId,
      sourceId: film.sourceId,
      sourceMid: film.sourceMid > 0 ? '${film.sourceMid}' : '',
      title: film.name,
    );
    if (!mounted) return;
    setState(() {});
    _restoreSearchScroll();
  }

  void _restoreSearchScroll() {
    final offset = _pendingRestoreOffset;
    if (offset == null) return;
    void apply() {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(offset.clamp(0.0, max));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      apply();
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    });
  }

  Future<void> _doSearch(bool reset, {bool keepSource = false}) async {
    final kw = _inputController.text.trim();
    if (kw.isEmpty) {
      if (reset) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入搜索关键词')),
        );
      }
      return;
    }

    final nextPage = reset ? 1 : _page.current + 1;
    if (!reset && nextPage > _page.pageCount) return;

    _focusNode.unfocus();

    if (!reset) {
      setState(() {
        _loadingMore = true;
      });
      try {
        final res = await FilmApi.searchFilm(kw, current: nextPage, source: _source);
        if (!mounted) return;
        setState(() {
          _submitted = kw;
          _page = res.page;
          _list = [..._list, ...res.list];
          _cache[_source] = _CachedSource(list: _list, page: res.page);
          _loadingMore = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _loadingMore = false;
        });
      }
      return;
    }

    if (!keepSource) {
      _source = '';
      _anchorFilmId = null;
      _pendingRestoreOffset = null;
    }
    _sourceError = '';
    final gen = ++_searchGen;
    HttpClient.instance.trackView('search', kw, 'SearchPage');
    setState(() {
      _loading = true;
      _list = [];
      _cache.clear();
    });
    SearchHistoryManager.add(kw).then((_) => _loadHistory());

    try {
      final res = await FilmApi.searchFilm(kw, current: 1, source: '');
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _submitted = kw;
        _cache[''] = _CachedSource(list: res.list, page: res.page, error: res.error);
        _sources = [
          for (final tab in res.sources)
            SearchSourceTab(
              id: tab.id,
              name: tab.name,
              count: tab.id.isEmpty
                  ? (tab.count > 0 ? tab.count : res.page.total)
                  : tab.count,
              loading: false,
            ),
        ];
        if (_source.isEmpty) {
          _list = res.list;
          _page = res.page;
          _sourceError = res.error;
          _loading = false;
        } else if (_cache[_source] != null) {
          _applySource(_source);
        } else if (_source.isNotEmpty) {
          _loading = true;
        }
      });
      await Future.wait([
        for (final tab in res.sources)
          if (tab.id.isNotEmpty) _fetchSource(gen, kw, tab.id),
      ]);
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _sources = [
          for (final tab in _sources)
            SearchSourceTab(id: tab.id, name: tab.name, count: tab.count, loading: false),
        ];
      });
    } catch (_) {
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: AdaptiveContent(
        child: SafeArea(
          child: Column(
          children: [
            // Top Search Input Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppTheme.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, size: 18, color: AppTheme.textMuted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: _inputController,
                              focusNode: _focusNode,
                              style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                              decoration: InputDecoration(
                                hintText: _getSearchPlaceholder(),
                                hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _doSearch(true),
                              onChanged: (val) {
                                if (val.trim().isEmpty && _submitted.isNotEmpty) {
                                  setState(() {
                                    _submitted = '';
                                    _list = [];
                                  });
                                }
                              },
                            ),
                          ),
                          if (_inputController.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _focusNode.unfocus();
                                setState(() {
                                  _inputController.clear();
                                  _submitted = '';
                                  _list = [];
                                });
                              },
                              child: const Icon(Icons.cancel_rounded, size: 18, color: AppTheme.textMuted),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _doSearch(true),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: AppTheme.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.search_rounded, size: 20, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),

            // Body Area
            Expanded(
              child: Column(
                children: [
                  if (_submitted.isNotEmpty)
                    SearchSourceTabs(
                      sources: _sources,
                      activeId: _source,
                      onChange: (id) {
                        if (id == _source) return;
                        _focusNode.unfocus();
                        setState(() {
                          _source = id;
                          _applySource(id);
                        });
                      },
                    ),
                  Expanded(
                    child: _loading
                        ? LoadingView(label: _source.isNotEmpty ? '正在搜索该采集源' : '正在搜索')
                        : _submitted.isEmpty
                            ? SearchSuggestPane(
                                searchHistory: _searchHistory,
                                hotKeywords: _hotKeywords,
                                onSelectKeyword: (item) {
                                  _inputController.text = item;
                                  _doSearch(true);
                                },
                                onClearHistory: _confirmClearHistory,
                                onRemoveHistory: (item) {
                                  SearchHistoryManager.remove(item).then((_) => _loadHistory());
                                },
                              )
                            : _buildResultList(),
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultList() {
    return SearchResultList(
      list: _list,
      page: _page,
      loadingMore: _loadingMore,
      sourceError: _sourceError,
      submitted: _submitted,
      sourceId: _source,
      scrollController: _scrollController,
      anchorFilmId: _anchorFilmId,
      onFilmTap: _openPlayFromSearch,
      onRefresh: () async {
        if (_scrollController.hasClients) {
          _pendingRestoreOffset = _scrollController.offset;
        }
        await _doSearch(true, keepSource: true);
        if (mounted) _restoreSearchScroll();
      },
    );
  }
}

class _CachedSource {
  final List<MovieBasicInfo> list;
  final PageInfo page;
  final String error;

  _CachedSource({required this.list, required this.page, this.error = ''});
}
