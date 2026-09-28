import 'dart:io';

import 'package:flutter/material.dart';

import '../core/models.dart';
import 'afterword_art.dart';

typedef AsyncAction = Future<void> Function();

class AppFrame extends StatelessWidget {
  const AppFrame({
    super.key,
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
    this.floatingActionButton,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return Scaffold(
      appBar: AppBar(
        leading: canPop
            ? IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const AfterwordIcon(Icons.chevron_left),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: actions,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: child,
          ),
        ),
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.scene,
    required this.title,
    required this.message,
    this.icon,
    this.action,
  });

  final String scene;
  final IconData? icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AfterwordScene(
                scene: scene,
                motion: FoxMotion.empty,
                size: 112,
                color: colors.primary,
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: ReadingLayout.of(context).pagePadding,
        vertical: 8,
      ),
      child: Padding(
        padding:
            padding ?? EdgeInsets.all(ReadingLayout.of(context).rowPadding),
        child: child,
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.positive = false});

  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = positive ? colors.primary : colors.tertiary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(label, style: TextStyle(color: color, fontSize: 12)),
      ),
    );
  }
}

class SourceList extends StatelessWidget {
  const SourceList({
    super.key,
    required this.sources,
    this.labelForSource,
    this.onSourceTap,
  });

  final List<String> sources;
  final String Function(String source)? labelForSource;
  final void Function(String source)? onSourceTap;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return const Text('暂无来源引用');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in sources.indexed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 13,
              child: Text(
                '${entry.$1 + 1}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            title: Text(sourceDisplayLabel(entry.$2, entry.$1, labelForSource)),
            subtitle: Text(
              sourceDisplaySubtitle(entry.$2, entry.$1, labelForSource),
            ),
            trailing: onSourceTap == null
                ? null
                : const AfterwordIcon(Icons.chevron_right),
            onTap: onSourceTap == null ? null : () => onSourceTap!(entry.$2),
          ),
      ],
    );
  }
}

String readerCitationText(
  String text,
  List<String> sources, {
  String Function(String source)? labelForSource,
}) {
  if (text.isEmpty) return text;
  final numbers = <String, int>{};
  for (final entry in sources.indexed) {
    if (!_isMissingSource(entry.$2, labelForSource)) {
      numbers[entry.$2] = entry.$1 + 1;
    }
  }
  final declaredSources = sources.toSet();
  return text.replaceAllMapped(RegExp(r'\[([A-Za-z0-9_-]+)\]'), (match) {
    final source = match.group(1)!;
    final number = numbers[source];
    if (number != null) return '[$number]';
    if (declaredSources.contains(source)) {
      return '[未知来源]';
    }
    return match.group(0)!;
  });
}

String sourceDisplayLabel(
  String source,
  int index,
  String Function(String source)? labelForSource,
) {
  final label = labelForSource?.call(source).trim();
  if (label == null || label.isEmpty || label == source) {
    return '来源 ${index + 1}';
  }
  if (_isDeletedSourceLabel(label)) return '来源已删除';
  return label;
}

String sourceDisplaySubtitle(
  String source,
  int index,
  String Function(String source)? labelForSource,
) {
  if (_isMissingSource(source, labelForSource)) return '未能解析原始来源';
  return '引用 [${index + 1}]';
}

bool _isMissingSource(
  String source,
  String Function(String source)? labelForSource,
) {
  final label = labelForSource?.call(source).trim();
  return label == null ||
      label.isEmpty ||
      label == source ||
      _isDeletedSourceLabel(label);
}

bool _isDeletedSourceLabel(String label) => label.startsWith('来源已删除');

class AssetStrip extends StatelessWidget {
  const AssetStrip({
    super.key,
    required this.assets,
    required this.assetPath,
    this.onOpen,
  });

  final List<Asset> assets;
  final String Function(Asset asset) assetPath;
  final Future<void> Function(Asset asset)? onOpen;

  @override
  Widget build(BuildContext context) {
    if (assets.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          final asset = assets[index];
          final path = assetPath(asset);
          final isImage = asset.mime.startsWith('image/');
          return InkWell(
            onTap: onOpen == null ? null : () => onOpen!(asset),
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 108,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                  ),
                  child: isImage
                      ? Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          errorBuilder: (context, _, _) =>
                              const AfterwordIcon(Icons.image_not_supported),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const AfterwordIcon(Icons.insert_drive_file),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                asset.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemCount: assets.length,
      ),
    );
  }
}

Future<void> runUiAction(
  BuildContext context,
  AsyncAction action, {
  String? success,
}) async {
  try {
    await action();
    if (!context.mounted) {
      return;
    }
    if (success != null) {
      final snackTheme = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AfterwordScene(
                  scene: 'saved',
                  motion: FoxMotion.saved,
                  size: 40,
                  color: snackTheme.onInverseSurface,
                  backgroundColor: snackTheme.inverseSurface,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(success)),
              ],
            ),
          ),
        );
    }
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$error')));
  }
}

/// Shared typography and spacing; presets never alter reading order or actions.
@immutable
class ReadingLayout extends ThemeExtension<ReadingLayout> {
  const ReadingLayout(this.preset);
  final ReadingPreset preset;
  static ReadingLayout of(BuildContext context) =>
      Theme.of(context).extension<ReadingLayout>() ??
      const ReadingLayout(ReadingPreset.editorial);
  double get pagePadding => switch (preset) {
    ReadingPreset.editorial => 20,
    ReadingPreset.compact => 16,
    ReadingPreset.magazine => 24,
  };
  double get sectionGap => switch (preset) {
    ReadingPreset.editorial => 28,
    ReadingPreset.compact => 20,
    ReadingPreset.magazine => 36,
  };
  double get rowPadding => switch (preset) {
    ReadingPreset.editorial => 16,
    ReadingPreset.compact => 10,
    ReadingPreset.magazine => 20,
  };
  double get titleSize => switch (preset) {
    ReadingPreset.editorial => 26,
    ReadingPreset.compact => 24,
    ReadingPreset.magazine => 30,
  };
  double get sectionTitleSize => switch (preset) {
    ReadingPreset.editorial => 20,
    ReadingPreset.compact => 18,
    ReadingPreset.magazine => 24,
  };
  double get bodyHeight => preset == ReadingPreset.compact ? 1.6 : 1.7;
  @override
  ReadingLayout copyWith({ReadingPreset? preset}) =>
      ReadingLayout(preset ?? this.preset);
  @override
  ReadingLayout lerp(covariant ReadingLayout? other, double t) =>
      other == null || t < .5 ? this : other;
}

class ReadingHeading extends StatelessWidget {
  const ReadingHeading(this.text, {super.key, this.fontScale = 1});
  final String text;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    final magazine = layout.preset == ReadingPreset.magazine;
    return Semantics(
      header: true,
      child: Container(
        width: double.infinity,
        padding: magazine ? const EdgeInsets.all(12) : EdgeInsets.zero,
        decoration: magazine
            ? BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                ),
              )
            : null,
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontSize: layout.sectionTitleSize * fontScale),
        ),
      ),
    );
  }
}

String readingPresetLabel(ReadingPreset preset) => switch (preset) {
  ReadingPreset.editorial => '阅读刊物',
  ReadingPreset.compact => '紧凑研究工具',
  ReadingPreset.magazine => '数字杂志',
};

ThemeData readlaterTheme([ReadingPreset preset = ReadingPreset.editorial]) {
  final layout = ReadingLayout(preset);
  const green = Color(0xff476b4f);
  const warm = Color(0xfffaf8f3);
  const ink = Color(0xff202823);
  final scheme = ColorScheme.fromSeed(seedColor: green).copyWith(
    primary: green,
    surface: warm,
    onSurface: ink,
    onSurfaceVariant: const Color(0xff646c63),
    outlineVariant: const Color(0xffe2e5dc),
    primaryContainer: const Color(0xffedf2e8),
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: warm,
    extensions: [layout],
    textTheme: base.textTheme.copyWith(
      headlineSmall: TextStyle(
        fontSize: layout.titleSize,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: layout.titleSize,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleMedium: const TextStyle(
        fontSize: 17,
        height: 1.45,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleSmall: TextStyle(
        fontSize: layout.sectionTitleSize,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 17, height: layout.bodyHeight, color: ink),
      bodyMedium: const TextStyle(fontSize: 14, height: 1.6, color: ink),
      bodySmall: const TextStyle(
        fontSize: 12,
        height: 1.5,
        color: Color(0xff646c63),
      ),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      titleSpacing: layout.pagePadding,
      titleTextStyle: TextStyle(
        fontSize: layout.titleSize,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      backgroundColor: warm,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xffe2e5dc),
      thickness: 1,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: preset == ReadingPreset.magazine
          ? const Color(0xffedf2e8)
          : Colors.white,
      shape: shape.copyWith(side: const BorderSide(color: Color(0xffe2e5dc))),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    chipTheme: ChipThemeData(
      shape: shape,
      side: const BorderSide(color: Color(0xff858e82)),
      labelStyle: const TextStyle(fontSize: 13, color: ink),
      selectedColor: scheme.primaryContainer,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: green,
      unselectedLabelColor: scheme.onSurfaceVariant,
      unselectedLabelStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      dividerColor: scheme.outlineVariant,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: warm,
      indicatorColor: Color(0xffedf2e8),
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: const WidgetStatePropertyAll(Colors.white),
      shape: WidgetStatePropertyAll(shape),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      helperMaxLines: 4,
      errorMaxLines: 4,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xff858e82)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: green, width: 2),
      ),
    ),
  );
}

String kindLabel(ItemKind kind) {
  return switch (kind) {
    ItemKind.web => '网页',
    ItemKind.text => '文字',
    ItemKind.image => '图片',
    ItemKind.pdf => 'PDF',
  };
}

String shortDate(DateTime? value) {
  if (value == null) {
    return '尚未执行';
  }
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

bool researchRunIsComplete(ResearchRun run) => run.status == 'complete';

String researchRunStatusLabel(String value) => switch (value) {
  'complete' => '已完成',
  'running' => '运行中',
  'paused' => '已暂停',
  'budget' => '预算用尽',
  'failed' => '有异常',
  'interrupted' => '已中断',
  'queued' => '排队中',
  'pending' => '待确认',
  'completed' || 'done' => '旧版完成状态',
  _ => value.isEmpty ? '运行中' : value,
};

String researchRunScene(String value) => switch (value) {
  'complete' => 'complete',
  'running' => 'analyzing',
  'paused' => 'paused',
  'budget' => 'unanalyzed',
  'failed' || 'interrupted' => 'startup-error',
  'queued' || 'pending' => 'research-empty',
  _ => 'research-empty',
};

FoxMotion researchRunMotion(String value) => switch (value) {
  'complete' => FoxMotion.complete,
  'running' => FoxMotion.analyze,
  'paused' => FoxMotion.paused,
  'budget' => FoxMotion.paused,
  'failed' || 'interrupted' => FoxMotion.retry,
  'queued' || 'pending' => FoxMotion.idle,
  _ => FoxMotion.none,
};
