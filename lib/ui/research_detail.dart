import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../services/knowledge_service.dart';
import 'common.dart';
import 'conversation_page.dart';
import 'developer_page.dart';
import 'item_detail.dart';
import 'knowledge_page.dart';
import 'reading_content.dart';
import 'research_dialogs.dart';
import 'afterword_art.dart';

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
          scene: 'item-missing',
          icon: Icons.search_off,
          title: '主题不存在',
          message: '它可能已经在其他窗口中被更新。',
        ),
      );
    }
    final sourceContext = _TopicReadingSourceContext.resolve(topic, controller);
    return AppFrame(
      title: topic.title,
      actions: [
        IconButton(
          tooltip: '围绕主题讨论',
          icon: const AfterwordIcon(Icons.question_answer_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ConversationPage(
                controller: controller,
                scope: ConversationScope.topic,
                scopeId: topic.id,
                sourceIds: topic.sourceIds,
                title: '围绕主题讨论',
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: '知识草稿',
          icon: const AfterwordIcon(Icons.library_add_check_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  KnowledgePage(controller: controller, topicId: topic.id),
            ),
          ),
        ),
        IconButton(
          tooltip: '编辑主题',
          icon: const AfterwordIcon(Icons.edit_outlined),
          onPressed: () => _editTopic(context, topic),
        ),
        IconButton(
          tooltip: '更新综述',
          icon: const AfterwordIcon(Icons.auto_awesome),
          onPressed: topic.status == 'synthesizing'
              ? null
              : () => runUiAction(
                  context,
                  () => _queueSynthesis(topic.id),
                  success: '综述更新已提交',
                ),
        ),
        IconButton(
          tooltip: '导出 Markdown',
          icon: const AfterwordIcon(Icons.download_outlined),
          onPressed: () => _exportMarkdown(context, topic),
        ),
      ],
      child: ListView(
        padding: EdgeInsets.only(
          top: ReadingLayout.of(context).sectionGap,
          bottom: 40,
        ),
        children: [
          _OverviewCard(
            topic: topic,
            controller: controller,
            sourceContext: sourceContext,
          ),
          KnowledgePanel(controller: controller, topic: topic),
          _TopicContextCard(topic: topic, controller: controller),
          _TopicScopeCard(topic: topic, controller: controller),
          if (topic.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton.icon(
                onPressed: () =>
                    openDiagnostics(context, controller, entityId: topic.id),
                icon: const AfterwordIcon(Icons.receipt_long_outlined),
                label: const Text('查看任务日志'),
              ),
            ),
          _TopicRunCard(controller: controller, runs: _topicRuns(topic.id)),
          _TrackingCard(topic: topic, controller: controller),
          if (!sourceContext.isAttachedRun)
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

  Future<void> _queueSynthesis(String id) async {
    await controller.queueSynthesis(id);
  }

  Future<void> _exportMarkdown(BuildContext context, Topic topic) async {
    await runUiAction(context, () async {
      final markdown = KnowledgeService.exportTopicMarkdown(
        topic,
        labelForSource: controller.sourceLabel,
      );
      final saved = await FilePicker.saveFile(
        fileName: KnowledgeService.encodeMarkdownFileName(
          topic.title,
          topic.id,
        ),
        bytes: utf8.encode(markdown),
        mimeType: 'text/markdown',
        dialogTitle: '导出研究 Markdown',
      );
      if (saved == null) throw StateError('已取消导出');
    }, success: 'Markdown 已导出');
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
              scene: 'item-missing',
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
        padding: EdgeInsets.only(
          top: ReadingLayout.of(context).sectionGap,
          bottom: 40,
        ),
        children: [
          _RunReportSection(run: run, controller: controller),
          if (run.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton.icon(
                onPressed: () =>
                    openDiagnostics(context, controller, entityId: run.id),
                icon: const AfterwordIcon(Icons.receipt_long_outlined),
                label: const Text('查看任务日志'),
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
  const _OverviewCard({
    required this.topic,
    required this.controller,
    required this.sourceContext,
  });

  final Topic topic;
  final AppController controller;
  final _TopicReadingSourceContext sourceContext;

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    final topicJson = topic.toJson();
    final presentation = topicJson['presentation'];
    final brief = briefFromPresentation(presentation);
    final sections = sectionsFromPresentation(presentation);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            topic.question,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: layout.rowPadding),
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
              if (topic.toJson()['overviewStale'] == true)
                const StatusPill(label: '结论需更新'),
            ],
          ),
          SizedBox(height: layout.rowPadding),
          ReadingContent(
            brief: brief,
            sections: sections,
            fallback: topic.overview,
            sources: sourceContext.citationIds,
            labelForSource: sourceContext.labelForCitation,
            emptyText: '暂无综述，更新后会在这里沉淀当前认识。',
            legacyLabel: sections.isEmpty && brief.isEmpty ? null : '完整综述',
            initiallyExpandFallback: sections.isEmpty && brief.isEmpty,
          ),
          if (sourceContext.run != null) ...[
            SizedBox(height: layout.sectionGap),
            _RunSourceContextList(
              run: sourceContext.run!,
              controller: controller,
            ),
          ],
          if (topic.reason.isNotEmpty) ...[
            SizedBox(height: layout.sectionGap),
            Text('触发原因：${topic.reason}'),
          ],
          if (topic.toJson()['reviewAt'] is String)
            Text('复查：${topic.toJson()['reviewAt']}'),
          SizedBox(height: layout.rowPadding),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                icon: const AfterwordIcon(Icons.event_repeat_outlined),
                label: const Text('7 天后复查'),
                onPressed: () => controller.setTopicReview(
                  topic.id,
                  DateTime.now().add(const Duration(days: 7)),
                ),
              ),
              TextButton.icon(
                icon: const AfterwordIcon(Icons.event_busy_outlined),
                label: const Text('清除复查'),
                onPressed: () => controller.setTopicReview(topic.id, null),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopicReadingSourceContext {
  const _TopicReadingSourceContext({
    required this.citationIds,
    required this.labelForCitation,
    this.run,
  });

  final List<String> citationIds;
  final String Function(String id) labelForCitation;
  final ResearchRun? run;
  bool get isAttachedRun => run != null;

  static _TopicReadingSourceContext resolve(
    Topic topic,
    AppController controller,
  ) {
    final runs = topic.sourceIds
        .map(
          (id) => controller.data.runs
              .where((candidate) => candidate.id == id)
              .firstOrNull,
        )
        .nonNulls
        .toList(growable: false);
    if (topic.sourceIds.length != 1 || runs.length != 1) {
      return _TopicReadingSourceContext(
        citationIds: topic.sourceIds,
        labelForCitation: controller.sourceLabel,
      );
    }
    final run = runs.single;
    final runSourceIds = run.sources.map((source) => source.id).toList();
    return _TopicReadingSourceContext(
      citationIds: [...runSourceIds, run.id],
      labelForCitation: (id) {
        final source = run.sources
            .where((candidate) => candidate.id == id)
            .firstOrNull;
        if (source != null) return source.title;
        if (id == run.id) return '研究记录：${run.goal}';
        return controller.sourceLabel(id);
      },
      run: run,
    );
  }
}

class _RunSourceContextList extends StatelessWidget {
  const _RunSourceContextList({required this.run, required this.controller});

  final ResearchRun run;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (run.sources.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本次研究来源', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(radius: 13, child: Text('1')),
            title: Text('研究记录：${run.goal}'),
            trailing: const AfterwordIcon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ResearchRunPage(controller: controller, runId: run.id),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('本次研究来源', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final entry in run.sources.indexed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 13,
              child: Text(
                '${entry.$1 + 1}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            title: Text(entry.$2.title),
            subtitle: Text(entry.$2.url),
            trailing: const AfterwordIcon(Icons.open_in_new),
            onTap: () => runUiAction(
              context,
              () => controller.native.openUrl(entry.$2.url),
            ),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 13,
            child: Text(
              '${run.sources.length + 1}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          title: Text('研究记录：${run.goal}'),
          trailing: const AfterwordIcon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ResearchRunPage(controller: controller, runId: run.id),
            ),
          ),
        ),
      ],
    );
  }
}

class _RunReportSection extends StatelessWidget {
  const _RunReportSection({required this.run, required this.controller});

  final ResearchRun run;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    final runJson = run.toJson();
    final presentation = runJson['presentation'];
    final brief = briefFromPresentation(presentation);
    final sections = sectionsFromPresentation(presentation);
    final sourceIds = run.sources.map((source) => source.id).toList();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AfterwordScene(
                scene: researchRunScene(run.status),
                motion: researchRunMotion(run.status),
                size: 72,
                color: Theme.of(context).colorScheme.primary,
                semanticLabel: researchRunStatusLabel(run.status),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  run.goal,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          SizedBox(height: layout.rowPadding),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                label: researchRunStatusLabel(run.status),
                positive: researchRunIsComplete(run),
              ),
              Text('调用：${run.calls}/${run.callLimit}'),
              Text('开始：${shortDate(run.startedAt)}'),
              if (run.completedAt != null)
                Text(
                  '${researchRunIsComplete(run) ? '完成' : '结束'}：${shortDate(run.completedAt)}',
                ),
              if (run.stale) const StatusPill(label: '输入已变化，结果可能过时'),
              if (run.requestPending) const StatusPill(label: '等待确认'),
            ],
          ),
          if (run.error.isNotEmpty) ...[
            SizedBox(height: layout.rowPadding),
            Text(
              run.error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          SizedBox(height: layout.sectionGap),
          ReadingContent(
            brief: brief,
            sections: sections,
            fallback: run.report.isEmpty ? run.error : run.report,
            sources: sourceIds,
            labelForSource: (source) => _runSourceLabel(run, source),
            emptyText: '暂无研究报告。',
            legacyLabel: sections.isEmpty && brief.isEmpty ? null : '完整报告',
            initiallyExpandFallback: sections.isEmpty && brief.isEmpty,
          ),
          SizedBox(height: layout.sectionGap),
        ],
      ),
    );
  }

  String _runSourceLabel(ResearchRun run, String id) {
    final source = run.sources.where((source) => source.id == id).firstOrNull;
    if (source != null) return source.title;
    return controller.sourceLabel(id);
  }
}

class _TopicContextCard extends StatelessWidget {
  const _TopicContextCard({required this.topic, required this.controller});

  final Topic topic;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final entries = KnowledgeService.contextEntriesForTopic(topic);
    if (entries.isEmpty) {
      return SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('暂无个人背景、判断或未解决问题'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  icon: const AfterwordIcon(Icons.add),
                  label: const Text('添加 context'),
                  onPressed: () => _addContext(context),
                ),
                OutlinedButton.icon(
                  icon: const AfterwordIcon(Icons.library_books_outlined),
                  label: const Text('从资料/笔记加入'),
                  onPressed: () => _importContext(context),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '个人 context',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: '从资料/笔记加入',
                icon: const AfterwordIcon(Icons.library_books_outlined),
                onPressed: () => _importContext(context),
              ),
              IconButton(
                tooltip: '添加 context',
                icon: const AfterwordIcon(Icons.add),
                onPressed: () => _addContext(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final entry in entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AfterwordIcon(
                _contextAfterwordIcon(entry['kind'] as String? ?? ''),
              ),
              title: Text(entry['text'] as String? ?? ''),
              trailing: PopupMenuButton<String>(
                icon: const AfterwordIcon(Icons.more_horiz),
                onSelected: (value) =>
                    _handleEntryAction(context, entry, value),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(
                    value: entry['confirmed'] == true ? 'unconfirm' : 'confirm',
                    child: Text(entry['confirmed'] == true ? '标为待确认' : '标为已确认'),
                  ),
                  PopupMenuItem(
                    value: entry['active'] == false ? 'restore' : 'disable',
                    child: Text(entry['active'] == false ? '恢复使用' : '排除'),
                  ),
                ],
              ),
              subtitle: Wrap(
                spacing: 8,
                children: [
                  Text(_contextLabel(entry['kind'] as String? ?? '')),
                  Text(entry['confirmed'] == true ? '已确认' : '待确认'),
                  if (entry['sourceId'] is String)
                    Text('来源 ${entry['sourceId']}'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addContext(BuildContext context) async {
    final input = await showContextEntryDialog(context);
    if (input == null || !context.mounted) return;
    await runUiAction(
      context,
      () => controller.addTopicContext(
        topic.id,
        kind: input.kind,
        text: input.text,
        confirmed: input.confirmed,
      ),
      success: 'Context 已保存',
    );
  }

  Future<void> _importContext(BuildContext context) async {
    final input = await showSourceContextPicker(context, controller.data.items);
    if (input == null || !context.mounted) return;
    await runUiAction(
      context,
      () => controller.addTopicContext(
        topic.id,
        kind: 'background',
        text: input.text,
        confirmed: true,
        sourceId: input.sourceId,
      ),
      success: 'Context 已加入',
    );
  }

  Future<void> _handleEntryAction(
    BuildContext context,
    Json entry,
    String action,
  ) async {
    final id = entry['id'] as String? ?? '';
    if (id.isEmpty) return;
    if (action == 'edit') {
      final input = await showContextEntryDialog(
        context,
        kind: entry['kind'] as String? ?? 'background',
        text: entry['text'] as String? ?? '',
        confirmed: entry['confirmed'] == true,
      );
      if (input == null || !context.mounted) return;
      await runUiAction(
        context,
        () => controller.updateTopicContext(
          topic.id,
          id,
          text: input.text,
          kind: input.kind,
          confirmed: input.confirmed,
        ),
        success: 'Context 已更新',
      );
      return;
    }
    await runUiAction(
      context,
      () => controller.updateTopicContext(
        topic.id,
        id,
        confirmed: switch (action) {
          'confirm' => true,
          'unconfirm' => false,
          _ => null,
        },
        active: switch (action) {
          'restore' => true,
          'disable' => false,
          _ => null,
        },
      ),
      success: 'Context 已更新',
    );
  }

  IconData _contextAfterwordIcon(String kind) => switch (kind) {
    'goal' => Icons.flag_outlined,
    'constraint' => Icons.rule_outlined,
    'judgement' => Icons.psychology_alt_outlined,
    'question' => Icons.help_outline,
    _ => Icons.notes_outlined,
  };

  String _contextLabel(String kind) => switch (kind) {
    'goal' => '目标',
    'constraint' => '限制',
    'judgement' => '个人判断',
    'question' => '未解决问题',
    _ => '背景',
  };
}

class _TopicScopeCard extends StatelessWidget {
  const _TopicScopeCard({required this.topic, required this.controller});

  final Topic topic;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final sources = KnowledgeService.selectedSourceIdsForTopic(topic);
    final contexts = KnowledgeService.selectedContextIdsForTopic(topic);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '本轮范围',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                icon: const AfterwordIcon(Icons.tune_outlined),
                label: const Text('选择'),
                onPressed: () => _editScope(context),
              ),
            ],
          ),
          if (sources == null && contexts == null)
            const Text('自动选择可用资料与已确认 context')
          else if (sources?.isEmpty == true)
            const Text('资料：本轮明确不纳入资料'),
          if (sources != null && sources.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('资料', style: Theme.of(context).textTheme.titleSmall),
            for (final id in sources) Text('• ${controller.sourceLabel(id)}'),
          ],
          if (contexts != null && contexts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Context', style: Theme.of(context).textTheme.titleSmall),
            for (final id in contexts) Text('• $id'),
          ],
        ],
      ),
    );
  }

  Future<void> _editScope(BuildContext context) async {
    final result =
        await showDialog<({List<String>? sources, List<String>? contexts})>(
          context: context,
          builder: (context) =>
              _TopicScopeDialog(topic: topic, controller: controller),
        );
    if (result == null || !context.mounted) return;
    await runUiAction(
      context,
      () => controller.updateTopicScope(
        topic.id,
        sourceIds: result.sources,
        contextIds: result.contexts,
      ),
      success: '范围已更新',
    );
  }
}

class _TopicScopeDialog extends StatefulWidget {
  const _TopicScopeDialog({required this.topic, required this.controller});

  final Topic topic;
  final AppController controller;

  @override
  State<_TopicScopeDialog> createState() => _TopicScopeDialogState();
}

class _TopicScopeDialogState extends State<_TopicScopeDialog> {
  late bool _autoSources;
  late Set<String> _sources;
  late bool _autoContexts;
  late Set<String> _contexts;

  @override
  void initState() {
    super.initState();
    final sourceIds = KnowledgeService.selectedSourceIdsForTopic(widget.topic);
    final contextIds = KnowledgeService.selectedContextIdsForTopic(
      widget.topic,
    );
    _autoSources = sourceIds == null;
    _sources = (sourceIds ?? widget.topic.sourceIds).toSet();
    _autoContexts = contextIds == null;
    _contexts = (contextIds ?? <String>[]).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.controller.data.items
        .where((item) => item.isActive)
        .toList();
    final contexts = KnowledgeService.contextEntriesForTopic(widget.topic);
    return AlertDialog(
      title: const Text('研究范围'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('自动选择资料'),
            value: _autoSources,
            onChanged: (value) => setState(() => _autoSources = value),
          ),
          if (!_autoSources)
            for (final item in items)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _sources.contains(item.id),
                title: Text(item.title),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _sources.add(item.id);
                  } else {
                    _sources.remove(item.id);
                  }
                }),
              ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('自动选择 context'),
            value: _autoContexts,
            onChanged: (value) => setState(() => _autoContexts = value),
          ),
          if (!_autoContexts)
            for (final entry in contexts)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _contexts.contains(entry['id']),
                title: Text(entry['text'] as String? ?? ''),
                onChanged: (value) => setState(() {
                  final id = entry['id'] as String? ?? '';
                  if (value == true) {
                    _contexts.add(id);
                  } else {
                    _contexts.remove(id);
                  }
                }),
              ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            sources: _autoSources ? null : _sources.toList(),
            contexts: _autoContexts ? null : _contexts.toList(),
          )),
          child: const Text('保存'),
        ),
      ],
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
                icon: AfterwordIcon(
                  topic.tracking ? Icons.pause : Icons.play_arrow,
                ),
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
              leading: const AfterwordIcon(Icons.travel_explore_outlined),
              title: Text(
                run.goal,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${run.sources.length} 个来源 · ${shortDate(run.completedAt ?? run.startedAt)}${run.stale ? ' · 已过时' : ''}',
              ),
              trailing: const AfterwordIcon(Icons.chevron_right),
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
              leading: const AfterwordIcon(Icons.link),
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
