import 'package:flutter/material.dart';

import '../data/inventory_api.dart';
import '../models/auth_session.dart';
import '../screens/login_screen.dart';
import '../screens/inventory_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({required this.api, super.key});
  final InventoryApi api;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AuthSession?>(
    valueListenable: api.session,
    builder: (context, user, _) {
      if (user == null) return LoginScreen(api: api);
      return InventoryScreen(
        key: ValueKey(user.userId),
        api: api,
        currentUserId: user.userId,
        currentUserRole: user.role,
        userName: user.name,
        initialDashboard: user.stockRole,
        onLogout: api.logout,
      );
    },
  );
}
