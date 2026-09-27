import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'common.dart';
import 'developer_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller, required this.data});

  final AppController controller;
  final AppData data;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _savingAppearance = false;
  late final TextEditingController _endpoint;
  late final TextEditingController _textModel;
  late final TextEditingController _visionModel;
  late final TextEditingController _apiKey;
  late final TextEditingController _searchEndpoint;
  late final TextEditingController _searchKey;
  late final TextEditingController _instructions;
  late final TextEditingController _explicit;
  late final TextEditingController _inferred;

  @override
  void initState() {
    super.initState();
    final settings = widget.data.settings;
    _endpoint = TextEditingController(text: settings.endpoint);
    _textModel = TextEditingController(text: settings.textModel);
    _visionModel = TextEditingController(text: settings.visionModel);
    _apiKey = TextEditingController();
    _searchEndpoint = TextEditingController(text: settings.searchEndpoint);
    _searchKey = TextEditingController();
    _instructions = TextEditingController(text: settings.customInstructions);
    _explicit = TextEditingController(
      text: settings.explicitInterests.join('\n'),
    );
    _inferred = TextEditingController(
      text: settings.confirmedInterests.join('\n'),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _endpoint,
      _textModel,
      _visionModel,
      _apiKey,
      _searchEndpoint,
      _searchKey,
      _instructions,
      _explicit,
      _inferred,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppFrame(
      title: '设置',
      actions: [
        IconButton(
          tooltip: '开发者日志',
          icon: const Icon(Icons.receipt_long_outlined),
          onPressed: () => openDiagnostics(context, widget.controller),
        ),
      ],
      child: ListView(
        children: [
          _appearanceSection(context),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('通知', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _NotificationPermissionRow(controller: widget.controller),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('每日汇总'),
                  subtitle: Text(
                    '本地时间 ${_two(widget.data.settings.digestHour)}:${_two(widget.data.settings.digestMinute)} 左右',
                  ),
                  value:
                      widget.data.settings.digestEnabled &&
                      widget.data.settings.digestNotifications,
                  onChanged: (value) => runUiAction(
                    context,
                    () => widget.controller.updateNotificationSettings(
                      digestEnabled: value,
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: const Text('汇总时间'),
                  subtitle: Text(
                    '${_two(widget.data.settings.digestHour)}:${_two(widget.data.settings.digestMinute)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickDigestTime(context),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('运行进度'),
                  subtitle: const Text('前台服务仍会显示系统运行提示；关闭后只减少应用内进度通知。'),
                  value: widget.data.settings.progressNotifications,
                  onChanged: (value) => runUiAction(
                    context,
                    () => widget.controller.updateNotificationSettings(
                      progress: value,
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('任务结果'),
                  value: widget.data.settings.resultNotifications,
                  onChanged: (value) => runUiAction(
                    context,
                    () => widget.controller.updateNotificationSettings(
                      results: value,
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('研究提醒'),
                  value: widget.data.settings.researchNotifications,
                  onChanged: (value) => runUiAction(
                    context,
                    () => widget.controller.updateNotificationSettings(
                      research: value,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('个性化', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: _instructions,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: '分析要求'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _explicit,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: '明确兴趣（每行一个）'),
                ),
                const SizedBox(height: 10),
                Text(
                  '推断兴趣：${widget.data.settings.inferredInterests.isEmpty ? '尚未形成' : widget.data.settings.inferredInterests.join('、')}',
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _inferred,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '确认的兴趣（每行一个）',
                    helperText: '你确认的兴趣将保留，不随自动推断变化。',
                  ),
                ),
              ],
            ),
          ),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('模型', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: _endpoint,
                  decoration: const InputDecoration(
                    labelText: '服务地址',
                    helperText: '公网鉴权服务需使用 HTTPS；本机或私有网络调试可使用 HTTP',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _textModel,
                  decoration: const InputDecoration(labelText: '文本模型'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _visionModel,
                  decoration: const InputDecoration(labelText: '多模态模型'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _apiKey,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: '模型 API Key',
                    helperText: widget.controller.modelConfigured
                        ? '已保存，可留空不改'
                        : '尚未配置',
                  ),
                ),
              ],
            ),
          ),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('搜索', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchEndpoint,
                  decoration: const InputDecoration(
                    labelText: 'Tavily 地址',
                    helperText: '搜索服务使用独立 Key，不与模型 Key 共用',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchKey,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: '搜索 API Key（独立于模型 Key）',
                    helperText: widget.controller.searchConfigured
                        ? '已保存，可留空不改'
                        : '尚未配置',
                  ),
                ),
              ],
            ),
          ),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('回收站', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('从删除当天起计算。缩短保留期会立即永久清理已到期的资料。'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final days in [3, 7])
                      ChoiceChip(
                        label: Text('$days 天'),
                        selected:
                            widget.data.settings.trashRetentionDays == days,
                        onSelected: (_) => _setRetention(context, days),
                      ),
                  ],
                ),
              ],
            ),
          ),
          _backupSection(context),
          SectionCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.code_outlined),
              title: const Text('开发者'),
              subtitle: const Text('任务日志、交互调试与导出'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openDiagnostics(context, widget.controller),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: FilledButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存设置'),
              onPressed: () => _save(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _appearanceSection(BuildContext context) {
    final selected = widget.controller.data.settings.readingPreset;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('外观与阅读', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            '即时生效，阅读内容与操作保持一致。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final preset in ReadingPreset.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: selected == preset
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  key: ValueKey('appearance-${preset.name}'),
                  selected: selected == preset,
                  enabled: !_savingAppearance,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  title: Text(readingPresetLabel(preset)),
                  subtitle: Text(switch (preset) {
                    ReadingPreset.editorial => '舒展正文 · 轻分隔 · 默认',
                    ReadingPreset.compact => '紧凑列表 · 清晰状态 · 正文不缩小',
                    ReadingPreset.magazine => '醒目标题 · 章节色面 · 丰富留白',
                  }),
                  trailing: Icon(
                    selected == preset
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                  ),
                  onTap: () => _setPreset(context, preset),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _setPreset(BuildContext context, ReadingPreset preset) async {
    if (_savingAppearance ||
        widget.controller.data.settings.readingPreset == preset) {
      return;
    }
    setState(() => _savingAppearance = true);
    try {
      await runUiAction(
        context,
        () => widget.controller.setReadingPreset(preset),
      );
    } finally {
      if (mounted) setState(() => _savingAppearance = false);
    }
  }

  Widget _backupSection(BuildContext context) {
    return SectionCard(
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined),
              const SizedBox(width: 12),
              const Expanded(child: Text('本地备份与恢复')),
              OutlinedButton(
                onPressed: () => _backup(context),
                child: const Text('导出 ZIP'),
              ),
            ],
          ),
          const Divider(),
          Row(
            children: [
              const Icon(Icons.restore_outlined),
              const SizedBox(width: 12),
              const Expanded(child: Text('从 ZIP 恢复资料库')),
              FilledButton(
                onPressed: () => _restore(context),
                child: const Text('恢复'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final settings = AppSettings.fromJson({
      ...widget.controller.data.settings.toJson(),
      'endpoint': _endpoint.text.trim(),
      'textModel': _textModel.text.trim(),
      'visionModel': _visionModel.text.trim(),
      'searchEndpoint': _searchEndpoint.text.trim(),
      'customInstructions': _instructions.text.trim(),
      'explicitInterests': _lines(_explicit.text),
      'confirmedInterests': _lines(_inferred.text),
    });
    await runUiAction(
      context,
      () => widget.controller.saveSettings(
        settings,
        apiKey: _apiKey.text.trim().isEmpty ? null : _apiKey.text.trim(),
        searchKey: _searchKey.text.trim().isEmpty
            ? null
            : _searchKey.text.trim(),
      ),
      success: '设置已保存',
    );
  }

  Future<void> _setRetention(BuildContext context, int days) async {
    if (days == widget.controller.data.settings.trashRetentionDays) return;
    if (days < widget.controller.data.settings.trashRetentionDays) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('缩短回收站保留期？'),
          content: Text('改为 $days 天后，已到期的资料将立即永久删除，无法撤销。'),
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
      if (yes != true || !context.mounted) return;
    }
    await runUiAction(
      context,
      () => widget.controller.setTrashRetentionDays(days),
    );
  }

  Future<void> _pickDigestTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: widget.data.settings.digestHour,
        minute: widget.data.settings.digestMinute,
      ),
    );
    if (picked == null || !context.mounted) return;
    await runUiAction(
      context,
      () => widget.controller.updateNotificationSettings(
        hour: picked.hour,
        minute: picked.minute,
      ),
      success: '每日汇总时间已更新',
    );
  }

  Future<void> _backup(BuildContext context) async {
    await runUiAction(context, () async {
      final bytes = await widget.controller.backup();
      if (!context.mounted) {
        return;
      }
      final uri = await FilePicker.saveFile(
        fileName: _backupFileName(),
        bytes: bytes,
        mimeType: 'application/zip',
        dialogTitle: '导出有下文备份',
      );
      if (!context.mounted) {
        return;
      }
      final message = uri == null ? '已取消导出' : '备份已导出';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    });
  }

  Future<void> _restore(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认恢复？'),
        content: const Text('恢复会用 ZIP 中的本地资料库替换当前数据。API Key 不包含在备份中。'),
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
    final picked = await FilePicker.pickFile();
    if (picked == null || !context.mounted) {
      return;
    }
    final bytes = await picked.readAsBytes();
    if (!context.mounted) {
      return;
    }
    await runUiAction(context, () async {
      await widget.controller.restore(Uint8List.fromList(bytes));
      _syncFromSettings(widget.controller.data.settings);
    }, success: '资料库已恢复');
  }

  void _syncFromSettings(AppSettings settings) {
    _endpoint.text = settings.endpoint;
    _textModel.text = settings.textModel;
    _visionModel.text = settings.visionModel;
    _searchEndpoint.text = settings.searchEndpoint;
    _instructions.text = settings.customInstructions;
    _explicit.text = settings.explicitInterests.join('\n');
    _inferred.text = settings.confirmedInterests.join('\n');
  }

  String _backupFileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'afterword-backup-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.zip';
  }

  List<String> _lines(String value) {
    return value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

class _NotificationPermissionRow extends StatelessWidget {
  const _NotificationPermissionRow({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final allowed = controller.notificationsAllowed;
    final label = allowed == null
        ? '未知'
        : allowed
        ? '已允许'
        : '不可用';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            allowed == true
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
          ),
          title: Text('系统通知权限：$label'),
          subtitle: const Text('拒绝权限不会阻止分析；完成后只是不弹出系统通知。'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => runUiAction(
                context,
                () => controller.refreshNotificationPermission(),
              ),
              child: const Text('刷新'),
            ),
            FilledButton(
              onPressed: () => runUiAction(
                context,
                () => controller.refreshNotificationPermission(request: true),
              ),
              child: const Text('请求权限'),
            ),
          ],
        ),
      ],
    );
  }
}
