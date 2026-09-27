import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide DiagnosticLevel;

import 'core/app_controller.dart';
import 'core/diagnostics.dart';
import 'platform/native_bridge.dart';
import 'ui/app_shell.dart';
import 'ui/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    var runtime = await const NativeBridge().runtimeContext();
    final controller = await AppController.open(
      digestOnly: runtime.mode == 'digestOnly',
    );
    _installGlobalDiagnostics(controller);
    controller.bindNativeRuntime();
    runtime = await controller.native.runtimeContext();
    if (runtime.mode == 'interactive') await controller.activateInteractive();
    for (final event in runtime.recentEvents) {
      controller.logRuntimeEvent(event, source: 'native.replay');
      if (event.kind == 'cancelAll' || event.kind == 'timeout') {
        await controller.pauseTasks(cancelled: event.kind == 'cancelAll');
      }
    }
    if (runtime.openedEntityType != null) {
      controller.pendingNavigation = {
        'entityType': runtime.openedEntityType!,
        'entityId': runtime.openedEntityId ?? '',
      };
    }
    runApp(ReadlaterApp(controller: controller));
    if (controller.digestOnly) {
      unawaited(controller.sendDailyDigest());
    }
  } catch (error) {
    runApp(ReadlaterStartupError(error: error));
  }
}

class ReadlaterApp extends StatefulWidget {
  const ReadlaterApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<ReadlaterApp> createState() => _ReadlaterAppState();
}

class _ReadlaterAppState extends State<ReadlaterApp>
    with WidgetsBindingObserver {
  Timer? _resumeTimer;
  bool _resuming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _resume());
    _resumeTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _resume();
      }
    });
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.diagnostics.flush();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.controller.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      _resume();
    }
  }

  Future<void> _resume() async {
    if (_resuming || !mounted) {
      return;
    }
    _resuming = true;
    try {
      if (!widget.controller.digestOnly) {
        widget.controller.setForeground(true);
        await widget.controller.resume();
      }
    } catch (_) {
      // The controller owns visible errors; background resume should stay quiet.
    } finally {
      _resuming = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => MaterialApp(
        title: '有下文 · Afterword',
        debugShowCheckedModeBanner: false,
        theme: readlaterTheme(widget.controller.data.settings.readingPreset),
        themeAnimationDuration: Duration.zero,
        home: ReadlaterShell(controller: widget.controller),
      ),
    );
  }
}

class ReadlaterStartupError extends StatefulWidget {
  const ReadlaterStartupError({super.key, required this.error});

  final Object error;

  @override
  State<ReadlaterStartupError> createState() => _ReadlaterStartupErrorState();
}

class _ReadlaterStartupErrorState extends State<ReadlaterStartupError> {
  bool _recovering = false;
  String? _recoveryError;

  Future<void> _restoreFromBackup() async {
    setState(() {
      _recovering = true;
      _recoveryError = null;
    });
    try {
      final picked = await FilePicker.pickFile();
      if (picked == null || !mounted) {
        return;
      }
      final bytes = await picked.readAsBytes();
      final controller = await AppController.open(
        recoveryBackup: Uint8List.fromList(bytes),
      );
      _installGlobalDiagnostics(controller);
      controller.bindNativeRuntime();
      if (!mounted) {
        return;
      }
      runApp(ReadlaterApp(controller: controller));
    } catch (error) {
      if (mounted) {
        setState(() => _recoveryError = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _recovering = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '有下文 · Afterword',
      debugShowCheckedModeBanner: false,
      theme: readlaterTheme(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 42),
                const SizedBox(height: 16),
                const Text('有下文启动失败'),
                const SizedBox(height: 8),
                Text(
                  '${widget.error}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_recoveryError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _recoveryError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  icon: _recovering
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restore),
                  label: const Text('从备份恢复'),
                  onPressed: _recovering ? null : _restoreFromBackup,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _installGlobalDiagnostics(AppController controller) {
  final previousFlutter = FlutterError.onError;
  FlutterError.onError = (details) {
    controller.diagnostics.log(
      DiagnosticLevel.error,
      'flutter',
      'framework.exception',
      error: details.exception,
      stackTrace: details.stack,
      data: {
        'library': details.library,
        'context': details.context?.toString(),
      },
    );
    previousFlutter?.call(details);
  };
  final previousPlatform = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    controller.diagnostics.log(
      DiagnosticLevel.error,
      'flutter',
      'async.exception',
      error: error,
      stackTrace: stackTrace,
    );
    return previousPlatform?.call(error, stackTrace) ?? false;
  };
}
