# Gestión de usuarios

El administrador dispone de **Usuarios** en el menú. Puede consultar las cuentas
de encargados y vendedores y crear una nueva con nombre, email, rol, contraseña
y confirmación. Sólo se ofrecen **Encargado de stock** y **Vendedor**. Cada fila incluye **Editar**, que reutiliza el formulario para cambiar
únicamente nombre y email. El rol se muestra como dato de consulta y no se
piden contraseñas al editar. El menú de acceso permite desactivar/reactivar, restablecer contraseñas y cambiar
entre los dos roles operativos. Los tres roles también pueden cambiar su propia contraseña desde **Mi cuenta**.

La contraseña admite entre 8 y 1024 caracteres y debe coincidir con su
confirmación. Se guarda con el mismo Argon2 del login. No aparece en el listado,
en la respuesta del alta ni en los errores de validación. El formulario la
oculta y limpia sus campos tras el alta o al cancelar.

El email se valida con `email-validator`, se recorta y se convierte a minúsculas.
Se aceptan direcciones válidas sin comprobar la existencia del buzón ni enviar
emails. No se usa Supabase Auth: las cuentas utilizan el login propio de StockIA.

## Servidor y base

- `GET /usuarios/`: devuelve ID, nombre, email y rol de encargados y vendedores.
- `POST /usuarios/`: crea una cuenta y devuelve únicamente esos datos públicos.
- `PATCH /usuarios/{id}/`: actualiza únicamente nombre y email de un encargado
  o vendedor existente. Rechaza rol, contraseña, confirmación y campos adicionales;
  no permite editar administradores. Comprueba duplicados excluyendo al propio
  usuario y conserva la unicidad sin distinguir mayúsculas.
- `PATCH /usuarios/{id}/estado`: recibe `activo` como booleano real. La baja es
  lógica: conserva ID, cuenta e historial. Desactivar elimina sus sesiones y el
  login rechaza la cuenta. Reactivar no recupera tokens anteriores.
- `POST /usuarios/{id}/password`: recibe contraseña y confirmación, valida los
  mismos límites del alta, guarda Argon2 y elimina las sesiones anteriores.
  No modifica el estado activo ni el rol y no devuelve claves ni hashes.
- `PATCH /usuarios/{id}/rol`: sólo acepta Encargado de stock o Vendedor. Un
  cambio efectivo revoca las sesiones para que el próximo login cargue los
  permisos nuevos. Repetir el rol actual no hace cambios ni revoca sesiones.
- Todas las rutas requieren una sesión de Administrador en el middleware y también
  en una dependencia de las propias rutas. El rol enviado en el alta no puede
  ser Administrador; los campos adicionales se rechazan.
- Al iniciar `server:app` se prepara el índice único
  `stockia_usuario_email_ci` sobre `lower(btrim(email))`. La misma preparación
  aplica `sql/user_management_schema.sql`: agrega `USUARIO.activo` con valor
  inicial verdadero para conservar el acceso de las cuentas existentes. Si falla, no impide
  iniciar el resto de la aplicación y el alta vuelve a intentarlo; nunca se
  eliminan duplicados existentes automáticamente.
- La tabla actual no tiene secuencia para `idUsuario`. El alta toma brevemente
  un bloqueo de escritura sobre USUARIO y asigna `MAX(idUsuario)+1` dentro de la
  misma transacción. Argon2 se calcula antes del bloqueo. La espera está limitada
  a tres segundos y las sentencias a diez segundos.
- El índice evita duplicados aun entre procesos. El doble clic se bloquea en la
  interfaz y una repetición con el mismo email devuelve 409. Ante una respuesta
  incierta se exige actualizar el listado antes de reintentar.

La dependencia nueva se instala con `instalar.ps1` o los requirements habituales;
no hace falta un comando de instalación separado. Las cuentas existentes no se
modifican al preparar el índice. Iniciar el proyecto con `server:app`.

## Pruebas

Las pruebas del backend verifican restricciones de roles, validaciones sin
exponer contraseñas, normalización y unicidad de email, Argon2, liberación de
conexiones y compatibilidad con el login. Flutter verifica el formulario, los
errores, doble envío, resultado incierto, menú por rol y ancho móvil.

La verificación adicional con PostgreSQL usa tablas temporales y una transacción
que se revierte: crea ambos roles, inicia sesión con cada uno y comprueba que
pueden realizar únicamente las operaciones permitidas. No deja cuentas de prueba
ni cambia ventas o stock.

El listado conserva las altas confirmadas cuando termina una lectura iniciada antes del alta. Las respuestas superadas por otra actualización se descartan; una lectura anterior tampoco habilita reintentos de un alta con resultado incierto. Estas condiciones tienen pruebas con respuestas demoradas.

## Edición de identidad

La edición conserva ID, rol y hash de contraseña. El usuario ingresa con el
nuevo email y su contraseña habitual; el email anterior deja de servir para
nuevos ingresos. Las sesiones ya abiertas conservan su validez porque están
asociadas al ID, y el servidor consulta la identidad actual en cada petición.

Un resultado incierto de edición exige actualizar el listado antes de volver
a guardar. Las revisiones del listado conservan también ediciones confirmadas
frente a respuestas antiguas. Cancelar no escribe cambios.

Las pruebas incluyen permisos, cuentas protegidas, campos no editables, email
propio y duplicado, cancelación, ancho móvil y respuesta vieja tras editar. La
verificación con tablas temporales PostgreSQL compara el hash antes y después,
comprueba el ingreso con el email nuevo y la validez de la sesión anterior.

## Administración de acceso

El listado muestra **Activo/Inactivo**. Junto a Editar, el menú de tres puntos
ofrece Desactivar o Reactivar, Restablecer contraseña y Cambiar rol. Las acciones
piden confirmación o los datos correspondientes. Mientras se guardan se bloquea
el doble envío; un resultado incierto exige actualizar antes de reintentar.
Las respuestas viejas tampoco deben revertir un estado o rol ya confirmado.

Estas acciones sólo pueden afectar encargados y vendedores. Ninguna permite
crear administradores ni modificar sus cuentas mediante estas rutas. El
administrador cambia su propia contraseña por el flujo de Mi cuenta. No se elimina historial ni se reasignan IDs.

Login y cambios de acceso bloquean la misma fila de usuario. Así, una emisión
de token concurrente se completa antes de su revocación o lee el estado/clave
nuevos; no queda una sesión emitida con el estado anterior después del cambio.
La actualización y eliminación de sesiones se confirman en una transacción.
Si falla la revocación se revierte también el cambio de la cuenta.

La validación de sesiones filtra `activo = TRUE` en cada petición. Las sesiones
revocadas devuelven 401 y Flutter vuelve al login en su siguiente solicitud; el
canal de alertas también revalida periódicamente la sesión. Esto no cancela
operaciones que el servidor ya había autorizado antes de confirmar el cambio.

El arranque prepara el esquema antes de aceptar solicitudes. El script
`python -m scripts.init_auth_db` también agrega el estado activo si falta. Si
falla la preparación de la base, revisar permisos y logs; no se usa una
alternativa que omita la comprobación de cuenta activa.

Las verificaciones adicionales cubren los dos roles, bloqueo de login inactivo,
no recuperación de tokens al reactivar, claves antiguas rechazadas después del
reset, permisos nuevos tras cambiar rol, administradores protegidos y rollback
atómico ante un fallo. Las pruebas con PostgreSQL usan tablas temporales y se
revierten por completo, sin modificar usuarios reales.

## Cambio de contraseña propio

Disponible para Administrador, Encargado de stock y Vendedor desde **Mi cuenta →
Cambiar mi contraseña**. Pide la clave actual, una nueva de entre 8 y 1024
caracteres, distinta de la anterior, y su confirmación. Todos los campos están
ocultos. No exige intervención de un administrador.

`POST /auth/password` recibe `passwordActual`, `password` y `confirmacion`. No
acepta ID de usuario, email, rol ni campos adicionales: la cuenta se toma de la
sesión. Revalida que la cuenta esté activa y que el token siga vigente después
de tomar el bloqueo de fila compartido con login y cambios administrativos.
Esto respeta una revocación ocurrida después del middleware.

La verificación de clave actual, actualización Argon2 y eliminación de todas
las sesiones de esa cuenta se realizan en una sola transacción. Si falla la
revocación, se revierte también la clave. Nombre, email, rol, estado e historial
no cambian. El hash nuevo se calcula antes de adquirir conexión. El cambio
admite las contraseñas anteriores compatibles con el login.

Una clave actual incorrecta devuelve 400, conserva la sesión y permite corregir.
Se limitan los intentos con la misma política del login, en un contador separado.
Al confirmar el cambio se vuelve al login; las sesiones de otros dispositivos
tampoco pueden seguir usando los tokens anteriores.

Ante un resultado incierto, el formulario impide repetir automáticamente y
ofrece volver a ingresar. Una respuesta tardía no cierra una sesión que haya
reemplazado la original. Los errores de validación no reflejan valores de entrada
ni contraseñas. La validación compartida está en `sistema/validation.py`, sin
dependencias entre las funcionalidades de autenticación y usuarios.

Las pruebas cubren los tres roles, clave actual incorrecta, confirmación,
intentos limitados, revocación entre autorización y guardado, rollback,
resultado incierto y respuestas tardías. El recorrido PostgreSQL usa tablas
temporales y se revierte; no cambia contraseñas ni cuentas reales.
