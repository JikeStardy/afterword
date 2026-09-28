import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'common.dart';
import 'research_dialogs.dart';
import 'research_detail.dart';
import 'afterword_art.dart';

class ResearchPage extends StatelessWidget {
  const ResearchPage({super.key, required this.controller, required this.data});

  final AppController controller;
  final AppData data;

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    final runs = data.runs.reversed.toList();
    return AppFrame(
      title: '研究',
      actions: [
        IconButton(
          tooltip: '单次研究',
          icon: const AfterwordIcon(Icons.travel_explore),
          onPressed: () => _startResearch(context),
        ),
        IconButton(
          tooltip: '新建主题',
          icon: const AfterwordIcon(Icons.add),
          onPressed: () => _addTopic(context),
        ),
      ],
      child: data.topics.isEmpty && data.runs.isEmpty
          ? EmptyState(
              scene: 'research-empty',
              icon: Icons.psychology_alt_outlined,
              title: '还没有研究主题',
              message: '可以先围绕一个长期问题建立主题，再把收藏资料积累成有来源的综述。',
              action: FilledButton.icon(
                icon: const AfterwordIcon(Icons.add),
                label: const Text('新建主题'),
                onPressed: () => _addTopic(context),
              ),
            )
          : ListView(
              padding: EdgeInsets.only(bottom: layout.sectionGap),
              children: [
                _ResearchSectionHeader(title: '主题', count: data.topics.length),
                for (final indexed in data.topics.indexed) ...[
                  _TopicRow(
                    topic: indexed.$2,
                    onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TopicDetailPage(
                          controller: controller,
                          topicId: indexed.$2.id,
                        ),
                      ),
                    ),
                  ),
                  if (indexed.$1 != data.topics.length - 1)
                    Divider(
                      height: 1,
                      indent: layout.pagePadding,
                      endIndent: layout.pagePadding,
                    ),
                ],
                SizedBox(height: layout.sectionGap / 2),
                _ResearchSectionHeader(title: '研究活动', count: runs.length),
                if (runs.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: layout.pagePadding,
                    ),
                    child: const Text('暂无外部研究记录'),
                  ),
                for (final indexed in runs.indexed) ...[
                  _RunRow(
                    run: indexed.$2,
                    onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ResearchRunPage(
                          controller: controller,
                          runId: indexed.$2.id,
                        ),
                      ),
                    ),
                  ),
                  if (indexed.$1 != runs.length - 1)
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

  Future<void> _addTopic(BuildContext context) async {
    final result = await showTopicDialog(context);
    if (result == null || !context.mounted) {
      return;
    }
    await runUiAction(
      context,
      () => controller.addTopic(result.$1, result.$2),
      success: '主题已创建',
    );
  }

  Future<void> _startResearch(BuildContext context) async {
    final result = await showResearchDialog(context, data.topics);
    if (result == null || !context.mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认外部研究'),
        content: Text(
          '目标：${result.goal}\n调用上限：${result.callLimit}\n\n会使用搜索服务和模型推理。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await runUiAction(
      context,
      () => controller.research(
        goal: result.goal,
        topicId: result.topicId,
        confirmed: true,
        callLimit: result.callLimit,
      ),
      success: '研究已完成',
    );
  }
}

class _ResearchSectionHeader extends StatelessWidget {
  const _ResearchSectionHeader({required this.title, required this.count});

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
          Text('$count 项', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({required this.topic, required this.onOpen});

  final Topic topic;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    final brief = _clean(
      topic.overview.isEmpty ? topic.question : topic.overview,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding,
            layout.rowPadding,
            layout.pagePadding,
            layout.rowPadding,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AfterwordIcon(
                topic.tracking
                    ? Icons.notifications_active
                    : Icons.travel_explore_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topic.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (brief.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(brief, maxLines: 3, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        StatusPill(
                          label: topic.tracking
                              ? '跟踪中'
                              : _topicStatus(topic.status),
                          positive: topic.tracking,
                        ),
                        Text(
                          '${topic.sourceIds.length} 个来源',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (topic.overviewStale)
                          const Text('综述待更新', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              const AfterwordIcon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunRow extends StatelessWidget {
  const _RunRow({required this.run, required this.onOpen});

  final ResearchRun run;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    final brief = _runBrief(run);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding,
            layout.rowPadding,
            layout.pagePadding,
            layout.rowPadding,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AfterwordIcon(
                researchRunIsComplete(run)
                    ? Icons.check_circle_outline
                    : Icons.science_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      run.goal,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (brief.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(brief, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        StatusPill(
                          label: researchRunStatusLabel(run.status),
                          positive: researchRunIsComplete(run),
                        ),
                        Text(
                          '${run.calls}/${run.callLimit} 次调用',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (run.sources.isNotEmpty)
                          Text(
                            '${run.sources.length} 个外部来源',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const AfterwordIcon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

String _topicStatus(String value) => switch (value) {
  'idle' => '未跟踪',
  'running' => '研究中',
  'failed' => '有异常',
  _ => value.isEmpty ? '未跟踪' : value,
};

String _runBrief(ResearchRun run) {
  if (run.error.isNotEmpty) return run.error;
  if (run.report.isNotEmpty) return _clean(run.report);
  if (run.pendingStage.isNotEmpty) return run.pendingStage;
  if (run.steps.isNotEmpty) return run.steps.last;
  return run.status;
}

String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
