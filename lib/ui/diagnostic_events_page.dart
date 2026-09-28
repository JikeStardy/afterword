import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide DiagnosticLevel;

import '../core/app_controller.dart';
import '../core/diagnostic_controller.dart';
import '../core/diagnostics.dart';
import '../services/diagnostic_transfer.dart';
import 'common.dart';
import 'afterword_art.dart';

class DiagnosticEventsPage extends StatefulWidget {
  const DiagnosticEventsPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<DiagnosticEventsPage> createState() => _DiagnosticEventsPageState();
}

class _DiagnosticEventsPageState extends State<DiagnosticEventsPage> {
  String? _session, _module, _task;
  DiagnosticLevel? _level;
  String _period = 'all';
  DateTimeRange? _range;
  DiagnosticBundle? _bundle;
  DiagnosticUploadConfig _config = const DiagnosticUploadConfig('', '');
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _session =
        widget.controller.diagnostics.latestDebugSessionId ??
        widget.controller.diagnostics.sessionId;
    _load();
  }

  Future<void> _load() async {
    try {
      final config = await widget.controller.loadDiagnosticUploadConfig();
      final bundle = await widget.controller.pendingDiagnosticBundle();
      if (mounted) {
        setState(() {
          _config = config;
          _bundle = bundle;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _message = '未能读取上传配置或历史诊断包，请重新配置或生成');
    }
  }

  DiagnosticSelection get _selection {
    final now = DateTime.now();
    final from = switch (_period) {
      'hour' => now.subtract(const Duration(hours: 1)),
      'day' => now.subtract(const Duration(days: 1)),
      'week' => now.subtract(const Duration(days: 7)),
      'custom' => _range?.start,
      _ => null,
    };
    return DiagnosticSelection(
      sessionId: _session,
      module: _module,
      level: _level,
      taskId: _task,
      from: from,
      to: _period == 'custom'
          ? _range?.end
                .add(const Duration(days: 1))
                .subtract(const Duration(microseconds: 1))
          : null,
    );
  }

  Future<void> _action(Future<void> Function() body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await body();
    } catch (error) {
      if (mounted) {
        setState(
          () => _message =
              error is DiagnosticUploadException || error is FormatException
              ? error.toString()
              : '操作未完成，请检查本地存储或接收端配置',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _configure() async {
    final endpoint = TextEditingController(text: _config.endpoint);
    final token = TextEditingController(text: _config.token);
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('配置电脑接收端'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: endpoint,
                decoration: const InputDecoration(
                  labelText: '完整接收地址',
                  hintText: 'http://192.168.1.2:18766/diagnostics',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: token,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: '上传令牌'),
              ),
              const SizedBox(height: 16),
              const Text('手机和电脑连接同一 Wi-Fi，并启动接收服务。HTTP 在内网明文传输；请只使用可信家庭网络。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (
              endpoint.text.trim(),
              token.text.trim(),
            )),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // Let the dialog reverse animation dispose its TextFields first.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    endpoint.dispose();
    token.dispose();
    if (result == null || !mounted) return;
    await _action(() async {
      await widget.controller.saveDiagnosticUploadConfig(result.$1, result.$2);
      final config = await widget.controller.loadDiagnosticUploadConfig();
      if (mounted) {
        setState(() {
          _config = config;
          _message = '接收端配置已保存';
        });
      }
    });
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空诊断日志与诊断包？'),
        content: const Text('本机记录将删除，已经上传到电脑的文件不受影响。'),
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
    if (confirmed != true || !mounted) return;
    await _action(() async {
      await widget.controller.clearAppDiagnostics();
      if (mounted) {
        setState(() {
          _bundle = null;
          _session = null;
          _module = null;
          _task = null;
          _message = '本机诊断记录已清空';
        });
      }
    });
  }

  Widget _filter(
    String label,
    String? selected,
    List<(String, String)> values,
    void Function(String?) changed,
  ) => SizedBox(
    width: 245,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$selected'),
      icon: const AfterwordIcon(Icons.arrow_drop_down),
      initialValue: values.any((v) => v.$1 == selected) ? selected : '',
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: '', child: Text('全部')),
        ...values.map(
          (v) => DropdownMenuItem(
            value: v.$1,
            child: Text(v.$2, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: _busy
          ? null
          : (value) => setState(() => changed(value == '' ? null : value)),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller.diagnostics,
    builder: (context, _) {
      final logs = widget.controller.diagnostics;
      final all = logs.events;
      final events = all.where(_selection.includes).toList();
      final sessions = {
        ...all.map((e) => e.sessionId),
        ...logs.tasks.map((t) => t.sessionId).whereType<String>(),
        logs.sessionId,
      }.toList()..sort((a, b) => b.compareTo(a));
      final modules = all.map((e) => e.module).toSet().toList()..sort();
      final tasks = logs.tasks;
      return AppFrame(
        title: 'App 事件与诊断包',
        actions: [
          IconButton(
            tooltip: '清空诊断记录',
            onPressed: _busy ? null : _clear,
            icon: const AfterwordIcon(Icons.delete_outline),
          ),
        ],
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('日志级别：${logs.level.name.toUpperCase()}'),
              subtitle: const Text(
                '开启 DEBUG 记录详细步骤；进程重启恢复 INFO，后台返回保持当前级别。不会开启模型正文记录。',
              ),
              value: logs.level == DiagnosticLevel.debug,
              onChanged: _busy
                  ? null
                  : (value) => logs.setLevel(
                      value ? DiagnosticLevel.debug : DiagnosticLevel.info,
                    ),
            ),
            Text(
              '本机日志 ${(logs.logicalBytes / 1024 / 1024).toStringAsFixed(1)} / 50 MiB · DEBUG 保留 7 天，其余 30 天',
            ),
            if (logs.lastError != null)
              Text(
                logs.lastError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _filter(
                  '运行会话',
                  _session,
                  sessions
                      .map((s) => (s, s == logs.sessionId ? '本次运行 · $s' : s))
                      .toList(),
                  (v) => _session = v,
                ),
                _filter(
                  '模块',
                  _module,
                  modules.map((s) => (s, s)).toList(),
                  (v) => _module = v,
                ),
                _filter(
                  '日志级别',
                  _level?.name,
                  DiagnosticLevel.values
                      .map((l) => (l.name, l.name.toUpperCase()))
                      .toList(),
                  (v) => _level = v == null
                      ? null
                      : DiagnosticLevel.values.byName(v),
                ),
                _filter(
                  '关联任务',
                  _task,
                  tasks.map((t) => (t.id, '${t.type} · ${t.id}')).toList(),
                  (v) => _task = v,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final option in [
                  ('all', '全部时间'),
                  ('hour', '近 1 小时'),
                  ('day', '近 24 小时'),
                  ('week', '近 7 天'),
                ])
                  ChoiceChip(
                    label: Text(option.$2),
                    selected: _period == option.$1,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _period = option.$1),
                  ),
                ActionChip(
                  label: Text(_period == 'custom' ? '自选日期已启用' : '自选日期'),
                  onPressed: _busy
                      ? null
                      : () async {
                          final range = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 365),
                            ),
                            lastDate: DateTime.now(),
                            initialDateRange: _range,
                          );
                          if (range != null && mounted) {
                            setState(() {
                              _range = range;
                              _period = 'custom';
                            });
                          }
                        },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _action(() async {
                          final bundle = await widget.controller
                              .prepareDiagnosticBundle(_selection);
                          if (mounted) {
                            setState(() {
                              _bundle = bundle;
                              _message = '诊断包已生成；筛选变化后需重新生成';
                            });
                          }
                        }),
                  icon: const AfterwordIcon(Icons.inventory_2_outlined),
                  label: const Text('生成诊断包'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _configure,
                  child: const Text('配置接收端'),
                ),
              ],
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _message!,
                  key: const ValueKey('diagnostic-message'),
                ),
              ),
            if (_bundle case final bundle?)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '诊断包预览',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '报告 ${bundle.reportId}\n${bundle.eventCount} 条事件 · ${bundle.taskCount} 个任务 · ${(bundle.bytes.length / 1024).toStringAsFixed(1)} KiB',
                      ),
                      Text(
                        '时间：${bundle.from?.toLocal() ?? bundle.createdAt.toLocal()} — ${bundle.to?.toLocal() ?? bundle.createdAt.toLocal()}',
                      ),
                      const Text('不含模型完整请求、响应或资料正文；导出与上传使用此份快照。'),
                      Text(
                        _config.endpoint.isEmpty
                            ? '尚未配置上传目标'
                            : '上传目标：${_config.endpoint}',
                      ),
                      if (_config.endpoint.startsWith('http:'))
                        const Text('HTTP：内网明文传输'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _action(() async {
                                    final saved = await FilePicker.saveFile(
                                      fileName:
                                          'afterword-diagnostics-${bundle.reportId}.zip',
                                      bytes: bundle.bytes,
                                      mimeType: 'application/zip',
                                      dialogTitle: '导出诊断包',
                                    );
                                    if (saved != null && mounted) {
                                      setState(() => _message = '诊断包已导出');
                                    }
                                  }),
                            child: const Text('导出文件'),
                          ),
                          FilledButton(
                            onPressed: _busy || _config.endpoint.isEmpty
                                ? null
                                : () => _action(() async {
                                    await widget.controller
                                        .uploadDiagnosticBundle(bundle);
                                    if (mounted) {
                                      setState(
                                        () => _message =
                                            '上传成功，已校验报告 ${bundle.reportId}；电脑可读取分析',
                                      );
                                    }
                                  }),
                            child: const Text('上传到电脑'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              '事件记录（${events.length}）',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('此范围内暂无事件。开启 DEBUG 后重现问题，再生成诊断包。'),
              ),
            for (final event in events.take(200))
              ExpansionTile(
                key: ValueKey(event.id),
                title: Text(
                  '${event.level.name.toUpperCase()} · ${event.module} · ${event.name}',
                ),
                subtitle: Text(event.time.toLocal().toString()),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ')
                          .convert(event.toJson()),
                    ),
                  ),
                ],
              ),
            if (events.length > 200) const Text('仅展示最近 200 条，诊断包包含筛选范围内全部事件。'),
          ],
        ),
      );
    },
  );
}
