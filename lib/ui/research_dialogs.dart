import 'package:flutter/material.dart';

import '../core/models.dart';

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
