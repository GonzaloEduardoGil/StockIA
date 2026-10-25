class DashboardSales {
  const DashboardSales(this.count, this.total);
  final int count;
  final double total;
  factory DashboardSales.fromApi(Map<String, dynamic> row) => DashboardSales(
    dashboardCount(row['cantidadVentas']),
    dashboardAmount(row['totalFacturado']),
  );
}

class DashboardInventory {
  const DashboardInventory(this.products, this.units, this.low, this.normal);
  final int products;
  final int units;
  final int low;
  final int normal;
  factory DashboardInventory.fromApi(Map<String, dynamic> row) {
    final products = dashboardCount(row['productosActivos']);
    final low = dashboardCount(row['productosStockBajo']);
    final normal = dashboardCount(row['productosStockNormal']);
    if (low + normal != products) throw const FormatException();
    return DashboardInventory(
      products,
      dashboardCount(row['unidadesDisponibles']),
      low,
      normal,
    );
  }
}

class RankedProduct {
  const RankedProduct(this.id, this.name, this.units);
  final int id;
  final String name;
  final int units;
  factory RankedProduct.fromApi(Map<String, dynamic> row) {
    final id = dashboardCount(row['idProducto']);
    if (id == 0) throw const FormatException();
    return RankedProduct(
      id,
      row['nombre'] as String,
      dashboardCount(row['cantidadVendida']),
    );
  }
}

class DailySales {
  const DailySales(this.date, this.count, this.total);
  final DateTime date;
  final int count;
  final double total;
}

// Cada sección se interpreta por separado para conservar los resultados
// disponibles cuando una parte de la respuesta está incompleta (CU16, A2).
class DashboardData {
  const DashboardData({
    this.sales,
    this.inventory,
    this.best,
    this.least,
    this.trend,
  });
  final DashboardSales? sales;
  final DashboardInventory? inventory;
  final List<RankedProduct>? best;
  final List<RankedProduct>? least;
  final List<DailySales>? trend;
  factory DashboardData.fromApi(Map<String, dynamic> data) => DashboardData(
    sales: _section(
      () =>
          DashboardSales.fromApi(data['resumenVentas'] as Map<String, dynamic>),
    ),
    inventory: _section(
      () => DashboardInventory.fromApi(
        data['inventario'] as Map<String, dynamic>,
      ),
    ),
    best: _section(
      () => _ranking(data['productosMasVendidos'], descending: true),
    ),
    least: _section(
      () => _ranking(data['productosMenosVendidos'], descending: false),
    ),
    trend: _section(() => _trend(data['evolucionVentas'])),
  );
}

T? _section<T>(T Function() parse) {
  try {
    return parse();
  } catch (_) {
    return null;
  }
}

List<RankedProduct> _ranking(dynamic data, {required bool descending}) {
  final rows = (data as List<dynamic>)
      .map((row) => RankedProduct.fromApi(row as Map<String, dynamic>))
      .toList();
  rows.sort(
    (a, b) =>
        descending ? b.units.compareTo(a.units) : a.units.compareTo(b.units),
  );
  return rows.take(5).toList();
}

List<DailySales> _trend(dynamic data) {
  final grouped = <DateTime, (int, int)>{};
  for (final row in data as List<dynamic>) {
    final item = row as Map<String, dynamic>;
    final date = DateTime.parse(item['fecha'] as String);
    final day = DateTime(date.year, date.month, date.day);
    final previous = grouped[day] ?? (0, 0);
    grouped[day] = (
      previous.$1 + dashboardCount(item['cantidadVentas']),
      previous.$2 + (dashboardAmount(item['totalFacturado']) * 100).round(),
    );
  }
  return grouped.entries
      .map((e) => DailySales(e.key, e.value.$1, e.value.$2 / 100))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));
}

int dashboardCount(dynamic value) {
  if (value is! num ||
      !value.isFinite ||
      value < 0 ||
      value != value.roundToDouble()) {
    throw const FormatException();
  }
  return value.toInt();
}

double dashboardAmount(dynamic value) {
  if (value is! num || !value.isFinite || value < 0) {
    throw const FormatException();
  }
  return value.toDouble();
}
