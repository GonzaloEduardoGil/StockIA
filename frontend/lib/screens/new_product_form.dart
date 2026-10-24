import 'package:flutter/material.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/new_product.dart';
import '../models/product.dart';

class ProductCreationResult {
  const ProductCreationResult({
    this.id,
    this.uncertain = false,
    this.deactivated = false,
  });
  final int? id;
  final bool uncertain;
  final bool deactivated;
}

Future<ProductCreationResult?> openNewProduct(
  BuildContext context,
  InventoryApi api,
) => _openProductForm(context, api);

Future<ProductCreationResult?> openEditProduct(
  BuildContext context,
  InventoryApi api,
  Product product,
) => _openProductForm(context, api, product: product);

Future<ProductCreationResult?> _openProductForm(
  BuildContext context,
  InventoryApi api, {
  Product? product,
}) {
  if (MediaQuery.sizeOf(context).width < 700) {
    return Navigator.of(context).push<ProductCreationResult>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          body: NewProductForm(api: api, product: product),
        ),
      ),
    );
  }
  return showDialog<ProductCreationResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 700,
        height: (MediaQuery.sizeOf(context).height - 64).clamp(300, 800),
        child: NewProductForm(api: api, product: product),
      ),
    ),
  );
}

class NewProductForm extends StatefulWidget {
  const NewProductForm({required this.api, this.product, super.key});
  final InventoryApi api;
  final Product? product;
  @override
  State<NewProductForm> createState() => _NewProductFormState();
}

class _NewProductFormState extends State<NewProductForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _category = TextEditingController();
  final _price = TextEditingController();
  final _minimum = TextEditingController(text: '0');
  final _initial = TextEditingController(text: '0');
  NewProduct? _review;
  bool _saving = false;
  bool _uncertain = false;
  String? _error;
  bool get _editing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    if (product != null) {
      _name.text = product.name;
      _description.text = product.description ?? '';
      _category.text =
          product.rawCategory ??
          (product.category == 'Sin categoría' ? '' : product.category);
      _price.text = product.price?.toString().replaceAll('.', ',') ?? '';
      _minimum.text = '${product.minimum}';
      _initial.text = '${product.quantity}';
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _description,
      _category,
      _price,
      _minimum,
      _initial,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _prepare() {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _review = NewProduct(
        name: _name.text.trim(),
        price: parsePrice(_price.text)!,
        minimum: parseStock(_minimum.text)!,
        initial: parseStock(_initial.text)!,
        description: _description.text.trim(),
        category: _category.text.trim(),
      );
    });
  }

  Future<void> _save() async {
    if (_saving || _uncertain || _review == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = _editing
          ? await widget.api.updateProduct(widget.product!, _review!)
          : await widget.api.createProduct(_review!);
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.pop(context, ProductCreationResult(id: id));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is ApiFailure
            ? error.message
            : 'No pudimos completar el registro.';
        _uncertain =
            error is ApiFailure &&
            (error.mayHaveSaved || error.requiresRefresh);
      });
    }
  }

  void _close() {
    if (_saving) return;
    Navigator.pop(
      context,
      _uncertain ? const ProductCreationResult(uncertain: true) : null,
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving && !_uncertain,
    child: Material(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _review == null
                              ? (_editing
                                    ? 'Editar producto'
                                    : 'Nuevo producto')
                              : (_editing
                                    ? 'Revisar cambios'
                                    : 'Revisar producto'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _review == null
                              ? 'Completá los datos y revisalos antes de guardar.'
                              : (_editing
                                    ? 'Comprobá las modificaciones antes de guardarlas.'
                                    : 'Comprobá los datos antes de confirmar el registro.'),
                          style: const TextStyle(color: muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar formulario',
                    onPressed: _saving ? null : _close,
                    icon: const Icon(Icons.close, color: muted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1DC),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFF83550D),
                              height: 1.6,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],
                    if (_review == null) _fields() else _summary(_review!),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.end,
                  children: [
                    if (!_uncertain)
                      TextButton(
                        onPressed: _saving ? null : _close,
                        child: const Text('Cancelar'),
                      ),
                    if (_review != null && !_uncertain)
                      OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                _review = null;
                                _error = null;
                              }),
                        child: const Text('Editar datos'),
                      ),
                    if (_uncertain)
                      FilledButton(
                        onPressed: _close,
                        child: const Text('Volver al inventario'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _saving
                            ? null
                            : (_review == null ? _prepare : _save),
                        icon: _saving
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _review == null
                                    ? Icons.arrow_forward
                                    : Icons.check,
                                size: 18,
                              ),
                        label: Text(
                          _saving
                              ? 'Guardando…'
                              : _review == null
                              ? 'Revisar datos'
                              : (_editing
                                    ? 'Confirmar cambios'
                                    : 'Confirmar registro'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _fields() => Form(
    key: _form,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DATOS DEL PRODUCTO',
          style: TextStyle(
            color: muted,
            fontWeight: FontWeight.w600,
            fontSize: 11,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          key: const Key('product-name'),
          controller: _name,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Nombre *',
            hintText: 'Ej.: Mouse inalámbrico',
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Ingresá el nombre del producto.'
              : null,
        ),
        const SizedBox(height: 20),
        TextFormField(
          key: const Key('product-description'),
          controller: _description,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Descripción',
            hintText: 'Información adicional (opcional)',
          ),
        ),
        const SizedBox(height: 20),
        _pair(
          TextFormField(
            key: const Key('product-category'),
            controller: _category,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Categoría',
              hintText: 'Ej.: Periféricos (opcional)',
            ),
          ),
          TextFormField(
            key: const Key('product-price'),
            controller: _price,
            textInputAction: TextInputAction.next,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: r'Precio de venta ($) *',
              hintText: '18500,00',
            ),
            validator: (value) => parsePrice(value ?? '') == null
                ? 'Ingresá un precio mayor que cero.'
                : null,
          ),
        ),
        if (!_editing) ...[
          const SizedBox(height: 28),
          const Text(
            'EXISTENCIAS',
            style: TextStyle(
              color: muted,
              fontWeight: FontWeight.w600,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 20),
          _pair(
            TextFormField(
              key: const Key('product-minimum'),
              controller: _minimum,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Stock mínimo *',
                helperText: 'Cantidad para detectar stock bajo.',
              ),
              validator: (value) => parseStock(value ?? '') == null
                  ? 'Usá un entero igual o mayor a cero.'
                  : null,
            ),
            TextFormField(
              key: const Key('product-initial'),
              controller: _initial,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Stock inicial *',
                helperText: 'Unidades disponibles al registrar.',
              ),
              validator: (value) => parseStock(value ?? '') == null
                  ? 'Usá un entero igual o mayor a cero.'
                  : null,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          _editing
              ? 'Código ${widget.product!.id}. Se conservan el stock, el mínimo y el historial del producto.'
              : '* Campos obligatorios. El código se asigna al guardar.',
          style: const TextStyle(color: muted, fontSize: 12, height: 1.6),
        ),
      ],
    ),
  );

  Widget _pair(Widget first, Widget second) => LayoutBuilder(
    builder: (_, constraints) => constraints.maxWidth < 500
        ? Column(children: [first, const SizedBox(height: 20), second])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 20),
              Expanded(child: second),
            ],
          ),
  );

  Widget _summary(NewProduct product) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFFEBF1F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.inventory_2_outlined, color: navy),
      ),
      const SizedBox(height: 18),
      Text(product.name, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 22),
      _summaryRow(
        'Categoría',
        product.category?.isNotEmpty == true
            ? product.category!
            : 'Sin categoría',
      ),
      _summaryRow('Precio de venta', money(product.price)),
      if (_editing)
        _summaryRow('Código (sin cambios)', '${widget.product!.id}'),
      _summaryRow(
        _editing ? 'Stock mínimo (sin cambios)' : 'Stock mínimo',
        '${product.minimum} unidades',
      ),
      _summaryRow(
        _editing ? 'Stock actual (sin cambios)' : 'Stock inicial',
        '${product.initial} unidades',
      ),
      _summaryRow(
        'Descripción',
        product.description?.isNotEmpty == true
            ? product.description!
            : 'Sin descripción',
      ),
      const SizedBox(height: 24),
      Text(
        _editing
            ? 'Al confirmar se guardarán los datos modificados. El código, las existencias y el historial se conservarán.'
            : 'Al confirmar se guardarán el producto y su stock inicial.',
        style: const TextStyle(color: muted, height: 1.6),
      ),
    ],
  );
  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
