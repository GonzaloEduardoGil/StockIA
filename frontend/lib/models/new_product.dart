class NewProduct {
  const NewProduct({
    required this.name,
    required this.price,
    required this.minimum,
    required this.initial,
    this.description,
    this.category,
  });
  final String name;
  final double price;
  final int minimum;
  final int initial;
  final String? description;
  final String? category;

  Map<String, dynamic> toJson() => {
    'nombre': name.trim(),
    'precio': price,
    'stockMinimo': minimum,
    'stockInicial': initial,
    'descripcion': _optional(description),
    'categoria': _optional(category),
  };
  static String? _optional(String? text) =>
      text == null || text.trim().isEmpty ? null : text.trim();
}

double? parsePrice(String text) {
  var normalized = text.trim();
  if (normalized.contains(',')) {
    if (','.allMatches(normalized).length != 1) return null;
    final parts = normalized.split(',');
    if (!RegExp(r'^\d+(?:\.\d{3})*$').hasMatch(parts[0]) ||
        !RegExp(r'^\d+$').hasMatch(parts[1])) {
      return null;
    }
    normalized = '${parts[0].replaceAll('.', '')}.${parts[1]}';
  }
  if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(normalized)) return null;
  final value = double.tryParse(normalized);
  return value != null && value.isFinite && value > 0 ? value : null;
}

int? parseStock(String text) =>
    RegExp(r'^\d+$').hasMatch(text.trim()) ? int.tryParse(text.trim()) : null;
