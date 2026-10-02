import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'afterword_art.dart';
import 'common.dart';
import 'item_detail.dart';
import 'research_detail.dart';

class ConversationPage extends StatefulWidget {
  const ConversationPage({
    super.key,
    required this.controller,
    required this.scope,
    this.scopeId,
    this.sourceIds = const <String>[],
    this.title,
    this.initialConversationId,
  });

  final AppController controller;
  final ConversationScope scope;
  final String? scopeId;
  final List<String> sourceIds;
  final String? title;
  final String? initialConversationId;

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final TextEditingController _question = TextEditingController();
  String? _selectedConversationId;
  bool _submitting = false;
  late bool _explicitSources;
  late Set<String> _sourceIds;

  @override
  void initState() {
    super.initState();
    _selectedConversationId = widget.initialConversationId;
    _explicitSources =
        widget.scope == ConversationScope.item || widget.sourceIds.isNotEmpty;
    _sourceIds = widget.sourceIds.toSet();
    if (widget.scope == ConversationScope.item && widget.scopeId != null) {
      _sourceIds = {widget.scopeId!};
    }
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final conversations = _scopeConversations();
        final selected = _selectedConversation(conversations);
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        return AppFrame(
          title: widget.title ?? _scopeTitle(widget.scope),
          actions: [
            IconButton(
              tooltip: '新对话',
              icon: const AfterwordIcon(Icons.add_comment_outlined),
              onPressed: _submitting ? null : () => _startConversation(context),
            ),
          ],
          child: Column(
            children: [
              if (!keyboardOpen)
                _ConversationHeader(
                  controller: widget.controller,
                  scope: widget.scope,
                  scopeId: widget.scopeId,
                  sourceIds:
                      selected?.sourceIds ?? _selectedSourceIdsForStart(),
                  explicitSources: selected != null
                      ? selected.sourceIds != null
                      : _explicitSources,
                  selected: selected,
                  conversations: conversations,
                  onSelected: (id) =>
                      setState(() => _selectedConversationId = id),
                  onStart: _submitting
                      ? null
                      : () => _startConversation(context),
                  onChooseSources:
                      selected == null && widget.scope != ConversationScope.item
                      ? () => _chooseSources(context)
                      : null,
                ),
              Expanded(
                child: selected == null
                    ? _ConversationEmpty(
                        scope: widget.scope,
                        onStart: _submitting
                            ? null
                            : () => _startConversation(context),
                      )
                    : _TurnList(
                        controller: widget.controller,
                        turns: _turnsFor(selected.id),
                        onNewQuestion: (question) {
                          _question.text = question;
                          _question.selection = TextSelection.collapsed(
                            offset: _question.text.length,
                          );
                        },
                      ),
              ),
              _QuestionComposer(
                controller: _question,
                submitting: _submitting,
                onSubmit: (question) => _submitQuestion(context, question),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Conversation> _scopeConversations() {
    final conversations = widget.controller.data.conversations
        .where(
          (conversation) =>
              conversation.scope == widget.scope &&
              (widget.scopeId == null ||
                  widget.scopeId!.isEmpty ||
                  conversation.scopeId == widget.scopeId),
        )
        .toList();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  Conversation? _selectedConversation(List<Conversation> conversations) {
    if (conversations.isEmpty) return null;
    final selectedId = _selectedConversationId;
    if (selectedId != null) {
      for (final conversation in conversations) {
        if (conversation.id == selectedId) return conversation;
      }
    }
    return conversations.first;
  }

  List<ConversationTurn> _turnsFor(String conversationId) {
    final turns = widget.controller.data.conversationTurns
        .where((turn) => turn.conversationId == conversationId)
        .toList();
    turns.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return turns;
  }

  Future<void> _startConversation(BuildContext context) async {
    final selection = await _sourceSelectionForNewConversation(context);
    if (selection == null) return;
    if (mounted) setState(() => _submitting = true);
    try {
      final id = await widget.controller.startConversation(
        widget.scope,
        scopeId: widget.scopeId,
        sourceIds: selection.explicit ? selection.sourceIds : null,
      );
      if (mounted) setState(() => _selectedConversationId = id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitQuestion(BuildContext context, String question) async {
    final text = question.trim();
    if (text.isEmpty) return;
    setState(() => _submitting = true);
    try {
      var conversation = _selectedConversation(_scopeConversations());
      if (conversation == null) {
        final id = await widget.controller.startConversation(
          widget.scope,
          scopeId: widget.scopeId,
          sourceIds: _selectedSourceIdsForStart(),
        );
        _selectedConversationId = id;
        conversation = widget.controller.data.conversations
            .where((candidate) => candidate.id == id)
            .firstOrNull;
      }
      if (conversation == null) {
        throw StateError('对话尚未建立');
      }
      await widget.controller.submitQuestion(conversation.id, text);
      _question.clear();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  List<String>? _selectedSourceIdsForStart() {
    if (widget.scope == ConversationScope.item) return _sourceIds.toList();
    return _explicitSources ? _sourceIds.toList() : null;
  }

  Future<_SourceSelection?> _sourceSelectionForNewConversation(
    BuildContext context,
  ) async {
    if (widget.scope == ConversationScope.item) {
      return _SourceSelection(explicit: true, sourceIds: _sourceIds.toList());
    }
    final result = await showDialog<_SourceSelection>(
      context: context,
      builder: (_) => _SourcePickerDialog(
        controller: widget.controller,
        explicit: _explicitSources,
        selectedIds: _sourceIds,
      ),
    );
    if (result == null) return null;
    if (mounted) {
      setState(() {
        _explicitSources = result.explicit;
        _sourceIds = result.sourceIds.toSet();
      });
    }
    return result;
  }

  Future<void> _chooseSources(BuildContext context) async {
    final result = await showDialog<_SourceSelection>(
      context: context,
      builder: (_) => _SourcePickerDialog(
        controller: widget.controller,
        explicit: _explicitSources,
        selectedIds: _sourceIds,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _explicitSources = result.explicit;
      _sourceIds = result.sourceIds.toSet();
    });
  }

  String _scopeTitle(ConversationScope scope) => switch (scope) {
    ConversationScope.item => '问这篇资料',
    ConversationScope.topic => '围绕主题讨论',
    ConversationScope.library => '问知识库',
  };
}

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.controller,
    required this.scope,
    required this.scopeId,
    required this.sourceIds,
    required this.explicitSources,
    required this.selected,
    required this.conversations,
    required this.onSelected,
    required this.onStart,
    required this.onChooseSources,
  });

  final AppController controller;
  final ConversationScope scope;
  final String? scopeId;
  final List<String>? sourceIds;
  final bool explicitSources;
  final Conversation? selected;
  final List<Conversation> conversations;
  final ValueChanged<String> onSelected;
  final VoidCallback? onStart;
  final VoidCallback? onChooseSources;

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        layout.pagePadding,
        layout.rowPadding,
        layout.pagePadding,
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(label: _scopeLabel(scope), positive: true),
              Text(_scopeDescription()),
              if (explicitSources)
                Text('${sourceIds?.length ?? 0} 个指定来源')
              else
                const Text('自动选源'),
              if (selected != null)
                Text('更新：${shortDate(selected!.updatedAt)}'),
            ],
          ),
          if (onChooseSources != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const AfterwordIcon(Icons.tune_outlined),
              label: const Text('选择来源'),
              onPressed: onChooseSources,
            ),
          ],
          if (conversations.isNotEmpty) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: selected?.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '历史对话'),
              items: [
                for (final conversation in conversations)
                  DropdownMenuItem(
                    value: conversation.id,
                    child: Text(
                      conversation.title.trim().isEmpty
                          ? '未命名对话'
                          : conversation.title,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onSelected(value);
              },
            ),
          ] else ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const AfterwordIcon(Icons.add_comment_outlined),
              label: const Text('开始对话'),
              onPressed: onStart,
            ),
          ],
        ],
      ),
    );
  }

  String _scopeLabel(ConversationScope scope) => switch (scope) {
    ConversationScope.item => '单篇资料',
    ConversationScope.topic => '主题',
    ConversationScope.library => '知识库',
  };

  String _scopeDescription() {
    if (scope == ConversationScope.item) {
      final id = scopeId ?? sourceIds?.firstOrNull ?? '';
      return id.isEmpty ? '当前资料' : controller.sourceLabel(id);
    }
    if (scope == ConversationScope.topic) return '主题范围';
    return '全库范围';
  }
}

class _SourceSelection {
  const _SourceSelection({required this.explicit, required this.sourceIds});

  final bool explicit;
  final List<String> sourceIds;
}

class _SourcePickerDialog extends StatefulWidget {
  const _SourcePickerDialog({
    required this.controller,
    required this.explicit,
    required this.selectedIds,
  });

  final AppController controller;
  final bool explicit;
  final Set<String> selectedIds;

  @override
  State<_SourcePickerDialog> createState() => _SourcePickerDialogState();
}

class _SourcePickerDialogState extends State<_SourcePickerDialog> {
  late bool _explicit;
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _explicit = widget.explicit;
    _selected = widget.selectedIds.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final items =
        widget.controller.data.items.where((item) => item.isActive).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final excludedCount = widget.controller.data.items.length - items.length;
    return AlertDialog(
      title: const Text('选择对话来源'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('指定来源'),
              subtitle: const Text('关闭后会按问题自动从当前范围选取相关资料。'),
              value: _explicit,
              onChanged: (value) => setState(() => _explicit = value),
            ),
            if (excludedCount > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '已排除 $excludedCount 个归档或回收站资料。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const Divider(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in items)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _explicit && _selected.contains(item.id),
                      title: Text(
                        item.title.trim().isEmpty ? '未命名资料' : item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(kindLabel(item.kind)),
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _explicit = true;
                            _selected.add(item.id);
                          } else {
                            _selected.remove(item.id);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _explicit && _selected.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  _SourceSelection(
                    explicit: _explicit,
                    sourceIds: _selected.toList(),
                  ),
                ),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _ConversationEmpty extends StatelessWidget {
  const _ConversationEmpty({required this.scope, required this.onStart});

  final ConversationScope scope;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      scene: 'research-empty',
      icon: Icons.question_answer_outlined,
      title: '还没有对话',
      message: switch (scope) {
        ConversationScope.item => '可以围绕当前资料追问，回答会保留来源窗口和证据。',
        ConversationScope.topic => '可以围绕这个主题继续追问，再把有价值的回答沉淀为知识修订。',
        ConversationScope.library => '可以向整个知识库提问，长资料会按预算读取片段。',
      },
      action: FilledButton.icon(
        icon: const AfterwordIcon(Icons.add_comment_outlined),
        label: const Text('开始对话'),
        onPressed: onStart,
      ),
    );
  }
}

class _TurnList extends StatelessWidget {
  const _TurnList({
    required this.controller,
    required this.turns,
    required this.onNewQuestion,
  });

  final AppController controller;
  final List<ConversationTurn> turns;
  final ValueChanged<String> onNewQuestion;

  @override
  Widget build(BuildContext context) {
    if (turns.isEmpty) {
      return const Center(child: Text('提出一个问题后，回答会出现在这里。'));
    }
    return ListView(
      padding: EdgeInsets.only(
        left: ReadingLayout.of(context).pagePadding,
        right: ReadingLayout.of(context).pagePadding,
        bottom: 24,
      ),
      children: [
        for (final turn in turns)
          _TurnCard(
            controller: controller,
            turn: turn,
            onNewQuestion: onNewQuestion,
          ),
      ],
    );
  }
}

class _TurnCard extends StatelessWidget {
  const _TurnCard({
    required this.controller,
    required this.turn,
    required this.onNewQuestion,
  });

  final AppController controller;
  final ConversationTurn turn;
  final ValueChanged<String> onNewQuestion;

  bool get _active => const {'queued', 'running'}.contains(turn.status);
  bool get _retryable => const {
    'paused',
    'failed',
    'interrupted',
    'cancelled',
  }.contains(turn.status);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reusable =
        turn.status != 'completed' ||
        controller.isConversationTurnReusable(turn);
    final exhausted =
        turn.calls >= turn.callLimit && turn.status != 'completed';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              turn.question,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusPill(
                  label: _turnStatusLabel(turn.status),
                  positive: turn.status == 'completed',
                ),
                Text('调用：${turn.calls}/${turn.callLimit}'),
                Text('预算：${turn.textBudgetChars} 字符'),
                if (turn.stage.trim().isNotEmpty) Text(turn.stage),
                if (turn.requestPending) const StatusPill(label: '状态不确定'),
                if (turn.stale || !reusable) const StatusPill(label: '来源已变化'),
              ],
            ),
            if (turn.requestPending) ...[
              const SizedBox(height: 10),
              Text(
                '上次请求可能已经发出；停止或重试前，请留意可能产生的模型调用费用。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (exhausted) ...[
              const SizedBox(height: 10),
              Text(
                '本轮调用预算已用完，请把问题作为新问题重新提交。',
                style: TextStyle(color: colors.error),
              ),
            ],
            if (_active) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 3),
            ],
            if (turn.error.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(turn.error, style: TextStyle(color: colors.error)),
            ],
            const SizedBox(height: 12),
            SelectableText(
              turn.answer.trim().isEmpty
                  ? (_active ? '正在读取来源并生成回答…' : '暂无回答')
                  : turn.answer,
            ),
            if (turn.windows.isNotEmpty) ...[
              const SizedBox(height: 12),
              _WindowsSection(controller: controller, windows: turn.windows),
            ],
            if (turn.evidence.isNotEmpty) ...[
              const SizedBox(height: 12),
              _EvidenceSection(controller: controller, evidence: turn.evidence),
            ],
            if (turn.visualEvidence.isNotEmpty) ...[
              const SizedBox(height: 12),
              _VisualEvidenceSection(items: turn.visualEvidence),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_active)
                  OutlinedButton.icon(
                    icon: const AfterwordIcon(Icons.stop_circle_outlined),
                    label: const Text('停止'),
                    onPressed: () => runUiAction(context, () async {
                      await controller.cancelTurn(turn.id);
                    }),
                  ),
                if (_retryable)
                  OutlinedButton.icon(
                    icon: const AfterwordIcon(Icons.refresh_outlined),
                    label: const Text('重试'),
                    onPressed: exhausted || !reusable
                        ? null
                        : () => runUiAction(context, () async {
                            await controller.retryTurn(turn.id);
                          }),
                  ),
                if (exhausted || !reusable)
                  OutlinedButton.icon(
                    icon: const AfterwordIcon(Icons.edit_outlined),
                    label: const Text('作为新问题重问'),
                    onPressed: () => onNewQuestion(turn.question),
                  ),
                if (turn.status == 'completed' && turn.answer.trim().isNotEmpty)
                  FilledButton.icon(
                    icon: const AfterwordIcon(Icons.library_add_check_outlined),
                    label: const Text('沉淀为知识'),
                    onPressed: reusable
                        ? () => runUiAction(context, () async {
                            await controller.proposeKnowledgeFromTurn(turn.id);
                          }, success: '已生成知识草稿')
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _turnStatusLabel(String status) => switch (status) {
    'queued' => '排队中',
    'running' => '生成中',
    'paused' => '已暂停',
    'interrupted' => '已中断',
    'failed' => '失败',
    'completed' => '已完成',
    'cancelled' => '已停止',
    _ => status,
  };
}

class _WindowsSection extends StatelessWidget {
  const _WindowsSection({required this.controller, required this.windows});

  final AppController controller;
  final List<SourceWindow> windows;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('读取窗口 · ${windows.length}'),
      children: [
        for (final window in windows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(controller.sourceLabel(window.sourceId)),
            subtitle: Text(
              window.text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _hasSource(controller, window.sourceId)
                ? const AfterwordIcon(Icons.chevron_right)
                : null,
            onTap: _hasSource(controller, window.sourceId)
                ? () => _openSource(
                    context,
                    controller,
                    window.sourceId,
                    initialBlockId: window.blockId.trim().isEmpty
                        ? null
                        : window.blockId,
                  )
                : null,
          ),
      ],
    );
  }
}

class _EvidenceSection extends StatelessWidget {
  const _EvidenceSection({required this.controller, required this.evidence});

  final AppController controller;
  final List<EvidenceAnchor> evidence;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('证据 · ${evidence.length}'),
      children: [
        for (final anchor in evidence)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(controller.sourceLabel(anchor.sourceId)),
            subtitle: Text(
              anchor.quote.trim().isEmpty ? anchor.note : anchor.quote,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _hasSource(controller, anchor.sourceId)
                ? const AfterwordIcon(Icons.chevron_right)
                : null,
            onTap: _hasSource(controller, anchor.sourceId)
                ? () => _openSource(
                    context,
                    controller,
                    anchor.sourceId,
                    initialBlockId: anchor.blockId.trim().isEmpty
                        ? null
                        : anchor.blockId,
                    initialPdfPage: anchor.pdfPage,
                  )
                : null,
          ),
      ],
    );
  }
}

class _VisualEvidenceSection extends StatelessWidget {
  const _VisualEvidenceSection({required this.items});

  final List<VisualEvidence> items;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('视觉证据 · ${items.length}'),
      subtitle: const Text('视觉观察不是精确校验；请以原始附件为准。'),
      children: [
        for (final item in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const AfterwordIcon(Icons.image_outlined),
            title: Text(
              item.observation.trim().isEmpty ? '视觉观察' : item.observation,
            ),
            subtitle: Text(
              [
                '来源 ${item.sourceId}',
                if (item.page != null) '第 ${item.page} 页',
                if (item.unverified) '未精确验证',
              ].join(' · '),
            ),
          ),
      ],
    );
  }
}

class _QuestionComposer extends StatelessWidget {
  const _QuestionComposer({
    required this.controller,
    required this.submitting,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool submitting;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          keyboardOpen ? 0 : 8,
          12,
          keyboardOpen ? 0 : 4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '继续追问…',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: '发送',
              icon: submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const AfterwordIcon(Icons.send),
              onPressed: submitting ? null : () => onSubmit(controller.text),
            ),
          ],
        ),
      ),
    );
  }
}

bool _hasSource(AppController controller, String sourceId) =>
    controller.data.items.any((item) => item.id == sourceId) ||
    controller.data.runs.any((run) => run.id == sourceId);

void _openSource(
  BuildContext context,
  AppController controller,
  String sourceId, {
  String? initialBlockId,
  int? initialPdfPage,
}) {
  final item = controller.data.items
      .where((candidate) => candidate.id == sourceId)
      .firstOrNull;
  if (item != null) {
    if (initialPdfPage != null) {
      controller.updateReadingPosition(sourceId, pdfPage: initialPdfPage);
    } else if (initialBlockId != null && initialBlockId.isNotEmpty) {
      controller.updateReadingPosition(sourceId, blockId: initialBlockId);
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArticleDetailPage(
          controller: controller,
          item: item,
          initialBlockId: initialBlockId,
          initialPdfPage: initialPdfPage,
        ),
      ),
    );
    return;
  }
  final run = controller.data.runs
      .where((candidate) => candidate.id == sourceId)
      .firstOrNull;
  if (run != null) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ResearchRunPage(controller: controller, runId: run.id),
      ),
    );
  }
}
