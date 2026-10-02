import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/retrieval.dart';
import 'common.dart';
import 'item_detail.dart';
import 'item_actions.dart';
import 'research_detail.dart';
import 'afterword_art.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.controller, required this.data});
  final AppController controller;
  final AppData data;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String _query = '';
  String _scope = '使用中';
  String _filter = '全部';
  final Set<String> _selected = {};
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _inScope(LibraryItem item) => switch (_scope) {
    '已归档' => item.isArchived && !item.isTrashed,
    '回收站' => item.isTrashed,
    _ => item.isActive,
  };
  bool _matches(LibraryItem item) {
    final matchesStatus = switch (_filter) {
      '未读' => item.readCount == 0,
      '已分析' => item.analysis != null,
      '异常' => ['failed', 'error', 'interrupted'].contains(item.status),
      _ => true,
    };
    return _inScope(item) && matchesStatus;
  }

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    final trimmedQuery = _query.trim();
    final hits = trimmedQuery.isEmpty
        ? const <SearchHit>[]
        : searchLibrary(widget.data, trimmedQuery, includeItem: _matches);
    final itemHits = {
      for (final hit in hits.where((h) => h.type == 'item')) hit.id: hit,
    };
    final items =
        widget.data.items
            .where(
              (item) => trimmedQuery.isEmpty
                  ? _matches(item)
                  : itemHits.containsKey(item.id),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (trimmedQuery.isNotEmpty) {
      items.sort((a, b) {
        final byScore = (itemHits[b.id]?.score ?? 0).compareTo(
          itemHits[a.id]?.score ?? 0,
        );
        return byScore != 0 ? byScore : b.createdAt.compareTo(a.createdAt);
      });
    }
    final knowledgeHits = hits.where((hit) => hit.type != 'item').toList();
    _selected.removeWhere((id) => !items.any((item) => item.id == id));
    final hasScopeItems = widget.data.items.any(_inScope);
    final hasResults = items.isNotEmpty || knowledgeHits.isNotEmpty;
    return AppFrame(
      title: _selected.isEmpty ? '资料' : '已选 ${_selected.length} 项',
      actions: _selected.isNotEmpty
          ? [
              IconButton(
                tooltip: '全选当前结果',
                icon: const AfterwordIcon(Icons.select_all),
                onPressed: () =>
                    setState(() => _selected.addAll(items.map((e) => e.id))),
              ),
              ItemActionsMenu(
                controller: widget.controller,
                items: items.where((e) => _selected.contains(e.id)).toList(),
                onDone: () {
                  if (mounted) setState(_selected.clear);
                },
              ),
              IconButton(
                tooltip: '退出多选',
                icon: const AfterwordIcon(Icons.close),
                onPressed: () => setState(_selected.clear),
              ),
            ]
          : [
              if (_scope == '回收站' && hasScopeItems)
                IconButton(
                  tooltip: '清空回收站',
                  icon: const AfterwordIcon(Icons.delete_sweep_outlined),
                  onPressed: () => performItemAction(
                    context,
                    widget.controller,
                    'purge',
                    widget.data.items.where((e) => e.isTrashed).toList(),
                  ),
                ),
              PopupMenuButton<String>(
                tooltip: '添加资料',
                icon: const AfterwordIcon(Icons.add),
                onSelected: (value) {
                  switch (value) {
                    case 'url':
                      _showUrlDialog(context);
                    case 'text':
                      _showTextDialog(context);
                    case 'file':
                      _importFile(context);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'url', child: Text('收藏链接')),
                  PopupMenuItem(value: 'text', child: Text('添加文字')),
                  PopupMenuItem(value: 'file', child: Text('导入文件')),
                ],
              ),
            ],
      child: CustomScrollView(
        key: const PageStorageKey('library-list'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    layout.pagePadding,
                    8,
                    layout.pagePadding,
                    4,
                  ),
                  child: SearchBar(
                    controller: _search,
                    hintText: '搜索标题、正文、笔记',
                    leading: const AfterwordIcon(Icons.search),
                    trailing: [
                      if (_query.isNotEmpty)
                        IconButton(
                          tooltip: '清除搜索',
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                          icon: const AfterwordIcon(Icons.close),
                        ),
                    ],
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                _chipGroup(
                  context,
                  label: '范围',
                  labels: const ['使用中', '已归档', '回收站'],
                  selected: _scope,
                  onSelect: (v) => setState(() {
                    _scope = v;
                    _selected.clear();
                  }),
                ),
                _chipGroup(
                  context,
                  label: '状态',
                  labels: const ['全部', '未读', '已分析', '异常'],
                  selected: _filter,
                  onSelect: (v) => setState(() {
                    _filter = v;
                    _selected.clear();
                  }),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    layout.pagePadding,
                    6,
                    layout.pagePadding,
                    10,
                  ),
                  child: Text(
                    '当前 ${items.length} 条资料 · ${_sortLabel(trimmedQuery)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (_scope == '回收站')
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      layout.pagePadding,
                      0,
                      layout.pagePadding,
                      8,
                    ),
                    child: Text(
                      '删除后保留 ${widget.data.settings.trashRetentionDays} 天，到期永久移除。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const Divider(height: 1),
              ],
            ),
          ),
          if (!hasResults)
            SliverToBoxAdapter(
              child: EmptyState(
                scene: hasScopeItems
                    ? 'search-empty'
                    : switch (_scope) {
                        '已归档' => 'archive-empty',
                        '回收站' => 'trash-empty',
                        _ => 'library-empty',
                      },
                icon: hasScopeItems
                    ? Icons.search_off_outlined
                    : Icons.collections_bookmark_outlined,
                title: hasScopeItems
                    ? '没有匹配的资料'
                    : switch (_scope) {
                        '已归档' => '暂无归档资料',
                        '回收站' => '回收站为空',
                        _ => '还没有待处理资料',
                      },
                message: hasScopeItems
                    ? '试试其他关键词或筛选条件。'
                    : switch (_scope) {
                        '已归档' => '归档后仍可阅读，且不会参与新的分析和研究。',
                        '回收站' => '删除的资料可在保留期内恢复。',
                        _ => '收藏网页、文字、图片或 PDF，让阅读慢慢积累成认识。',
                      },
                action: !hasScopeItems && _scope == '使用中'
                    ? FilledButton.icon(
                        onPressed: () => _showUrlDialog(context),
                        icon: const AfterwordIcon(Icons.add_link),
                        label: const Text('收藏链接'),
                      )
                    : null,
              ),
            ),
          if (items.isNotEmpty)
            SliverList.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                indent: layout.pagePadding,
                endIndent: layout.pagePadding,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                return _LibraryTile(
                  item: item,
                  selecting: _selected.isNotEmpty,
                  selected: _selected.contains(item.id),
                  onTap: () {
                    if (_selected.isEmpty) {
                      _openDetail(context, item);
                    } else {
                      _toggle(item.id);
                    }
                  },
                  onLongPress: () => _toggle(item.id),
                  trailing: _selected.isNotEmpty
                      ? const SizedBox(width: 12)
                      : ItemActionsMenu(
                          controller: widget.controller,
                          items: [item],
                        ),
                  snippet: trimmedQuery.isEmpty
                      ? null
                      : itemHits[item.id]?.snippet,
                  controller: widget.controller,
                );
              },
            ),
          if (knowledgeHits.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  layout.pagePadding,
                  layout.sectionGap / 2,
                  layout.pagePadding,
                  6,
                ),
                child: Text(
                  '研究与主题命中',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            SliverList.separated(
              itemCount: knowledgeHits.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                indent: layout.pagePadding,
                endIndent: layout.pagePadding,
              ),
              itemBuilder: (context, index) {
                final hit = knowledgeHits[index];
                return ListTile(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: layout.pagePadding,
                    vertical: 4,
                  ),
                  leading: AfterwordIcon(
                    hit.type == 'topic'
                        ? Icons.travel_explore_outlined
                        : Icons.science_outlined,
                  ),
                  title: Text(hit.title),
                  subtitle: Text(
                    hit.snippet,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _openHit(context, hit),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  void _toggle(String id) => setState(() {
    if (!_selected.add(id)) _selected.remove(id);
  });
  Widget _chipGroup(
    BuildContext context, {
    required String label,
    required List<String> labels,
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    final layout = ReadingLayout.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final chipLabel in labels)
                  ChoiceChip(
                    label: Text(chipLabel),
                    selected: chipLabel == selected,
                    onSelected: (_) => onSelect(chipLabel),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _sortLabel(String query) => query.isEmpty ? '按加入时间排序' : '按相关度排序';

  Future<void> _importFile(BuildContext context) async {
    final file = await FilePicker.pickFile();
    if (file?.path == null || !context.mounted) {
      return;
    }
    await runUiAction(
      context,
      () => widget.controller.importFile(file!.path!, name: file.name),
      success: '文件已入库',
    );
  }

  Future<void> _showUrlDialog(BuildContext context) async {
    final result = await showTextEntryDialog(
      context,
      title: '收藏链接',
      primaryLabel: '链接',
      secondaryLabel: '备注',
    );
    if (result == null || !context.mounted) {
      return;
    }
    await runUiAction(
      context,
      () => widget.controller.captureUrl(
        result.$1,
        notes: result.$2,
        openWhenBlocked: true,
      ),
      success: '链接已保存',
    );
  }

  Future<void> _showTextDialog(BuildContext context) async {
    final result = await showTextEntryDialog(
      context,
      title: '添加文字资料',
      primaryLabel: '正文',
      secondaryLabel: '标题或关注点',
      multiline: true,
    );
    if (result == null || !context.mounted) {
      return;
    }
    await runUiAction(
      context,
      () => widget.controller.captureText(
        result.$1,
        title: result.$2,
        notes: result.$2,
      ),
      success: '文字已保存',
    );
  }

  void _openDetail(BuildContext context, LibraryItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ArticleDetailPage(controller: widget.controller, item: item),
      ),
    );
  }

  void _openHit(BuildContext context, SearchHit hit) {
    if (hit.type == 'topic') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              TopicDetailPage(controller: widget.controller, topicId: hit.id),
        ),
      );
      return;
    }
    final run = widget.data.runs
        .where((candidate) => candidate.id == hit.id)
        .firstOrNull;
    if (run == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ResearchRunPage(controller: widget.controller, runId: run.id),
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.item,
    required this.onTap,
    required this.onLongPress,
    required this.trailing,
    required this.selecting,
    required this.selected,
    required this.controller,
    this.snippet,
  });
  final LibraryItem item;
  final VoidCallback onTap, onLongPress;
  final Widget trailing;
  final bool selecting, selected;
  final AppController controller;
  final String? snippet;
  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding,
            layout.rowPadding,
            4,
            layout.rowPadding,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selecting)
                Checkbox(value: selected, onChanged: (_) => onTap()),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      snippet?.isNotEmpty == true
                          ? snippet!
                          : _libraryPreview(item),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          kindLabel(item.kind),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        StatusPill(
                          label: _libraryStatusLabel(item),
                          positive: item.analysis != null,
                        ),
                        PopupMenuButton<WorkState>(
                          tooltip: '处理状态',
                          onSelected: (value) =>
                              controller.setWorkState(item.id, value),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: WorkState.pending,
                              child: Text('待判断'),
                            ),
                            PopupMenuItem(
                              value: WorkState.reading,
                              child: Text('阅读中'),
                            ),
                            PopupMenuItem(
                              value: WorkState.done,
                              child: Text('已处理'),
                            ),
                            PopupMenuItem(
                              value: WorkState.snoozed,
                              child: Text('搁置到明天'),
                            ),
                          ],
                          child: StatusPill(
                            label: _workStateLabel(item.workState),
                            positive: item.workState == WorkState.done,
                          ),
                        ),
                        if (item.readCount == 0)
                          const Text('未读', style: TextStyle(fontSize: 12)),
                        Text(
                          shortDate(item.createdAt).split(' ').first,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

String _libraryPreview(LibraryItem item) {
  final brief = item.analysis?.brief.trim() ?? '';
  if (brief.isNotEmpty) return brief;
  final summary = item.analysis?.summary.trim() ?? '';
  if (summary.isNotEmpty) return '摘录：$summary';
  final body = item.body.trim();
  if (body.isNotEmpty) return '摘录：$body';
  return item.url;
}

String _workStateLabel(WorkState state) => switch (state) {
  WorkState.pending => '待判断',
  WorkState.reading => '阅读中',
  WorkState.done => '已处理',
  WorkState.snoozed => '搁置',
};

String _libraryStatusLabel(LibraryItem item) {
  return switch (item.status) {
    'pending' => '待处理',
    'saved' => '已保存',
    'waiting' => '待配置模型',
    'analyzing' => '分析中',
    'ready' => '已分析',
    'failed' => '提取失败',
    'error' => '分析失败',
    'interrupted' => '已中断',
    _ => item.status.isEmpty ? '已保存' : item.status,
  };
}
