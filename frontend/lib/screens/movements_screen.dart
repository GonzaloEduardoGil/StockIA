import 'package:flutter/material.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/product.dart';
import '../models/stock_movement.dart';
import '../widgets/compact_calendar.dart';

class MovementsScreen extends StatefulWidget {
  const MovementsScreen({required this.api, this.embedded = false, super.key});
  final InventoryApi api;
  final bool embedded;
  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  List<StockMovement> _movements = [];
  bool _loading = true;
  String? _error;
  int? _product;
  String? _type;
  String? _reason;
  final _search = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  int _generation = 0;
  bool _calendarOpen = false;
  final _fromAnchor = GlobalKey();
  final _toAnchor = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
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
      final data = await widget.api.loadMovements();
      if (!mounted || generation != _generation) return;
      setState(() {
        _movements = data;
        if (_product != null && !data.any((m) => m.productId == _product)) {
          _product = null;
        }
        if (_reason != null && !_reasons.containsKey(_reason)) _reason = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error is ApiFailure
            ? error.message
            : 'No se pudieron cargar los movimientos.';
      });
    }
  }

  Map<String, String> get _reasons {
    final reasons = <String, String>{};
    for (final m in _movements) {
      final label = m.reason?.trim() ?? '';
      reasons.putIfAbsent(
        searchable(label),
        () => label.isEmpty
            ? 'Sin motivo'
            : switch (searchable(label)) {
                'perdida' => 'Pérdida',
                'rotura' => 'Rotura',
                'vencimiento' => 'Vencimiento',
                'diferencia de inventario' => 'Diferencia de inventario',
                _ => label,
              },
      );
    }
    return reasons;
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

  List<StockMovement> get _filtered {
    final from = parseMovementDate(_from.text);
    final to = parseMovementDate(_to.text);
    final query = searchable(_search.text.trim());
    return _movements
        .where(
          (m) =>
              (_product == null || m.productId == _product) &&
              (_type == null || m.type == _type) &&
              (_reason == null ||
                  searchable(m.reason?.trim() ?? '') == _reason) &&
              (from == null || !m.date.isBefore(from)) &&
              (to == null ||
                  m.date.isBefore(to.add(const Duration(days: 1)))) &&
              (query.isEmpty || searchable(m.reasonLabel).contains(query)),
        )
        .toList();
  }

  Future<void> _pickDate(bool from) async {
    if (_calendarOpen) return;
    _calendarOpen = true;
    FocusScope.of(context).unfocus();
    final controller = from ? _from : _to;
    final first = DateTime(1900);
    final last = DateTime(2100, 12, 31);
    var initial = parseMovementDate(controller.text) ?? DateTime.now();
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    try {
      final anchor =
          (from ? _fromAnchor : _toAnchor).currentContext!.findRenderObject()
              as RenderBox;
      final origin = anchor.localToGlobal(Offset.zero);
      final rect = origin & anchor.size;
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
                    key: const Key('movement-date-popover'),
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

  void _clear() => setState(() {
    _product = null;
    _type = null;
    _reason = null;
    _search.clear();
    _from.clear();
    _to.clear();
  });

  void _open(StockMovement movement) => showDialog<void>(
    context: context,
    builder: (_) => MovementDetails(api: widget.api, id: movement.id),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: !widget.embedded,
      title: const Text('Movimientos'),
      backgroundColor: Colors.white,
      actions: [
        IconButton(
          tooltip: 'Actualizar movimientos',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
        ),
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _filters(),
                  if (_dateError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _dateError!,
                        style: const TextStyle(color: Color(0xFFB23C3C)),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_error != null)
                    _message(_error!, retry: true)
                  else if (_dateError == null) ...[
                    Text(
                      '${_filtered.length} de ${_movements.length} movimientos',
                      style: const TextStyle(color: muted),
                    ),
                    const SizedBox(height: 16),
                    if (_filtered.isEmpty)
                      _message(
                        _movements.isEmpty
                            ? 'Todavía no hay movimientos.'
                            : 'No hay movimientos con estos filtros.',
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) =>
                            constraints.maxWidth < 850
                            ? Column(children: _filtered.map(_card).toList())
                            : _table(),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _filters() => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final fieldWidth = width < 550
          ? width
          : (width < 1050 ? (width - 12) / 2 : (width - 36) / 4);
      final products = <int, String>{
        for (final m in _movements) m.productId: m.productName,
      };
      final productIds = products.keys.toList()
        ..sort((a, b) => products[a]!.compareTo(products[b]!));
      final reasons = _reasons;
      final reasonKeys = reasons.keys.toList()
        ..sort((a, b) => reasons[a]!.compareTo(reasons[b]!));
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: fieldWidth,
            child: DropdownButtonFormField<int>(
              key: ValueKey(
                'movement-product-$_product-${productIds.join(',')}',
              ),
              initialValue: _product,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Producto'),
              items: [
                const DropdownMenuItem<int>(
                  value: null,
                  child: Text('Todos los productos'),
                ),
                ...productIds.map(
                  (id) => DropdownMenuItem(
                    value: id,
                    child: Text(
                      '${products[id]} (#$id)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _product = value),
            ),
          ),
          SizedBox(
            width: fieldWidth,
            child: DropdownButtonFormField<String>(
              key: ValueKey('movement-type-$_type'),
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Tipo de movimiento',
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Todos los tipos'),
                ),
                ...['Entrada', 'Ajuste', 'Venta'].map(
                  (type) => DropdownMenuItem(value: type, child: Text(type)),
                ),
              ],
              onChanged: (value) => setState(() => _type = value),
            ),
          ),
          SizedBox(
            width: fieldWidth,
            child: DropdownButtonFormField<String>(
              key: ValueKey('movement-reason-$_reason-${reasonKeys.join(',')}'),
              initialValue: _reason,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Motivo'),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Todos los motivos'),
                ),
                ...reasonKeys.map(
                  (key) => DropdownMenuItem(
                    value: key,
                    child: Text(reasons[key]!, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _reason = value),
            ),
          ),
          SizedBox(
            width: fieldWidth,
            child: TextField(
              key: const Key('movement-reason-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Buscar en motivos',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
          ),
          SizedBox(
            key: _fromAnchor,
            width: fieldWidth,
            child: TextField(
              key: const Key('movement-date-from'),
              controller: _from,
              onTap: () => _pickDate(true),
              keyboardType: TextInputType.datetime,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Desde',
                hintText: 'dd/mm/aaaa',
                suffixIcon: IconButton(
                  tooltip: 'Elegir fecha desde',
                  onPressed: () => _pickDate(true),
                  icon: const Icon(Icons.calendar_month_outlined),
                ),
              ),
            ),
          ),
          SizedBox(
            key: _toAnchor,
            width: fieldWidth,
            child: TextField(
              key: const Key('movement-date-to'),
              controller: _to,
              onTap: () => _pickDate(false),
              keyboardType: TextInputType.datetime,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Hasta',
                hintText: 'dd/mm/aaaa',
                suffixIcon: IconButton(
                  tooltip: 'Elegir fecha hasta',
                  onPressed: () => _pickDate(false),
                  icon: const Icon(Icons.calendar_month_outlined),
                ),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _clear,
            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
            label: const Text('Limpiar filtros'),
          ),
        ],
      );
    },
  );

  Widget _quantity(StockMovement m) => Text(
    m.quantityLabel,
    style: TextStyle(
      fontWeight: FontWeight.w700,
      color: m.signedQuantity < 0
          ? const Color(0xFFB23C3C)
          : const Color(0xFF24745C),
    ),
  );
  Widget _card(StockMovement m) => Card(
    key: ValueKey('movement-${m.id}'),
    color: Colors.white,
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: line),
      borderRadius: BorderRadius.circular(10),
    ),
    child: InkWell(
      onTap: () => _open(m),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  '${movementDate(m.date)} · ${m.type}',
                  style: const TextStyle(color: muted),
                ),
                _quantity(m),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              m.productName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              m.reasonLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: muted),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _table() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(width: 90, child: Text('Fecha')),
              SizedBox(width: 80, child: Text('Tipo')),
              Expanded(flex: 2, child: Text('Producto')),
              SizedBox(width: 130, child: Text('Cantidad')),
              Expanded(flex: 2, child: Text('Motivo')),
            ],
          ),
        ),
        for (final m in _filtered)
          InkWell(
            key: ValueKey('movement-${m.id}'),
            onTap: () => _open(m),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: line)),
              ),
              child: Row(
                children: [
                  SizedBox(width: 90, child: Text(movementDate(m.date))),
                  SizedBox(width: 80, child: Text(m.type)),
                  Expanded(flex: 2, child: Text(m.productName)),
                  SizedBox(width: 130, child: _quantity(m)),
                  Expanded(flex: 2, child: Text(m.reasonLabel)),
                ],
              ),
            ),
          ),
      ],
    ),
  );
  Widget _message(String text, {bool retry = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(text, textAlign: TextAlign.center),
          if (retry)
            TextButton(onPressed: _load, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}

class MovementDetails extends StatefulWidget {
  const MovementDetails({required this.api, required this.id, super.key});
  final InventoryApi api;
  final int id;
  @override
  State<MovementDetails> createState() => _MovementDetailsState();
}

class _MovementDetailsState extends State<MovementDetails> {
  late Future<StockMovement> _details;
  @override
  void initState() {
    super.initState();
    _details = widget.api.loadMovement(widget.id);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    constraints: const BoxConstraints(maxWidth: 500),
    title: Text('Movimiento #${widget.id}'),
    content: SingleChildScrollView(
      child: FutureBuilder<StockMovement>(
        future: _details,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  snapshot.error is ApiFailure
                      ? (snapshot.error as ApiFailure).message
                      : 'No se pudo cargar el detalle.',
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _details = widget.api.loadMovement(widget.id);
                  }),
                  child: const Text('Reintentar detalle'),
                ),
              ],
            );
          }
          final m = snapshot.data!;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.productName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text('Producto #${m.productId}'),
              const SizedBox(height: 12),
              Text('Fecha: ${movementDate(m.date)}'),
              const SizedBox(height: 12),
              Text('Tipo: ${m.type}'),
              const SizedBox(height: 12),
              Text('Cantidad: ${m.quantityLabel}'),
              const SizedBox(height: 12),
              Text('Motivo: ${m.reasonLabel}'),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
    ],
  );
}
