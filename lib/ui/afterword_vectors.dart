import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

part 'afterword_vector_data.g.dart';

sealed class VectorNode {
  const VectorNode();
}

final class VectorGroup extends VectorNode {
  const VectorGroup(
    this.children, {
    this.part,
    this.dx = 0,
    this.dy = 0,
    this.scaleX = 1,
    this.scaleY = 1,
    this.opacity = 1,
  });

  final List<VectorNode> children;
  final String? part;
  final double dx;
  final double dy;
  final double scaleX;
  final double scaleY;
  final double opacity;
}

final class VectorPath extends VectorNode {
  const VectorPath(
    this.path, {
    this.fill = VectorInk.none,
    this.stroke = VectorInk.none,
    this.strokeWidth = 1.75,
    this.opacity = 1,
    this.dash = const <double>[],
  });

  final Path path;
  final VectorInk fill;
  final VectorInk stroke;
  final double strokeWidth;
  final double opacity;
  final List<double> dash;
}

enum VectorInk { none, primary, eye }

enum FoxMotion {
  none,
  idle,
  collect,
  analyze,
  saved,
  empty,
  retry,
  paused,
  complete,
}

const double afterwordIconViewBox = 24;
const double afterwordSceneViewBox = 160;

@visibleForTesting
List<VectorNode>? debugAfterwordVectorNodes(String id) {
  return afterwordVectorFactories[id]?.call();
}

final Map<String, List<VectorNode>> _vectorCache = <String, List<VectorNode>>{};

List<VectorNode>? cachedAfterwordVectorNodes(String id) {
  final factory = afterwordVectorFactories[id];
  if (factory == null) return null;
  return _vectorCache.putIfAbsent(id, factory);
}

@immutable
final class AfterwordMotionFrame {
  const AfterwordMotionFrame({
    this.motion = FoxMotion.none,
    this.progress = 1,
    this.reduceMotion = false,
  });

  final FoxMotion motion;
  final double progress;
  final bool reduceMotion;

  AfterwordMotionFrame copyWith({double? progress}) {
    return AfterwordMotionFrame(
      motion: motion,
      progress: progress ?? this.progress,
      reduceMotion: reduceMotion,
    );
  }
}

class AfterwordVectorPicture extends StatelessWidget {
  const AfterwordVectorPicture({
    super.key,
    required this.id,
    required this.viewBox,
    required this.size,
    required this.color,
    required this.eyeColor,
    this.backgroundColor,
    this.motion = const AfterwordMotionFrame(),
    this.textDirection = TextDirection.ltr,
    this.shadows,
    this.blendMode,
    this.excludeFromSemantics = true,
    this.progressAnimation,
  });

  final String id;
  final double viewBox;
  final double size;
  final Color color;
  final Color eyeColor;
  final Color? backgroundColor;
  final AfterwordMotionFrame motion;
  final TextDirection textDirection;
  final List<Shadow>? shadows;
  final BlendMode? blendMode;
  final bool excludeFromSemantics;
  final Animation<double>? progressAnimation;

  @override
  Widget build(BuildContext context) {
    final nodes = cachedAfterwordVectorNodes(id);
    assert(nodes != null, 'Unknown Afterword vector id: $id');
    final child = CustomPaint(
      size: Size.square(size),
      painter: _AfterwordVectorPainter(
        nodes: nodes ?? const <VectorNode>[],
        viewBox: viewBox,
        color: color,
        eyeColor: eyeColor,
        backgroundColor: backgroundColor,
        motion: motion,
        textDirection: textDirection,
        shadows: shadows,
        blendMode: blendMode,
        progressAnimation: progressAnimation,
      ),
    );
    if (!excludeFromSemantics) return child;
    return ExcludeSemantics(child: child);
  }
}

class _AfterwordVectorPainter extends CustomPainter {
  const _AfterwordVectorPainter({
    required this.nodes,
    required this.viewBox,
    required this.color,
    required this.eyeColor,
    required this.backgroundColor,
    required this.motion,
    required this.textDirection,
    required this.shadows,
    required this.blendMode,
    required this.progressAnimation,
  }) : super(repaint: progressAnimation);

  final List<VectorNode> nodes;
  final double viewBox;
  final Color color;
  final Color eyeColor;
  final Color? backgroundColor;
  final AfterwordMotionFrame motion;
  final TextDirection textDirection;
  final List<Shadow>? shadows;
  final BlendMode? blendMode;
  final Animation<double>? progressAnimation;

  @override
  void paint(Canvas canvas, Size size) {
    final paintMotion = progressAnimation == null
        ? motion
        : motion.copyWith(progress: progressAnimation!.value);
    if (backgroundColor != null) {
      final radius = Radius.circular(size.shortestSide * 0.2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, radius),
        Paint()..color = backgroundColor!,
      );
    }

    final scale = size.shortestSide / viewBox;
    canvas.save();
    canvas.translate((size.width - size.shortestSide) / 2, 0);
    canvas.scale(scale);
    final whole = _wholeTransform(paintMotion);
    whole.apply(canvas, viewBox, opacityOnly: false);
    _paintNodes(canvas, nodes, <String>[], whole.opacity, paintMotion);
    canvas.restore();
  }

  void _paintNodes(
    Canvas canvas,
    List<VectorNode> current,
    List<String> parts,
    double inheritedOpacity,
    AfterwordMotionFrame paintMotion,
  ) {
    for (final node in current) {
      switch (node) {
        case VectorGroup():
          final nextParts = node.part == null
              ? parts
              : <String>[...parts, node.part!];
          final partTransform = node.part == null
              ? const _VectorTransform()
              : _partTransform(node.part!, paintMotion);
          canvas.save();
          canvas.translate(node.dx, node.dy);
          canvas.scale(node.scaleX, node.scaleY);
          partTransform.apply(canvas, viewBox, opacityOnly: false);
          _paintNodes(
            canvas,
            node.children,
            nextParts,
            inheritedOpacity * node.opacity * partTransform.opacity,
            paintMotion,
          );
          canvas.restore();
        case VectorPath():
          _paintPath(canvas, node, parts, inheritedOpacity, paintMotion);
      }
    }
  }

  void _paintPath(
    Canvas canvas,
    VectorPath node,
    List<String> parts,
    double inheritedOpacity,
    AfterwordMotionFrame paintMotion,
  ) {
    final pathOpacity = (inheritedOpacity * node.opacity).clamp(0.0, 1.0);
    if (pathOpacity <= 0) return;

    if (node.fill != VectorInk.none) {
      _drawPathWithShadows(
        canvas,
        node.path,
        _paintFor(node.fill, PaintingStyle.fill, pathOpacity),
        pathOpacity,
      );
    }
    if (node.stroke != VectorInk.none) {
      final paint = _paintFor(node.stroke, PaintingStyle.stroke, pathOpacity)
        ..strokeWidth = node.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = _dashedPath(node.path, node.dash, parts, paintMotion);
      _drawPathWithShadows(canvas, path, paint, pathOpacity);
    }
  }

  void _drawPathWithShadows(
    Canvas canvas,
    Path path,
    Paint paint,
    double opacity,
  ) {
    for (final shadow in shadows ?? const <Shadow>[]) {
      final shadowPaint = Paint()
        ..color = shadow.color.withValues(alpha: shadow.color.a * opacity)
        ..style = paint.style
        ..strokeWidth = paint.strokeWidth
        ..strokeCap = paint.strokeCap
        ..strokeJoin = paint.strokeJoin
        ..maskFilter = shadow.blurSigma == 0
            ? null
            : MaskFilter.blur(BlurStyle.normal, shadow.blurSigma)
        ..blendMode = paint.blendMode;
      canvas.drawPath(path.shift(shadow.offset), shadowPaint);
    }
    canvas.drawPath(path, paint);
  }

  Paint _paintFor(VectorInk ink, PaintingStyle style, double opacity) {
    final base = switch (ink) {
      VectorInk.primary => color,
      VectorInk.eye => eyeColor,
      VectorInk.none => Colors.transparent,
    };
    return Paint()
      ..color = base.withValues(alpha: base.a * opacity)
      ..style = style
      ..blendMode = blendMode ?? BlendMode.srcOver;
  }

  @override
  bool shouldRepaint(covariant _AfterwordVectorPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.viewBox != viewBox ||
        oldDelegate.color != color ||
        oldDelegate.eyeColor != eyeColor ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.motion != motion ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.shadows != shadows ||
        oldDelegate.blendMode != blendMode ||
        oldDelegate.progressAnimation != progressAnimation;
  }
}

@immutable
final class _VectorTransform {
  const _VectorTransform({
    this.dy = 0,
    this.rotation = 0,
    this.scale = 1,
    this.opacity = 1,
    this.pivot = Offset.zero,
  });

  final double dy;
  final double rotation;
  final double scale;
  final double opacity;
  final Offset pivot;

  void apply(Canvas canvas, double viewBox, {required bool opacityOnly}) {
    if (opacityOnly) return;
    if (dy != 0) canvas.translate(0, dy);
    if (rotation != 0 || scale != 1) {
      final resolvedPivot = pivot == Offset.zero
          ? Offset(viewBox / 2, viewBox / 2)
          : pivot;
      canvas.translate(resolvedPivot.dx, resolvedPivot.dy);
      if (rotation != 0) canvas.rotate(rotation);
      if (scale != 1) canvas.scale(scale);
      canvas.translate(-resolvedPivot.dx, -resolvedPivot.dy);
    }
  }
}

_VectorTransform _wholeTransform(AfterwordMotionFrame frame) {
  if (frame.reduceMotion || frame.motion != FoxMotion.empty) {
    return const _VectorTransform();
  }
  final t = _ease(frame.progress);
  return _VectorTransform(dy: _lerp(10, 0, t), opacity: _lerp(0, 1, t));
}

_VectorTransform _partTransform(String part, AfterwordMotionFrame frame) {
  if (frame.reduceMotion) return const _VectorTransform();
  final tail = part.contains('fox-tail');
  final body = part.contains('fox-body');
  final accent = part.contains('scene-accent');
  final eye = part.contains('fox-eye');
  final motionPath = part.contains('motion-path');
  final t = _ease(frame.progress);
  switch (frame.motion) {
    case FoxMotion.none:
      return const _VectorTransform();
    case FoxMotion.idle:
      if (tail) {
        return _VectorTransform(
          rotation: _degrees(_triangle(t) * 3),
          pivot: const Offset(108, 118),
        );
      }
      if (body) return _VectorTransform(dy: -2 * _triangle(t));
    case FoxMotion.collect:
      if (tail) {
        return _VectorTransform(
          rotation: _degrees(_keyframes(t, -2, 3, 0)),
          pivot: const Offset(108, 118),
        );
      }
      if (accent) {
        return _VectorTransform(dy: _lerp(-8, 0, t), opacity: _lerp(.72, 1, t));
      }
    case FoxMotion.analyze:
      if (tail) {
        return _VectorTransform(
          rotation: _degrees(_triangle(t) * 2),
          pivot: const Offset(108, 118),
        );
      }
      if (accent || eye) {
        return _VectorTransform(opacity: _lerp(.54, 1, _triangle(t)));
      }
      if (motionPath) return const _VectorTransform();
    case FoxMotion.saved:
      if (accent) {
        return _VectorTransform(
          scale: _keyframes(t, .92, 1.05, 1),
          opacity: t == 0 ? 0 : 1,
        );
      }
      if (body) return _VectorTransform(dy: _keyframes(t, 2, -3, 0));
    case FoxMotion.empty:
      return const _VectorTransform();
    case FoxMotion.retry:
      if (accent) {
        return _VectorTransform(
          rotation: _degrees(_multiKeyframes(t, const <double>[-3, 3, -1, 0])),
        );
      }
    case FoxMotion.paused:
      if (tail) {
        return _VectorTransform(
          rotation: _degrees(_lerp(5, 0, t)),
          pivot: const Offset(108, 118),
        );
      }
    case FoxMotion.complete:
      if (accent) {
        return _VectorTransform(
          scale: _keyframes(t, .94, 1.08, 1),
          opacity: _lerp(.56, 1, t),
        );
      }
  }
  return const _VectorTransform();
}

Path _dashedPath(
  Path source,
  List<double> dash,
  List<String> parts,
  AfterwordMotionFrame frame,
) {
  if (dash.isEmpty) return source;
  final pattern = dash.where((value) => value > 0).toList(growable: false);
  if (pattern.isEmpty) return source;
  var offset = 0.0;
  if (!frame.reduceMotion &&
      frame.motion == FoxMotion.analyze &&
      parts.join('/').contains('motion-path')) {
    offset = _lerp(18, -18, _ease(frame.progress));
  }
  return _dashPath(source, pattern, offset);
}

Path _dashPath(Path source, List<double> pattern, double offset) {
  final result = Path();
  final totalPattern = pattern.fold<double>(0, (sum, value) => sum + value);
  if (totalPattern <= 0) return source;
  for (final PathMetric metric in source.computeMetrics()) {
    var distance = -offset % totalPattern;
    var patternIndex = 0;
    var draw = true;
    while (distance < metric.length) {
      final segment = pattern[patternIndex % pattern.length];
      final start = distance.clamp(0.0, metric.length);
      final end = (distance + segment).clamp(0.0, metric.length);
      if (draw && end > 0 && start < metric.length && end > start) {
        result.addPath(metric.extractPath(start, end), Offset.zero);
      }
      distance += segment;
      patternIndex += 1;
      draw = !draw;
    }
  }
  return result;
}

double _ease(double value) {
  final t = value.clamp(0.0, 1.0);
  return Curves.easeInOut.transform(t);
}

double _triangle(double value) {
  final t = value.clamp(0.0, 1.0);
  return t < .5 ? t * 2 : (1 - t) * 2;
}

double _keyframes(double t, double a, double b, double c) {
  return t < .5 ? _lerp(a, b, t * 2) : _lerp(b, c, (t - .5) * 2);
}

double _multiKeyframes(double t, List<double> values) {
  if (values.length < 2) return values.isEmpty ? 0 : values.single;
  final scaled = t.clamp(0.0, 1.0) * (values.length - 1);
  final index = scaled.floor().clamp(0, values.length - 2);
  return _lerp(values[index], values[index + 1], scaled - index);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _degrees(double value) => value * math.pi / 180;
