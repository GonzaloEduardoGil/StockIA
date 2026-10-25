class SaleSummary {
  const SaleSummary({
    required this.id,
    required this.date,
    required this.total,
    required this.seller,
  });
  final int id;
  final DateTime date;
  final double total;
  final String seller;

  factory SaleSummary.fromApi(
    Map<String, dynamic> data, {
    bool detail = false,
  }) {
    final id = data['idVenta'] as int;
    final total = (data['total'] as num).toDouble();
    final date = DateTime.parse(data['fecha'] as String);
    final seller = detail
        ? (data['vendedor'] as Map<String, dynamic>)['nombre'] as String
        : data['vendedor'] as String;
    if (id <= 0 || !total.isFinite || total < 0) throw const FormatException();
    return SaleSummary(id: id, date: date, total: total, seller: seller);
  }
}

class HistoricalSaleLine {
  const HistoricalSaleLine({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });
  final int productId;
  final String name;
  final int quantity;
  final double unitPrice;
  final double subtotal;
  factory HistoricalSaleLine.fromApi(Map<String, dynamic> data) {
    final id = data['idProducto'] as int;
    final quantity = data['cantidad'] as int;
    final price = (data['precioUnitario'] as num).toDouble();
    final subtotal = (data['subtotal'] as num).toDouble();
    if (id <= 0 ||
        quantity <= 0 ||
        !price.isFinite ||
        price < 0 ||
        !subtotal.isFinite ||
        subtotal < 0) {
      throw const FormatException();
    }
    return HistoricalSaleLine(
      productId: id,
      name: data['nombreProducto'] as String,
      quantity: quantity,
      unitPrice: price,
      subtotal: subtotal,
    );
  }
}

class HistoricalSale {
  const HistoricalSale({required this.summary, required this.lines});
  final SaleSummary summary;
  final List<HistoricalSaleLine> lines;
  factory HistoricalSale.fromApi(Map<String, dynamic> data) => HistoricalSale(
    summary: SaleSummary.fromApi(data, detail: true),
    lines: (data['detalles'] as List<dynamic>)
        .map((row) => HistoricalSaleLine.fromApi(row as Map<String, dynamic>))
        .toList(),
  );
}
