import 'package:flutter/material.dart';

/// A compact, non-interactive indicator which leaves the middle of the video clear.
class AdjustmentIndicator extends StatelessWidget {
  const AdjustmentIndicator({
    super.key,
    required this.kind,
    required this.value,
  });
  final String kind;
  final double value;

  @override
  Widget build(BuildContext context) {
    final speed = kind == 'speed';
    final fraction = speed
        ? ((value - .25) / 3.25).clamp(0.0, 1.0)
        : value.clamp(0.0, 1.0);
    final icon = speed
        ? Icons.speed_rounded
        : kind == 'volume'
        ? (value <= .01 ? Icons.volume_off_rounded : Icons.volume_up_rounded)
        : Icons.brightness_6_rounded;
    final label = speed
        ? '${value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')}×'
        : '${(value * 100).round()}%';
    const accent = Color(0xffff315a);
    final bar = Container(
      width: speed ? 92 : 6,
      height: speed ? 6 : 82,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(6),
      ),
      child: FractionallySizedBox(
        alignment: speed ? Alignment.centerLeft : Alignment.bottomCenter,
        widthFactor: speed ? fraction : 1,
        heightFactor: speed ? 1 : fraction,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
    final children = [
      Icon(icon, color: Colors.white, size: 24),
      SizedBox(width: speed ? 10 : 0, height: speed ? 0 : 12),
      bar,
      SizedBox(width: speed ? 10 : 0, height: speed ? 0 : 10),
      Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ];
    return Semantics(
      label:
          '${speed
              ? 'Tốc độ'
              : kind == 'volume'
              ? 'Âm lượng'
              : 'Độ sáng'} $label',
      child: Container(
        key: Key('adjustment-$kind'),
        padding: EdgeInsets.symmetric(
          horizontal: speed ? 14 : 12,
          vertical: speed ? 10 : 12,
        ),
        decoration: BoxDecoration(
          color: const Color(0xdd171717),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: speed
            ? Row(mainAxisSize: MainAxisSize.min, children: children)
            : Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
