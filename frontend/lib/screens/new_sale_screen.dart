import 'package:flutter/material.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/new_product.dart';
import '../models/product.dart';
import '../models/sale.dart';

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({
    required this.api,
    required this.onBusyChanged,
    required this.onSaved,
    required this.onInventory,
    required this.onMovements,
    this.currentUserId,
    super.key,
  });
  final InventoryApi api;
  // El ID se recibe de la sesión autenticada.
  // No pedirlo en el formulario ni reemplazarlo por un vendedor fijo.
  final int? currentUserId;
  final ValueChanged<bool> onBusyChanged;
  final Future<void> Function() onSaved;
  final VoidCallback onInventory;
  final VoidCallback onMovements;
  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final _form = GlobalKey<FormState>();
  final _search = TextEditingController();
  final _cart = <int, Product>{};
  final _quantities = <int, TextEditingController>{};
  List<Product> _products = [];
  List<SaleLine>? _review;
  SaleReceipt? _receipt;
  bool _loading = true;
  bool _busy = false;
  bool _uncertain = false;
  bool _needsRefresh = false;
  String? _error;
  String? _cartError;
  bool get _hasSession =>
      widget.currentUserId != null && widget.currentUserId! > 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await widget.api.loadInventory();
      if (!mounted) return;
      setState(() {
        _products = products;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is ApiFailure
            ? error.message
            : 'No se pudieron cargar los productos.';
      });
    }
  }

  Product? _current(int id) {
    for (final product in _products) {
      if (product.id == id) return product;
    }
    return null;
  }

  bool _hasPrice(Product p) =>
      p.price != null && p.price!.isFinite && p.price! > 0;
  int? _subtotal(int id) {
    final p = _current(id);
    final q = parseStock(_quantities[id]!.text);
    if (p == null || !_hasPrice(p) || q == null || q <= 0) return null;
    return SaleLine(product: p, quantity: q).subtotalCents;
  }

  int get _total => _cart.keys.fold(0, (sum, id) => sum + (_subtotal(id) ?? 0));
  void _add(Product p) {
    if (_busy || p.quantity <= 0 || !_hasPrice(p)) return;
    setState(() {
      if (_cart.containsKey(p.id)) {
        final quantity = parseStock(_quantities[p.id]!.text) ?? 0;
        if (quantity < p.quantity) _quantities[p.id]!.text = '${quantity + 1}';
      } else {
        _cart[p.id] = p;
        _quantities[p.id] = TextEditingController(text: '1');
      }
      _cartError = null;
      _search.clear();
    });
  }

  void _remove(int id) {
    final controller = _quantities.remove(id);
    setState(() => _cart.remove(id));
    // Let the field leave the tree before disposing its controller.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller?.dispose());
  }

  String? _validateQuantity(int id, String? text) {
    final p = _current(id);
    if (p == null) return 'Producto no disponible.';
    if (!_hasPrice(p)) return 'Precio no disponible.';
    final quantity = parseStock(text ?? '');
    if (quantity == null || quantity <= 0 || quantity > 2147483647) {
      return 'Ingresá una cantidad entera mayor a 0.';
    }
    if (quantity > p.quantity) return 'Stock disponible: ${p.quantity}.';
    if (SaleLine(product: p, quantity: quantity).subtotalCents >
        9007199254740991) {
      return 'El importe supera el límite permitido.';
    }
    return null;
  }

  void _setBusy(bool busy) {
    setState(() => _busy = busy);
    widget.onBusyChanged(busy);
  }

  Future<void> _prepare() async {
    if (_busy) return;
    if (_cart.isEmpty) {
      setState(() => _cartError = 'Agregá al menos un producto.');
      return;
    }
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    _setBusy(true);
    try {
      final products = await widget.api.loadInventory();
      if (!mounted) return;
      setState(() {
        _products = products;
        _error = null;
      });
      if (!_form.currentState!.validate()) return;
      setState(() {
        _review = _cart.keys
            .map(
              (id) => SaleLine(
                product: _current(id)!,
                quantity: parseStock(_quantities[id]!.text)!,
              ),
            )
            .toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error =
            'No se pudieron actualizar los productos. Intentá nuevamente.',
      );
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  Future<void> _confirm() async {
    if (_busy ||
        !_hasSession ||
        _uncertain ||
        _needsRefresh ||
        _review == null) {
      return;
    }
    _setBusy(true);
    setState(() => _error = null);
    try {
      final receipt = await widget.api.registerSale(
        widget.currentUserId!,
        _review!,
      );
      if (!mounted) return;
      setState(() => _receipt = receipt);
      await widget.onSaved();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiFailure
            ? error.message
            : 'No se pudo confirmar el resultado de la venta.';
        _uncertain = error is! ApiFailure || error.mayHaveSaved;
        _needsRefresh = error is ApiFailure && error.requiresRefresh;
      });
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  Future<void> _refreshDraft() async {
    _setBusy(true);
    await _load();
    if (!mounted) return;
    setState(() {
      if (_error == null) {
        _review = null;
        _needsRefresh = false;
      }
    });
    _setBusy(false);
  }

  Future<void> _newSale() async {
    final old = _quantities.values.toList();
    setState(() {
      _cart.clear();
      _quantities.clear();
      _review = null;
      _receipt = null;
      _error = null;
      _cartError = null;
      _uncertain = false;
      _needsRefresh = false;
      _search.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in old) {
        controller.dispose();
      }
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: ListView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 32),
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1050),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ventas / Registrar venta',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 18),
                Text(
                  _receipt != null
                      ? 'Venta #${_receipt!.id} registrada'
                      : (_review == null ? 'Registrar venta' : 'Revisar venta'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 20),
                if (_receipt != null)
                  _success()
                else ...[
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFFB23C3C)),
                        ),
                      ),
                    ),
                  if (_review == null) ...[
                    if (_loading)
                      const LinearProgressIndicator()
                    else if (_products.isEmpty && _error != null)
                      TextButton(
                        onPressed: _load,
                        child: const Text('Reintentar productos'),
                      ),
                    const SizedBox(height: 12),
                    Semantics(
                      container: true,
                      explicitChildNodes: true,
                      child: TextField(
                        key: const Key('sale-product-search'),
                        controller: _search,
                        enabled: !_busy && !_loading,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Buscar producto por nombre o código',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    if (_search.text.trim().isNotEmpty) ..._results(),
                    const SizedBox(height: 22),
                    if (_cart.isEmpty)
                      const Text(
                        'Todavía no agregaste productos.',
                        style: TextStyle(color: muted),
                      )
                    else
                      Form(
                        key: _form,
                        child: Column(
                          children: _cart.keys.map(_cartRow).toList(),
                        ),
                      ),
                    if (_cartError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _cartError!,
                          style: const TextStyle(color: Color(0xFFB23C3C)),
                        ),
                      ),
                  ] else ...[
                    for (final line in _review!)
                      _summaryLine(
                        line.product.name,
                        '${line.quantity} × ${money(line.unitCents / 100)}',
                        money(line.subtotalCents / 100),
                      ),
                  ],
                  const SizedBox(height: 20),
                  _totalPanel(
                    _review == null
                        ? _total / 100
                        : _review!.fold<int>(
                                0,
                                (sum, line) => sum + line.subtotalCents,
                              ) /
                              100,
                  ),
                  const SizedBox(height: 20),
                  if (_review != null && !_hasSession && !_uncertain)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Necesitás iniciar sesión para confirmar.',
                        style: TextStyle(color: muted),
                      ),
                    ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      TextButton(
                        onPressed: _busy ? null : widget.onInventory,
                        child: const Text('Volver al inventario'),
                      ),
                      if (_uncertain)
                        FilledButton(
                          onPressed: _busy ? null : widget.onMovements,
                          child: const Text('Ver movimientos'),
                        )
                      else if (_needsRefresh)
                        FilledButton(
                          onPressed: _busy ? null : _refreshDraft,
                          child: const Text('Actualizar productos'),
                        )
                      else if (_review != null) ...[
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _review = null;
                                  _error = null;
                                }),
                          child: const Text('Corregir'),
                        ),
                        FilledButton(
                          onPressed: _busy || !_hasSession ? null : _confirm,
                          child: Text(_busy ? 'Guardando…' : 'Confirmar venta'),
                        ),
                      ] else
                        FilledButton(
                          onPressed: _busy || _loading ? null : _prepare,
                          child: Text(_busy ? 'Revisando…' : 'Revisar venta'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _results() {
    final query = searchable(_search.text.trim());
    final matches = _products
        .where((p) => searchable('${p.id} ${p.name}').contains(query))
        .take(8)
        .toList();
    if (matches.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No se encontraron productos.'),
        ),
      ];
    }
    return [
      const SizedBox(height: 8),
      ...matches.map(
        (p) => Semantics(
          container: true,
          child: Material(
            color: Colors.white,
            child: ListTile(
              title: Text(p.name),
              subtitle: Text(
                'Código ${p.id} · Stock ${p.quantity} · ${money(p.price)}',
              ),
              trailing: TextButton(
                key: ValueKey('sale-add-${p.id}'),
                onPressed: _busy || p.quantity <= 0 || !_hasPrice(p)
                    ? null
                    : () => _add(p),
                child: Text(
                  p.quantity <= 0
                      ? 'Sin stock'
                      : (!_hasPrice(p) ? 'Sin precio' : 'Agregar'),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _cartRow(int id) {
    final p = _current(id) ?? _cart[id]!;
    final subtotal = _subtotal(id);
    final quantity = TextFormField(
      key: ValueKey('sale-quantity-$id'),
      controller: _quantities[id],
      enabled: !_busy,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      keyboardType: TextInputType.number,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(labelText: 'Cantidad'),
      validator: (text) => _validateQuantity(id, text),
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(
          'Código ${p.id} · Stock ${p.quantity} · ${money(p.price)} c/u',
          style: const TextStyle(color: muted),
        ),
      ],
    );
    final amount = Text(
      'Subtotal: ${subtotal == null ? '—' : money(subtotal / 100)}',
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
    final remove = IconButton(
      tooltip: 'Quitar ${p.name}',
      onPressed: _busy ? null : () => _remove(id),
      icon: const Icon(Icons.close, size: 20),
    );
    return Container(
      key: ValueKey('sale-line-$id'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 620
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 16),
                  SizedBox(width: 140, child: quantity),
                  const SizedBox(width: 16),
                  SizedBox(width: 150, child: amount),
                  remove,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: info),
                      remove,
                    ],
                  ),
                  const SizedBox(height: 16),
                  quantity,
                  const SizedBox(height: 12),
                  amount,
                ],
              ),
      ),
    );
  }

  Widget _totalPanel(double total) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFFEBF1F9),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 24,
      runSpacing: 8,
      children: [
        const Text('Total', style: TextStyle(fontSize: 18)),
        Text(
          money(total),
          style: const TextStyle(
            color: ink,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
  Widget _summaryLine(String name, String detail, String amount) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 24,
          runSpacing: 6,
          children: [
            Text(detail, style: const TextStyle(color: muted)),
            Text(amount, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    ),
  );
  Widget _success() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final line in _receipt!.lines)
        _summaryLine(
          line.name,
          '${line.quantity} unidades',
          money(line.subtotal),
        ),
      const SizedBox(height: 12),
      Text(
        'Total: ${money(_receipt!.total)}',
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
      const SizedBox(height: 24),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton(
            onPressed: _busy ? null : _newSale,
            child: const Text('Registrar otra venta'),
          ),
          TextButton(
            onPressed: _busy ? null : widget.onInventory,
            child: const Text('Volver al inventario'),
          ),
        ],
      ),
    ],
  );
}
