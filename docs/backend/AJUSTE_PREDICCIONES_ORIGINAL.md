# Ajuste de predicciones respecto del main original

> Documento histórico de la extracción anterior. El flujo vigente retira la opción manual y la dependencia de la tabla auxiliar. Ver [PREDICCIONES.md](PREDICCIONES.md).

Fecha: 30/10/2026. Base: `backend/main.py` del commit
`dc6bb9eb7fbba72505aeecda3da714bd4c7dd427`. También se tomó una copia de la
implementación inmediatamente anterior a este ajuste para comparar ambos puntos.

## Extracción, sin cambios del algoritmo

- `main.py` conserva `app`, el decorador, la ruta, el nombre y la firma manual
  `generar_prediccion(id_producto, datos: SolicitudPrediccion)`.
- Su cuerpo importa el módulo `service` y devuelve
  `service.generar_prediccion(id_producto, datos)`. El módulo externo utiliza el
  mismo nombre original. **No se utiliza ningún alias de función ni clase**:
  la calificación por módulo evita la colisión de nombres.
- `SolicitudPrediccion` conserva exactamente la definición original. Se importa
  en `main.py` y vive junto al cálculo, como ya ocurría antes de este ajuste.
- La función externa contiene toda la secuencia original. Se retiraron los
  fragmentos `read_history`, `forecast` y `generate_prediction` de la versión
  previa para evitar nombres alternativos y fragmentación del cuerpo original.
- El bloque desde la validación de las 14 filas hasta el cálculo del total y del
  período coincide textualmente con el original, salvo `date.today()` por
  `fecha_historial`. No cambian entrenamiento, ventanas, parámetros de XGBoost,
  predicción recursiva, límite inferior cero, `ceil` ni redondeo diario.
- Se conservan los seis comentarios originales de la función, los nombres de
  variables originales y los campos originales de la respuesta. Los comentarios
  nuevos explican únicamente préstamos, coordinación y fecha de negocio.

## Diferencias funcionales autorizadas y necesarias

| Aspecto | Original | Ajuste |
| --- | --- | --- |
| Conexión | Una conexión abierta durante toda la operación | Pool; un préstamo para leer y otro para guardar; ninguno durante el entrenamiento |
| Fecha de referencia | `date.today()` del servidor | Fecha de Argentina para manual; domingo cerrado para semanal |
| Historial | Consulta sin límite de fecha; serie hasta hoy | Mismo agrupamiento `v.fecha`, con `AND v.fecha <= %s`; incluye hoy en manual y sólo el domingo cerrado en semanal |
| Origen | Sin registro de ejecuciones | Se conserva el registro Manual/Semanal y su coordinación |
| Semanal | No existía | Mismo cálculo de siete días; lunes a domingo, iniciado tras cerrar el domingo |
| Guardado | Insertar predicción y confirmar | Mismo INSERT, más validación de reserva/producto y confirmación atómica del registro |
| Respuesta manual | Campos originales | Todos conservados, más cinco campos de compatibilidad con la UI actual |
| Errores y limpieza | Rollback y close directos | Mismos errores de negocio y formato 500; limpieza que no omite devolver el préstamo si falla rollback |

El corte SQL evita incorporar ventas posteriores al domingo durante una
recuperación semanal. Para el pedido manual incluye el día actual. La columna
real `VENTA.fecha` se verificó como `date`; no se requiere cambiar su agrupamiento
ni transformar marcas horarias. La consulta de producto y el INSERT de
`PREDICCION_DEMANDA` son textualmente iguales al original. Se conserva
`CURRENT_DATE` configurando localmente la zona horaria de esa transacción.

El proceso separado conserva la pasada al arrancar y cada 30 minutos. Ejecuta la
semana vigente a partir del cierre del domingo; si vuelve tarde conserva el corte
de ese domingo. La selección del momento y el período fue aclarada antes de
modificar la implementación. No se calcula con otro algoritmo para recuperar días.

## Nombres, consultas y respuestas que requieren diferencias

- La función externa añade los argumentos internos `origen`, `clave` y
  `fecha_historial`. No son campos de la petición HTTP ni permiten al cliente
  modificar el origen. `propietario`, `fecha_desde` y `fecha_hasta` son metadatos
  nuevos para la coordinación; no sustituyen variables originales.
- `claim`, `record_failure`, `business_today` y los nombres del proceso semanal
  conservan los nombres de la implementación previa, porque no tenían equivalente
  original. `_revertir`, `_cerrar_recursos` y `_registrar_fallo` son helpers nuevos
  de limpieza. No hay alias de funciones o clases originales.
- La consulta del historial añade únicamente el corte de fecha descrito. Las
  consultas de reserva, confirmación y revalidación del producto no existían en el
  original y se conservan por coordinación.
- A la respuesta original se añaden `activo`, `fechaPrediccion`, `origen`,
  `fechaDesde` y `fechaHasta` para conservar la interfaz actual. Ningún campo
  original se quita o renombra. El formato de `periodoPrediccion` vuelve a
  `Próximos N días` para ambos orígenes.
- El análisis de producto añade un LEFT JOIN al registro de ejecución y esos tres
  metadatos: origen y fechas. Usa los alias de tabla `d` y `e` para distinguir las
  dos columnas `idPrediccion`; no cambia nombres de tablas o columnas. Así, el
  historial distingue origen sin depender del texto del período. Conserva también
  las filas antiguas sin registro.
- No se perdió ningún comentario original de la función de predicción. Se
  conservó el formato del bloque de cálculo y sus consultas originales donde no
  era necesaria una adaptación.

## Frente a la versión inmediatamente anterior

Se reemplaza el enum manual 7/15/30 por el modelo original 1–30; se vuelve a incluir
hoy y desaparece el paso recursivo extra que simulaba hoy sin devolverlo. Se
recuperan el mensaje de éxito, el texto del período y el 500 original. La semanal
ya no etiqueta como hoy una salida que corresponde a mañana. Ver el detalle del
contrato y ejemplos en [PREDICCIONES.md](PREDICCIONES.md).

En `main.py` sólo cambian el cuerpo delegado de `generar_prediccion` y la consulta
y los metadatos del historial de `consultar_analisis_producto`. Las demás
definiciones se compararon por AST y permanecen iguales a la copia previa al
ajuste. No se reorganizó el backend ni se alteraron usuarios, autenticación,
permisos, ventas o generación de recomendaciones.

## Verificación

- Comparación automática del bloque de cálculo, clase, comentarios, consultas y
  campos de respuesta contra el commit original; parámetros de XGBoost iguales.
- Comparación de `main.py` y de OpenAPI contra la copia previa. Se conservan 31
  rutas y 35 operaciones; el único esquema que cambia es `SolicitudPrediccion`.
- Pruebas del pedido HTTP de 1 a 30, límites, falta de datos, producto inactivo,
  permisos, recursión y redondeo, entrenamiento sin préstamo del pool, reservas,
  rechazo de propietario reemplazado y cierre del proceso.
- Pruebas semanales de lunes, mitad de semana, domingo y cambio de año: siempre
  siete días y el mismo domingo cerrado.
- XGBoost y PostgreSQL reales con tablas temporales: pedidos manuales de 1, 14 y
  30 días comparados campo por campo contra la función original ejecutada sobre los
  mismos datos; semanal comparada con el original usando el domingo como fecha.
- Verificación real de prioridad de la semanal sobre una manual nueva, historial
  con ambos orígenes, recomendaciones sin nuevo entrenamiento, rechazo de
  duplicados y recuperación de reservas vencidas. Rollback final, sin modificar
  productos, ventas, predicciones o usuarios reales.
- Suite completa: 109 pruebas de backend y 255 de Flutter aprobadas. Análisis
  estático de Flutter sin problemas.

No se realizaron commit ni push.
