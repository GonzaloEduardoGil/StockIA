# Acceso de StockIA

El servicio web se inicia con `uvicorn server:app`. Este punto de entrada incluye
la autenticación, los permisos y CORS. `main.py` conserva las funciones originales
del proyecto y no es el punto de arranque de la aplicación web autenticada.

Preparación del entorno del backend:

Ejecutar estos comandos desde `backend/`.

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m scripts.init_auth_db
.\.venv\Scripts\python.exe -m uvicorn server:app --host 127.0.0.1 --port 8000
```

`scripts/init_auth_db.py` aplica `sql/auth_schema.sql`: crea la tabla de sesiones y su índice si no existen. Activa RLS
y revoca el acceso de los roles públicos de Supabase a usuarios y sesiones;
el backend continúa usando su conexión de servicio original.
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
