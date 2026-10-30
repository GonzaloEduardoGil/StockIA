import 'package:flutter/material.dart';

import '../app.dart';
import '../models/product_analysis.dart';
import '../models/stock_movement.dart';

const predictionPurple = Color(0xFF6952A3);

class PredictionCard extends StatelessWidget {
  const PredictionCard({required this.prediction, this.onOpen, super.key});
  final DemandPrediction prediction;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF6F2FC),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: Color(0xFFDFD4F1)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8DFF7),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  'PREDICCIÓN',
                  style: const TextStyle(
                    color: predictionPurple,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
              if (!prediction.active)
                const Text(
                  'Producto inactivo',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${prediction.productName} (#${prediction.productId})',
            style: const TextStyle(fontWeight: FontWeight.w600, color: ink),
          ),
          const SizedBox(height: 8),
          Text(
            '${demandUnits(prediction.units)} unidades estimadas',
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: predictionPurple,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Generada: ${movementDate(prediction.date)}',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            prediction.from != null && prediction.to != null
                ? '${movementDate(prediction.from!)} – ${movementDate(prediction.to!)}'
                : 'Horizonte al generarse: ${prediction.period}',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          if (prediction.isCurrent == false)
            const Text(
              'Predicción reemplazada',
              style: TextStyle(color: muted, fontSize: 12),
            )
          else if (prediction.isValid != null)
            Text(
              prediction.isValid!
                  ? 'Vigente'
                  : prediction.to == null
                  ? 'Vigencia no informada'
                  : 'Período finalizado',
              style: const TextStyle(color: muted, fontSize: 12),
            )
          else if (prediction.to != null &&
              prediction.to!.isBefore(
                DateTime.now().subtract(const Duration(days: 1)),
              ))
            const Text(
              'Período finalizado',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          if (onOpen != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onOpen,
              child: const Text('Ver análisis'),
            ),
          ],
        ],
      ),
    ),
  );
}
