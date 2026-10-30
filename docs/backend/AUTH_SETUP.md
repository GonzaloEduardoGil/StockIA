# Acceso de StockIA

El servicio web se inicia con `uvicorn server:app`, que reexporta la aplicación
de `main.py`. `main:app` también está protegido. La aplicación incluye
la autenticación, los permisos y CORS. Las rutas de login/logout están en
`acceso/autenticacion.py`; las sesiones, hashes y permisos compartidos están reunidos
en ese mismo archivo. Usuarios y alertas reutilizan sus funciones.

Preparación del entorno del backend:

Ejecutar estos comandos desde `backend/`.

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m scripts.init_auth_db
.\.venv\Scripts\python.exe -m uvicorn server:app --host 127.0.0.1 --port 8000
```

`scripts/init_auth_db.py` aplica `sql/auth_schema.sql`: crea la tabla de sesiones y su índice si no existen. Activa RLS
y revoca el acceso de los roles públicos de Supabase a usuarios y sesiones;
el backend continúa usando la conexión de servicio del proyecto, gestionada
por `sistema/database.py`. El pool no almacena la identidad del usuario y la
sesión y los permisos se siguen verificando en cada petición.
No crea usuarios ni cambia cuentas, roles o contraseñas. El login usa el email y
la contraseña de `USUARIO`. Una contraseña anterior se convierte a Argon2 al
autenticarse correctamente, conservando la misma clave.

Las sesiones vencen a las ocho horas, se revocan al salir y el cliente mantiene
el token solamente en memoria. Recargar/cerrar la aplicación requiere ingresar
de nuevo. Las credenciales no se guardan en almacenamiento del navegador.

Los permisos del servidor corresponden a los actores de los CU. Administrador
gestiona productos; Encargado y Administrador gestionan stock, alertas, análisis
y recomendaciones; Vendedor registra ventas. Todos consultan stock y ventas.
La API verifica que el usuario enviado al registrar ventas y recomendaciones
coincida con la sesión. El encargado decide sus recomendaciones y el
administrador puede decidir cualquiera, según el backend original.

Pruebas sin cuentas reales:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m unittest discover -s tests -p "test_*.py"
```

## Estado y cambios administrativos

`USUARIO.activo` permite la baja lógica. El estado se agrega con valor inicial
verdadero mediante `sql/user_management_schema.sql` al iniciar el servidor o
mediante el script de preparación de autenticación. No se borran usuarios ni
se modifican sus claves durante esa preparación.

El login bloquea la fila de usuario hasta emitir su sesión y comprobar que
continúa activo. Las modificaciones de acceso usan el mismo bloqueo. Desactivar,
restablecer contraseña o cambiar efectivamente el rol revoca las sesiones de esa
cuenta en la misma transacción. Reactivar requiere un login nuevo.

Administradores sólo pueden gestionar Encargado de stock y Vendedor; el cambio propio está
disponible para los tres roles desde Mi cuenta, validando la clave actual y
cerrando todas sus sesiones al confirmar. Ver [gestión de usuarios](USUARIOS.md).

`POST /auth/password` es una operación autenticada para cualquier rol válido.
La identidad procede del token, no del cuerpo. Verifica de nuevo sesión y cuenta
activa bajo bloqueo antes de comprobar la clave actual. Una clave actual
incorrecta devuelve 400; 401 queda reservado para una sesión inválida. Usa un
limitador de intentos separado del login y no devuelve claves ni hashes.
No requiere nuevas dependencias ni cambios de esquema.
