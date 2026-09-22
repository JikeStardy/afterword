import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'common.dart';
import 'item_detail.dart';

class RssPage extends StatelessWidget {
  const RssPage({super.key, required this.controller, required this.data});

  final AppController controller;
  final AppData data;

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList()
      ..sort((a, b) {
        final left = a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
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
                for (final feed in data.feeds) _FeedCard(feed: feed),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 18, 16, 6),
                  child: Text('待挑选条目'),
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
      () => controller.addFeed(url.trim()),
      success: '订阅已添加',
    );
  }
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.feed});

  final Feed feed;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.rss_feed),
        title: Text(feed.title.isEmpty ? feed.url : feed.title),
        subtitle: Text(
          feed.error.isEmpty
              ? '上次刷新：${shortDate(feed.refreshedAt)}'
              : feed.error,
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
  });

  final FeedEntry entry;
  final Feed? feed;
  final VoidCallback? onSelect;
  final VoidCallback onOpen;
  final LibraryItem? savedItem;

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
                    ? '未分析'
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
            ],
          ),
        ],
      ),
    );
  }
}
