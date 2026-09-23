import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/diagnostics.dart';
import 'common.dart';
import 'diagnostic_events_page.dart';
import '../core/diagnostic_controller.dart';

void openDiagnostics(
  BuildContext context,
  AppController controller, {
  String? entityId,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DeveloperPage(controller: controller, entityId: entityId),
    ),
  );
}

String _status(String value) => switch (value) {
  'running' => '进行中',
  'succeeded' => '成功',
  'failed' => '失败',
  'cancelled' => '已取消',
  'interrupted' => '已中断',
  _ => value,
};
String _type(String value) => switch (value) {
  'capture' => '保存资料',
  'import' => '导入附件',
  'management' => '资料管理',
  'tracking' => '主题追踪',
  'extract' => '提取正文',
  'analysis' || 'analyze' => '分析',
  'research' => '研究',
  'synthesis' || 'synthesize' => '综述',
  'rss' || 'refreshFeeds' => 'RSS',
  'backup' => '备份',
  'restore' => '恢复',
  _ => value,
};

class DeveloperPage extends StatefulWidget {
  const DeveloperPage({super.key, required this.controller, this.entityId});
  final AppController controller;
  final String? entityId;
  @override
  State<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends State<DeveloperPage> {
  String? _kind, _state;
  bool _relatedOnly = true;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.controller,
      widget.controller.diagnostics,
    ]),
    builder: (context, _) {
      final logs = widget.controller.diagnostics;
      final all = logs.tasks
          .where(
            (task) =>
                !_relatedOnly ||
                widget.entityId == null ||
                task.entityId == widget.entityId ||
                task.inputItemIds.contains(widget.entityId),
          )
          .toList();
      final tasks = all
          .where(
            (task) =>
                (_kind == null || task.type == _kind) &&
                (_state == null || task.status == _state),
          )
          .toList();
      final kinds = all.map((task) => task.type).toSet().toList()..sort();
      return AppFrame(
        title: '开发者日志',
        actions: [
          IconButton(
            tooltip: '导出全部日志',
            onPressed: () => _export(context, logs),
            icon: const Icon(Icons.ios_share_outlined),
          ),
          IconButton(
            tooltip: '清空日志',
            onPressed: () => _clear(context, widget.controller),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: const Text('App 事件与诊断包'),
                    subtitle: Text(
                      '当前 ${logs.level.name.toUpperCase()} · 临时 DEBUG、筛选与内网上传',
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            DiagnosticEventsPage(controller: widget.controller),
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('记录模型完整交互'),
                    subtitle: const Text('仅记录开启后的请求与响应；可能包含资料正文。密钥与图片内容会移除。'),
                    value: widget.controller.data.settings.debugModelLogging,
                    onChanged: (value) => runUiAction(
                      context,
                      () => widget.controller.setDebugModelLogging(value),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      '普通日志保留 30 天，详细交互保留 7 天；总容量上限 50 MB。每次请求或响应最多 256 KiB。日志独立于资料备份。',
                    ),
                  ),
                  if (logs.lastError != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '日志存储异常：${logs.lastError}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (widget.entityId != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FilterChip(
                        label: const Text('仅此资料 / 研究'),
                        selected: _relatedOnly,
                        onSelected: (v) => setState(() {
                          _relatedOnly = v;
                          _kind = null;
                        }),
                      ),
                    ),
                  _filters(
                    [null, ...kinds],
                    _kind,
                    (v) => setState(() => _kind = v),
                    (v) => v == null ? '全部类别' : _type(v),
                  ),
                  _filters(
                    [
                      null,
                      'running',
                      'succeeded',
                      'failed',
                      'cancelled',
                      'interrupted',
                    ],
                    _state,
                    (v) => setState(() => _state = v),
                    (v) => v == null ? '全部状态' : _status(v),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Text(
                      '${tasks.length} 条任务',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const Divider(height: 1),
                ],
              ),
            ),
            if (tasks.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: '暂无匹配日志',
                  message: '执行保存、分析或研究后，可在这里查看任务过程。',
                ),
              ),
            SliverList.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      title: Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              StatusPill(
                                label: _status(task.status),
                                positive: task.status == 'succeeded',
                              ),
                              Text(_type(task.type)),
                              Text(shortDate(task.startedAt)),
                            ],
                          ),
                          if (task.error != null)
                            Text(
                              task.error!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => DiagnosticTaskPage(
                            controller: widget.controller,
                            taskId: task.id,
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  ],
                );
              },
            ),
          ],
        ),
      );
    },
  );
  Widget _filters(
    List<String?> values,
    String? selected,
    ValueChanged<String?> onSelected,
    String Function(String?) label,
  ) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        for (final value in values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(label(value)),
              selected: value == selected,
              onSelected: (_) => onSelected(value),
            ),
          ),
      ],
    ),
  );
  Future<void> _clear(BuildContext context, AppController controller) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空全部日志？'),
        content: const Text('任务记录与详细交互将永久删除，资料库不会改变。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (yes == true && context.mounted) {
      await runUiAction(context, controller.clearAppDiagnostics);
    }
  }
}

class DiagnosticTaskPage extends StatelessWidget {
  const DiagnosticTaskPage({
    super.key,
    required this.controller,
    required this.taskId,
  });
  final AppController controller;
  final String taskId;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller.diagnostics,
    builder: (context, _) {
      final task = controller.diagnostics.task(taskId);
      if (task == null) {
        return const AppFrame(
          title: '任务日志',
          child: EmptyState(
            icon: Icons.receipt_long_outlined,
            title: '日志已清理',
            message: '日志可能已到保留期限或被手动清空。',
          ),
        );
      }
      return AppFrame(
        title: '任务日志',
        actions: [
          IconButton(
            tooltip: '导出此任务',
            onPressed: () =>
                _export(context, controller.diagnostics, taskId: taskId),
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(task.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusPill(
                  label: _status(task.status),
                  positive: task.status == 'succeeded',
                ),
                Text(_type(task.type)),
              ],
            ),
            const SizedBox(height: 12),
            Text('开始：${shortDate(task.startedAt)}'),
            Text(
              '结束：${task.endedAt == null ? '尚未结束' : shortDate(task.endedAt)}',
            ),
            if (task.endedAt != null)
              Text(
                '耗时：${task.endedAt!.difference(task.startedAt).inMilliseconds} ms',
              ),
            if (task.entityId != null)
              Text('关联：${controller.sourceLabel(task.entityId!)}'),
            if (task.parentId != null) Text('父任务：${task.parentId}'),
            if (task.inputItemIds.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('输入资料 · ${task.inputItemIds.length}'),
                children: [
                  for (final id in task.inputItemIds)
                    ListTile(title: Text(controller.sourceLabel(id))),
                ],
              ),
            if (task.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SelectableText(
                  task.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const Divider(height: 32),
            Text('执行时间线', style: Theme.of(context).textTheme.titleMedium),
            if (task.steps.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('暂无步骤记录'),
              ),
            for (final step in task.steps)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  step.status == 'succeeded'
                      ? Icons.check_circle_outline
                      : step.status == 'running'
                      ? Icons.timelapse
                      : Icons.error_outline,
                ),
                title: Text(step.label),
                subtitle: Text(
                  '${_status(step.status)} · ${shortDate(step.startedAt)}${step.endedAt == null ? '' : ' · ${step.endedAt!.difference(step.startedAt).inMilliseconds} ms'}${step.error == null ? '' : '\n${step.error}'}',
                ),
              ),
            const Divider(height: 32),
            Text(
              '模型与网络调用 · ${task.calls.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final call in task.calls) _CallDetails(call: call),
          ],
        ),
      );
    },
  );
}

class _CallDetails extends StatelessWidget {
  const _CallDetails({required this.call});
  final DiagnosticCall call;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Text(call.model ?? '网络请求'),
    subtitle: Text(
      '${call.statusCode == null ? '未收到状态码' : 'HTTP ${call.statusCode}'} · ${shortDate(call.startedAt)}',
    ),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(call.endpoint),
            if (call.stepId != null) Text('步骤 ID：${call.stepId}'),
            Text('请求 ID：${call.requestId ?? '未提供'}'),
            if (call.endedAt != null)
              Text(
                '耗时：${call.endedAt!.difference(call.startedAt).inMilliseconds} ms',
              ),
            if (call.error != null)
              Text(
                call.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            Text('实际用量', style: Theme.of(context).textTheme.titleSmall),
            SelectableText(
              call.usage == null
                  ? '服务未提供用量信息'
                  : const JsonEncoder.withIndent('  ').convert(call.usage),
            ),
            _payload(context, '请求', call.request, call.requestTruncated),
            _payload(context, '响应', call.response, call.responseTruncated),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ],
  );
  Widget _payload(
    BuildContext context,
    String title,
    String? content,
    bool truncated,
  ) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        if (truncated) const Text('内容超过上限，已截断'),
        const SizedBox(height: 8),
        SelectableText(
          content ?? '未记录详细内容（调试关闭或已到期）',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

Future<void> _export(
  BuildContext context,
  DiagnosticStore logs, {
  String? taskId,
}) => runUiAction(context, () async {
  final saved = await FilePicker.saveFile(
    fileName: 'readlater-logs-${DateTime.now().millisecondsSinceEpoch}.json',
    bytes: logs.exportLogs(taskId: taskId),
    mimeType: 'application/json',
    dialogTitle: '导出日志',
  );
  if (saved != null && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('日志已导出')));
  }
});
