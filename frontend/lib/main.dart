import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Mantener disponibles los controles accesibles en la versión web.
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  runApp(const StockiaApp(requireLogin: true));
}
