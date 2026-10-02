import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'item_detail.dart';
import 'conversation_page.dart';
import 'knowledge_page.dart';
import 'library_page.dart';
import 'research_detail.dart';
import 'research_page.dart';
import 'rss_page.dart';
import 'settings_page.dart';
import 'today_page.dart';
import 'afterword_art.dart';

class ReadlaterShell extends StatefulWidget {
  const ReadlaterShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<ReadlaterShell> createState() => _ReadlaterShellState();
}

class _ReadlaterShellState extends State<ReadlaterShell> {
  int _index = 0;
  bool _navigationScheduled = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        _schedulePendingNavigation(context);
        final data = widget.controller.data;
        final pages = <Widget>[
          TodayPage(controller: widget.controller, data: data),
          LibraryPage(controller: widget.controller, data: data),
          RssPage(controller: widget.controller, data: data),
          ResearchPage(controller: widget.controller, data: data),
          SettingsPage(controller: widget.controller, data: data),
        ];
        return ScaffoldMessenger(
          child: Stack(
            children: [
              Scaffold(
                body: Column(
                  children: [
                    Expanded(
                      child: IndexedStack(
                        index: _index,
                        children: [
                          for (final page in pages.indexed)
                            TickerMode(
                              enabled: page.$1 == _index,
                              child: page.$2,
                            ),
                        ],
                      ),
                    ),
                    _ErrorBanner(
                      error: widget.controller.lastError,
                      onClear: widget.controller.dismissError,
                    ),
                    if (widget.controller.lastError == null)
                      _NoticeBanner(
                        notices: data.notices,
                        onClear: widget.controller.clearNotices,
                      ),
                  ],
                ),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (value) =>
                      setState(() => _index = value),
                  destinations: const [
                    NavigationDestination(
                      icon: AfterwordIcon(Icons.today_outlined),
                      selectedIcon: AfterwordIcon(Icons.today, selected: true),
                      label: '今日',
                    ),
                    NavigationDestination(
                      icon: AfterwordIcon(Icons.collections_bookmark_outlined),
                      selectedIcon: AfterwordIcon(
                        Icons.collections_bookmark,
                        selected: true,
                      ),
                      label: '资料',
                    ),
                    NavigationDestination(
                      icon: AfterwordIcon(Icons.rss_feed_outlined),
                      selectedIcon: AfterwordIcon(
                        Icons.rss_feed,
                        selected: true,
                      ),
                      label: 'RSS',
                    ),
                    NavigationDestination(
                      icon: AfterwordIcon(Icons.travel_explore_outlined),
                      selectedIcon: AfterwordIcon(
                        Icons.travel_explore,
                        selected: true,
                      ),
                      label: '研究',
                    ),
                    NavigationDestination(
                      icon: AfterwordIcon(Icons.tune_outlined),
                      selectedIcon: AfterwordIcon(Icons.tune, selected: true),
                      label: '设置',
                    ),
                  ],
                ),
              ),
              if (widget.controller.busy) const _BusyBar(),
            ],
          ),
        );
      },
    );
  }

  void _schedulePendingNavigation(BuildContext context) {
    if (_navigationScheduled || widget.controller.pendingNavigation == null) {
      return;
    }
    _navigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigationScheduled = false;
      if (!mounted) return;
      final navigation = widget.controller.pendingNavigation;
      if (navigation == null) return;
      widget.controller.consumeNavigation();
      _openNavigation(context, navigation);
    });
  }

  void _openNavigation(BuildContext context, Map<String, String> navigation) {
    final type = navigation['entityType'] ?? '';
    final id = navigation['entityId'] ?? '';
    if (type == 'conversation') {
      final turn = widget.controller.data.conversationTurns
          .where((t) => t.id == id)
          .firstOrNull;
      final conversation = widget.controller.data.conversations
          .where((c) => c.id == turn?.conversationId)
          .firstOrNull;
      setState(() => _index = 3);
      if (conversation != null) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ConversationPage(
              controller: widget.controller,
              initialConversationId: conversation.id,
              scope: conversation.scope,
              scopeId: conversation.scopeId,
              sourceIds: conversation.sourceIds ?? [],
            ),
          ),
        );
      }
      return;
    }
    if (type == 'knowledge') {
      setState(() => _index = 3);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              KnowledgePage(controller: widget.controller, topicId: id),
        ),
      );
      return;
    }
    if (type == 'today') {
      setState(() => _index = 0);
      return;
    }
    if (type == 'item') {
      final item = widget.controller.data.items
          .where((candidate) => candidate.id == id)
          .firstOrNull;
      if (item == null) {
        setState(() => _index = 1);
        return;
      }
      setState(() => _index = 1);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ArticleDetailPage(controller: widget.controller, item: item),
        ),
      );
      return;
    }
    if (type == 'topic') {
      setState(() => _index = 3);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              TopicDetailPage(controller: widget.controller, topicId: id),
        ),
      );
      return;
    }
    setState(() => _index = 3);
  }
}

class _BusyBar extends StatelessWidget {
  const _BusyBar();

  @override
  Widget build(BuildContext context) {
    return const Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: LinearProgressIndicator(minHeight: 3),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error, required this.onClear});

  final String? error;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (error == null || error!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.errorContainer,
        child: ListTile(
          leading: const AfterwordIcon(Icons.error_outline),
          title: Text(error!, maxLines: 3, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            tooltip: '关闭',
            icon: const AfterwordIcon(Icons.close),
            onPressed: onClear,
          ),
        ),
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.notices, required this.onClear});

  final List<String> notices;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (notices.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.primaryContainer,
        child: ListTile(
          leading: const AfterwordIcon(Icons.notifications_active_outlined),
          title: Text(
            notices.last,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: '已读',
            icon: const AfterwordIcon(Icons.done),
            onPressed: onClear,
          ),
        ),
      ),
    );
  }
}

List<LibraryItem> relatedItems(AppData data, List<String> ids) {
  return [for (final id in ids) ...data.items.where((item) => item.id == id)];
}
