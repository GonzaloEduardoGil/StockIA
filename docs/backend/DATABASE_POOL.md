# Conexiones a PostgreSQL

`backend/sistema/database.py` centraliza la configuración y el acceso a la base.
`main.py`, las funcionalidades, autenticación y seguridad utilizan el mismo pool por proceso.
Se conservó el valor de la URL existente al reorganizar el backend. Los helpers
de transacción, rollback y cierre también se centralizan aquí.

## Funcionamiento

- El pool se prepara en el lifespan de `server:app` y precalienta una conexión.
  Si la base no responde, se registra un aviso genérico y las siguientes
  peticiones pueden volver a intentar obtener conexión.
- Se abren conexiones según la demanda hasta el límite configurado. Un préstamo
  queda reservado durante su uso y limpieza; nunca se entrega a dos operaciones.
- `close()` devuelve el préstamo una sola vez. La conexión y sus cursores dejan
  de poder utilizarse mediante referencias anteriores, incluso métodos guardados.
- Al devolver se cierran cursores, se revierte cualquier transacción pendiente,
  se restablecen las opciones del cliente psycopg y se ejecuta `DISCARD ALL` fuera
  de una transacción. Se eliminan timeouts, estado de sesión, objetos temporales
  y cambios de rol. Se limpian también los avisos pendientes del driver. Luego
  se vuelve al modo transaccional normal.
- Si falla la limpieza o la conexión está rota, se descarta. Una conexión que
  estuvo inactiva durante 30 segundos se verifica antes de prestarse. No se
  repiten automáticamente escrituras ante una desconexión.
- El cierre del servicio cierra las conexiones libres. Un préstamo que todavía
  estuviera activo se cierra al devolverse, sin interrumpir su operación.

## Configuración

| Variable | Valor inicial | Significado |
| --- | --- | --- |
| `DB_POOL_MAX_SIZE` | `5` | Máximo de conexiones por proceso para peticiones |
| `DB_POOL_WAIT_SECONDS` | `3` | Espera máxima cuando todos los préstamos están ocupados |
| `ALERTS_DATABASE_URL` | Conexión del proyecto | Conexión opcional separada para LISTEN |

Por ejemplo, desde PowerShell, antes de iniciar:

```powershell
$env:DB_POOL_MAX_SIZE = '5'
$env:DB_POOL_WAIT_SECONDS = '3'
.\iniciar-backend.ps1
```

Los handlers con SQL siguen siendo síncronos y FastAPI los ejecuta en su
threadpool. La autenticación ya usa `run_in_threadpool`, al igual que el inicio
y cierre del pool. La espera usa una condición de hilos y no bloquea el event
loop de ASGI. No llamar a este acceso síncrono directamente desde un handler
`async def`; en ese caso debe derivarse al threadpool.

La espera máxima se refiere al pool ocupado. Abrir una nueva conexión tiene
su propio timeout de red de 10 segundos. Los endpoints mantienen su manejo de
errores y no se modificaron sus contratos.

## Sesiones y Observer

Las sesiones de usuario son independientes de las conexiones PostgreSQL. Cada
petición sigue consultando y validando su token y rol; no se agregó caché de
autenticación. Los tokens y permisos no se guardan en las conexiones del pool.

El Observer mantiene su conexión LISTEN dedicada, fuera del pool. Con un proceso
hay como máximo cinco conexiones de peticiones más una del Observer; con varios
procesos se multiplica ese límite. Considerar también conexiones de scripts y
otras herramientas al dimensionar el servicio.

## Pruebas

Desde `backend/`:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -p "test_*.py"
```

`tests/test_database.py` comprueba concurrencia, espera limitada, limpieza,
lectura seguida de escritura, préstamos ya devueltos, fallas y cierre. También
simula desconexiones durante el rollback de predicciones, recomendaciones y
validación de sesión: debe liberarse la plaza y conservarse el resultado o error
original de la consulta. La
validación con PostgreSQL real se realiza por separado: la venta de prueba se
revierte y se verifica que el stock original se conserve.

## Medición local del 29/10/2026

Comparación con el diagnóstico anterior, con el pool ya disponible. Los valores
actuales de consultas son la mediana de dos lecturas HTTP por endpoint.

| Operación | Antes | Con pool |
| --- | --- | --- |
| Validación de sesión `/auth/me` | 1308 ms | 567 ms |
| Stock | 2435 ms | 1136 ms |
| Productos | 2440 ms | 1132 ms |
| Dashboard | 2872 ms | 1563 ms |
| Alertas | 2439 ms | 1133 ms |
| Predicciones guardadas | 2738 ms | 1272 ms |

El login pasó de 1601 ms en el diagnóstico a 827–984 ms en las tres cuentas
usadas para esta prueba. Tres sesiones concurrentes completaron sus consultas
con identidades y permisos correctos; cerrar una no invalidó las demás.

Estos tiempos son de la API local con PostgreSQL remoto. El arranque del pool
y las conexiones nuevas tienen un costo inicial. La descarga y compilación de
Flutter en modo debug sigue siendo un problema separado; no se modificó el
frontend en este cambio.

Referencias de comportamiento del driver:
[set_session de psycopg2](https://www.psycopg.org/docs/connection.html#connection.set_session)
y [DISCARD de PostgreSQL](https://www.postgresql.org/docs/current/sql-discard.html).
