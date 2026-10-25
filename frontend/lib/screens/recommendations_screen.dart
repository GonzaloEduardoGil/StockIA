import 'package:flutter/material.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/product.dart';
import '../models/recommendation.dart';
import '../models/stock_movement.dart';
import '../widgets/date_filter_field.dart';

class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({
    required this.api,
    required this.onBusyChanged,
    this.currentUserId,
    super.key,
  });
  final InventoryApi api;
  final ValueChanged<bool> onBusyChanged;
  // El usuario proviene de la sesión; el servidor valida su identidad y rol.
  final int? currentUserId;
  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  final _search = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  List<Recommendation> _rows = [];
  bool _loading = true;
  bool _busy = false;
  bool _uncertain = false;
  String? _error;
  String? _notice;
  bool _noticeError = false;
  String? _status;
  int? _selectedId;
  int _request = 0;
  bool get _hasSession =>
      widget.currentUserId != null && widget.currentUserId! > 0;
  bool get _canWrite =>
      _hasSession && !_busy && !_loading && _error == null && !_uncertain;
  Recommendation? get _selected {
    for (final row in _rows) {
      if (row.id == _selectedId) return row;
    }
    return null;
  }

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
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.api.loadRecommendations();
      if (!mounted || request != _request) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = error is ApiFailure
            ? error.message
            : 'No se pudieron cargar las recomendaciones.';
      });
    }
  }

  void _setBusy(bool value) {
    if (!mounted) return;
    setState(() => _busy = value);
    widget.onBusyChanged(value);
  }

  Future<bool> _confirm(String title, String description, String label) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(description),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(label),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _generate() async {
    if (!_canWrite) return;
    final confirmed = await _confirm(
      'Generar recomendaciones',
      'Se guardarán sugerencias de reposición para los productos con riesgo de agotamiento.',
      'Generar',
    );
    if (!mounted || !confirmed || !_canWrite) return;
    _setBusy(true);
    setState(() {
      _notice = null;
      _noticeError = false;
    });
    try {
      final count = await widget.api.generateRecommendations(
        widget.currentUserId!,
      );
      if (!mounted) return;
      setState(() {
        _notice = count == 0
            ? 'No se generaron recomendaciones nuevas. Revisá las pendientes.'
            : count == 1
            ? 'Se generó 1 recomendación.'
            : 'Se generaron $count recomendaciones.';
        _selectedId = null;
        _status = count == 0 ? _status : 'Pendiente';
        if (count > 0) {
          _search.clear();
          _from.clear();
          _to.clear();
        }
      });
      await _load();
    } on ApiFailure catch (error) {
      await _writeFailure(error);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _decide(Recommendation row, String status) async {
    if (!_canWrite || !row.pending) return;
    final accept = status == 'Aceptada';
    final confirmed = await _confirm(
      accept ? 'Aceptar recomendación' : 'Rechazar recomendación',
      '${row.productName} · ${row.units} unidades sugeridas.\n${accept ? 'La decisión quedará registrada. La reposición se carga después como entrada de stock.' : 'El rechazo quedará registrado en el historial.'}',
      accept ? 'Aceptar' : 'Rechazar',
    );
    if (!mounted || !confirmed || !_canWrite) return;
    _setBusy(true);
    setState(() {
      _notice = null;
      _noticeError = false;
    });
    try {
      final updated = await widget.api.decideRecommendation(
        row,
        widget.currentUserId!,
        status,
      );
      if (!mounted) return;
      setState(() {
        _rows = _rows.map((r) => r.id == updated.id ? updated : r).toList();
        _notice = 'Decisión registrada: ${status.toLowerCase()}.';
      });
      await _load();
    } on ApiFailure catch (error) {
      await _writeFailure(error);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _writeFailure(ApiFailure error) async {
    if (!mounted) return;
    setState(() {
      _notice = error.message;
      _noticeError = true;
      _uncertain = error.mayHaveSaved;
    });
    if (error.requiresRefresh) await _load();
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

  List<Recommendation> get _filtered {
    if (_dateError != null) return [];
    final query = searchable(_search.text.trim());
    final from = parseMovementDate(_from.text);
    final to = parseMovementDate(_to.text);
    return _rows.where((r) {
      final day = DateTime(r.date.year, r.date.month, r.date.day);
      return (_status == null || r.status == _status) &&
          (query.isEmpty ||
              searchable('${r.id} ${r.productId} ${r.productName}')
                  .contains(query)) &&
          (from == null || !day.isBefore(from)) &&
          (to == null || !day.isAfter(to));
    }).toList();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 950;
      final width = constraints.maxWidth - (narrow ? 40 : 64);
      return SingleChildScrollView(
        padding: EdgeInsets.all(narrow ? 20 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recomendaciones / Reposición',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Recomendaciones de reposición',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _loading || _busy ? null : _load,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Actualizar'),
                ),
                FilledButton.icon(
                  key: const Key('generate-recommendations'),
                  onPressed: _canWrite ? _generate : null,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Generar recomendaciones'),
                ),
              ],
            ),
            if (!_hasSession)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text(
                  'Iniciá sesión para generar y decidir recomendaciones.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
            if (_notice != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 18),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _noticeError
                      ? const Color(0xFFFFF3D6)
                      : const Color(0xFFE6F4EE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_notice!),
              ),
            const SizedBox(height: 24),
            if (_selectedId != null) ...[
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() => _selectedId = null),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver al listado'),
              ),
              const SizedBox(height: 16),
            ] else ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: narrow ? width : 280,
                    child: Semantics(
                      container: true,
                      child: TextField(
                        key: const Key('recommendation-search'),
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Buscar producto o código',
                          prefixIcon: Icon(Icons.search, size: 20),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: narrow ? width : 185,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('recommendation-status-$_status'),
                      initialValue: _status,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Estado'),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Todos'),
                        ),
                        ...['Pendiente', 'Aceptada', 'Rechazada'].map(
                          (s) => DropdownMenuItem(value: s, child: Text(s)),
                        ),
                      ],
                      onChanged: (s) => setState(() => _status = s),
                    ),
                  ),
                  SizedBox(
                    width: narrow ? width : 185,
                    child: DateFilterField(
                      key: const Key('recommendation-from'),
                      label: 'Desde',
                      controller: _from,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                  SizedBox(
                    width: narrow ? width : 185,
                    child: DateFilterField(
                      key: const Key('recommendation-to'),
                      label: 'Hasta',
                      controller: _to,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _search.clear();
                      _status = null;
                      _from.clear();
                      _to.clear();
                    }),
                    child: const Text('Limpiar filtros'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              _failure(_error!)
            else if (_selectedId != null)
              _selected == null
                  ? const Text('La recomendación ya no está disponible.')
                  : _detail(_selected!)
            else if (_dateError != null)
              Text(
                _dateError!,
                style: const TextStyle(color: Color(0xFFA53028)),
              )
            else if (_rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Todavía no hay recomendaciones guardadas.'),
              )
            else if (_filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No encontramos recomendaciones con estos filtros.',
                ),
              )
            else ...[
              Text(
                'Recomendaciones: ${_filtered.length}',
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 12),
              if (narrow)
                ..._filtered.map(_card)
              else
                SizedBox(
                  width: double.infinity,
                  child: DataTable(
                    columnSpacing: 20,
                    columns: const [
                      DataColumn(label: Text('Producto')),
                      DataColumn(label: Text('Sugeridas'), numeric: true),
                      DataColumn(label: Text('Fecha')),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('')),
                    ],
                    rows: _filtered
                        .map(
                          (r) => DataRow(
                            cells: [
                              DataCell(
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 220,
                                  ),
                                  child: Text(
                                    '${r.productName} (#${r.productId})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(Text('${r.units}')),
                              DataCell(Text(movementDate(r.date))),
                              DataCell(_statusChip(r.status)),
                              DataCell(_detailButton(r)),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );

  Widget _detailButton(Recommendation r) => OutlinedButton(
    key: ValueKey('recommendation-detail-${r.id}'),
    onPressed: _busy ? null : () => setState(() => _selectedId = r.id),
    child: const Text('Ver detalle'),
  );
  Widget _statusChip(String status) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: status == 'Pendiente'
          ? const Color(0xFFFFF3D6)
          : status == 'Aceptada'
          ? const Color(0xFFE6F4EE)
          : const Color(0xFFEDF0F5),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      status,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
  Widget _card(Recommendation r) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${r.productName} (#${r.productId})',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text('${r.units} unidades sugeridas'),
          const SizedBox(height: 8),
          Text(movementDate(r.date), style: const TextStyle(color: muted)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [_statusChip(r.status), _detailButton(r)],
          ),
        ],
      ),
    ),
  );
  Widget _detail(Recommendation r) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recomendación #${r.id}', style: const TextStyle(color: muted)),
        const SizedBox(height: 12),
        Text(
          '${r.productName} (#${r.productId})',
          style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _statusChip(r.status),
            Text(movementDate(r.date)),
            if (!r.active)
              const Text('Producto inactivo', style: TextStyle(color: muted)),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          '${r.units} unidades sugeridas',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: 20),
        const Text('Motivo', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(r.reason),
        const SizedBox(height: 20),
        Text(
          'Generada por ${r.creatorName}',
          style: const TextStyle(color: muted),
        ),
        if (r.pending) ...[
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                key: const Key('accept-recommendation'),
                onPressed: _canWrite ? () => _decide(r, 'Aceptada') : null,
                child: const Text('Aceptar'),
              ),
              OutlinedButton(
                key: const Key('reject-recommendation'),
                onPressed: _canWrite ? () => _decide(r, 'Rechazada') : null,
                child: const Text('Rechazar'),
              ),
            ],
          ),
        ],
      ],
    ),
  );
  Widget _failure(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        TextButton.icon(
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      ],
    ),
  );
}
