class AuthSession {
  const AuthSession({
    required this.token,
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    required this.expires,
  });
  final String token;
  final int userId;
  final String name;
  final String email;
  final String role;
  final DateTime expires;
  bool get stockRole => role == 'Administrador' || role == 'Encargado de stock';
  factory AuthSession.fromApi(Map<String, dynamic> data) {
    final user = data['usuario'] as Map<String, dynamic>;
    final id = user['idUsuario'] as int;
    final token = data['token'] as String;
    final role = user['rol'] as String;
    if (id <= 0 ||
        !RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(token) ||
        !['Administrador', 'Encargado de stock', 'Vendedor'].contains(role)) {
      throw const FormatException();
    }
    return AuthSession(
      token: token,
      userId: id,
      name: user['nombre'] as String,
      email: user['email'] as String,
      role: role,
      expires: DateTime.parse(data['expira'] as String),
    );
  }
}
