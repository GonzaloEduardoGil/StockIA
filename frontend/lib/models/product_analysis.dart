import 'dashboard.dart';

class DemandPrediction {
  const DemandPrediction({
    required this.id,
    required this.productId,
    required this.productName,
    required this.date,
    required this.period,
    required this.units,
    this.active = true,
    this.origin,
    this.from,
    this.to,
  });
  final int id;
  final int productId;
  final String productName;
  final DateTime date;
  final String period;
  final double units;
  final bool active;
  final String? origin;
  final DateTime? from;
  final DateTime? to;
  factory DemandPrediction.fromApi(
    Map<String, dynamic> data, {
    int? productId,
    String? productName,
    bool? active,
  }) {
    final id = dashboardCount(data['idPrediccion']);
    final product = productId ?? dashboardCount(data['idProducto']);
    if (id == 0 || product == 0) throw const FormatException();
    return DemandPrediction(
      id: id,
      productId: product,
      productName: productName ?? data['nombreProducto'] as String,
      date: DateTime.parse(data['fechaPrediccion'] as String),
      period: data['periodoPrediccion'] as String,
      origin:
          data['origen'] as String? ??
          ((data['periodoPrediccion'] as String).startsWith('Semanal:')
              ? 'Semanal'
              : (data['periodoPrediccion'] as String).startsWith('Manual:')
              ? 'Manual'
              : null),
      from: DateTime.tryParse(data['fechaDesde'] as String? ?? ''),
      to: DateTime.tryParse(data['fechaHasta'] as String? ?? ''),
      units: dashboardAmount(data['cantidadEstimada']),
      active: active ?? data['activo'] as bool? ?? true,
    );
  }
}

String demandUnits(double value) {
  final raw = value
      .toStringAsFixed(value == value.roundToDouble() ? 0 : 2)
      .split('.');
  final whole = raw[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return raw.length == 1 ? whole : '$whole,${raw[1]}';
}

class ProductAnalysis {
  const ProductAnalysis({
    required this.id,
    required this.name,
    required this.category,
    required this.active,
    required this.minimum,
    this.stock,
    this.trend,
    this.predictions,
    this.recommendations,
  });
  final int id;
  final String name;
  final String category;
  final bool active;
  final int minimum;
  final int? stock;
  // count representa unidades vendidas por día en el análisis del producto.
  final List<DailySales>? trend;
  final List<DemandPrediction>? predictions;
  final List<SavedRecommendation>? recommendations;
  factory ProductAnalysis.fromApi(Map<String, dynamic> data) {
    final product = data['producto'] as Map<String, dynamic>;
    final id = dashboardCount(product['idProducto']);
    if (id == 0) throw const FormatException();
    final name = product['nombre'] as String;
    final active = product['activo'] as bool;
    T? section<T>(T Function() parse) {
      try {
        return parse();
      } catch (_) {
        return null;
      }
    }

    return ProductAnalysis(
      id: id,
      name: name,
      category: (product['categoria'] as String?)?.trim().isNotEmpty == true
          ? product['categoria'] as String
          : 'Sin categoría',
      active: active,
      minimum: dashboardCount(product['stockMinimo']),
      stock: product['cantidadDisponible'] == null
          ? null
          : dashboardCount(product['cantidadDisponible']),
      trend: section(() {
        final grouped = <DateTime, (int, int)>{};
        for (final row in data['evolucionVentas'] as List<dynamic>) {
          final date = DateTime.parse(row['fecha'] as String);
          final day = DateTime(date.year, date.month, date.day);
          final previous = grouped[day] ?? (0, 0);
          grouped[day] = (
            previous.$1 + dashboardCount(row['unidadesVendidas']),
            previous.$2 +
                (dashboardAmount(row['totalFacturado']) * 100).round(),
          );
        }
        return grouped.entries
            .map((e) => DailySales(e.key, e.value.$1, e.value.$2 / 100))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
      }),
      predictions: section(() {
        final rows = (data['predicciones'] as List<dynamic>)
            .map(
              (p) => DemandPrediction.fromApi(
                p as Map<String, dynamic>,
                productId: id,
                productName: name,
                active: active,
              ),
            )
            .toList();
        rows.sort((a, b) {
          final date = b.date.compareTo(a.date);
          return date == 0 ? b.id.compareTo(a.id) : date;
        });
        return rows;
      }),
      recommendations: section(
        () =>
            (data['recomendaciones'] as List<dynamic>)
                .map(
                  (r) => SavedRecommendation.fromApi(r as Map<String, dynamic>),
                )
                .toList()
              ..sort((a, b) => b.date.compareTo(a.date)),
      ),
    );
  }
}

class SavedRecommendation {
  const SavedRecommendation(this.date, this.units, this.reason, this.status);
  final DateTime date;
  final int units;
  final String reason;
  final String status;
  factory SavedRecommendation.fromApi(Map<String, dynamic> data) =>
      SavedRecommendation(
        DateTime.parse(data['fecha'] as String),
        dashboardCount(data['cantidadSugerida']),
        data['motivo'] as String,
        data['estado'] as String,
      );
}
