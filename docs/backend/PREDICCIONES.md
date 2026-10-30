# Predicciones de demanda

## Uso actual

Las predicciones se generan automáticamente al cierre del domingo, para el lunes
a domingo siguientes. El dashboard y el análisis de producto permiten consultar
resultados guardados e históricos. El formulario manual y sus botones siguen
retirados del front. Se recuperó únicamente la ruta manual original del backend,
`POST /predicciones/{id_producto}/generar`, para Administrador y Encargado de stock.
Recibe `{"diasPrediccion": N}` con N entre 1 y 30, incluye hoy en el historial,
predice exactamente los próximos N días y guarda `Próximos N días`, como el original.
No cambia la base ni requiere una tabla auxiliar. Su aplicación en la interfaz
queda para una decisión posterior.

El servidor revisa pendientes al arrancar y cada 30 minutos. Inicia la nueva semana
en la primera revisión posterior a las 00:00 del lunes, hora argentina; no garantiza
ejecutar exactamente a esa hora. Debe estar encendido. Si vuelve a mitad de semana,
calcula la semana vigente usando como corte el domingo anterior, sin incorporar
ventas posteriores. No recupera semanas ya terminadas.

`PREDICTIONS_WEEKLY_ENABLED=false` permite desactivar el proceso automático.
Los comandos habituales `main:app` y `server:app` conservan la misma aplicación
protegida. El cierre espera al producto que esté calculándose antes de cerrar el
pool.

## Esquema original, sin tabla auxiliar

La ejecución no crea ni consulta `STOCKIA_PREDICCION_EJECUCION`. Sólo utiliza
`PREDICCION_DEMANDA` con sus cinco columnas originales. No añade tablas, columnas,
índices o restricciones.

El campo existente `periodoPrediccion` registra explícitamente las fechas:

```text
Semanal: 2026-11-02 a 2026-11-08
```

El texto ocupa 32 caracteres y cabe en el campo existente de 100. Un resultado con
el mismo producto y el mismo período identifica una semana ya completada.

Los datos anteriores no se modifican. Textos como `Próximos 7 días` no demuestran
qué semana se predijo, especialmente si hubo una recuperación durante la semana:
no se infieren fechas ni origen. Un resultado anterior que ya tenga exactamente
el identificador semanal de fechas sí evita repetir esa semana. Cuando sólo
existen registros ambiguos, la primera pasada puede guardar un nuevo resultado
explícito para esa semana; no elimina ni reclasifica los anteriores.

## Coordinación y conexiones

Antes de calcular se obtiene `pg_try_advisory_xact_lock(71324, id_producto)`.
El bloqueo es transaccional y no agrega estructura a la base. Si otro proceso
lo tiene, la pasada automática omite ese producto y el pedido manual devuelve 409.
Después de obtenerlo, sólo la automática comprueba el período semanal guardado.
Los pedidos manuales no se consideran una semana completada ni se deduplican por
el texto `Próximos N días`.

**Se mantiene una conexión del pool durante lectura, entrenamiento y guardado.**
Es necesario para que el bloqueo transaccional proteja toda la operación sin
tabla de reservas ni conexión dedicada. Usa un hilo de XGBoost y procesa los
productos secuencialmente. Commit, rollback o desconexión liberan el bloqueo;
no quedan reservas durables de 30 minutos. La conexión se devuelve o descarta al
terminar, también ante errores de rollback o cierre del cursor.

Sin tabla de ejecuciones no hay historial durable de intentos ni estado
`Sin datos` por semana. Los productos sin datos o con errores se vuelven a probar
en la siguiente revisión, mientras que las semanas guardadas no se repiten.

## Algoritmo y consultas

`funciones/predicciones.py` conserva `SolicitudPrediccion` como modelo
interno y `generar_prediccion` con el cálculo original del commit
`dc6bb9eb7fbba72505aeecda3da714bd4c7dd427`: nombres, seis comentarios, preparación,
variables de entrenamiento, parámetros de XGBoost, recursión, límite inferior
cero, total con `ceil` y redondeo diario. No hay otro algoritmo.

Las adaptaciones son el domingo como fecha de referencia, el corte SQL
`v.fecha <= fecha_historial`, el bloqueo y la identificación del período antes
de guardar. La comprobación final de producto activo se conserva. El cálculo
recursivo se ejecuta exactamente siete veces para la semanal o N para el pedido manual, desde el día siguiente al corte.

`main.py` conserva la ruta manual y delega en el mismo cálculo que usa la semanal. Recupera textualmente las funciones
originales `consultar_analisis_producto` y `generar_recomendaciones`.
Recomendaciones toma la última predicción por `fechaPrediccion DESC,
idPrediccion DESC`, sin filtrar origen ni exigir vigencia. Si falta, conserva
las ventas de los últimos 30 días y la fórmula original de reposición.
Generar recomendaciones no entrena ni genera una predicción.

## Cambios intencionales de API

- Se recupera `POST /predicciones/{id_producto}/generar` y `SolicitudPrediccion`
  con la validación original 1–30 y su conversión normal de Pydantic. Administrador
  y Encargado pueden generar; Vendedor recibe 403 y una llamada sin sesión 401.
  Se conservan los campos de respuesta originales: mensaje, IDs, nombre del
  producto, período, cantidad estimada y predicciones diarias. Si el producto está
  ocupado se devuelve 409. No se reincorpora el formulario de Flutter.
- `GET /predicciones/` conserva la consulta protegida de la última predicción
  guardada por producto y sus siete campos básicos. Ya no devuelve `origen`,
  `fechaDesde` o `fechaHasta` desde el registro auxiliar.
- `GET /productos/{id_producto}/analisis` vuelve a la respuesta original del
  historial, sin esos tres metadatos adicionales. Conserva todos los resultados.
- El dashboard muestra el período guardado. Puede reconocer el prefijo semanal
  del texto para presentarlo, sin suponer fechas de resultados ambiguos.
- Se mantienen las demás rutas, autenticación, usuarios y permisos. Quedan
  **31 rutas y 35 operaciones** al recuperar la ruta original manual.

## Primera etapa y verificación

**Etapa posterior completada el 30/10/2026:** la tabla auxiliar fue eliminada
sin CASCADE, después de verificar que sus 13 registros coincidían con el respaldo
completo. Se conservaron las 11 predicciones guardadas y el esquema de las demás
tablas. Se comprobaron las consultas reales de predicciones y análisis de producto.
El respaldo se encuentra fuera del repositorio, en `respaldos-stockia/2026-10-30_12-26-19`.

Se verifican entrenamiento y redondeo originales, semana y cambio de año,
recuperación, duplicados, bloqueo ocupado, errores de lectura y guardado con
pool de una conexión, limpieza, cierre y arranque sin preparar tablas de
predicciones. Flutter verifica consulta y navegación en móvil y escritorio,
sin formulario ni peticiones manuales.

El recorrido real usa tablas temporales originales y rollback: XGBoost comparado
con el original sobre las mismas ventas, bloqueo frente a otra conexión,
repetición de la pasada sin duplicados, historial, última predicción del dashboard
y recomendaciones sin nuevo entrenamiento. No se crea una tabla temporal de
ejecuciones ni se escribe en las tablas reales.

El documento [AJUSTE_PREDICCIONES_ORIGINAL.md](AJUSTE_PREDICCIONES_ORIGINAL.md)
describe la extracción anterior; este documento establece el comportamiento
vigente: automática más ruta manual del backend recuperada, sin formulario ni tabla auxiliar.

Verificación de esta etapa: 104 pruebas de backend y 247 de Flutter aprobadas; análisis estático de Flutter sin problemas. Sin commit ni push.

## Recuperación de la ruta manual

Se verificaron 106 pruebas del backend, incluyendo permisos y validación de 1 a
30 días. Con PostgreSQL y XGBoost reales, los pedidos 1/14/30 se compararon contra
la función original sobre las mismas ventas mediante tablas temporales y rollback.
La automática y su protección entre procesos se verificaron en el mismo recorrido.
No se escribieron predicciones reales ni se modificó el frontend en esta recuperación.
Recomendaciones conserva la regla original de tomar la última predicción guardada,
incluida una manual si es la más reciente; no se cambió esa regla.

## Archivo único de predicciones

La consulta GET, el cálculo y la programación semanal están reunidos en `backend/funciones/predicciones.py`. Se conservaron las funciones, clases, reglas y rutas; sólo cambian su ubicación e imports. No se agregaron tablas ni dependencias.
