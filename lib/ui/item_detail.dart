import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'common.dart';
import 'research_detail.dart';
import 'item_actions.dart';
import 'developer_page.dart';

class ArticleDetailPage extends StatefulWidget {
  const ArticleDetailPage({
    super.key,
    required this.controller,
    required this.item,
  });

  final AppController controller;
  final LibraryItem item;

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  late final TextEditingController _notes;
  String _lastSyncedNotes = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.controller.markRead(widget.item.id);
      }
    });
    _lastSyncedNotes = widget.item.notes;
    _notes = TextEditingController(text: widget.item.notes);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final item = widget.controller.data.items
            .where((candidate) => candidate.id == widget.item.id)
            .firstOrNull;
        if (item == null) {
          return const AppFrame(
            title: '阅读',
            child: EmptyState(
              icon: Icons.delete_outline,
              title: '资料已移除',
              message: '这份资料已被永久删除。',
            ),
          );
        }
        if (_notes.text == _lastSyncedNotes && item.notes != _lastSyncedNotes) {
          _lastSyncedNotes = item.notes;
          _notes.text = item.notes;
        }
        return _ArticleDetailView(
          controller: widget.controller,
          item: item,
          notes: _notes,
          syncSavedNotes: (value) => _lastSyncedNotes = value,
        );
      },
    );
  }
}

class _ArticleDetailView extends StatelessWidget {
  const _ArticleDetailView({
    required this.controller,
    required this.item,
    required this.notes,
    required this.syncSavedNotes,
  });

  final AppController controller;
  final LibraryItem item;
  final TextEditingController notes;
  final ValueChanged<String> syncSavedNotes;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: item.analysis == null ? 0 : 1,
      child: AppFrame(
        title: '阅读',
        actions: [
          IconButton(
            tooltip: '重新分析',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed:
                item.isActive &&
                    controller.modelConfigured &&
                    item.status != 'analyzing'
                ? () => runUiAction(context, () => controller.analyze(item.id))
                : null,
          ),
          ItemActionsMenu(controller: controller, items: [item]),
        ],
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: '原文'),
                Tab(text: '分析'),
                Tab(text: '笔记'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _reader(context, [
                    if (item.assets.isNotEmpty)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text('附件 · ${item.assets.length}'),
                        leading: const Icon(Icons.attach_file),
                        children: [
                          AssetStrip(
                            assets: item.assets,
                            assetPath: controller.assetPath,
                            onOpen: (asset) => runUiAction(
                              context,
                              () => controller.native.openFile(
                                controller.assetPath(asset),
                              ),
                            ),
                          ),
                        ],
                      ),
                    SelectableText(
                      item.body.isEmpty ? item.url : item.body,
                      style: const TextStyle(fontSize: 17, height: 1.7),
                    ),
                  ]),
                  _reader(context, [
                    _AnalysisSection(controller: controller, item: item),
                  ]),
                  _reader(context, [
                    _NotesCard(
                      notes: notes,
                      onSave: () async {
                        await controller.updateNotes(item.id, notes.text);
                        syncSavedNotes(notes.text);
                      },
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reader(BuildContext context, List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
    children: [
      Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Text(kindLabel(item.kind)),
          Text(shortDate(item.createdAt)),
          if (!item.isActive) StatusPill(label: item.isTrashed ? '回收站' : '已归档'),
        ],
      ),
      if (!item.isActive)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text('当前资料仅供阅读，不参与新的分析和研究。恢复到使用中后可重新分析。'),
        ),
      if (item.warning.isNotEmpty || item.error.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.error.isNotEmpty ? item.error : item.warning,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton.icon(
                onPressed: () =>
                    openDiagnostics(context, controller, entityId: item.id),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('查看任务日志'),
              ),
            ],
          ),
        ),
      const SizedBox(height: 24),
      ...children,
    ],
  );
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.notes, required this.onSave});

  final TextEditingController notes;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('笔记', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: notes,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(hintText: '记录疑问、适用条件或收藏原因'),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存笔记'),
              onPressed: () => runUiAction(context, onSave, success: '笔记已保存'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisSection extends StatelessWidget {
  const _AnalysisSection({required this.controller, required this.item});

  final AppController controller;
  final LibraryItem item;

  @override
  Widget build(BuildContext context) {
    final analysis = item.analysis;
    if (analysis == null) {
      return Padding(
        padding: EdgeInsets.zero,
        child: EmptyState(
          icon: Icons.auto_awesome_outlined,
          title: '还没有观点卡片',
          message: controller.modelConfigured
              ? '可以对这条资料做总结、关联和研究建议。'
              : '先在设置中配置模型，再进行分析。',
          action: FilledButton.icon(
            icon: const Icon(Icons.auto_awesome),
            label: const Text('开始分析'),
            onPressed: item.isActive && controller.modelConfigured
                ? () => runUiAction(context, () => controller.analyze(item.id))
                : null,
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('观点卡片', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SelectableText(
            readerCitationText(
              analysis.summary,
              analysis.sourceIds,
              labelForSource: controller.sourceLabel,
            ),
            style: const TextStyle(fontSize: 17, height: 1.7),
          ),
          const SizedBox(height: 12),
          for (final insight in analysis.insights)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lightbulb_outline),
              title: Text(
                readerCitationText(
                  insight,
                  analysis.sourceIds,
                  labelForSource: controller.sourceLabel,
                ),
              ),
            ),
          if (analysis.connections.isNotEmpty) ...[
            const Divider(),
            Text('与已有资料的关系', style: Theme.of(context).textTheme.titleSmall),
            for (final connection in analysis.connections)
              Text(
                '• ${readerCitationText(connection, analysis.sourceIds, labelForSource: controller.sourceLabel)}',
              ),
          ],
          if (analysis.questions.isNotEmpty) ...[
            const Divider(),
            Text('研究建议', style: Theme.of(context).textTheme.titleSmall),
            for (final question in analysis.questions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  readerCitationText(
                    question,
                    analysis.sourceIds,
                    labelForSource: controller.sourceLabel,
                  ),
                ),
                subtitle: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: item.isActive && analysis.inputItemIds != null
                        ? () => _confirmResearch(context, question)
                        : null,
                    child: const Text('确认研究'),
                  ),
                ),
              ),
          ],
          const Divider(),
          SourceList(
            sources: analysis.sourceIds,
            labelForSource: controller.sourceLabel,
            onSourceTap: (source) => _openSource(context, source),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: -1, label: Text('无用')),
              ButtonSegment(value: 0, label: Text('中立')),
              ButtonSegment(value: 1, label: Text('有用')),
            ],
            selected: {item.feedback},
            onSelectionChanged: (value) =>
                controller.setFeedback(item.id, value.single),
          ),
        ],
      ),
    );
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

  Future<void> _confirmResearch(BuildContext context, String goal) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '启动外部研究？',
      message: '目标：$goal\n\n研究会使用搜索服务和模型调用，默认上限 6 次。',
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await runUiAction(
      context,
      () => controller.research(
        goal: goal,
        confirmed: true,
        originItemId: item.id,
      ),
      success: '研究已完成',
    );
  }
}

Future<(String, String)?> showTextEntryDialog(
  BuildContext context, {
  required String title,
  required String primaryLabel,
  required String secondaryLabel,
  bool multiline = false,
}) async {
  final primary = TextEditingController();
  final secondary = TextEditingController();
  return showDialog<(String, String)>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: primary,
            minLines: multiline ? 5 : 1,
            maxLines: multiline ? 8 : 1,
            decoration: InputDecoration(labelText: primaryLabel),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: secondary,
            decoration: InputDecoration(labelText: secondaryLabel),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (primary.text, secondary.text)),
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

Future<bool?> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
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
}
