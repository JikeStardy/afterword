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
    final layout = ReadingLayout.of(context);
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
        padding: EdgeInsets.only(bottom: layout.sectionGap),
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
            _ReadingSectionHeader(title: '今日推荐', count: entries.length),
            for (final entry in entries)
              _TodayRow(controller: controller, data: data, entry: entry),
          ],
          if (jobs.isNotEmpty) ...[
            SizedBox(height: layout.sectionGap / 2),
            _ReadingSectionHeader(title: '后台任务', count: jobs.length),
            for (final job in jobs)
              _JobCard(controller: controller, data: data, job: job),
          ],
        ],
      ),
    );
  }
}

class _ReadingSectionHeader extends StatelessWidget {
  const _ReadingSectionHeader({required this.title, this.count});

  final String title;
  final int? count;

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
          if (count != null)
            Text('$count 项', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _TodayRow extends StatelessWidget {
  const _TodayRow({
    required this.controller,
    required this.data,
    required this.entry,
  });

  final AppController controller;
  final AppData data;
  final TodayEntry entry;

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    final item = _item();
    final title = _title();
    final excerpt = _excerpt();
    final sourceSummary = _sourceSummary();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _open(context),
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
                children: [
                  Icon(
                    _icon(),
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _metaLabel(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  if (sourceSummary.isNotEmpty)
                    Flexible(
                      child: Text(
                        sourceSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                key: Key('today-title-${entry.id}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                excerpt,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (entry.reason.isNotEmpty) ...[
                const SizedBox(height: 8),
                _LabelledLine(label: '推荐原因', text: entry.reason),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.done),
                    label: const Text('已处理'),
                    onPressed: () => runUiAction(
                      context,
                      () => controller.completeToday(entry.id),
                      success: '已处理',
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '更多操作',
                    onSelected: (value) => _handleMenu(context, value, item),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'open', child: Text('打开')),
                      if (item != null)
                        const PopupMenuItem(
                          value: 'reading',
                          child: Text('标为阅读中'),
                        ),
                      const PopupMenuItem(value: 'skip', child: Text('跳过')),
                      const PopupMenuItem(value: 'defer', child: Text('延后')),
                      if (item != null)
                        const PopupMenuItem(
                          value: 'less',
                          child: Text('少推荐类似'),
                        ),
                      if (item != null)
                        const PopupMenuItem(value: 'useful', child: Text('有用')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  LibraryItem? _item() => entry.entityType == 'item'
      ? data.items.where((item) => item.id == entry.entityId).firstOrNull
      : null;

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

  String _metaLabel() => switch (entry.entityType) {
    'topic' => '主题复盘',
    'run' => '研究记录',
    _ => '阅读资料',
  };

  String _excerpt() {
    final item = _item();
    final topic = data.topics
        .where((topic) => topic.id == entry.entityId)
        .firstOrNull;
    final run = data.runs.where((run) => run.id == entry.entityId).firstOrNull;
    final text = switch (entry.entityType) {
      'topic' => _firstText([
        topic?.presentation?.brief,
        topic?.overview,
        topic?.question,
      ]),
      'run' => _firstText([run?.presentation?.brief, run?.report, run?.status]),
      _ => _firstText([
        item?.analysis?.brief,
        item?.analysis?.summary,
        item?.body,
      ]),
    };
    final cleaned = _clean(text);
    if (cleaned.isEmpty) return '等待重新整理推荐';
    final hasGuide = switch (entry.entityType) {
      'topic' => topic?.presentation?.brief.trim().isNotEmpty == true,
      'run' => run?.presentation?.brief.trim().isNotEmpty == true,
      _ => item?.analysis?.brief.trim().isNotEmpty == true,
    };
    return hasGuide ? cleaned : '摘录：$cleaned';
  }

  String _sourceSummary() {
    if (entry.relatedIds.isEmpty) return '';
    if (entry.entityType == 'item' &&
        entry.relatedIds.length == 1 &&
        entry.relatedIds.single == entry.entityId) {
      return '来源：当前资料';
    }
    final titles = [
      for (final id in entry.relatedIds)
        data.items.where((item) => item.id == id).firstOrNull?.title,
    ].whereType<String>().where((title) => title.trim().isNotEmpty).toList();
    if (titles.isEmpty) return '来源：${entry.relatedIds.length} 个关联资料';
    final visible = titles.take(2).join('、');
    final more = titles.length > 2 ? ' 等 ${titles.length} 个来源' : '';
    return '来源：$visible$more';
  }

  void _handleMenu(BuildContext context, String value, LibraryItem? item) {
    switch (value) {
      case 'open':
        _open(context);
      case 'reading':
        if (item == null) return;
        runUiAction(
          context,
          () => controller.setWorkState(item.id, WorkState.reading),
          success: '已标为阅读中',
        );
      case 'skip':
        runUiAction(
          context,
          () => controller.dismissToday(entry.id),
          success: '已跳过',
        );
      case 'defer':
        runUiAction(
          context,
          () => controller.dismissToday(entry.id, defer: true),
          success: '已延后到明天',
        );
      case 'less':
        if (item == null) return;
        runUiAction(
          context,
          () => controller.setFeedback(item.id, -1),
          success: '会减少类似推荐',
        );
      case 'useful':
        if (item == null) return;
        runUiAction(
          context,
          () => controller.setFeedback(item.id, 1),
          success: '已记录偏好',
        );
    }
  }

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
        final item = _item();
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

class _LabelledLine extends StatelessWidget {
  const _LabelledLine({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
        Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
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
            title: Text(
              _jobTitle(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              job.error.isEmpty ? job.stage : job.error,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
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

String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

String _firstText(Iterable<String?> values) {
  for (final value in values) {
    final cleaned = _clean(value ?? '');
    if (cleaned.isNotEmpty) return cleaned;
  }
  return '';
}
