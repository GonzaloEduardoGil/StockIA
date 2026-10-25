import 'dashboard.dart';

class Recommendation {
  const Recommendation({
    required this.id,
    required this.productId,
    required this.productName,
    required this.active,
    required this.creatorId,
    required this.creatorName,
    required this.date,
    required this.type,
    required this.units,
    required this.reason,
    required this.status,
  });
  final int id;
  final int productId;
  final String productName;
  final bool active;
  final int creatorId;
  final String creatorName;
  final DateTime date;
  final String type;
  final int units;
  final String reason;
  final String status;
  bool get pending => status == 'Pendiente';
  factory Recommendation.fromApi(Map<String, dynamic> data) {
    final id = dashboardCount(data['idRecomendacion']);
    final productId = dashboardCount(data['idProducto']);
    final creatorId = dashboardCount(data['idUsuario']);
    final units = dashboardCount(data['cantidadSugerida']);
    final status = data['estado'] as String;
    if (id == 0 ||
        productId == 0 ||
        creatorId == 0 ||
        units == 0 ||
        !['Pendiente', 'Aceptada', 'Rechazada'].contains(status)) {
      throw const FormatException();
    }
    return Recommendation(
      id: id,
      productId: productId,
      productName: data['nombreProducto'] as String,
      active: data['activo'] as bool,
      creatorId: creatorId,
      creatorName: data['nombreUsuario'] as String,
      date: DateTime.parse(data['fecha'] as String),
      type: data['tipo'] as String,
      units: units,
      reason: data['motivo'] as String,
      status: status,
    );
  }
  Recommendation withStatus(String value) => Recommendation(
    id: id,
    productId: productId,
    productName: productName,
    active: active,
    creatorId: creatorId,
    creatorName: creatorName,
    date: date,
    type: type,
    units: units,
    reason: reason,
    status: value,
  );
}
