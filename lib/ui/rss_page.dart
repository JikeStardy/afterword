import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'common.dart';
import 'item_detail.dart';

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
    final data = widget.data;
    final controller = widget.controller;
    _selected.removeWhere((id) => !data.entries.any((entry) => entry.id == id));
    final entries =
        data.entries
            .where((entry) => !_hideProcessed || !entry.processed)
            .toList()
          ..sort((a, b) {
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
          icon: const Icon(Icons.refresh),
          onPressed: () =>
              runUiAction(context, controller.refreshFeeds, success: '订阅已刷新'),
        ),
        IconButton(
          tooltip: '添加订阅',
          icon: const Icon(Icons.add),
          onPressed: () => _addFeed(context),
        ),
      ],
      child: data.feeds.isEmpty && entries.isEmpty
          ? EmptyState(
              icon: Icons.rss_feed,
              title: '还没有 RSS 订阅',
              message: '添加订阅后只浏览条目；只有你选中的条目才会保存并进入分析。',
              action: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('添加订阅'),
                onPressed: () => _addFeed(context),
              ),
            )
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('隐藏已处理条目'),
                    value: _hideProcessed,
                    onChanged: (value) =>
                        setState(() => _hideProcessed = value),
                  ),
                ),
                for (final feed in data.feeds)
                  _FeedCard(
                    feed: feed,
                    onPaused: (value) => runUiAction(
                      context,
                      () => controller.setFeedPaused(feed.id, value),
                      success: value ? '订阅已暂停' : '订阅已恢复',
                    ),
                    onRemove: () => _removeFeed(context, feed),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 18, 16, 6),
                  child: Text('待挑选条目'),
                ),
                if (_selected.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.done_all),
                          label: Text('标记 ${_selected.length} 条已处理'),
                          onPressed: () => _processSelected(context, false),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.block),
                          label: const Text('批量跳过'),
                          onPressed: () => _processSelected(context, true),
                        ),
                      ],
                    ),
                  ),
                if (entries.isEmpty)
                  const EmptyState(
                    icon: Icons.inbox_outlined,
                    title: '暂无新条目',
                    message: '刷新订阅后，新内容会先停在这里等待你挑选。',
                  ),
                for (final entry in entries)
                  _EntryCard(
                    entry: entry,
                    selected: _selected.contains(entry.id),
                    feed: data.feeds
                        .where((feed) => feed.id == entry.feedId)
                        .firstOrNull,
                    savedItem: data.items
                        .where((item) => item.id == entry.savedItemId)
                        .firstOrNull,
                    onOpen: () {
                      final item = data.items
                          .where((item) => item.id == entry.savedItemId)
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
                    onSelect: entry.savedItemId == null
                        ? () => runUiAction(
                            context,
                            () => controller.selectEntry(entry.id),
                            success: '已保存并进入分析流程',
                          )
                        : null,
                    onToggleSelected: (value) => setState(() {
                      if (value) {
                        _selected.add(entry.id);
                      } else {
                        _selected.remove(entry.id);
                      }
                    }),
                    onSkip: entry.processed
                        ? null
                        : () => runUiAction(
                            context,
                            () => controller.processEntries([entry.id]),
                            success: '条目已跳过',
                          ),
                  ),
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

class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.feed,
    required this.onPaused,
    required this.onRemove,
  });

  final Feed feed;
  final ValueChanged<bool> onPaused;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.rss_feed),
        title: Text(feed.title.isEmpty ? feed.url : feed.title),
        subtitle: Text(
          feed.error.isEmpty
              ? '${feed.paused ? '已暂停 · ' : ''}上次刷新：${shortDate(feed.refreshedAt)}'
              : feed.error,
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: feed.paused ? '恢复订阅' : '暂停订阅',
              icon: Icon(feed.paused ? Icons.play_arrow : Icons.pause),
              onPressed: () => onPaused(!feed.paused),
            ),
            IconButton(
              tooltip: '退订',
              icon: const Icon(Icons.delete_outline),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
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
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(feed?.title.isEmpty == false ? feed!.title : entry.url),
          if (entry.summary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(entry.summary, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(
                label: savedItem == null
                    ? entry.skipped
                          ? '已跳过'
                          : entry.processed
                          ? '已处理'
                          : '未分析'
                    : savedItem!.isTrashed
                    ? '回收站'
                    : savedItem!.isArchived
                    ? '已归档'
                    : '已选中',
                positive: entry.savedItemId != null,
              ),
              FilledButton.icon(
                icon: const Icon(Icons.playlist_add_check),
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
    );
  }
}
