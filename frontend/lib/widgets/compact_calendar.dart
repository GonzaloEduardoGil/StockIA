import 'package:flutter/material.dart';

import '../app.dart';

class CompactCalendar extends StatefulWidget {
  const CompactCalendar({
    required this.initialDate,
    required this.onSelected,
    super.key,
  });
  final DateTime initialDate;
  final ValueChanged<DateTime> onSelected;
  @override
  State<CompactCalendar> createState() => _CompactCalendarState();
}

class _CompactCalendarState extends State<CompactCalendar> {
  static const months = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];
  late DateTime _month;
  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initialDate.year, widget.initialDate.month);
  }

  void _move(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));
  @override
  Widget build(BuildContext context) {
    final start = _month.subtract(Duration(days: _month.weekday - 1));
    return SizedBox(
      width: 320,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Mes anterior',
                  visualDensity: VisualDensity.compact,
                  onPressed: _month.year == 1900 && _month.month == 1
                      ? null
                      : () => _move(-1),
                  icon: const Icon(Icons.chevron_left, size: 20),
                ),
                Expanded(
                  flex: 3,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      key: const Key('calendar-month'),
                      value: _month.month,
                      isExpanded: true,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      iconSize: 16,
                      items: List.generate(
                        12,
                        (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text(
                            months[i],
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      onChanged: (month) {
                        if (month != null) {
                          setState(() => _month = DateTime(_month.year, month));
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: 2,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      key: const Key('calendar-year'),
                      value: _month.year,
                      isExpanded: true,
                      menuMaxHeight: 240,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      iconSize: 16,
                      items: List.generate(
                        201,
                        (i) => DropdownMenuItem(
                          value: i + 1900,
                          child: Text('${i + 1900}'),
                        ),
                      ),
                      onChanged: (year) {
                        if (year != null) {
                          setState(() => _month = DateTime(year, _month.month));
                        }
                      },
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Mes siguiente',
                  visualDensity: VisualDensity.compact,
                  onPressed: _month.year == 2100 && _month.month == 12
                      ? null
                      : () => _move(1),
                  icon: const Icon(Icons.chevron_right, size: 20),
                ),
              ],
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              children: ['L', 'M', 'X', 'J', 'V', 'S', 'D']
                  .map(
                    (day) => Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: const TextStyle(
                            color: muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 4),
            for (var week = 0; week < 6; week++)
              Row(
                children: List.generate(7, (day) {
                  final date = start.add(Duration(days: week * 7 + day));
                  final currentMonth =
                      date.month == _month.month && date.year == _month.year;
                  final selected = DateUtils.isSameDay(
                    date,
                    widget.initialDate,
                  );
                  return Expanded(
                    child: SizedBox(
                      height: 36,
                      child: currentMonth
                          ? Semantics(
                              button: true,
                              selected: selected,
                              label:
                                  '${date.day} de ${months[date.month - 1]} de ${date.year}',
                              child: InkWell(
                                key: ValueKey(
                                  'calendar-day-${date.year}-${date.month}-${date.day}',
                                ),
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => widget.onSelected(date),
                                child: Center(
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: selected ? navy : null,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '${date.day}',
                                      style: TextStyle(
                                        color: selected ? Colors.white : ink,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                '${date.day}',
                                style: const TextStyle(
                                  color: Color(0xFFCCD2DA),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                    ),
                  );
                }),
              ),
          ],
        ),
      ),
    );
  }
}
