class ManagedUser {
  const ManagedUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.active = true,
  });
  final int id;
  final String name;
  final String email;
  final String role;
  final bool active;

  factory ManagedUser.fromApi(Map<String, dynamic> data) {
    final id = data['idUsuario'] as int;
    final role = data['rol'] as String;
    if (id <= 0 || !['Encargado de stock', 'Vendedor'].contains(role)) {
      throw const FormatException();
    }
    return ManagedUser(
      id: id,
      name: data['nombre'] as String,
      email: data['email'] as String,
      role: role,
      active: data['activo'] as bool? ?? true,
    );
  }
}
