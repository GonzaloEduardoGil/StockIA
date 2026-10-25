import 'package:flutter/material.dart';

import '../app.dart';
import '../models/stock_movement.dart';
import 'compact_calendar.dart';

class DateFilterField extends StatefulWidget {
  const DateFilterField({
    required this.label,
    required this.controller,
    required this.onChanged,
    super.key,
  });
  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  @override
  State<DateFilterField> createState() => _DateFilterFieldState();
}

class _DateFilterFieldState extends State<DateFilterField> {
  final _anchor = GlobalKey();
  bool _open = false;
  Future<void> _pick() async {
    if (_open) return;
    _open = true;
    FocusScope.of(context).unfocus();
    var initial = parseMovementDate(widget.controller.text) ?? DateTime.now();
    if (initial.year < 1900) initial = DateTime(1900);
    if (initial.year > 2100) initial = DateTime(2100, 12, 31);
    try {
      final box = _anchor.currentContext!.findRenderObject() as RenderBox;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final selected = await showDialog<DateTime>(
        context: context,
        barrierColor: Colors.transparent,
        useSafeArea: false,
        builder: (popupContext) => LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 16).clamp(1.0, 320.0);
            const height = 320.0;
            final left = rect.left.clamp(8.0, constraints.maxWidth - width - 8);
            final desired =
                rect.bottom + 6 + height <= constraints.maxHeight - 8
                ? rect.bottom + 6
                : rect.top - height - 6;
            final top = desired.clamp(
              8.0,
              (constraints.maxHeight - height - 8).clamp(8.0, double.infinity),
            );
            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: width,
                  child: Material(
                    key: const Key('dashboard-date-popover'),
                    color: Colors.white,
                    elevation: 8,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: CompactCalendar(
                      initialDate: initial,
                      onSelected: (date) => Navigator.pop(popupContext, date),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
      if (!mounted || selected == null) return;
      widget.controller.text = movementDate(selected);
      widget.onChanged();
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: TextField(
      key: _anchor,
      controller: widget.controller,
      keyboardType: TextInputType.datetime,
      onTap: _pick,
      onChanged: (_) => widget.onChanged(),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: 'dd/mm/aaaa',
        suffixIcon: IconButton(
          tooltip: 'Elegir fecha ${widget.label.toLowerCase()}',
          onPressed: _pick,
          icon: const Icon(Icons.calendar_month_outlined),
        ),
      ),
    ),
  );
}
