class StockMovement {
  const StockMovement({
    required this.id,
    required this.date,
    required this.type,
    required this.quantity,
    required this.productId,
    required this.productName,
    this.reason,
  });
  final int id;
  final DateTime date;
  final String type;
  final int quantity;
  final int productId;
  final String productName;
  final String? reason;
  String get reasonLabel =>
      reason?.trim().isNotEmpty == true ? reason!.trim() : 'Sin motivo';
  int get signedQuantity => type == 'Venta' ? -quantity.abs() : quantity;
  String get quantityLabel =>
      '${signedQuantity > 0 ? '+' : (signedQuantity < 0 ? '−' : '')}${signedQuantity.abs()} unidades';
  factory StockMovement.fromApi(Map<String, dynamic> data) {
    final type = data['tipoMovimiento'] as String;
    if (!['Entrada', 'Ajuste', 'Venta'].contains(type)) {
      throw const FormatException();
    }
    return StockMovement(
      id: data['idMovimiento'] as int,
      date: DateTime.parse(data['fecha'] as String),
      type: type,
      quantity: data['cantidad'] as int,
      productId: data['idProducto'] as int,
      productName: data['nombreProducto'] as String,
      reason: data['motivo'] as String?,
    );
  }
}

String movementDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().padLeft(4, '0')}';

DateTime? parseMovementDate(String text) {
  if (!RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(text.trim())) return null;
  final parts = text.trim().split('/').map(int.parse).toList();
  final date = DateTime(parts[2], parts[1], parts[0]);
  return date.day == parts[0] && date.month == parts[1] && date.year == parts[2]
      ? date
      : null;
}
