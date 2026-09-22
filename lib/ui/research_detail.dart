import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'common.dart';
import 'developer_page.dart';
import 'item_detail.dart';
import 'research_dialogs.dart';

class TopicDetailPage extends StatelessWidget {
  const TopicDetailPage({
    super.key,
    required this.controller,
    required this.topicId,
  });

  final AppController controller;
  final String topicId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _buildTopic(context),
    );
  }

  Widget _buildTopic(BuildContext context) {
    final topic = controller.data.topics
        .where((candidate) => candidate.id == topicId)
        .firstOrNull;
    if (topic == null) {
      return const AppFrame(
        title: '主题',
        child: EmptyState(
          icon: Icons.search_off,
          title: '主题不存在',
          message: '它可能已经在其他窗口中被更新。',
        ),
      );
    }
    return AppFrame(
      title: topic.title,
      actions: [
        IconButton(
          tooltip: '编辑主题',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => _editTopic(context, topic),
        ),
        IconButton(
          tooltip: '更新综述',
          icon: const Icon(Icons.auto_awesome),
          onPressed: topic.status == 'synthesizing'
              ? null
              : () => runUiAction(
                  context,
                  () => _synthesize(topic.id),
                  success: '综述已更新',
                ),
        ),
      ],
      child: ListView(
        children: [
          _OverviewCard(topic: topic, controller: controller),
          if (topic.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton.icon(
                onPressed: () =>
                    openDiagnostics(context, controller, entityId: topic.id),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('查看任务日志'),
              ),
            ),
          _TopicRunCard(controller: controller, runs: _topicRuns(topic.id)),
          _TrackingCard(topic: topic, controller: controller),
          SectionCard(
            child: SourceList(
              sources: topic.sourceIds,
              labelForSource: controller.sourceLabel,
              onSourceTap: (source) => _openSource(context, source),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _synthesize(String id) async {
    await controller.synthesizeTopic(id);
    final topic = controller.data.topics
        .where((candidate) => candidate.id == id)
        .firstOrNull;
    if (topic == null) {
      throw StateError('主题不存在');
    }
    if (topic.status == 'error' || topic.error.isNotEmpty) {
      throw StateError(topic.error);
    }
    if (topic.status != 'ready') {
      throw StateError('综述尚未完成');
    }
  }

  List<ResearchRun> _topicRuns(String topicId) {
    return controller.data.runs.where((run) => run.topicId == topicId).toList();
  }

  void _openSource(BuildContext context, String source) {
    final item = controller.data.items
        .where((candidate) => candidate.id == source)
        .firstOrNull;
    if (item != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ArticleDetailPage(controller: controller, item: item),
        ),
      );
      return;
    }
    final run = controller.data.runs
        .where((candidate) => candidate.id == source)
        .firstOrNull;
    if (run != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ResearchRunPage(controller: controller, runId: run.id),
        ),
      );
    }
  }

  Future<void> _editTopic(BuildContext context, Topic topic) async {
    final result = await showTopicDialog(
      context,
      title: topic.title,
      question: topic.question,
    );
    if (result == null || !context.mounted) {
      return;
    }
    await runUiAction(
      context,
      () => controller.updateTopic(topic.id, result.$1, result.$2),
      success: '主题已更新',
    );
  }
}

class ResearchRunPage extends StatelessWidget {
  const ResearchRunPage({
    super.key,
    required this.controller,
    required this.runId,
  });

  final AppController controller;
  final String runId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final run = controller.data.runs
            .where((candidate) => candidate.id == runId)
            .firstOrNull;
        if (run == null) {
          return const AppFrame(
            title: '研究记录',
            child: EmptyState(
              icon: Icons.search_off,
              title: '研究记录不存在',
              message: '它可能已经在其他窗口中被更新。',
            ),
          );
        }
        return _ResearchRunView(controller: controller, run: run);
      },
    );
  }
}

class _ResearchRunView extends StatelessWidget {
  const _ResearchRunView({required this.controller, required this.run});

  final AppController controller;
  final ResearchRun run;

  @override
  Widget build(BuildContext context) {
    return AppFrame(
      title: '研究记录',
      child: ListView(
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(run.goal, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                StatusPill(label: run.status, positive: run.status == 'done'),
                const SizedBox(height: 8),
                Text('调用：${run.calls}/${run.callLimit}'),
                Text('开始：${shortDate(run.startedAt)}'),
                if (run.completedAt != null)
                  Text('完成：${shortDate(run.completedAt)}'),
              ],
            ),
          ),
          if (run.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton.icon(
                onPressed: () =>
                    openDiagnostics(context, controller, entityId: run.id),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('查看任务日志'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SelectableText(
              run.report.isEmpty ? run.error : run.report,
              style: const TextStyle(fontSize: 17, height: 1.7),
            ),
          ),
          if (run.steps.isNotEmpty)
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('步骤', style: Theme.of(context).textTheme.titleMedium),
                  for (final step in run.steps) Text('• $step'),
                ],
              ),
            ),
          if (run.sources.isNotEmpty)
            _SourcesCard(controller: controller, sources: run.sources),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.topic, required this.controller});

  final Topic topic;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(topic.question, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                label: topic.status,
                positive: topic.status == 'ready',
              ),
              if (topic.error.isNotEmpty)
                Text(
                  topic.error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            topic.overview.isEmpty
                ? '暂无综述，更新后会在这里沉淀当前认识。'
                : readerCitationText(
                    topic.overview,
                    topic.sourceIds,
                    labelForSource: controller.sourceLabel,
                  ),
            style: const TextStyle(fontSize: 17, height: 1.7),
          ),
          if (topic.reason.isNotEmpty) ...[
            const Divider(),
            Text('触发原因：${topic.reason}'),
          ],
        ],
      ),
    );
  }
}

class _TrackingCard extends StatelessWidget {
  const _TrackingCard({required this.topic, required this.controller});

  final Topic topic;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('持续追踪', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('上次执行：${shortDate(topic.lastRun)}'),
          Text('下次状态：${shortDate(topic.nextRun)}'),
          Text('调用上限：${topic.callLimit}，间隔：${topic.intervalHours} 小时'),
          const SizedBox(height: 12),
          Row(
            children: [
              StatusPill(
                label: topic.tracking ? '已授权' : '未开启',
                positive: topic.tracking,
              ),
              const Spacer(),
              TextButton.icon(
                icon: Icon(topic.tracking ? Icons.pause : Icons.play_arrow),
                label: Text(topic.tracking ? '暂停追踪' : '授权追踪'),
                onPressed: () =>
                    topic.tracking ? _pause(context) : _authorize(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pause(BuildContext context) {
    return runUiAction(
      context,
      () => controller.setTracking(topic.id, enabled: false, confirmed: true),
      success: '追踪已暂停',
    );
  }

  Future<void> _authorize(BuildContext context) async {
    final result = await showTrackingDialog(context, topic);
    if (result == null || !context.mounted) {
      return;
    }
    await runUiAction(
      context,
      () => controller.setTracking(
        topic.id,
        enabled: true,
        intervalHours: result.intervalHours,
        callLimit: result.callLimit,
        confirmed: true,
      ),
      success: '持续追踪已授权',
    );
  }
}

class _TopicRunCard extends StatelessWidget {
  const _TopicRunCard({required this.controller, required this.runs});

  final AppController controller;
  final List<ResearchRun> runs;

  @override
  Widget build(BuildContext context) {
    if (runs.isEmpty) {
      return const SectionCard(child: Text('暂无关联外部研究记录'));
    }
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('关联外部研究', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final run in runs)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.travel_explore_outlined),
              title: Text(
                run.goal,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${run.sources.length} 个来源 · ${shortDate(run.completedAt ?? run.startedAt)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ResearchRunPage(controller: controller, runId: run.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SourcesCard extends StatelessWidget {
  const _SourcesCard({required this.controller, required this.sources});

  final AppController controller;
  final List<ResearchSource> sources;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('来源', style: Theme.of(context).textTheme.titleMedium),
          for (final source in sources)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link),
              title: Text(source.title),
              subtitle: Text(source.url),
              onTap: () => runUiAction(
                context,
                () => controller.native.openUrl(source.url),
              ),
            ),
        ],
      ),
    );
  }
}
