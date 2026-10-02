import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'common.dart';
import 'afterword_art.dart';

class ItemActionsMenu extends StatelessWidget {
  const ItemActionsMenu({
    super.key,
    required this.controller,
    required this.items,
    this.onDone,
  });
  final AppController controller;
  final List<LibraryItem> items;
  final VoidCallback? onDone;
  @override
  Widget build(BuildContext context) {
    final trashed = items.every((item) => item.isTrashed);
    final archived = items.every((item) => item.isArchived);
    return PopupMenuButton<String>(
      tooltip: '管理资料',
      icon: const AfterwordIcon(Icons.more_horiz),
      onSelected: (action) async {
        await performItemAction(context, controller, action, items);
        onDone?.call();
      },
      itemBuilder: (_) => [
        if (trashed) ...[
          const PopupMenuItem(value: 'restore', child: Text('恢复资料')),
          const PopupMenuItem(value: 'purge', child: Text('永久删除')),
        ] else ...[
          PopupMenuItem(
            value: archived ? 'unarchive' : 'archive',
            child: Text(archived ? '取消归档' : '归档'),
          ),
          const PopupMenuItem(value: 'trash', child: Text('移入回收站')),
        ],
      ],
    );
  }
}

Future<void> performItemAction(
  BuildContext context,
  AppController controller,
  String action,
  List<LibraryItem> items,
) async {
  if (items.isEmpty) return;
  if (action == 'purge') {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除资料？'),
        content: Text('将永久删除 ${items.length} 项资料及其相关详细日志。此操作无法撤销。历史来源将显示为已移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
  }
  final ids = items.map((item) => item.id).toList();
  await runUiAction(
    context,
    () => switch (action) {
      'archive' => controller.archiveItems(ids),
      'unarchive' => controller.unarchiveItems(ids),
      'trash' => controller.trashItems(ids),
      'restore' => controller.restoreItems(ids),
      'purge' => controller.purgeItems(ids),
      _ => Future<void>.value(),
    },
  );
}
