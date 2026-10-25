import 'product.dart';

class StockAlert {
  const StockAlert({
    required this.productId,
    required this.name,
    required this.category,
    required this.quantity,
    required this.minimum,
    this.date,
  });
  final int productId;
  final String name;
  final String category;
  final int quantity;
  final int minimum;
  final DateTime? date;
  bool get outOfStock => quantity == 0;
  String get status => outOfStock ? 'Sin stock' : 'Stock bajo';
  factory StockAlert.fromApi(Map<String, dynamic> data) {
    final id = data['idProducto'] as int;
    final quantity = data['cantidadDisponible'] as int;
    final minimum = data['stockMinimo'] as int;
    if (id <= 0 || quantity < 0 || minimum < 0 || quantity > minimum) {
      throw const FormatException();
    }
    final category = data['categoria'] as String?;
    return StockAlert(
      productId: id,
      name: data['nombreProducto'] as String,
      category: category?.trim().isNotEmpty == true
          ? category!
          : 'Sin categoría',
      quantity: quantity,
      minimum: minimum,
      date: data['fechaCreacion'] == null
          ? null
          : DateTime.parse(data['fechaCreacion'] as String),
    );
  }
}

class StockAlertDetail {
  const StockAlertDetail({required this.product, this.lastAlertDate});
  final Product product;
  final DateTime? lastAlertDate;
  factory StockAlertDetail.fromApi(Map<String, dynamic> data) {
    final row = data['producto'] as Map<String, dynamic>;
    final alert = StockAlert.fromApi({...row, 'nombreProducto': row['nombre']});
    final last = data['ultimaAlerta'] as Map<String, dynamic>?;
    final price = (row['precio'] as num?)?.toDouble();
    if (price != null && (!price.isFinite || price < 0)) {
      throw const FormatException();
    }
    return StockAlertDetail(
      product: Product(
        id: alert.productId,
        name: alert.name,
        category: alert.category,
        rawCategory: row['categoria'] as String?,
        quantity: alert.quantity,
        minimum: alert.minimum,
        description: row['descripcion'] as String?,
        price: price,
      ),
      lastAlertDate: last?['fechaCreacion'] == null
          ? null
          : DateTime.parse(last!['fechaCreacion'] as String),
    );
  }
}
