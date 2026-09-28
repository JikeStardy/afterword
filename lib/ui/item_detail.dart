import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../platform/native_bridge.dart';
import '../services/knowledge_service.dart';
import 'common.dart';
import 'research_detail.dart';
import 'item_actions.dart';
import 'developer_page.dart';
import 'reading_content.dart';

class ArticleDetailPage extends StatefulWidget {
  const ArticleDetailPage({
    super.key,
    required this.controller,
    required this.item,
    this.initialBlockId,
    this.initialPdfPage,
  });

  final AppController controller;
  final LibraryItem item;
  final String? initialBlockId;
  final int? initialPdfPage;

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
          initialBlockId: widget.initialBlockId,
          initialPdfPage: widget.initialPdfPage,
        );
      },
    );
  }
}

class _ArticleDetailView extends StatefulWidget {
  const _ArticleDetailView({
    required this.controller,
    required this.item,
    required this.notes,
    required this.syncSavedNotes,
    this.initialBlockId,
    this.initialPdfPage,
  });

  final AppController controller;
  final LibraryItem item;
  final TextEditingController notes;
  final ValueChanged<String> syncSavedNotes;
  final String? initialBlockId;
  final int? initialPdfPage;

  @override
  State<_ArticleDetailView> createState() => _ArticleDetailViewState();
}

class _ArticleDetailViewState extends State<_ArticleDetailView> {
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _blockKeys = <String, GlobalKey>{};
  final Map<String, GlobalKey> _analysisKeys = <String, GlobalKey>{};
  bool _initialTargetHandled = false;
  ReadingPreset? _lastPreset;
  String? _visibleAnalysisAnchorId;

  AppController get controller => widget.controller;
  LibraryItem get item => widget.item;
  TextEditingController get notes => widget.notes;
  ValueChanged<String> get syncSavedNotes => widget.syncSavedNotes;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_captureVisibleAnalysisAnchor);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restoreInitialPosition();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final preset = ReadingLayout.of(context).preset;
    final previous = _lastPreset;
    _lastPreset = preset;
    if (previous != null && previous != preset) {
      final anchor = _visibleAnalysisAnchorId ?? _firstMountedAnalysisAnchor();
      final anchorContext = anchor == null
          ? null
          : _analysisKeys[anchor]?.currentContext;
      final topOffset = anchorContext == null
          ? 0.0
          : _anchorViewportOffset(anchorContext);
      if (anchor != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final anchorContext = _analysisKeys[anchor]?.currentContext;
          if (anchorContext == null) return;
          final box = anchorContext.findRenderObject() as RenderBox?;
          if (box == null || !box.attached || !_scroll.hasClients) return;
          final currentOffset = _anchorViewportOffset(anchorContext);
          final target = (_scroll.offset + currentOffset - topOffset).clamp(
            0.0,
            _scroll.position.maxScrollExtent,
          );
          _scroll.jumpTo(target.toDouble());
        });
      }
    }
  }

  @override
  void dispose() {
    _saveReadingPosition();
    _scroll.removeListener(_captureVisibleAnalysisAnchor);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fontScale = controller.data.settings.readerFontScale;
    return DefaultTabController(
      length: 3,
      initialIndex:
          item.analysis == null ||
              widget.initialBlockId != null ||
              widget.initialPdfPage != null
          ? 0
          : 1,
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
                ? () => runUiAction(
                    context,
                    () => _queueAnalysis(item.id),
                    success: '分析已提交',
                  )
                : null,
          ),
          if (item.kind == ItemKind.web)
            IconButton(
              tooltip: '重抓正文',
              icon: const Icon(Icons.refresh_outlined),
              onPressed: item.isActive
                  ? () => runUiAction(
                      context,
                      () => controller.retryCapture(item.id),
                      success: '重抓已提交',
                    )
                  : null,
            ),
          IconButton(
            tooltip: '导出 Markdown',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _exportMarkdown(context),
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
                    if (item.contentHistory.isNotEmpty)
                      _RevisionHistoryCard(
                        revisions: item.contentHistory,
                        fontScale: fontScale,
                      ),
                    if (_shouldShowWebRecovery(item))
                      _WebRecoveryPanel(controller: controller, item: item),
                    _StructuredReader(
                      controller: controller,
                      item: item,
                      fontScale: fontScale,
                      onSelection: (text, blockId) =>
                          _saveAnnotation(context, text, blockId),
                      onPageNote: (page) => _savePageNote(context, page),
                      blockKeys: _blockKeys,
                      initialPdfPage: widget.initialPdfPage,
                    ),
                  ]),
                  _reader(context, [
                    _AnalysisSection(
                      controller: controller,
                      item: item,
                      fontScale: fontScale,
                      analysisKeys: _analysisKeys,
                    ),
                  ]),
                  _reader(context, [
                    _NotesCard(
                      controller: controller,
                      item: item,
                      notes: notes,
                      fontScale: fontScale,
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

  Future<void> _queueAnalysis(String itemId) async {
    await controller.queueAnalysis(itemId);
  }

  Future<void> _exportMarkdown(BuildContext context) async {
    await runUiAction(context, () async {
      final markdown = KnowledgeService.exportItemMarkdown(
        item,
        labelForSource: controller.sourceLabel,
      );
      final saved = await FilePicker.saveFile(
        fileName: KnowledgeService.encodeMarkdownFileName(item.title, item.id),
        bytes: utf8.encode(markdown),
        mimeType: 'text/markdown',
        dialogTitle: '导出 Markdown',
      );
      if (saved == null) throw StateError('已取消导出');
    }, success: 'Markdown 已导出');
  }

  Future<void> _saveAnnotation(
    BuildContext context,
    String text,
    String? blockId,
  ) async {
    final quote = text.trim();
    if (quote.isEmpty) return;
    final note = await showDialog<String>(
      context: context,
      builder: (context) {
        final note = TextEditingController();
        return AlertDialog(
          title: const Text('保存高亮'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(quote, maxLines: 4, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(hintText: '批注，可留空'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, note.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (note == null) return;
    await controller.addAnnotation(
      item.id,
      quote: quote,
      blockId: blockId,
      note: note.trim(),
    );
  }

  Future<void> _savePageNote(BuildContext context, int page) async {
    final existing = item.annotations
        .where(
          (annotation) =>
              annotation.anchor.pdfPage == page &&
              annotation.highlightedText.isEmpty,
        )
        .firstOrNull;
    await showDialog<void>(
      context: context,
      builder: (_) => _AutosaveNoteDialog(
        title: '第 $page 页笔记',
        initialNote: existing?.note ?? '',
        onSave: (note) => controller.updatePageNote(item.id, page, note),
      ),
    );
  }

  void _restoreInitialPosition() {
    if (!mounted || _initialTargetHandled) return;
    _initialTargetHandled = true;
    final blockId = widget.initialBlockId;
    if (blockId != null && blockId.isNotEmpty) {
      final context = _blockKeys[blockId]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 250),
          alignment: 0.08,
        );
        controller.updateReadingPosition(item.id, blockId: blockId);
        return;
      }
    }
    final rawPosition = item.toJson()['readingPosition'];
    final offset = rawPosition is Map ? rawPosition['offset'] : null;
    if (offset is num && _scroll.hasClients) {
      _scroll.jumpTo(
        offset.toDouble().clamp(0, _scroll.position.maxScrollExtent).toDouble(),
      );
    }
  }

  void _saveReadingPosition() {
    if (!_scroll.hasClients) return;
    controller.updateReadingPosition(item.id, scrollOffset: _scroll.offset);
  }

  void _captureVisibleAnalysisAnchor() {
    if (!_scroll.hasClients) return;
    final next = _firstVisibleAnalysisAnchor();
    if (next != null) _visibleAnalysisAnchorId = next;
  }

  String? _firstVisibleAnalysisAnchor() {
    final viewport = _readerViewport();
    if (viewport == null) return _firstMountedAnalysisAnchor();
    String? closestBelow;
    double? closestDistance;
    String? bestOverlap;
    double bestOverlapHeight = 0;
    for (final entry in _analysisKeys.entries) {
      final anchorContext = entry.value.currentContext;
      if (anchorContext == null) continue;
      final box = anchorContext.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      final overlap =
          bottom.clamp(viewport.top, viewport.bottom) -
          top.clamp(viewport.top, viewport.bottom);
      if (overlap > bestOverlapHeight) {
        bestOverlapHeight = overlap;
        bestOverlap = entry.key;
      }
      if (top < viewport.top) continue;
      if (closestDistance == null || top < closestDistance) {
        closestDistance = top;
        closestBelow = entry.key;
      }
    }
    return bestOverlap ?? closestBelow ?? _firstMountedAnalysisAnchor();
  }

  String? _firstMountedAnalysisAnchor() {
    for (final entry in _analysisKeys.entries) {
      if (entry.value.currentContext != null) return entry.key;
    }
    return null;
  }

  Rect? _readerViewport() {
    final renderObject = context.findRenderObject() as RenderBox?;
    if (renderObject == null || !renderObject.attached) return null;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    return topLeft & renderObject.size;
  }

  double _anchorViewportOffset(BuildContext anchorContext) {
    final viewport = _readerViewport();
    final box = anchorContext.findRenderObject() as RenderBox?;
    if (viewport == null || box == null || !box.attached) return 0;
    return box.localToGlobal(Offset.zero).dy - viewport.top;
  }

  Widget _reader(BuildContext context, List<Widget> children) {
    final layout = ReadingLayout.of(context);
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
        layout.pagePadding,
        layout.sectionGap,
        layout.pagePadding,
        40,
      ),
      children: [
        Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Text(kindLabel(item.kind)),
            Text(shortDate(item.createdAt)),
            if (!item.isActive)
              StatusPill(label: item.isTrashed ? '回收站' : '已归档'),
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
                if (item.kind == ItemKind.web &&
                    item.warning.contains('图片') &&
                    item.isActive)
                  TextButton.icon(
                    onPressed: () => runUiAction(
                      context,
                      () => controller.retryImages(item.id),
                      success: '补图已提交',
                    ),
                    icon: const Icon(Icons.image_search_outlined),
                    label: const Text('重试补图'),
                  ),
              ],
            ),
          ),
        SizedBox(height: layout.sectionGap),
        ...children,
      ],
    );
  }
}

bool _shouldShowWebRecovery(LibraryItem item) {
  if (item.kind != ItemKind.web) return false;
  if (item.bodyOrigin.isNotEmpty) return true;
  return _needsWebRecovery(item);
}

bool _needsWebRecovery(LibraryItem item) {
  return item.body.trim().isEmpty || item.error.startsWith('正文提取失败');
}

class _WebRecoveryPanel extends StatefulWidget {
  const _WebRecoveryPanel({required this.controller, required this.item});

  final AppController controller;
  final LibraryItem item;

  @override
  State<_WebRecoveryPanel> createState() => _WebRecoveryPanelState();
}

class _WebRecoveryPanelState extends State<_WebRecoveryPanel> {
  bool _opening = false, _saving = false;

  bool get _canOpenWebPage {
    final uri = Uri.tryParse(widget.item.url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'mp.weixin.qq.com' &&
        uri.userInfo.isEmpty &&
        uri.port == 443;
  }

  bool get _disabled => !widget.item.isActive || _opening || _saving;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bodyOrigin = widget.item.bodyOrigin;
    final needsRecovery = _needsWebRecovery(widget.item);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.travel_explore_outlined, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        needsRecovery ? '补全网页正文' : '已保存提取内容',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        needsRecovery
                            ? '链接仍保留。可打开页面完成验证后保存正文，或把正文粘贴到这份资料里。'
                            : '来源链接仍保留。如内容不全，可重新抓取或补充正文。',
                      ),
                      if (bodyOrigin == 'pasted') ...[
                        const SizedBox(height: 8),
                        Text(
                          '正文由你粘贴，来源链接保留',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ] else if (bodyOrigin == 'webview') ...[
                        const SizedBox(height: 8),
                        Text(
                          '正文从打开的页面保存',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (!widget.item.isActive) ...[
                        const SizedBox(height: 8),
                        Text(
                          widget.item.isTrashed
                              ? '资料在回收站，恢复后才能补正文。'
                              : '资料已归档，取消归档后才能补正文。',
                          style: TextStyle(color: colors.error),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_canOpenWebPage)
                    FilledButton.icon(
                      onPressed: _disabled ? null : _recoverFromWebPage,
                      icon: _opening
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.open_in_browser_outlined),
                      label: const Text('打开页面保存'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _disabled ? null : _showPasteDialog,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.edit_note_outlined),
                    label: Text(needsRecovery ? '粘贴正文' : '补充正文'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _recoverFromWebPage() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final saved = await widget.controller.recoverWebArticle(widget.item.id);
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('正文已保存')));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _showPasteDialog() async {
    final result = await showDialog<({String title, String body})>(
      context: context,
      builder: (context) => const _PasteWebArticleDialog(),
    );
    if (!mounted) return;
    if (result == null || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.controller.supplementWebArticle(
        widget.item.id,
        body: result.body,
        title: result.title,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('正文已保存')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _PasteWebArticleDialog extends StatefulWidget {
  const _PasteWebArticleDialog();

  @override
  State<_PasteWebArticleDialog> createState() => _PasteWebArticleDialogState();
}

class _PasteWebArticleDialogState extends State<_PasteWebArticleDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _body.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('粘贴正文'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: '标题，可选'),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: TextField(
                  controller: _body,
                  autofocus: true,
                  minLines: 8,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: '正文',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
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
          onPressed: canSave
              ? () => Navigator.pop(context, (
                  title: _title.text.trim(),
                  body: _body.text.trim(),
                ))
              : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _RevisionHistoryCard extends StatelessWidget {
  const _RevisionHistoryCard({
    required this.revisions,
    required this.fontScale,
  });

  final List<ContentRevision> revisions;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final sorted = revisions.toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        leading: const Icon(Icons.history_outlined),
        title: Text('历史正文 · ${sorted.length}'),
        subtitle: const Text('重抓正文前保留的旧版本'),
        children: [
          for (final revision in sorted)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('v${revision.version} · ${revision.title}'),
              subtitle: Text(shortDate(revision.savedAt)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openRevision(context, revision),
            ),
        ],
      ),
    );
  }

  void _openRevision(BuildContext context, ContentRevision revision) {
    final blocks = revision.blocks
        .map((block) => block.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
    final body = blocks.isEmpty ? revision.body.trim() : blocks.join('\n\n');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('v${revision.version} · ${revision.title}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectionArea(
              child: Text(
                body.isEmpty ? '此版本没有可显示正文。' : body,
                style: TextStyle(fontSize: 16 * fontScale, height: 1.7),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _StructuredReader extends StatelessWidget {
  const _StructuredReader({
    required this.controller,
    required this.item,
    required this.fontScale,
    required this.onSelection,
    required this.onPageNote,
    required this.blockKeys,
    this.initialPdfPage,
  });

  final AppController controller;
  final LibraryItem item;
  final double fontScale;
  final void Function(String text, String? blockId) onSelection;
  final void Function(int page) onPageNote;
  final Map<String, GlobalKey> blockKeys;
  final int? initialPdfPage;

  @override
  Widget build(BuildContext context) {
    if (item.kind == ItemKind.pdf && item.assets.isNotEmpty) {
      return _PdfInlineReader(
        controller: controller,
        item: item,
        fontScale: fontScale,
        initialPage: initialPdfPage,
        onPageNote: onPageNote,
      );
    }
    final blocks = KnowledgeService.contentBlocksForItem(item);
    if (blocks.isEmpty) {
      return SelectableText(
        item.url,
        style: TextStyle(fontSize: 17 * fontScale, height: 1.7),
      );
    }
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final block in blocks)
            _ReaderBlock(
              key: _keyFor(block['id'] as String?),
              block: block,
              assetPathFor: _assetPathFor,
              fontScale: fontScale,
              onPageNote: onPageNote,
              onHighlight: () => onSelection(
                block['text'] as String? ?? '',
                block['id'] as String?,
              ),
            ),
        ],
      ),
    );
  }

  Key? _keyFor(String? blockId) {
    if (blockId == null || blockId.isEmpty) return null;
    return blockKeys.putIfAbsent(blockId, GlobalKey.new);
  }

  String _assetPathFor(String assetId) {
    final asset = item.assets
        .where(
          (candidate) => candidate.path == assetId || candidate.name == assetId,
        )
        .firstOrNull;
    return asset == null ? '' : controller.assetPath(asset);
  }
}

class _PdfInlineReader extends StatefulWidget {
  const _PdfInlineReader({
    required this.controller,
    required this.item,
    required this.fontScale,
    required this.onPageNote,
    this.initialPage,
  });

  final AppController controller;
  final LibraryItem item;
  final double fontScale;
  final int? initialPage;
  final void Function(int page) onPageNote;

  @override
  State<_PdfInlineReader> createState() => _PdfInlineReaderState();
}

class _PdfInlineReaderState extends State<_PdfInlineReader> {
  late int _page;
  Future<PdfPages>? _render;

  @override
  void initState() {
    super.initState();
    final savedPage = widget.item.readingPosition?.pdfPage;
    _page = _boundedPage(widget.initialPage ?? savedPage ?? 1);
    _render = _renderPage();
  }

  @override
  void didUpdateWidget(covariant _PdfInlineReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextInitial = widget.initialPage;
    if (nextInitial != null && nextInitial != oldWidget.initialPage) {
      _goTo(nextInitial);
    } else if (widget.item.pdfPageCount != oldWidget.item.pdfPageCount) {
      final bounded = _boundedPage(_page);
      if (bounded != _page) _goTo(bounded);
    }
  }

  int get _maxPage => widget.item.pdfPageCount ?? 100;
  int _boundedPage(int page) => page.clamp(1, _maxPage).toInt();

  Future<PdfPages> _renderPage() async {
    final requestedPage = _page;
    final asset = widget.item.assets.firstWhere(
      (asset) => asset.mime == 'application/pdf' || asset.name.endsWith('.pdf'),
      orElse: () => widget.item.assets.first,
    );
    final rendered = await widget.controller.native.renderPdf(
      widget.controller.assetPath(asset),
      startPage: requestedPage - 1,
      maxPages: 1,
    );
    if (!mounted || requestedPage != _page) return rendered;
    if (rendered.pageCount > 0 &&
        rendered.pageCount != widget.item.pdfPageCount) {
      await widget.controller.updatePdfPageCount(
        widget.item.id,
        rendered.pageCount,
      );
    }
    if (!mounted || requestedPage != _page) return rendered;
    if (rendered.pageCount > 0 && requestedPage > rendered.pageCount) {
      _goTo(rendered.pageCount);
      return rendered;
    }
    await widget.controller.updateReadingPosition(
      widget.item.id,
      pdfPage: requestedPage,
    );
    return rendered;
  }

  void _goTo(int page) {
    final next = _boundedPage(page);
    if (next == _page && _render != null) return;
    setState(() {
      _page = next;
      _render = _renderPage();
    });
  }

  Future<void> _jump(BuildContext context) async {
    final text = TextEditingController(text: '$_page');
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('跳转 PDF 页'),
        content: TextField(
          controller: text,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: '页码，1–$_maxPage'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(text.text)),
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    if (page != null && mounted) _goTo(page);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('PDF 第 $_page/${widget.item.pdfPageCount ?? '?'} 页'),
            OutlinedButton.icon(
              onPressed: _page <= 1 ? null : () => _goTo(_page - 1),
              icon: const Icon(Icons.chevron_left),
              label: const Text('上一页'),
            ),
            OutlinedButton.icon(
              onPressed:
                  widget.item.pdfPageCount != null &&
                      _page >= widget.item.pdfPageCount!
                  ? null
                  : () => _goTo(_page + 1),
              icon: const Icon(Icons.chevron_right),
              label: const Text('下一页'),
            ),
            TextButton.icon(
              onPressed: () => _jump(context),
              icon: const Icon(Icons.search_outlined),
              label: const Text('跳页'),
            ),
            TextButton.icon(
              onPressed: () => widget.onPageNote(_page),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('页笔记'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<PdfPages>(
          future: _render,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Text('PDF 渲染失败：${snapshot.error}');
            }
            final image = snapshot.data?.images.firstOrNull;
            if (image == null || image.isEmpty) {
              return const Text('这一页暂时无法渲染。');
            }
            return InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Image.memory(
                base64Decode(image),
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ReaderBlock extends StatelessWidget {
  const _ReaderBlock({
    super.key,
    required this.block,
    required this.assetPathFor,
    required this.fontScale,
    required this.onPageNote,
    required this.onHighlight,
  });

  final Json block;
  final String Function(String assetId) assetPathFor;
  final double fontScale;
  final void Function(int page) onPageNote;
  final VoidCallback onHighlight;

  @override
  Widget build(BuildContext context) {
    final kind = block['kind'] as String? ?? 'paragraph';
    final text = block['text'] as String? ?? '';
    final page = block['page'];
    final style = switch (kind) {
      'heading' => Theme.of(context).textTheme.titleMedium?.copyWith(
        fontSize: (20 - ((block['level'] as int? ?? 2) - 1) * 1.5) * fontScale,
        height: 1.35,
      ),
      'code' => TextStyle(
        fontFamily: 'monospace',
        fontSize: 15 * fontScale,
        height: 1.55,
      ),
      'listItem' => TextStyle(fontSize: 17 * fontScale, height: 1.6),
      _ => TextStyle(fontSize: 17 * fontScale, height: 1.7),
    };
    final child = switch (kind) {
      'code' => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SelectableText(text, style: style),
        ),
      ),
      'table' => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(text, style: style),
      ),
      'image' => _ImageContextBlock(
        block: block,
        style: style,
        assetPathFor: assetPathFor,
      ),
      'listItem' => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 7 * fontScale, right: 8),
            child: const Icon(Icons.circle, size: 6),
          ),
          Expanded(child: SelectableText(text, style: style)),
        ],
      ),
      _ => SelectableText(text, style: style),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: '高亮本段',
              icon: const Icon(Icons.border_color_outlined),
              onPressed: text.trim().isEmpty ? null : onHighlight,
            ),
          ),
          if (page is int)
            TextButton.icon(
              icon: const Icon(Icons.note_add_outlined),
              label: Text('PDF 第 $page 页笔记'),
              onPressed: () => onPageNote(page),
            ),
          child,
        ],
      ),
    );
  }
}

class _ImageContextBlock extends StatelessWidget {
  const _ImageContextBlock({
    required this.block,
    required this.style,
    required this.assetPathFor,
  });

  final Json block;
  final TextStyle? style;
  final String Function(String assetId) assetPathFor;

  @override
  Widget build(BuildContext context) {
    final text = block['text'] as String? ?? '';
    final assetId = block['assetPath'] as String? ?? '';
    final assetPath = assetPathFor(assetId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (assetPath.isNotEmpty && File(assetPath).existsSync())
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(File(assetPath), fit: BoxFit.contain),
          ),
        if (text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SelectableText('图片：$text', style: style),
          ),
      ],
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({
    required this.controller,
    required this.item,
    required this.notes,
    required this.fontScale,
    required this.onSave,
  });

  final AppController controller;
  final LibraryItem item;
  final TextEditingController notes;
  final double fontScale;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final bodyStyle = TextStyle(fontSize: 17 * fontScale, height: 1.7);
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
            style: bodyStyle,
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
          if (item.annotations.isNotEmpty) ...[
            const Divider(height: 28),
            Text('高亮与页笔记', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final annotation in item.annotations)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  annotation.anchor.pdfPage == null
                      ? Icons.border_color_outlined
                      : Icons.picture_as_pdf_outlined,
                ),
                title: Text(
                  annotation.highlightedText.isNotEmpty
                      ? annotation.highlightedText
                      : 'PDF 第 ${annotation.anchor.pdfPage} 页',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: bodyStyle,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (annotation.note.isNotEmpty) Text(annotation.note),
                    if (annotation.anchor.unresolved)
                      const Text('原文位置已失效，已保留摘录'),
                  ],
                ),
                trailing: IconButton(
                  tooltip: '编辑批注',
                  icon: const Icon(Icons.edit_note_outlined),
                  onPressed: () => _editAnnotation(context, annotation),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _editAnnotation(
    BuildContext context,
    Annotation annotation,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AutosaveNoteDialog(
        title: '编辑批注',
        initialNote: annotation.note,
        onSave: (note) =>
            controller.updateAnnotation(item.id, annotation.id, note),
      ),
    );
  }
}

class _AutosaveNoteDialog extends StatefulWidget {
  const _AutosaveNoteDialog({
    required this.title,
    required this.initialNote,
    required this.onSave,
  });
  final String title;
  final String initialNote;
  final Future<void> Function(String) onSave;
  @override
  State<_AutosaveNoteDialog> createState() => _AutosaveNoteDialogState();
}

class _AutosaveNoteDialogState extends State<_AutosaveNoteDialog> {
  String? _error;
  int _revision = 0;
  Future<void> _save(String value) async {
    final revision = ++_revision;
    try {
      await widget.onSave(value);
      if (mounted && revision == _revision) setState(() => _error = null);
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _error = '保存失败：$error');
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextFormField(
      initialValue: widget.initialNote,
      autofocus: true,
      minLines: 3,
      maxLines: 6,
      onChanged: _save,
      decoration: InputDecoration(
        hintText: '批注',
        helperText: '修改自动保存',
        errorText: _error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('完成'),
      ),
    ],
  );
}

class _AnalysisSection extends StatelessWidget {
  const _AnalysisSection({
    required this.controller,
    required this.item,
    required this.fontScale,
    required this.analysisKeys,
  });

  final AppController controller;
  final LibraryItem item;
  final double fontScale;
  final Map<String, GlobalKey> analysisKeys;

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
                ? () => runUiAction(
                    context,
                    () => _queueAnalysis(item.id),
                    success: '分析已提交',
                  )
                : null,
          ),
        ),
      );
    }
    final layout = ReadingLayout.of(context);
    final analysisJson = analysis.toJson();
    final structured = KnowledgeService.structuredInsights(analysis);
    final brief = stringField(analysisJson, 'brief');
    final hasBrief = brief.isNotEmpty;
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (analysis.toJson()['stale'] == true) ...[
            const StatusPill(label: '内容或背景已变化，建议更新'),
            SizedBox(height: layout.rowPadding),
          ],
          if (brief.isNotEmpty || analysis.summary.trim().isNotEmpty) ...[
            Text('导读', style: Theme.of(context).textTheme.bodySmall),
            SizedBox(height: layout.rowPadding * 0.5),
            ReadingContent(
              brief: brief,
              fallback: analysis.summary,
              sources: analysis.sourceIds,
              labelForSource: controller.sourceLabel,
              fontScale: fontScale,
              legacyLabel: structured.isEmpty && !hasBrief ? null : '完整总结',
              initiallyExpandFallback: structured.isEmpty && !hasBrief,
            ),
            SizedBox(height: layout.sectionGap),
          ],
          for (final insight in structured.indexed)
            KeyedSubtree(
              key: ValueKey(_insightUiKey(insight.$2, insight.$1)),
              child: _StructuredInsightTile(
                key: _keyForInsight(insight.$2, insight.$1),
                insight: insight.$2,
                fallbackTitle: _insightTitle(insight.$2, insight.$1),
                uiId: _insightUiId(insight.$2, insight.$1),
                controller: controller,
                itemId: item.id,
                labelForSource: controller.sourceLabel,
                fontScale: fontScale,
              ),
            ),
          if (analysis.insights.isNotEmpty) ...[
            if (structured.isNotEmpty) SizedBox(height: layout.sectionGap),
            if (structured.isEmpty)
              ReadingContent(
                title: '观点',
                sections: [
                  for (final insight in analysis.insights.indexed)
                    ReadingSectionData(
                      title: '观点 ${insight.$1 + 1}',
                      body: insight.$2,
                    ),
                ],
                sources: analysis.sourceIds,
                labelForSource: controller.sourceLabel,
                fontScale: fontScale,
              )
            else
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('此前生成的观点'),
                subtitle: const Text('查看此前生成的观点内容'),
                children: [
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
                ],
              ),
          ],
          if (analysis.connections.isNotEmpty) ...[
            SizedBox(height: layout.sectionGap),
            ReadingContent(
              title: '与已有资料的关系',
              sections: [
                for (final connection in analysis.connections.indexed)
                  ReadingSectionData(
                    title: '关系 ${connection.$1 + 1}',
                    body: connection.$2,
                  ),
              ],
              sources: analysis.sourceIds,
              labelForSource: controller.sourceLabel,
              fontScale: fontScale,
            ),
          ],
          if (analysis.questions.isNotEmpty) ...[
            SizedBox(height: layout.sectionGap),
            Text('研究建议', style: Theme.of(context).textTheme.titleSmall),
            SizedBox(height: layout.rowPadding),
            for (final question in analysis.questions.indexed)
              Padding(
                padding: EdgeInsets.only(bottom: layout.rowPadding),
                child: _QuestionRow(
                  question: readerCitationText(
                    question.$2,
                    analysis.sourceIds,
                    labelForSource: controller.sourceLabel,
                  ),
                  enabled: item.isActive && analysis.inputItemIds != null,
                  onConfirm: () => _confirmResearch(context, question.$2),
                ),
              ),
          ],
          SizedBox(height: layout.sectionGap),
          const Divider(),
          SourceList(
            sources: analysis.sourceIds,
            labelForSource: controller.sourceLabel,
            onSourceTap: (source) => _openSource(context, source),
          ),
          SizedBox(height: layout.rowPadding),
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
      success: '研究已提交',
    );
  }

  Future<void> _queueAnalysis(String itemId) async {
    await controller.queueAnalysis(itemId);
  }

  static String _insightTitle(Json insight, int index) {
    final title = stringField(insight, 'title');
    if (title.isNotEmpty) return title;
    return '观点 ${(index + 1).toString().padLeft(2, '0')}';
  }

  static String _insightUiId(Json insight, int index) {
    final id = (insight['id'] as String? ?? '').trim();
    return id.isEmpty ? 'row-$index' : '$id-$index';
  }

  static String _insightUiKey(Json insight, int index) {
    return 'insight-${_insightUiId(insight, index)}';
  }

  GlobalKey _keyForInsight(Json insight, int index) {
    final id = _insightUiId(insight, index);
    return analysisKeys.putIfAbsent(id, GlobalKey.new);
  }
}

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({
    required this.question,
    required this.enabled,
    required this.onConfirm,
  });

  final String question;
  final bool enabled;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              question,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: enabled ? onConfirm : null,
                icon: const Icon(Icons.travel_explore_outlined),
                label: const Text('确认研究'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StructuredInsightTile extends StatelessWidget {
  const _StructuredInsightTile({
    super.key,
    required this.insight,
    required this.fallbackTitle,
    required this.uiId,
    required this.controller,
    required this.itemId,
    required this.labelForSource,
    required this.fontScale,
  });

  final Json insight;
  final String fallbackTitle;
  final String uiId;
  final AppController controller;
  final String itemId;
  final String Function(String source) labelForSource;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final evidence = insight['evidence'];
    final unknowns = insight['unknowns'];
    final layout = ReadingLayout.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: layout.sectionGap),
      child: Padding(
        padding: EdgeInsets.only(bottom: layout.rowPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReadingHeading(
              stringField(insight, 'title').isEmpty
                  ? fallbackTitle
                  : stringField(insight, 'title'),
              fontScale: fontScale,
            ),
            SizedBox(height: layout.rowPadding),
            if (stringField(insight, 'finding').isNotEmpty)
              _InsightParagraph(
                label: '发现',
                text: stringField(insight, 'finding'),
                fontScale: fontScale,
              ),
            if ((insight['change'] as String? ?? '').isNotEmpty) ...[
              SizedBox(height: layout.rowPadding),
              _InsightParagraph(
                label: '变化',
                text: stringField(insight, 'change'),
                fontScale: fontScale,
              ),
            ],
            if ((insight['impact'] as String? ?? '').isNotEmpty) ...[
              SizedBox(height: layout.rowPadding),
              _InsightParagraph(
                label: '影响',
                text: stringField(insight, 'impact'),
                fontScale: fontScale,
              ),
            ],
            if (unknowns is List && unknowns.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: layout.rowPadding),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer
                        .withValues(alpha: 0.45),
                    border: Border(
                      left: BorderSide(
                        width: 3,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(layout.rowPadding),
                    child: SelectableText(
                      '未知与限制：${unknowns.whereType<String>().join('；')}',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 16 * fontScale,
                        height: layout.bodyHeight,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            SizedBox(height: layout.rowPadding),
            if (evidence is List)
              _EvidenceDisclosure(
                key: ValueKey('evidence-$uiId'),
                anchors: evidence
                    .whereType<Map>()
                    .map((raw) => Map<String, dynamic>.from(raw))
                    .toList(growable: false),
                controller: controller,
                labelForSource: labelForSource,
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: PopupMenuButton<String>(
                tooltip: '反馈',
                initialValue: _menuValue(insight['verdict'] as String? ?? ''),
                onSelected: (value) => controller.setInsightVerdict(
                  itemId,
                  insight['id'] as String? ?? '',
                  value,
                ),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: '认可', child: Text('认可')),
                  PopupMenuItem(value: '存疑', child: Text('存疑')),
                  PopupMenuItem(value: '过时', child: Text('过时')),
                  PopupMenuItem(value: '无关', child: Text('无关')),
                ],
                child: ConstrainedBox(
                  key: ValueKey('insight-feedback-$uiId'),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.rate_review_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '反馈',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Divider(height: layout.sectionGap),
          ],
        ),
      ),
    );
  }

  String _verdictLabel(String value) => switch (value) {
    'agreed' => '认可',
    'doubt' => '存疑',
    'stale' => '过时',
    'irrelevant' => '无关',
    'new' => '',
    _ => value,
  };

  String? _menuValue(String value) {
    final label = _verdictLabel(value);
    return {'认可', '存疑', '过时', '无关'}.contains(label) ? label : null;
  }
}

class _InsightParagraph extends StatelessWidget {
  const _InsightParagraph({
    required this.label,
    required this.text,
    required this.fontScale,
  });

  final String label;
  final String text;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        SelectableText(
          text,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(fontSize: 17 * fontScale, height: layout.bodyHeight),
        ),
      ],
    );
  }
}

class _EvidenceDisclosure extends StatelessWidget {
  const _EvidenceDisclosure({
    super.key,
    required this.anchors,
    required this.controller,
    required this.labelForSource,
  });

  final List<Json> anchors;
  final AppController controller;
  final String Function(String source) labelForSource;

  @override
  Widget build(BuildContext context) {
    if (anchors.isEmpty) {
      return const Text('证据：暂无可定位来源');
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text('证据 · ${anchors.length}'),
      subtitle: const Text('展开查看摘录和原文位置'),
      children: [
        for (final anchor in anchors)
          _EvidenceLine(
            anchor: anchor,
            controller: controller,
            labelForSource: labelForSource,
          ),
      ],
    );
  }
}

class _EvidenceLine extends StatelessWidget {
  const _EvidenceLine({
    required this.anchor,
    required this.controller,
    required this.labelForSource,
  });

  final Json anchor;
  final AppController controller;
  final String Function(String source) labelForSource;

  @override
  Widget build(BuildContext context) {
    final sourceId = anchor['sourceId'] as String? ?? '';
    final label = sourceId.isEmpty ? '未知来源' : labelForSource(sourceId);
    final page = anchor['pdfPage'] ?? anchor['page'];
    final location = anchor['unresolved'] == true
        ? '无法定位，保留摘录'
        : page is int
        ? 'PDF 第 $page 页 · 图像转录，待核对'
        : '段落 ${anchor['blockId'] ?? '未知'}';
    final quote = anchor['quote'] as String? ?? '';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.format_quote),
      title: Text('$label · $location'),
      subtitle: quote.isEmpty ? null : Text(quote),
      trailing: sourceId.isEmpty ? null : const Icon(Icons.chevron_right),
      onTap: sourceId.isEmpty ? null : () => _openEvidence(context, sourceId),
    );
  }

  void _openEvidence(BuildContext context, String sourceId) {
    final source = controller.data.items
        .where((candidate) => candidate.id == sourceId)
        .firstOrNull;
    if (source == null) return;
    final page = anchor['pdfPage'] ?? anchor['page'];
    final blockId = anchor['blockId'] as String? ?? '';
    if (page is int) {
      controller.updateReadingPosition(sourceId, pdfPage: page);
    } else if (blockId.isNotEmpty) {
      controller.updateReadingPosition(sourceId, blockId: blockId);
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArticleDetailPage(
          controller: controller,
          item: source,
          initialBlockId: blockId.isEmpty ? null : blockId,
          initialPdfPage: page is int ? page : null,
        ),
      ),
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
