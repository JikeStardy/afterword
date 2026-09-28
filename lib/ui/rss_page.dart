import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'common.dart';
import 'item_detail.dart';
import 'afterword_art.dart';

class RssPage extends StatefulWidget {
  const RssPage({super.key, required this.controller, required this.data});

  final AppController controller;
  final AppData data;

  @override
  State<RssPage> createState() => _RssPageState();
}

class _RssPageState extends State<RssPage> {
  final Set<String> _selected = {};
  bool _hideProcessed = true;

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    final data = widget.data;
    final controller = widget.controller;
    _selected.removeWhere((id) => !data.entries.any((entry) => entry.id == id));
    final entries =
        data.entries
            .where((entry) => !_hideProcessed || !entry.processed)
            .toList()
          ..sort((a, b) {
            if (a.processed != b.processed) return a.processed ? 1 : -1;
            final left =
                a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final right =
                b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return right.compareTo(left);
          });
    return AppFrame(
      title: 'RSS',
      actions: [
        IconButton(
          tooltip: '刷新订阅',
          icon: const AfterwordIcon(Icons.refresh),
          onPressed: () => _refreshFeeds(context),
        ),
        IconButton(
          tooltip: '添加订阅',
          icon: const AfterwordIcon(Icons.add),
          onPressed: () => _addFeed(context),
        ),
      ],
      child: data.feeds.isEmpty && entries.isEmpty
          ? EmptyState(
              scene: 'rss-empty',
              icon: Icons.rss_feed,
              title: '还没有 RSS 订阅',
              message: '添加订阅后只浏览条目；只有你选中的条目才会保存并进入分析。',
              action: FilledButton.icon(
                icon: const AfterwordIcon(Icons.add),
                label: const Text('添加订阅'),
                onPressed: () => _addFeed(context),
              ),
            )
          : ListView(
              padding: EdgeInsets.only(bottom: layout.sectionGap),
              children: [
                _FeedManager(
                  feeds: data.feeds,
                  hideProcessed: _hideProcessed,
                  onHideProcessedChanged: (value) =>
                      setState(() => _hideProcessed = value),
                  onPaused: (feed, value) => runUiAction(
                    context,
                    () => controller.setFeedPaused(feed.id, value),
                    success: value ? '订阅已暂停' : '订阅已恢复',
                  ),
                  onRemove: (feed) => _removeFeed(context, feed),
                ),
                _RssSectionHeader(title: '待挑选条目', count: entries.length),
                if (_selected.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      layout.pagePadding,
                      0,
                      layout.pagePadding,
                      8,
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          icon: const AfterwordIcon(Icons.done_all),
                          label: Text('标记 ${_selected.length} 条已处理'),
                          onPressed: () => _processSelected(context, false),
                        ),
                        OutlinedButton.icon(
                          icon: const AfterwordIcon(Icons.block),
                          label: const Text('批量跳过'),
                          onPressed: () => _processSelected(context, true),
                        ),
                      ],
                    ),
                  ),
                if (entries.isEmpty)
                  const EmptyState(
                    scene: 'feed-quiet',
                    icon: Icons.inbox_outlined,
                    title: '暂无新条目',
                    message: '刷新订阅后，新内容会先停在这里等待你挑选。',
                  ),
                for (final indexed in entries.indexed) ...[
                  _EntryRow(
                    entry: indexed.$2,
                    selected: _selected.contains(indexed.$2.id),
                    feed: data.feeds
                        .where((feed) => feed.id == indexed.$2.feedId)
                        .firstOrNull,
                    savedItem: data.items
                        .where((item) => item.id == indexed.$2.savedItemId)
                        .firstOrNull,
                    onOpen: () {
                      final item = data.items
                          .where((item) => item.id == indexed.$2.savedItemId)
                          .firstOrNull;
                      if (item != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ArticleDetailPage(
                              controller: controller,
                              item: item,
                            ),
                          ),
                        );
                      }
                    },
                    onSelect: indexed.$2.savedItemId == null
                        ? () => runUiAction(
                            context,
                            () => controller.selectEntry(indexed.$2.id),
                            success: '已保存并进入分析流程',
                          )
                        : null,
                    onToggleSelected: (value) => setState(() {
                      if (value) {
                        _selected.add(indexed.$2.id);
                      } else {
                        _selected.remove(indexed.$2.id);
                      }
                    }),
                    onSkip: indexed.$2.processed
                        ? null
                        : () => runUiAction(
                            context,
                            () => controller.processEntries([indexed.$2.id]),
                            success: '条目已跳过',
                          ),
                  ),
                  if (indexed.$1 != entries.length - 1)
                    Divider(
                      height: 1,
                      indent: layout.pagePadding,
                      endIndent: layout.pagePadding,
                    ),
                ],
              ],
            ),
    );
  }

  Future<void> _addFeed(BuildContext context) async {
    final url = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('添加 RSS 订阅'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: '订阅地址'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('添加'),
            ),
          ],
        );
      },
    );
    if (url == null || url.trim().isEmpty || !context.mounted) {
      return;
    }
    await runUiAction(
      context,
      () => widget.controller.addFeed(url.trim()),
      success: '订阅已添加',
    );
  }

  Future<void> _refreshFeeds(BuildContext context) async {
    try {
      final result = await widget.controller.refreshFeeds();
      if (!context.mounted) return;
      final message = result.hasFailures
          ? 'RSS 刷新完成：成功 ${result.succeeded}，失败 ${result.failed}'
          : 'RSS 刷新完成：成功 ${result.succeeded}';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _processSelected(BuildContext context, bool skipped) async {
    final ids = _selected.toList();
    await runUiAction(
      context,
      () => widget.controller.processEntries(ids, skipped: skipped),
      success: skipped ? '已批量跳过' : '已标记处理',
    );
    if (mounted) setState(_selected.clear);
  }

  Future<void> _removeFeed(BuildContext context, Feed feed) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退订 RSS？'),
        content: Text(feed.title.isEmpty ? feed.url : feed.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退订'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await runUiAction(
      context,
      () => widget.controller.removeFeed(feed.id),
      success: '订阅已移除',
    );
  }
}

class _FeedManager extends StatelessWidget {
  const _FeedManager({
    required this.feeds,
    required this.hideProcessed,
    required this.onHideProcessedChanged,
    required this.onPaused,
    required this.onRemove,
  });

  final List<Feed> feeds;
  final bool hideProcessed;
  final ValueChanged<bool> onHideProcessedChanged;
  final void Function(Feed feed, bool paused) onPaused;
  final ValueChanged<Feed> onRemove;

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    final errorCount = feeds.where((feed) => feed.error.isNotEmpty).length;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text('订阅管理', style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(
          errorCount == 0
              ? '${feeds.length} 个订阅'
              : '$errorCount 个异常 · ${feeds.length} 个订阅',
        ),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('隐藏已处理条目'),
            value: hideProcessed,
            onChanged: onHideProcessedChanged,
          ),
          if (feeds.isEmpty)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('还没有订阅'),
            ),
          for (final feed in feeds)
            _FeedRow(
              feed: feed,
              onPaused: (value) => onPaused(feed, value),
              onRemove: () => onRemove(feed),
            ),
        ],
      ),
    );
  }
}

class _RssSectionHeader extends StatelessWidget {
  const _RssSectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        layout.pagePadding,
        layout.sectionGap / 2,
        layout.pagePadding,
        6,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          Text('$count 条', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({
    required this.feed,
    required this.onPaused,
    required this.onRemove,
  });

  final Feed feed;
  final ValueChanged<bool> onPaused;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const AfterwordIcon(Icons.rss_feed),
      title: Text(feed.title.isEmpty ? feed.url : feed.title),
      subtitle: Text(
        feed.error.isEmpty
            ? '${feed.paused ? '已暂停 · ' : ''}上次刷新：${shortDate(feed.refreshedAt)}'
            : feed.error,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: feed.paused ? '恢复订阅' : '暂停订阅',
            icon: AfterwordIcon(feed.paused ? Icons.play_arrow : Icons.pause),
            onPressed: () => onPaused(!feed.paused),
          ),
          IconButton(
            tooltip: '退订',
            icon: const AfterwordIcon(Icons.delete_outline),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.feed,
    required this.onSelect,
    required this.onOpen,
    required this.savedItem,
    required this.selected,
    required this.onToggleSelected,
    required this.onSkip,
  });

  final FeedEntry entry;
  final Feed? feed;
  final VoidCallback? onSelect;
  final VoidCallback onOpen;
  final LibraryItem? savedItem;
  final bool selected;
  final ValueChanged<bool> onToggleSelected;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          layout.pagePadding,
          layout.rowPadding,
          layout.pagePadding,
          layout.rowPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        feed?.title.isEmpty == false ? feed!.title : entry.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: _statusLabel(),
                  positive: entry.savedItemId != null,
                ),
              ],
            ),
            if (entry.summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(entry.summary, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const AfterwordIcon(Icons.playlist_add_check),
                  label: Text(savedItem == null ? '选中处理' : '打开资料'),
                  onPressed: savedItem == null ? onSelect : onOpen,
                ),
                OutlinedButton(onPressed: onSkip, child: const Text('跳过')),
                FilterChip(
                  label: const Text('批量选择'),
                  selected: selected,
                  onSelected: onToggleSelected,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel() => savedItem == null
      ? entry.skipped
            ? '已跳过'
            : entry.processed
            ? '已处理'
            : '未分析'
      : savedItem!.isTrashed
      ? '回收站'
      : savedItem!.isArchived
      ? '已归档'
      : '已选中';
}
