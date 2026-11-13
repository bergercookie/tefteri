/// Twelve monthly stored values drawn as a strip with open gaps.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'annual_review_models.dart';

/// Draws the series of one key result. A gap is an open marker, never a
/// guessed point; the strip also carries a label for screen readers.
class SeriesStrip extends StatelessWidget {
  /// Creates the strip.
  const SeriesStrip({required this.points, super.key, this.height = 48});

  /// The twelve points.
  final List<SeriesPoint> points;

  /// Height of the drawing.
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.tefteri;
    final label = [
      for (final p in points)
        p.value == null
            ? '${_monthLabel(p.month)}: no value'
            : '${_monthLabel(p.month)}: ${_number(p.value!)}',
    ].join(', ');
    return Semantics(
      container: true,
      label: 'Monthly values. $label',
      child: ExcludeSemantics(
        child: SizedBox(
          key: const Key('series-strip'),
          height: height,
          child: CustomPaint(
            painter: _SeriesPainter(
              points: points,
              line: scheme.primary,
              graph: colors.rule,
              gap: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

String _monthLabel(String month) =>
    month.length >= 7 ? month.substring(5) : month;

String _number(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

class _SeriesPainter extends CustomPainter {
  const _SeriesPainter(
      {required this.points,
      required this.line,
      required this.graph,
      required this.gap});

  final List<SeriesPoint> points;
  final Color line;
  final Color graph;
  final Color gap;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final known =
        [for (final p in points) p.value].whereType<double>().toList();
    if (known.isEmpty) {
      final base = Paint()
        ..color = graph
        ..strokeWidth = 1;
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), base);
      return;
    }
    final min = known.reduce((a, b) => a < b ? a : b);
    final max = known.reduce((a, b) => a > b ? a : b);
    final span = max - min == 0 ? 1 : max - min;
    final step = size.width / (points.length - 1);
    final path = Path();
    var started = false;
    for (var i = 0; i < points.length; i++) {
      final value = points[i].value;
      final x = i * step;
      final y = value == null
          ? null
          : size.height - 6 - (value - min) / span * (size.height - 12);
      if (y == null) {
        started = false;
        canvas.drawCircle(
            Offset(x, size.height / 2),
            3,
            Paint()
              ..color = gap
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2);
        continue;
      }
      if (started) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
        started = true;
      }
      canvas.drawCircle(Offset(x, y), 2.6, Paint()..color = line);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_SeriesPainter old) =>
      old.line != line ||
      old.graph != graph ||
      old.gap != gap ||
      old.points != points;
}
