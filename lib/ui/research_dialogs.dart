import 'package:flutter/material.dart';

import '../core/models.dart';
import 'afterword_art.dart';

Future<(String, String)?> showTopicDialog(
  BuildContext context, {
  String title = '',
  String question = '',
}) {
  final titleController = TextEditingController(text: title);
  final questionController = TextEditingController(text: question);
  return showDialog<(String, String)>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('研究主题'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: titleController,
            decoration: const InputDecoration(labelText: '主题名称'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: questionController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(labelText: '研究问题'),
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
            titleController.text,
            questionController.text,
          )),
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

Future<ResearchInput?> showResearchDialog(
  BuildContext context,
  List<Topic> topics,
) {
  final goal = TextEditingController();
  String? topicId;
  var callLimit = 6;
  return showDialog<ResearchInput>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('单次外部研究'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: goal,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(labelText: '研究目标'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              icon: const AfterwordIcon(Icons.arrow_drop_down),
              initialValue: topicId,
              decoration: const InputDecoration(labelText: '关联主题'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('不关联'),
                ),
                for (final topic in topics)
                  DropdownMenuItem(value: topic.id, child: Text(topic.title)),
              ],
              onChanged: (value) => setState(() => topicId = value),
            ),
            Slider(
              value: callLimit.toDouble(),
              min: 2,
              max: 30,
              divisions: 28,
              label: '$callLimit 次',
              onChanged: (value) => setState(() => callLimit = value.round()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              ResearchInput(goal.text, topicId, callLimit),
            ),
            child: const Text('下一步'),
          ),
        ],
      ),
    ),
  );
}

Future<TrackingInput?> showTrackingDialog(BuildContext context, Topic topic) {
  var interval = topic.intervalHours;
  var callLimit = topic.callLimit;
  return showDialog<TrackingInput>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('授权持续追踪'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('范围：${topic.question}'),
            const SizedBox(height: 12),
            Text('频率：每 $interval 小时'),
            Slider(
              value: interval.toDouble(),
              min: 6,
              max: 168,
              divisions: 27,
              onChanged: (value) => setState(() => interval = value.round()),
            ),
            Text('每轮调用上限：$callLimit'),
            Slider(
              value: callLimit.toDouble(),
              min: 2,
              max: 30,
              divisions: 28,
              onChanged: (value) => setState(() => callLimit = value.round()),
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
                Navigator.pop(context, TrackingInput(interval, callLimit)),
            child: const Text('授权'),
          ),
        ],
      ),
    ),
  );
}

class ResearchInput {
  const ResearchInput(this.goal, this.topicId, this.callLimit);
  final String goal;
  final String? topicId;
  final int callLimit;
}

class TrackingInput {
  const TrackingInput(this.intervalHours, this.callLimit);
  final int intervalHours;
  final int callLimit;
}

Future<ContextEntryInput?> showContextEntryDialog(
  BuildContext context, {
  String kind = 'background',
  String text = '',
  bool confirmed = true,
}) {
  final textController = TextEditingController(text: text);
  var selectedKind = kind;
  var isConfirmed = confirmed;
  return showDialog<ContextEntryInput>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('个人 context'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              icon: const AfterwordIcon(Icons.arrow_drop_down),
              initialValue: selectedKind,
              decoration: const InputDecoration(labelText: '类型'),
              items: const [
                DropdownMenuItem(value: 'background', child: Text('背景')),
                DropdownMenuItem(value: 'goal', child: Text('目标')),
                DropdownMenuItem(value: 'constraint', child: Text('限制')),
                DropdownMenuItem(value: 'judgement', child: Text('个人判断')),
                DropdownMenuItem(value: 'question', child: Text('未解决问题')),
                DropdownMenuItem(value: 'ai_dialogue', child: Text('AI 对话导入')),
              ],
              onChanged: (value) => setState(() {
                selectedKind = value ?? selectedKind;
                if (selectedKind == 'ai_dialogue') isConfirmed = false;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(labelText: '内容'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('作为已确认个人判断纳入'),
              value: isConfirmed,
              onChanged: (value) => setState(() => isConfirmed = value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              ContextEntryInput(
                kind: selectedKind,
                text: textController.text,
                confirmed: isConfirmed,
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

Future<SourceContextInput?> showSourceContextPicker(
  BuildContext context,
  List<LibraryItem> items,
) {
  final candidates = <SourceContextInput>[
    for (final item in items.where((item) => item.isActive))
      ..._contextCandidatesForItem(item),
  ];
  if (candidates.isEmpty) {
    return showDialog<SourceContextInput>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从资料/笔记加入'),
        content: const Text('暂无可加入的资料正文或笔记。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
  var selected = 0;
  return showDialog<SourceContextInput>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('从资料/笔记加入'),
        scrollable: true,
        content: RadioGroup<int>(
          groupValue: selected,
          onChanged: (value) => setState(() => selected = value ?? selected),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < candidates.length; i++)
                RadioListTile<int>(
                  contentPadding: EdgeInsets.zero,
                  value: i,
                  title: Text(candidates[i].title),
                  subtitle: Text(
                    candidates[i].text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
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
            onPressed: () => Navigator.pop(context, candidates[selected]),
            child: const Text('加入'),
          ),
        ],
      ),
    ),
  );
}

List<SourceContextInput> _contextCandidatesForItem(LibraryItem item) {
  final candidates = <SourceContextInput>[];
  if (item.notes.trim().isNotEmpty) {
    candidates.add(
      SourceContextInput(
        sourceId: item.id,
        title: '${item.title} · 笔记',
        text: item.notes.trim(),
      ),
    );
  }
  final blockText = item.contentBlocks
      .map((block) => block.text.trim())
      .where((text) => text.isNotEmpty)
      .take(3)
      .join('\n\n');
  final text = blockText.isNotEmpty ? blockText : item.body.trim();
  if (text.isNotEmpty) {
    candidates.add(
      SourceContextInput(
        sourceId: item.id,
        title: '${item.title} · 正文摘录',
        text: text.length > 1200 ? '${text.substring(0, 1200)}…' : text,
      ),
    );
  }
  return candidates;
}

class SourceContextInput {
  const SourceContextInput({
    required this.sourceId,
    required this.title,
    required this.text,
  });

  final String sourceId, title, text;
}

class ContextEntryInput {
  const ContextEntryInput({
    required this.kind,
    required this.text,
    required this.confirmed,
  });

  final String kind, text;
  final bool confirmed;
}
