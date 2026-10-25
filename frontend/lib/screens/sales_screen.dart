import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/product.dart';
import '../models/sale_history.dart';
import '../models/stock_movement.dart';
import '../widgets/compact_calendar.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({required this.api, super.key});
  final InventoryApi api;
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final _number = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _fromAnchor = GlobalKey();
  final _toAnchor = GlobalKey();
  List<SaleSummary> _sales = [];
  bool _loading = true;
  String? _error;
  int _generation = 0;
  int _detailGeneration = 0;
  int? _selectedId;
  HistoricalSale? _detail;
  String? _detailError;
  bool _detailLoading = false;
  bool _calendarOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _number.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sales = await widget.api.loadSales();
      if (!mounted || generation != _generation) return;
      setState(() {
        _sales = sales;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error is ApiFailure
            ? error.message
            : 'No se pudieron cargar las ventas.';
      });
    }
  }

  String? get _dateError {
    final from = parseMovementDate(_from.text);
    final to = parseMovementDate(_to.text);
    if ((_from.text.trim().isNotEmpty && from == null) ||
        (_to.text.trim().isNotEmpty && to == null)) {
      return 'Usá fechas válidas: dd/mm/aaaa.';
    }
    if (from != null && to != null && from.isAfter(to)) {
      return 'La fecha desde debe ser anterior o igual a la fecha hasta.';
    }
    return null;
  }

  List<SaleSummary> get _filtered {
    if (_dateError != null) return [];
    final from = parseMovementDate(_from.text);
    final to = parseMovementDate(_to.text);
    final number = _number.text.trim();
    return _sales.where((sale) {
      // Comparar días del calendario incluye todo el día de la fecha hasta.
      final day = DateTime(sale.date.year, sale.date.month, sale.date.day);
      return (number.isEmpty || sale.id == int.tryParse(number)) &&
          (from == null || !day.isBefore(from)) &&
          (to == null || !day.isAfter(to));
    }).toList();
  }

  Future<void> _open(int id) async {
    final generation = ++_detailGeneration;
    setState(() {
      _selectedId = id;
      _detail = null;
      _detailError = null;
      _detailLoading = true;
    });
    try {
      final detail = await widget.api.loadSale(id);
      if (!mounted || generation != _detailGeneration) return;
      setState(() {
        _detail = detail;
        _detailLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _detailGeneration) return;
      setState(() {
        _detailLoading = false;
        _detailError = error is ApiFailure
            ? error.message
            : 'No se pudo cargar el detalle de la venta.';
      });
    }
  }

  void _back() {
    ++_detailGeneration;
    setState(() {
      _selectedId = null;
      _detail = null;
      _detailError = null;
      _detailLoading = false;
    });
  }

  void _clear() => setState(() {
    _number.clear();
    _from.clear();
    _to.clear();
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 850;
      return SingleChildScrollView(
        key: ValueKey(_selectedId),
        padding: EdgeInsets.all(narrow ? 20 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ventas / Consultar ventas',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 20),
            if (_selectedId != null) ...[
              TextButton.icon(
                onPressed: _back,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver a ventas'),
              ),
              const SizedBox(height: 12),
              Text(
                'Venta #$_selectedId',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 24),
              if (_detailLoading)
                const Center(child: CircularProgressIndicator())
              else if (_detailError != null)
                _message(_detailError!, retry: () => _open(_selectedId!))
              else if (_detail != null)
                _detailView(_detail!),
            ] else ...[
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Consultar ventas',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Actualizar'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: narrow ? constraints.maxWidth - 40 : 190,
                    child: TextField(
                      key: const Key('sale-number'),
                      controller: _number,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'N.º de venta',
                        prefixIcon: Icon(Icons.search, size: 20),
                      ),
                    ),
                  ),
                  _dateField(true, narrow ? constraints.maxWidth - 40 : 200),
                  _dateField(false, narrow ? constraints.maxWidth - 40 : 200),
                  TextButton(
                    onPressed: _clear,
                    child: const Text('Limpiar filtros'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_dateError != null)
                _message(_dateError!)
              else if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                _message(_error!, retry: _load)
              else if (_sales.isEmpty)
                _message('Todavía no hay ventas registradas.')
              else if (_filtered.isEmpty)
                _message('No encontramos ventas con estos filtros.')
              else ...[
                Text(
                  'Ventas: ${_filtered.length}',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 12),
                if (narrow)
                  ..._filtered.map(_saleCard)
                else
                  SizedBox(
                    width: double.infinity,
                    child: DataTable(
                      columnSpacing: 18,
                      columns: const [
                        DataColumn(label: Text('Venta')),
                        DataColumn(label: Text('Fecha')),
                        DataColumn(label: Text('Vendedor')),
                        DataColumn(label: Text('Total'), numeric: true),
                        DataColumn(label: Text('')),
                      ],
                      rows: _filtered
                          .map(
                            (sale) => DataRow(
                              cells: [
                                DataCell(Text('#${sale.id}')),
                                DataCell(Text(movementDate(sale.date))),
                                DataCell(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 180,
                                    ),
                                    child: Text(
                                      sale.seller,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(Text(money(sale.total))),
                                DataCell(_detailButton(sale)),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ],
          ],
        ),
      );
    },
  );

  Widget _detailButton(SaleSummary sale) => OutlinedButton(
    key: ValueKey('sale-detail-${sale.id}'),
    onPressed: () => _open(sale.id),
    child: const Text('Ver detalle'),
  );

  Widget _saleCard(SaleSummary sale) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Venta #${sale.id}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(movementDate(sale.date)),
          Text(sale.seller),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                money(sale.total),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              _detailButton(sale),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _detailView(HistoricalSale sale) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 24,
        runSpacing: 8,
        children: [
          Text('Fecha: ${movementDate(sale.summary.date)}'),
          Text('Vendedor: ${sale.summary.seller}'),
        ],
      ),
      const SizedBox(height: 24),
      if (sale.lines.isEmpty)
        const Text('Esta venta no tiene productos disponibles en el detalle.'),
      ...sale.lines.map(
        (item) => Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.name} (#${item.productId})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  Text('${item.quantity} × ${money(item.unitPrice)}'),
                  Text('Subtotal: ${money(item.subtotal)}'),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFEBF1F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 8,
          children: [
            const Text('Total', style: TextStyle(fontSize: 18)),
            Text(
              money(sale.summary.total),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _message(String text, {VoidCallback? retry}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text),
        if (retry != null)
          TextButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
      ],
    ),
  );

  Widget _dateField(bool from, double width) => SizedBox(
    key: from ? _fromAnchor : _toAnchor,
    width: width,
    child: TextField(
      key: Key(from ? 'sale-date-from' : 'sale-date-to'),
      controller: from ? _from : _to,
      onTap: () => _pickDate(from),
      onChanged: (_) => setState(() {}),
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        labelText: from ? 'Desde' : 'Hasta',
        hintText: 'dd/mm/aaaa',
        suffixIcon: IconButton(
          tooltip: from ? 'Elegir fecha desde' : 'Elegir fecha hasta',
          onPressed: () => _pickDate(from),
          icon: const Icon(Icons.calendar_month_outlined),
        ),
      ),
    ),
  );

  // El calendario se ancla al campo, igual que en los filtros de movimientos.
  Future<void> _pickDate(bool from) async {
    if (_calendarOpen) return;
    _calendarOpen = true;
    FocusScope.of(context).unfocus();
    final controller = from ? _from : _to;
    var initial = parseMovementDate(controller.text) ?? DateTime.now();
    if (initial.isBefore(DateTime(1900))) initial = DateTime(1900);
    if (initial.isAfter(DateTime(2100, 12, 31))) {
      initial = DateTime(2100, 12, 31);
    }
    try {
      final anchor =
          (from ? _fromAnchor : _toAnchor).currentContext!.findRenderObject()
              as RenderBox;
      final rect = anchor.localToGlobal(Offset.zero) & anchor.size;
      final selected = await showDialog<DateTime>(
        context: context,
        barrierColor: Colors.transparent,
        useSafeArea: false,
        builder: (popupContext) => LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 16).clamp(1.0, 320.0);
            const height = 320.0;
            final left = rect.left.clamp(8.0, constraints.maxWidth - width - 8);
            final desiredTop =
                rect.bottom + 6 + height <= constraints.maxHeight - 8
                ? rect.bottom + 6
                : rect.top - height - 6;
            final top = desiredTop.clamp(
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
                    key: const Key('sale-date-popover'),
                    color: Colors.white,
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
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
      if (mounted && selected != null) {
        setState(() => controller.text = movementDate(selected));
      }
    } finally {
      _calendarOpen = false;
    }
  }
}
