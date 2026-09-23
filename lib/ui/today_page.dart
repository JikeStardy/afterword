import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'common.dart';
import 'item_detail.dart';
import 'research_detail.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.controller, required this.data});

  final AppController controller;
  final AppData data;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.todaySnapshot;
    final entries = snapshot.entries.take(5).toList();
    final jobs = controller.pendingJobs;
    return AppFrame(
      title: '今日',
      actions: [
        IconButton(
          tooltip: '补充今日推荐',
          icon: const Icon(Icons.refresh),
          onPressed: () => runUiAction(
            context,
            () => controller.refreshToday(refill: true),
            success: '今日推荐已更新',
          ),
        ),
      ],
      child: ListView(
        children: [
          if (entries.isEmpty)
            EmptyState(
              icon: Icons.today_outlined,
              title: '今天没有新的推荐',
              message: '已处理、失效或延后的内容不会反复出现。',
              action: OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('手动补充'),
                onPressed: () => runUiAction(
                  context,
                  () => controller.refreshToday(refill: true),
                  success: '已重新整理今日推荐',
                ),
              ),
            )
          else ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text('今日推荐'),
            ),
            for (final entry in entries)
              _TodayCard(controller: controller, data: data, entry: entry),
          ],
          if (jobs.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text('后台任务'),
            ),
            for (final job in jobs)
              _JobCard(controller: controller, data: data, job: job),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.controller,
    required this.data,
    required this.entry,
  });

  final AppController controller;
  final AppData data;
  final TodayEntry entry;

  @override
  Widget build(BuildContext context) {
    final title = _title();
    final subtitle = _subtitle();
    final item = entry.entityType == 'item'
        ? data.items.where((item) => item.id == entry.entityId).firstOrNull
        : null;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon(), color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (entry.reason.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(entry.reason),
          ],
          if (entry.relatedIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('关联：${entry.relatedIds.length} 个来源'),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('打开'),
                onPressed: () => _open(context),
              ),
              if (item != null)
                OutlinedButton(
                  onPressed: () => runUiAction(
                    context,
                    () => controller.setWorkState(item.id, WorkState.reading),
                    success: '已标为阅读中',
                  ),
                  child: const Text('阅读中'),
                ),
              OutlinedButton(
                onPressed: () => runUiAction(
                  context,
                  () => controller.completeToday(entry.id),
                  success: '已处理',
                ),
                child: const Text('已处理'),
              ),
              TextButton(
                onPressed: () => runUiAction(
                  context,
                  () => controller.dismissToday(entry.id),
                  success: '已跳过',
                ),
                child: const Text('跳过'),
              ),
              TextButton(
                onPressed: () => runUiAction(
                  context,
                  () => controller.dismissToday(entry.id, defer: true),
                  success: '已延后到明天',
                ),
                child: const Text('延后'),
              ),
              if (item != null)
                TextButton(
                  onPressed: () => runUiAction(
                    context,
                    () => controller.setFeedback(item.id, -1),
                    success: '会减少类似推荐',
                  ),
                  child: const Text('少推荐'),
                ),
              if (item != null)
                TextButton(
                  onPressed: () => runUiAction(
                    context,
                    () => controller.setFeedback(item.id, 1),
                    success: '已记录偏好',
                  ),
                  child: const Text('有用'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _icon() => switch (entry.entityType) {
    'topic' => Icons.travel_explore_outlined,
    'run' => Icons.science_outlined,
    _ => Icons.article_outlined,
  };

  String _title() => switch (entry.entityType) {
    'topic' =>
      data.topics
              .where((topic) => topic.id == entry.entityId)
              .firstOrNull
              ?.title ??
          '主题已不可用',
    'run' =>
      data.runs.where((run) => run.id == entry.entityId).firstOrNull?.goal ??
          '研究已不可用',
    _ =>
      data.items
              .where((item) => item.id == entry.entityId)
              .firstOrNull
              ?.title ??
          '资料已不可用',
  };

  String _subtitle() => switch (entry.entityType) {
    'topic' =>
      data.topics
              .where((topic) => topic.id == entry.entityId)
              .firstOrNull
              ?.question ??
          '等待重新整理推荐',
    'run' =>
      data.runs.where((run) => run.id == entry.entityId).firstOrNull?.status ??
          '等待重新整理推荐',
    _ =>
      data.items
              .where((item) => item.id == entry.entityId)
              .firstOrNull
              ?.body
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim() ??
          '等待重新整理推荐',
  };

  void _open(BuildContext context) {
    switch (entry.entityType) {
      case 'topic':
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => TopicDetailPage(
              controller: controller,
              topicId: entry.entityId,
            ),
          ),
        );
      case 'item':
        final item = data.items
            .where((item) => item.id == entry.entityId)
            .firstOrNull;
        if (item == null) return;
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                ArticleDetailPage(controller: controller, item: item),
          ),
        );
      default:
        final run = data.runs
            .where((run) => run.id == entry.entityId)
            .firstOrNull;
        if (run?.topicId == null) return;
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                TopicDetailPage(controller: controller, topicId: run!.topicId!),
          ),
        );
    }
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.controller,
    required this.data,
    required this.job,
  });

  final AppController controller;
  final AppData data;
  final BackgroundJob job;

  @override
  Widget build(BuildContext context) {
    final completed = (job.checkpoint['completed'] as num?)?.toInt() ?? 0;
    final total = (job.checkpoint['total'] as num?)?.toInt() ?? 0;
    final progress = total <= 0 ? null : completed / total;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_jobIcon()),
            title: Text(_jobTitle()),
            subtitle: Text(job.error.isEmpty ? job.stage : job.error),
            trailing: StatusPill(
              label: _statusLabel(job.status),
              positive: job.status == 'running',
            ),
          ),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.close),
                label: const Text('取消'),
                onPressed: () => runUiAction(
                  context,
                  () => controller.cancelJob(job.id),
                  success: '任务已取消',
                ),
              ),
              if (job.status == 'paused')
                FilledButton.icon(
                  icon: const Icon(Icons.replay),
                  label: const Text('重试'),
                  onPressed: () => runUiAction(
                    context,
                    () => controller.retryJob(job.id),
                    success: '任务已重新排队',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _jobIcon() => switch (job.type) {
    'research' => Icons.science_outlined,
    'synthesis' => Icons.travel_explore_outlined,
    'fetch' => Icons.public,
    _ => Icons.auto_awesome,
  };

  String _jobTitle() {
    final item = data.items
        .where((item) => item.id == job.entityId)
        .firstOrNull;
    final topic = data.topics
        .where((topic) => topic.id == job.entityId)
        .firstOrNull;
    final run = data.runs.where((run) => run.id == job.entityId).firstOrNull;
    return item?.title ?? topic?.title ?? run?.goal ?? job.type;
  }

  String _statusLabel(String value) => switch (value) {
    'queued' => '排队中',
    'running' => '运行中',
    'paused' => '已暂停',
    _ => value,
  };
}
