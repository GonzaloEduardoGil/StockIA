import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/dashboard.dart';
import '../models/product.dart';
import '../models/stock_movement.dart';

class SalesTrendChart extends StatefulWidget {
  const SalesTrendChart({
    required this.days,
    this.countLabel = 'venta',
    this.countPlural = 'ventas',
    super.key,
  });
  final List<DailySales> days;
  final String countLabel;
  final String countPlural;
  @override
  State<SalesTrendChart> createState() => _SalesTrendChartState();
}

class _SalesTrendChartState extends State<SalesTrendChart> {
  late int _selected;
  @override
  void initState() {
    super.initState();
    _selected = widget.days.length - 1;
  }

  @override
  void didUpdateWidget(SalesTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.days != widget.days) _selected = widget.days.length - 1;
  }

  void _point(double x, double width) {
    final first = widget.days.first.date;
    final span = widget.days.last.date.difference(first).inDays;
    final target = (x / width).clamp(0.0, 1.0) * span;
    var best = 0;
    var distance = double.infinity;
    for (var i = 0; i < widget.days.length; i++) {
      final next = (widget.days[i].date.difference(first).inDays - target)
          .abs();
      if (next < distance) {
        distance = next;
        best = i;
      }
    }
    if (_selected != best) setState(() => _selected = best);
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    if (days.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Text('No hay ventas en este período.'),
      );
    }
    final chosen = days[_selected];
    final maximum = days.fold<double>(
      0,
      (value, day) => math.max(value, day.total),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          money(maximum),
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) => MouseRegion(
            onHover: (event) =>
                _point(event.localPosition.dx, constraints.maxWidth),
            child: GestureDetector(
              onTapDown: (event) =>
                  _point(event.localPosition.dx, constraints.maxWidth),
              child: Semantics(
                label: 'Facturación diaria. Elegí una fecha debajo de la gráfica para consultar su importe.',
                child: CustomPaint(
                  key: const Key('sales-trend-plot'),
                  size: Size(constraints.maxWidth, 180),
                  painter: _TrendPainter(days, _selected),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              movementDate(days.first.date),
              style: const TextStyle(fontSize: 11, color: muted),
            ),
            if (days.length > 1)
              Text(
                movementDate(days.last.date),
                style: const TextStyle(fontSize: 11, color: muted),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 20,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 165,
              child: DropdownButtonFormField<int>(
                key: ValueKey('trend-day-$_selected'),
                initialValue: _selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Día'),
                items: [
                  for (var i = 0; i < days.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(movementDate(days[i].date)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _selected = value);
                },
              ),
            ),
            Text(
              '${chosen.count} ${chosen.count == 1 ? widget.countLabel : widget.countPlural} · ${money(chosen.total)}',
              key: const Key('trend-selected-value'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.days, this.selected);
  final List<DailySales> days;
  final int selected;
  @override
  void paint(Canvas canvas, Size size) {
    const inset = 5.0;
    final maxValue = days.fold<double>(
      1,
      (value, day) => math.max(value, day.total),
    );
    final span = days.last.date.difference(days.first.date).inDays;
    Offset point(int i) => Offset(
      span == 0
          ? size.width / 2
          : inset +
                days[i].date.difference(days.first.date).inDays /
                    span *
                    (size.width - inset * 2),
      size.height -
          inset -
          days[i].total / maxValue * (size.height - inset * 2),
    );
    final grid = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = inset + (size.height - inset * 2) * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < days.length; i++) {
      path.lineTo(point(i).dx, point(i).dy);
    }
    final area = Path.from(path)
      ..lineTo(point(days.length - 1).dx, size.height - inset)
      ..lineTo(point(0).dx, size.height - inset)
      ..close();
    canvas.drawPath(area, Paint()..color = navy.withValues(alpha: .10));
    canvas.drawPath(
      path,
      Paint()
        ..color = navy
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
    final active = point(selected);
    canvas.drawLine(
      Offset(active.dx, inset),
      Offset(active.dx, size.height - inset),
      Paint()
        ..color = navy.withValues(alpha: .25)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(active, 5, Paint()..color = navy);
    canvas.drawCircle(active, 2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.days != days || oldDelegate.selected != selected;
}
