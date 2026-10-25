import 'product.dart';

class SaleLine {
  const SaleLine({required this.product, required this.quantity});
  final Product product;
  final int quantity;
  int get unitCents => (product.price! * 100).round();
  int get subtotalCents => unitCents * quantity;
  Map<String, int> toJson() => {'idProducto': product.id, 'cantidad': quantity};
}

class SaleReceipt {
  const SaleReceipt({
    required this.id,
    required this.total,
    required this.lines,
  });
  final int id;
  final double total;
  final List<SoldLine> lines;
  factory SaleReceipt.fromApi(
    Map<String, dynamic> data,
    List<SaleLine> requested,
  ) {
    final id = data['idVenta'] as int;
    final total = (data['total'] as num).toDouble();
    final rows = data['productos'] as List<dynamic>;
    if (id <= 0 ||
        !total.isFinite ||
        total <= 0 ||
        rows.length != requested.length) {
      throw const FormatException();
    }
    final expected = {
      for (final line in requested) line.product.id: line.quantity,
    };
    final seen = <int>{};
    final lines = rows.map((row) {
      final item = row as Map<String, dynamic>;
      final productId = item['idProducto'] as int;
      final quantity = item['cantidad'] as int;
      final subtotal = (item['subtotal'] as num).toDouble();
      if (!seen.add(productId) ||
          expected[productId] != quantity ||
          !subtotal.isFinite ||
          subtotal <= 0) {
        throw const FormatException();
      }
      return SoldLine(
        name: item['nombre'] as String,
        quantity: quantity,
        subtotal: subtotal,
      );
    }).toList();
    if ((lines.fold<double>(0, (sum, line) => sum + line.subtotal) * 100)
            .round() !=
        (total * 100).round()) {
      throw const FormatException();
    }
    return SaleReceipt(id: id, total: total, lines: lines);
  }
}

class SoldLine {
  const SoldLine({
    required this.name,
    required this.quantity,
    required this.subtotal,
  });
  final String name;
  final int quantity;
  final double subtotal;
}
