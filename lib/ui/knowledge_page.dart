import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'afterword_art.dart';
import 'common.dart';
import 'reading_content.dart';

class KnowledgePage extends StatelessWidget {
  const KnowledgePage({super.key, required this.controller, this.topicId});

  final AppController controller;
  final String? topicId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final topic = topicId == null
            ? null
            : controller.data.topics
                  .where((candidate) => candidate.id == topicId)
                  .firstOrNull;
        return AppFrame(
          title: topic == null ? '知识草稿' : '知识：${topic.title}',
          child: ListView(
            padding: EdgeInsets.only(
              top: ReadingLayout.of(context).sectionGap,
              bottom: 32,
            ),
            children: [KnowledgePanel(controller: controller, topic: topic)],
          ),
        );
      },
    );
  }
}

class KnowledgePanel extends StatelessWidget {
  const KnowledgePanel({super.key, required this.controller, this.topic});

  final AppController controller;
  final Topic? topic;

  @override
  Widget build(BuildContext context) {
    final proposals =
        controller.data.knowledgeProposals
            .where((proposal) => topic == null || proposal.topicId == topic!.id)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final revisions =
        controller.data.knowledgeRevisions
            .where((revision) => topic == null || revision.topicId == topic!.id)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final current = topic?.currentKnowledgeRevisionId == null
        ? null
        : revisions
              .where(
                (revision) => revision.id == topic!.currentKnowledgeRevisionId,
              )
              .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (topic != null)
          _ConfirmedKnowledgeCard(
            topic: topic!,
            current: current,
            controller: controller,
          ),
        _ProposalList(
          controller: controller,
          proposals: proposals,
          current: current,
        ),
        _RevisionList(
          controller: controller,
          revisions: revisions,
          currentRevisionId: topic?.currentKnowledgeRevisionId,
        ),
      ],
    );
  }
}

class _ConfirmedKnowledgeCard extends StatelessWidget {
  const _ConfirmedKnowledgeCard({
    required this.topic,
    required this.current,
    required this.controller,
  });

  final Topic topic;
  final KnowledgeRevision? current;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final currentReusable =
        current == null || controller.isKnowledgeRevisionReusable(current!);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('已确认知识', style: Theme.of(context).textTheme.titleMedium),
          if (!currentReusable) ...[
            const SizedBox(height: 8),
            const StatusPill(label: '来源已变化'),
          ],
          const SizedBox(height: 10),
          if (current != null)
            ReadingContent(
              brief: current!.presentation.brief,
              sections: [
                for (final section in current!.presentation.sections)
                  ReadingSectionData(title: section.title, body: section.body),
              ],
              fallback: current!.presentation.fullText,
              sources: current!.inputItemIds,
              labelForSource: controller.sourceLabel,
              emptyText: '当前修订为空。',
            )
          else
            const Text('暂无已确认知识。'),
          if (topic.overview.trim().isNotEmpty) ...[
            const Divider(),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('自动综述'),
              subtitle: const Text('自动生成的主题综述，供参考。'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(topic.overview),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ProposalList extends StatelessWidget {
  const _ProposalList({
    required this.controller,
    required this.proposals,
    required this.current,
  });

  final AppController controller;
  final List<KnowledgeProposal> proposals;
  final KnowledgeRevision? current;

  @override
  Widget build(BuildContext context) {
    final visible = proposals
        .where((proposal) => proposal.status != 'accepted')
        .toList();
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('知识草稿', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            const Text('暂无待确认草稿。')
          else
            for (final proposal in visible)
              _ProposalTile(
                controller: controller,
                proposal: proposal,
                current: current,
              ),
        ],
      ),
    );
  }
}

class _ProposalTile extends StatelessWidget {
  const _ProposalTile({
    required this.controller,
    required this.proposal,
    required this.current,
  });

  final AppController controller;
  final KnowledgeProposal proposal;
  final KnowledgeRevision? current;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    proposal.title.trim().isEmpty ? '未命名草稿' : proposal.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                StatusPill(label: _proposalStatus(proposal.status)),
              ],
            ),
            if (proposal.question.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(proposal.question),
            ],
            if (proposal.reason.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('原因：${proposal.reason}'),
            ],
            const SizedBox(height: 10),
            _DiffBlock(
              oldText: current?.presentation.fullText ?? '',
              newText: proposal.presentation.fullText,
            ),
            if (proposal.evidence.isNotEmpty) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('证据 · ${proposal.evidence.length}'),
                children: [
                  for (final anchor in proposal.evidence)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(controller.sourceLabel(anchor.sourceId)),
                      subtitle: Text(
                        anchor.quote.trim().isEmpty
                            ? anchor.note
                            : anchor.quote,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const AfterwordIcon(Icons.edit_note_outlined),
                  label: const Text('编辑并确认'),
                  onPressed: proposal.status == 'pending'
                      ? () => _editAndAccept(context)
                      : null,
                ),
                OutlinedButton.icon(
                  icon: const AfterwordIcon(Icons.close),
                  label: const Text('拒绝'),
                  onPressed: proposal.status == 'pending'
                      ? () => runUiAction(context, () async {
                          await controller.rejectKnowledgeProposal(proposal.id);
                        }, success: '草稿已拒绝')
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editAndAccept(BuildContext context) async {
    final edited = await showDialog<ReadingPresentation>(
      context: context,
      builder: (_) => _PresentationEditorDialog(
        title: proposal.title,
        initial: proposal.presentation,
      ),
    );
    if (edited == null || !context.mounted) return;
    await runUiAction(context, () async {
      await controller.acceptKnowledgeProposal(
        proposal.id,
        editedPresentation: edited,
      );
    }, success: '知识已确认');
  }

  String _proposalStatus(String status) => switch (status) {
    'pending' => '待确认',
    'accepted' => '已确认',
    'rejected' => '已拒绝',
    'stale' => '已过时',
    _ => status,
  };
}

class _RevisionList extends StatelessWidget {
  const _RevisionList({
    required this.controller,
    required this.revisions,
    required this.currentRevisionId,
  });

  final AppController controller;
  final List<KnowledgeRevision> revisions;
  final String? currentRevisionId;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('修订历史', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (revisions.isEmpty)
            const Text('暂无已确认修订。')
          else
            for (final revision in revisions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: AfterwordIcon(
                  revision.id == currentRevisionId
                      ? Icons.check_circle
                      : Icons.history,
                ),
                title: Text(
                  revision.presentation.brief.trim().isEmpty
                      ? '修订 ${shortDate(revision.createdAt)}'
                      : revision.presentation.brief,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Wrap(
                  spacing: 8,
                  children: [
                    Text(shortDate(revision.createdAt)),
                    if (revision.humanEdited) const Text('人工编辑'),
                    if (revision.stale ||
                        !controller.isKnowledgeRevisionReusable(revision))
                      const Text('来源已变化'),
                  ],
                ),
                trailing: revision.id == currentRevisionId
                    ? null
                    : TextButton(
                        onPressed: () => runUiAction(context, () async {
                          await controller.restoreKnowledgeRevision(
                            revision.id,
                          );
                        }, success: '已恢复修订'),
                        child: const Text('恢复'),
                      ),
              ),
        ],
      ),
    );
  }
}

class _DiffBlock extends StatelessWidget {
  const _DiffBlock({required this.oldText, required this.newText});

  final String oldText, newText;

  @override
  Widget build(BuildContext context) {
    final oldTrimmed = oldText.trim();
    final newTrimmed = newText.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('变更对照', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _DiffPane(
                title: '旧版',
                text: oldTrimmed.isEmpty ? '暂无已确认版本' : oldTrimmed,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DiffPane(
                title: '草稿',
                text: newTrimmed.isEmpty ? '草稿为空' : newTrimmed,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DiffPane extends StatelessWidget {
  const _DiffPane({required this.title, required this.text});

  final String title, text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            SelectableText(
              text,
              maxLines: 10,
              scrollPhysics: const NeverScrollableScrollPhysics(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresentationEditorDialog extends StatefulWidget {
  const _PresentationEditorDialog({required this.title, required this.initial});

  final String title;
  final ReadingPresentation initial;

  @override
  State<_PresentationEditorDialog> createState() =>
      _PresentationEditorDialogState();
}

class _PresentationEditorDialogState extends State<_PresentationEditorDialog> {
  late final TextEditingController _brief;
  late final TextEditingController _body;

  @override
  void initState() {
    super.initState();
    _brief = TextEditingController(text: widget.initial.brief);
    _body = TextEditingController(
      text: widget.initial.sections
          .map((section) => [section.title, section.body].join('\n'))
          .join('\n\n'),
    );
  }

  @override
  void dispose() {
    _brief.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title.trim().isEmpty ? '编辑知识草稿' : widget.title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _brief,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '摘要'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                minLines: 8,
                maxLines: 14,
                decoration: const InputDecoration(labelText: '正文'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            ReadingPresentation(
              brief: _brief.text.trim(),
              sections: [ReadingSection(title: '正文', body: _body.text.trim())],
            ),
          ),
          child: const Text('确认'),
        ),
      ],
    );
  }
}
