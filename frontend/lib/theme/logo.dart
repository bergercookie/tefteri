/// The Tefteri mark and wordmark.
library;

import 'package:flutter/material.dart';

import 'palette.dart';
import 'tokens.dart';

/// A notebook with a bookmark ribbon, drawn in code so it follows the theme.
class TefteriMark extends StatelessWidget {
  /// Creates the mark at [size].
  const TefteriMark({this.size = 28, super.key});

  /// Width and height.
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(
        cover: scheme.primary,
        page: scheme.onPrimary,
        ribbon: context.tefteri.now,
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.cover, required this.page, required this.ribbon});

  final Color cover;
  final Color page;
  final Color ribbon;

  @override
  void paint(Canvas canvas, Size s) {
    final u = s.width / 28;
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(4 * u, 1 * u, 20 * u, 26 * u), Radius.circular(3 * u));
    canvas.drawRRect(body, Paint()..color = cover);
    // ruled lines on the cover
    final line = Paint()
      ..color = page.withValues(alpha: 0.7)
      ..strokeWidth = 1.5 * u
      ..strokeCap = StrokeCap.round;
    for (final y in [9.0, 14.0, 19.0]) {
      canvas.drawLine(Offset(9 * u, y * u), Offset(19 * u, y * u), line);
    }
    // the spine
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(4 * u, 1 * u, 3 * u, 26 * u),
            Radius.circular(1.5 * u)),
        Paint()..color = Colors.black.withValues(alpha: 0.18));
    // the ribbon
    final path = Path()
      ..moveTo(17 * u, 1 * u)
      ..lineTo(21 * u, 1 * u)
      ..lineTo(21 * u, 9 * u)
      ..lineTo(19 * u, 7.2 * u)
      ..lineTo(17 * u, 9 * u)
      ..close();
    canvas.drawPath(path, Paint()..color = ribbon);
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.cover != cover || old.page != page || old.ribbon != ribbon;
}

/// The mark followed by the name in the display face.
class TefteriWordmark extends StatelessWidget {
  /// Creates the wordmark; [size] is the height of the mark.
  const TefteriWordmark({this.size = 28, this.showName = true, super.key});

  /// Height of the mark.
  final double size;

  /// False shows the mark alone.
  final bool showName;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TefteriMark(size: size),
          if (showName) ...[
            SizedBox(width: size * 0.32),
            Flexible(
                child: Text(
              'Tefteri',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: Fonts.display,
                fontSize: size * 1.0,
                height: 1,
                letterSpacing: -0.3,
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            )),
          ],
        ],
      );
}
