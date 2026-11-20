import 'package:flutter/material.dart';

import 'depthvibe_settings.dart';

class DepthVibeBrandMark extends StatelessWidget {
  const DepthVibeBrandMark({
    super.key,
    this.size = 40,
    this.showWordmark = true,
  });

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF7D8BFF),
                Color(0xFF9D72F5),
                Color(0xFF59D9CE),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            boxShadow: [
              BoxShadow(
                color: palette.accent.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            'DV',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.34,
              fontWeight: FontWeight.w900,
              letterSpacing: -size * 0.04,
              height: 1,
            ),
          ),
        ),
        if (showWordmark) ...[
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'DEPTHVIBE',
                style: TextStyle(
                  color: palette.primaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.15,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'N TECH CREATIVE STUDIO',
                style: TextStyle(
                  color: palette.secondaryText,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
