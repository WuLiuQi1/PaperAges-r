import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Geometry taken from the supplied 1170px-wide Books screenshots, normalized
/// to the viewport. Native system typography is deliberately not bundled.
class BooksNavigation extends StatelessWidget {
  const BooksNavigation({
    super.key,
    required this.index,
    required this.onChanged,
  });
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Colors.white : Colors.black;
    final width = math.min(330.0, MediaQuery.sizeOf(context).width * .72);
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 8),
      child: Center(
        heightFactor: 1,
        child: Container(
          width: width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .07),
                blurRadius: 18,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(40),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: (dark ? const Color(0xFF242424) : Colors.white)
                      .withValues(alpha: .83),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(
                    color: dark ? Colors.white24 : const Color(0xFFDDDDDF),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Expanded(
                          child: Semantics(
                            selected: index == i,
                            button: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onChanged(i),
                              child: AnimatedContainer(
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 220),
                                height: 54,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(32),
                                  color: index == i
                                      ? (dark
                                            ? Colors.black45
                                            : const Color(0xFFE9E9EA))
                                      : Colors.transparent,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (i == 1)
                                      SizedBox.square(
                                        dimension: 26,
                                        child: CustomPaint(
                                          painter: _BooksGlyph(ink),
                                        ),
                                      )
                                    else
                                      Icon(
                                        i == 0
                                            ? CupertinoIcons.house_fill
                                            : CupertinoIcons.search,
                                        size: 26,
                                        color: ink,
                                      ),
                                    Text(
                                      ['主页', '书库', '搜索'][i],
                                      style: TextStyle(
                                        fontSize: 11,
                                        height: 1.25,
                                        fontWeight: FontWeight.w600,
                                        color: ink,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BooksGlyph extends CustomPainter {
  const _BooksGlyph(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 26, size.height / 26);
    final paint = Paint()..color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, 5, 5, 20),
        const Radius.circular(1.5),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(8, 1, 6, 24),
        const Radius.circular(1.5),
      ),
      paint,
    );
    canvas.save();
    canvas.translate(16, 4);
    canvas.rotate(-.13);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 6, 21),
        const Radius.circular(1.5),
      ),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BooksGlyph oldDelegate) => oldDelegate.color != color;
}
