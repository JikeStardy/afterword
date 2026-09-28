import 'package:flutter/material.dart';

import 'afterword_vectors.dart';
export 'afterword_vectors.dart' show FoxMotion;

class AfterwordIcon extends Icon {
  const AfterwordIcon(
    super.icon, {
    super.key,
    super.size,
    super.fill,
    super.weight,
    super.grade,
    super.opticalSize,
    super.color,
    super.shadows,
    super.semanticLabel,
    super.textDirection,
    super.applyTextScaling,
    super.blendMode,
    super.fontWeight,
    this.selected = false,
    this.asset,
  });

  final bool selected;
  final String? asset;

  @override
  Widget build(BuildContext context) {
    assert(textDirection != null || debugCheckHasDirectionality(context));
    final direction = textDirection ?? Directionality.of(context);
    final vectorId = _iconVectorId();
    if (vectorId == null) {
      assert(() {
        debugPrint('AfterwordIcon: no custom vector mapping for $icon.');
        return true;
      }());
      return super.build(context);
    }

    final iconTheme = IconTheme.of(context);
    final shouldScale = applyTextScaling ?? iconTheme.applyTextScaling ?? false;
    final baseSize = size ?? iconTheme.size ?? kDefaultFontSize;
    final resolvedSize = shouldScale
        ? (MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling).scale(
            baseSize,
          )
        : baseSize;
    final opacity = iconTheme.opacity ?? 1.0;
    var resolvedColor =
        color ?? iconTheme.color ?? Theme.of(context).colorScheme.onSurface;
    if (opacity != 1) {
      resolvedColor = resolvedColor.withValues(
        alpha: resolvedColor.a * opacity,
      );
    }

    Widget picture = AfterwordVectorPicture(
      id: vectorId,
      viewBox: afterwordIconViewBox,
      size: resolvedSize,
      color: resolvedColor,
      eyeColor: Theme.of(context).colorScheme.surface,
      textDirection: direction,
      shadows: shadows ?? iconTheme.shadows,
      blendMode: blendMode,
    );

    if (_shouldMirror(direction)) {
      picture = Transform(
        transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1),
        alignment: Alignment.center,
        transformHitTests: false,
        child: picture,
      );
    }

    return Semantics(
      label: semanticLabel,
      child: SizedBox.square(dimension: resolvedSize, child: picture),
    );
  }

  String? _iconVectorId() {
    final explicit = asset?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      final selectedId = 'icon:$explicit-selected';
      if (selected && afterwordVectorFactories.containsKey(selectedId)) {
        return selectedId;
      }
      return 'icon:$explicit';
    }
    final id = icon == null ? null : afterwordMaterialIds[icon];
    if (id == null) return null;
    final selectedId = 'icon:$id-selected';
    if (selected && afterwordVectorFactories.containsKey(selectedId)) {
      return selectedId;
    }
    return 'icon:$id';
  }

  bool _shouldMirror(TextDirection direction) {
    if (direction != TextDirection.rtl) return false;
    final explicit = asset?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit == 'back' ||
          explicit == 'chevron-left' ||
          explicit == 'chevron-right';
    }
    return icon?.matchTextDirection ?? false;
  }
}

class AfterwordScene extends StatefulWidget {
  const AfterwordScene({
    super.key,
    required this.scene,
    this.motion = FoxMotion.none,
    this.size = 112,
    this.repeat = false,
    this.color,
    this.backgroundColor,
    this.semanticLabel,
  });

  final String scene;
  final FoxMotion motion;
  final double size;
  final bool repeat;
  final Color? color;
  final Color? backgroundColor;
  final String? semanticLabel;

  @override
  State<AfterwordScene> createState() => _AfterwordSceneState();
}

class _AfterwordSceneState extends State<AfterwordScene>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  bool _appVisible = true;
  bool _tickerEnabled = true;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appVisible =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _controller = AnimationController(
      vsync: this,
      duration: _durationFor(widget.motion),
      value: _startingValueFor(widget.motion),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _reduceMotion = _reduceMotionOf(context);
    _syncController(restartChangedMotion: false);
  }

  @override
  void didUpdateWidget(covariant AfterwordScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged =
        oldWidget.scene != widget.scene ||
        oldWidget.motion != widget.motion ||
        oldWidget.repeat != widget.repeat;
    if (oldWidget.motion != widget.motion) {
      _controller.duration = _durationFor(widget.motion);
    }
    if (identityChanged) {
      _controller.value = _startingValueFor(widget.motion);
    }
    _syncController(restartChangedMotion: identityChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible = switch (state) {
      AppLifecycleState.resumed => true,
      AppLifecycleState.inactive ||
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => false,
    };
    _syncController(restartChangedMotion: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentTicker = TickerMode.valuesOf(context).enabled;
    final currentReduceMotion = _reduceMotionOf(context);
    if (currentTicker != _tickerEnabled ||
        currentReduceMotion != _reduceMotion) {
      _tickerEnabled = currentTicker;
      _reduceMotion = currentReduceMotion;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncController(restartChangedMotion: false);
      });
    }

    final colors = Theme.of(context).colorScheme;
    final id = widget.scene == 'fox' ? 'brand:fox' : 'scene:${widget.scene}';
    final picture = AfterwordVectorPicture(
      id: id,
      viewBox: afterwordSceneViewBox,
      size: widget.size,
      color: widget.color ?? colors.primary,
      eyeColor: widget.backgroundColor ?? colors.surface,
      backgroundColor: widget.backgroundColor,
      motion: AfterwordMotionFrame(
        motion: widget.motion,
        progress: _reduceMotion
            ? _staticValueFor(widget.motion)
            : _controller.value,
        reduceMotion: _reduceMotion,
      ),
      progressAnimation: _reduceMotion ? null : _controller,
    );

    final sized = SizedBox.square(dimension: widget.size, child: picture);
    if (widget.semanticLabel == null) return ExcludeSemantics(child: sized);
    return Semantics(
      label: widget.semanticLabel,
      child: ExcludeSemantics(child: sized),
    );
  }

  void _syncController({required bool restartChangedMotion}) {
    if (!mounted) return;
    if (!_shouldAnimate) {
      _controller.stop(canceled: false);
      if (_reduceMotion) {
        _controller.value = _staticValueFor(widget.motion);
      }
      return;
    }
    if (_shouldLoop) {
      _controller.repeat();
      return;
    }
    if (_controller.isCompleted) return;
    if (restartChangedMotion || !_controller.isAnimating) {
      _controller.forward();
    }
  }

  bool get _shouldAnimate {
    return widget.motion != FoxMotion.none &&
        !_reduceMotion &&
        _tickerEnabled &&
        _appVisible;
  }

  bool get _shouldLoop {
    return widget.repeat &&
        (widget.motion == FoxMotion.collect ||
            widget.motion == FoxMotion.analyze);
  }
}

bool _reduceMotionOf(BuildContext context) {
  final media = MediaQuery.maybeOf(context);
  final platform =
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
  return (media?.disableAnimations ?? false) ||
      (media?.accessibleNavigation ?? false) ||
      platform.reduceMotion ||
      platform.disableAnimations;
}

Duration _durationFor(FoxMotion motion) {
  return switch (motion) {
    FoxMotion.none => Duration.zero,
    FoxMotion.idle => const Duration(milliseconds: 1800),
    FoxMotion.collect => const Duration(milliseconds: 1400),
    FoxMotion.analyze => const Duration(milliseconds: 2400),
    FoxMotion.saved => const Duration(milliseconds: 700),
    FoxMotion.empty => const Duration(milliseconds: 650),
    FoxMotion.retry => const Duration(milliseconds: 520),
    FoxMotion.paused => const Duration(milliseconds: 500),
    FoxMotion.complete => const Duration(milliseconds: 1000),
  };
}

double _startingValueFor(FoxMotion motion) {
  return motion == FoxMotion.none ? 1 : 0;
}

double _staticValueFor(FoxMotion motion) {
  return motion == FoxMotion.none ? 1 : 1;
}
