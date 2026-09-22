import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'common.dart';
import 'research_dialogs.dart';
import 'research_detail.dart';

class ResearchPage extends StatelessWidget {
  const ResearchPage({super.key, required this.controller, required this.data});

  final AppController controller;
  final AppData data;

  @override
  Widget build(BuildContext context) {
    return AppFrame(
      title: '研究',
      actions: [
        IconButton(
          tooltip: '单次研究',
          icon: const Icon(Icons.travel_explore),
          onPressed: () => _startResearch(context),
        ),
        IconButton(
          tooltip: '新建主题',
          icon: const Icon(Icons.add),
          onPressed: () => _addTopic(context),
        ),
      ],
      child: data.topics.isEmpty && data.runs.isEmpty
          ? EmptyState(
              icon: Icons.psychology_alt_outlined,
              title: '还没有研究主题',
              message: '可以先围绕一个长期问题建立主题，再把收藏资料积累成有来源的综述。',
              action: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('新建主题'),
                onPressed: () => _addTopic(context),
              ),
            )
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('主题'),
                ),
                for (final topic in data.topics)
                  _TopicCard(
                    topic: topic,
                    onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TopicDetailPage(
                          controller: controller,
                          topicId: topic.id,
                        ),
                      ),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 18, 16, 4),
                  child: Text('研究记录'),
                ),
                if (data.runs.isEmpty)
                  const SectionCard(child: Text('暂无外部研究记录')),
                for (final run in data.runs.reversed)
                  _RunCard(
                    run: run,
                    onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ResearchRunPage(
                          controller: controller,
                          runId: run.id,
                        ),
                      ),
                    ),
                  ),
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

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic, required this.onOpen});

  final Topic topic;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: onOpen,
        title: Text(topic.title),
        subtitle: Text(
          topic.overview.isEmpty ? topic.question : topic.overview,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          topic.tracking ? Icons.notifications_active : Icons.chevron_right,
        ),
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({required this.run, required this.onOpen});

  final ResearchRun run;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: onOpen,
        title: Text(run.goal, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text('${run.status} · ${run.calls}/${run.callLimit} 次调用'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
