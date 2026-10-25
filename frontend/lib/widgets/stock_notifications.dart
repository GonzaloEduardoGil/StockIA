import 'package:flutter/material.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/stock_alert.dart';

class StockNotifications extends StatefulWidget {
  const StockNotifications({
    required this.api,
    required this.count,
    required this.onAlert,
    required this.onAllAlerts,
    this.enabled = true,
    this.onCountChanged,
    super.key,
  });
  final InventoryApi api;
  final int count;
  final bool enabled;
  final ValueChanged<int> onAlert;
  final VoidCallback onAllAlerts;
  final ValueChanged<int>? onCountChanged;
  @override
  State<StockNotifications> createState() => _StockNotificationsState();
}

class _StockNotificationsState extends State<StockNotifications> {
  final _menu = MenuController();
  final _focus = FocusNode();
  List<StockAlert> _alerts = [];
  bool _loading = true;
  String? _error;
  int _request = 0;
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _alerts = [];
    });
    try {
      final alerts = await widget.api.loadAlerts();
      if (!mounted || request != _request) return;
      setState(() {
        _alerts = alerts;
        _loading = false;
      });
      widget.onCountChanged?.call(alerts.length);
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = error is ApiFailure
            ? error.message
            : 'No se pudieron cargar las alertas.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final width = (viewport.width - 16).clamp(1.0, 380.0);
    final bodyHeight = (viewport.height - 210).clamp(60.0, 320.0);
    return MenuAnchor(
      controller: _menu,
      childFocusNode: _focus,
      consumeOutsideTap: true,
      alignmentOffset: const Offset(0, 8),
      style: MenuStyle(
        alignment: Alignment.bottomRight,
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            side: const BorderSide(color: line),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      onOpen: _load,
      onClose: () => ++_request,
      builder: (context, controller, child) => IconButton(
        key: const Key('stock-alert-notification'),
        focusNode: _focus,
        tooltip: widget.count == 0
            ? 'Notificaciones de stock'
            : 'Notificaciones de stock (${widget.count})',
        onPressed: !widget.enabled
            ? null
            : () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
        icon: Badge(
          label: Text('${widget.count}'),
          isLabelVisible: widget.count > 0,
          child: const Icon(Icons.notifications_outlined, color: navy),
        ),
      ),
      menuChildren: [
        SizedBox(
          key: const Key('stock-notifications-menu'),
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: 18,
                  right: 6,
                  top: 6,
                  bottom: 6,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Alertas de stock',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar alertas',
                      onPressed: _menu.close,
                      icon: const Icon(Icons.close, size: 19),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: bodyHeight),
                child: SingleChildScrollView(
                  primary: false,
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_error!),
                              TextButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        )
                      : _alerts.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(22),
                          child: Text('No hay alertas de stock bajo.'),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [for (final alert in _alerts) _row(alert)],
                        ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(6),
                child: TextButton(
                  key: const Key('notification-all-alerts'),
                  onPressed: () {
                    _menu.close();
                    widget.onAllAlerts();
                  },
                  child: const Text('Ver todas las alertas'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(StockAlert alert) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${alert.name} (#${alert.productId})',
                style: const TextStyle(fontWeight: FontWeight.w600, color: ink),
              ),
              const SizedBox(height: 6),
              Text(
                alert.status,
                style: TextStyle(
                  color: alert.outOfStock
                      ? const Color(0xFFA53028)
                      : const Color(0xFF8A651D),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Stock: ${alert.quantity} · Mínimo: ${alert.minimum}',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          key: ValueKey('notification-open-${alert.productId}'),
          onPressed: () {
            _menu.close();
            widget.onAlert(alert.productId);
          },
          child: const Text('Ver alerta'),
        ),
      ],
    ),
  );
}
