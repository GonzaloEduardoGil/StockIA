# Predicciones de demanda

## Uso

La automática genera predicciones para productos activos sin una predicción vigente al comienzo de la semana. Trabaja al cierre del domingo y cubre de lunes a domingo. Si la última predicción vence entre semana, espera al siguiente cierre semanal.

Desde el análisis de cada producto activo, Administrador y Encargado de stock pueden pulsar **Generar predicción**, indicar un entero de **1 a 30 días** y confirmar. El horizonte comienza mañana. Al terminar, se recarga el análisis y se selecciona la nueva predicción. El Vendedor no tiene permiso para generarla.

La interfaz bloquea el doble envío y muestra los errores del servicio, incluidos falta de historial y producto ocupado. Si la respuesta no permite confirmar el resultado, exige actualizar el análisis antes de repetir.

## Vigencia e historial sin cambiar la base

PREDICCION_DEMANDA mantiene sus cinco columnas originales: idPrediccion, idProducto, fechaPrediccion, periodoPrediccion y cantidadEstimada. Esta versión no crea ni elimina tablas, columnas, índices o restricciones; no requiere migración.

La vigencia se calcula a partir de fechaPrediccion y del horizonte de texto:

- `Próximos N días`: desde el día posterior a la generación hasta fechaPrediccion + N, inclusive.
- Los períodos con fechas explícitas, por ejemplo `Semanal: 2026-11-02 a 2026-11-08`, se interpretan por sus fechas. También se admiten los textos históricos con prefijo Manual y fechas explícitas.
- Un período desconocido o inválido no se considera vigente. No se inventan fechas.

Se toma siempre la última predicción de cada producto, ordenando por fechaPrediccion e idPrediccion descendentes. Una anterior no recupera vigencia si la última vence. No se distingue el origen manual o automático para decidir la prioridad. Cada generación inserta un registro nuevo y conserva el historial completo.

La automática usa el lunes como referencia para determinar si corresponde generar esa semana. Si una predicción cubría ese lunes y vence el miércoles, las revisiones del jueves o viernes no la reemplazan; espera al siguiente cierre del domingo. Sin predicción o con una vencida antes del lunes, puede generar la semana pendiente.

## Programación y coordinación

El servidor revisa pendientes al arrancar y cada 30 minutos. Inicia la nueva semana en la primera revisión posterior a las 00:00 del lunes, hora argentina; debe estar encendido. Si vuelve a mitad de semana, calcula la semana vigente con el historial hasta el domingo cerrado, sin incorporar ventas posteriores. No recupera semanas ya terminadas.

`PREDICTIONS_WEEKLY_ENABLED=false` desactiva el proceso automático. `main:app` y `server:app` conservan la misma aplicación protegida.

Antes de calcular se obtiene `pg_try_advisory_xact_lock(71324, id_producto)`. La automática vuelve a comprobar la última predicción dentro del bloqueo. Si otro proceso lo tiene, omite ese producto; el pedido manual devuelve 409. El pedido manual puede reemplazar una predicción vigente insertando otra nueva.

Se mantiene una conexión del pool durante lectura, entrenamiento y guardado para que el bloqueo transaccional proteja toda la operación. Commit, rollback o desconexión liberan el bloqueo; los recursos se devuelven también ante errores de limpieza. No se usa una tabla de reservas. Los productos sin historial suficiente o con errores se reintentan en la siguiente revisión.

## Cálculo y recomendaciones

La ruta manual de main.py y la automática usan generar_prediccion en funciones/predicciones.py. Se conserva el bloque original de preparación de datos, parámetros XGBoost, cálculo recursivo, límite inferior cero, total con ceil y redondeo diario. La manual incluye hoy en el historial; la automática usa el domingo cerrado. Se necesitan al menos 14 días con ventas y suficientes filas de entrenamiento.

Las recomendaciones usan la última predicción únicamente si está vigente. Si falta, venció o tiene un horizonte no interpretable, usan las ventas de los últimos 30 días, manteniendo la fórmula existente de reposición. No recuperan una predicción anterior. Generar recomendaciones no entrena el modelo ni genera una predicción nueva; no se modifican automáticamente las recomendaciones pendientes.

## API

- `POST /predicciones/{id_producto}/generar`: conserva el cuerpo `{"diasPrediccion": N}`, validación 1–30 y respuesta original con IDs, producto, período, total y prediccionesDiarias. Requiere Administrador o Encargado de stock.
- `GET /predicciones/`: conserva la última por producto y los campos anteriores; agrega fechaDesde, fechaHasta, esActual y vigente calculados al consultar.
- `GET /productos/{id_producto}/analisis`: conserva todo el historial y agrega esos mismos campos calculados. Solo la última puede estar vigente.
- No se devuelven esAutomatica ni origen. Las fechas calculadas no son columnas nuevas.

La base solo guarda el total del horizonte. El desglose diario se devuelve al generar, pero no se conserva; no se agregó un gráfico de predicción diaria.

## Configuración y alcance de V3

Se trasladaron las funciones probadas en la copia local al repositorio original, conservando su configuración de conexión externa y sus comandos de arranque. No se trasladaron PostgreSQL local, credenciales de pruebas, puertos 8001/5174 ni scripts de preparación local. La configuración de database.py queda igual que en V2; no se ejecuta ninguna migración al desplegar esta versión.

Se mantienen los permisos de ventas anteriores: el Vendedor registra y el Administrador consulta el historial. El cambio para permitir ventas al Administrador fue cancelado y no se incluye.

Los documentos de extracciones y auditorías anteriores describen etapas históricas; este documento establece el comportamiento vigente.
