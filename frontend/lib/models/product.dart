class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.minimum,
    this.description,
    this.price,
    this.rawCategory,
  });
  final int id;
  final String name;
  final String category;
  final String? description;
  final double? price;
  final String? rawCategory;
  final int quantity;
  final int minimum;
  bool get isLow => quantity <= minimum;

  factory Product.fromApi(
    Map<String, dynamic> stock,
    Map<String, dynamic>? info,
  ) => Product(
    id: (stock['idProducto'] as num).toInt(),
    name: stock['nombre'] as String,
    rawCategory: stock['categoria'] as String?,
    category: (stock['categoria'] as String?)?.trim().isNotEmpty == true
        ? stock['categoria'] as String
        : 'Sin categoría',
    quantity: (stock['cantidadDisponible'] as num).toInt(),
    minimum: (stock['stockMinimo'] as num).toInt(),
    description: info?['descripcion'] as String?,
    price: (info?['precio'] as num?)?.toDouble(),
  );
  Product withDetails(Map<String, dynamic> data) => Product(
    id: id,
    name: data['nombre'] as String,
    category: (data['categoria'] as String?)?.trim().isNotEmpty == true
        ? data['categoria'] as String
        : 'Sin categoría',
    rawCategory: data['categoria'] as String?,
    quantity: quantity,
    minimum: (data['stockMinimo'] as num).toInt(),
    description: data['descripcion'] as String?,
    price: (data['precio'] as num).toDouble(),
  );
}

String searchable(String text) {
  var result = text.toLowerCase();
  const accented = 'áéíóúüñ';
  const plain = 'aeiouun';
  for (var i = 0; i < accented.length; i++) {
    result = result.replaceAll(accented[i], plain[i]);
  }
  return result;
}

String money(double? value) {
  if (value == null) return 'No disponible';
  final parts = value.toStringAsFixed(2).split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return '\$ $whole,${parts[1]}';
}
