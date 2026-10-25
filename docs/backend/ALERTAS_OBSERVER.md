# Actualización de alertas

El arranque sigue siendo `uvicorn server:app`. No hay dependencias nuevas ni
migraciones de tablas. El aviso funciona mientras la aplicación está abierta.

## Recorrido

1. Una operación de stock llama a `detectar_stock_bajo`. Dentro de su misma
   transacción se publica `pg_notify('stockia_alertas', 'actualizar')`.
2. PostgreSQL entrega la señal después del commit; un rollback no la entrega.
   Las señales idénticas de una misma transacción se agrupan.
3. `AlertEvents` mantiene una conexión `LISTEN` por proceso del backend y avisa
   a sus observadores mediante colas acotadas. Cada proceso recibe la señal,
   incluso si la venta ocurrió en otro proceso.
4. `GET /eventos/alertas` envía señales SSE a Administrador y Encargado. Requiere
   `Authorization: Bearer ...`; no se incluyen tokens en URLs ni datos del
   producto en los eventos. Se revalida sesión/rol cada 15 segundos.
5. Flutter escucha y consulta el listado existente. La campanita, su menú y la
   lista abierta observan el mismo resultado. Las consultas manuales comparten
   la solicitud en curso. Una señal recibida durante una consulta solicita una
   lectura posterior para evitar mostrar un snapshot anterior al commit.

La reposición y el cambio del mínimo también invalidan el listado aunque no
generen una alerta nueva. La baja lógica avisa para quitar alertas ya no vigentes.
Los avisos no cambian de pantalla ni descartan formularios abiertos.

## Conexión y despliegue

`LISTEN` requiere una conexión directa a PostgreSQL o un pooler en modo sesión
(en Supabase, puerto 5432). No usar el modo transacción, puerto 6543. Por defecto
el observador utiliza la URL existente del backend; `ALERTS_DATABASE_URL` permite
configurar una conexión de sesión separada. No hace falta activar Supabase
Realtime ni crear una publicación.

El proxy debe permitir streaming y desactivar buffering para este endpoint.
Se envían latidos cada 15 segundos. Flutter detecta un flujo sin actividad,
reconecta con espera creciente y resincroniza al recuperar la conexión.
La pérdida de señales no afecta los datos guardados: siempre se vuelve a leer
el estado actual. No hay recuperación de eventos individuales ni push con APK
cerrada. La actualización es una señal de invalidación, no un registro durable.

Referencias: [NOTIFY](https://www.postgresql.org/docs/current/sql-notify.html) y
[notificaciones con psycopg2](https://www.psycopg.org/docs/advanced.html#asynchronous-notifications).
