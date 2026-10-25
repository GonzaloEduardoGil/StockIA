import 'package:flutter/material.dart';

import 'data/inventory_api.dart';
import 'screens/inventory_screen.dart';
import 'widgets/auth_gate.dart';

const navy = Color(0xFF315A86);
const ink = Color(0xFF203B5A);
const muted = Color(0xFF76849B);
const canvas = Color(0xFFF5F6FB);
const line = Color(0xFFE7EBF2);

class StockiaApp extends StatefulWidget {
  const StockiaApp({
    super.key,
    this.api,
    this.currentUserId,
    this.initialDashboard = false,
    this.requireLogin = false,
  });
  final InventoryApi? api;
  final bool initialDashboard;
  final bool requireLogin;
  // Identidad inyectable para las pruebas de pantallas; el arranque real usa AuthGate.
  final int? currentUserId;
  @override
  State<StockiaApp> createState() => _StockiaAppState();
}

class _StockiaAppState extends State<StockiaApp> {
  late final InventoryApi _api;
  @override
  void initState() {
    super.initState();
    _api = widget.api ?? InventoryApi(enableAlertEvents: true);
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'StockIA · Inventario',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(seedColor: navy, surface: Colors.white),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 29,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleLarge: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        bodyMedium: TextStyle(fontSize: 14, color: ink),
        bodySmall: TextStyle(fontSize: 12, color: muted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: muted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: line),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
      dividerColor: line,
    ),
    home: widget.requireLogin
        ? AuthGate(api: _api)
        : InventoryScreen(
            api: _api,
            initialDashboard: widget.initialDashboard,
            currentUserId: widget.currentUserId,
          ),
  );
}
