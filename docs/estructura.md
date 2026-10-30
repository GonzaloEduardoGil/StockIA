# Organización de StockIA

- [Instalación e inicio](INSTALACION.md).
- [Diagrama de componentes y estructura de archivos](backend/COMPONENTES_ACTUALES.md).

| Carpeta o archivo | Contenido |
| --- | --- |
| `backend/main.py` | Código original de productos, stock, movimientos, ventas, alertas, dashboard y recomendaciones, integrado con los módulos actuales |
| `backend/sistema/` | Infraestructura y configuración compartidas |
| `backend/acceso/` | Autenticación, sesiones, permisos y administración de usuarios |
| `backend/funciones/` | Predicciones, consulta de recomendaciones y avisos de alertas |
| `backend/sistema/database.py` | Configuración de la base, pool compartido y conexión dedicada del Observer |
| `backend/server.py` | Entrada compatible: reexporta la aplicación autenticada de main.py |
| `backend/sistema/bootstrap.py` | Registro de módulos, seguridad, CORS y ciclos de vida sobre la misma aplicación |
| `backend/sistema/validation.py` | Validación compartida de contraseñas y errores sin datos privados |
| `backend/acceso/autenticacion.py` | Login, contraseñas, sesiones y permisos |
| `backend/acceso/usuarios.py` | Gestión de usuarios por el administrador |
| `backend/funciones/predicciones.py` | Consulta, cálculo y programación semanal de predicciones |
| `backend/funciones/alertas.py` | Publicación de cambios, Observer y SSE |
| `backend/scripts/` | Preparación del backend mediante comandos de desarrollo |
| `backend/tests/` | Pruebas automatizadas sin acceso a la base real |
| `backend/sql/` | SQL de preparación de sesiones |
| `frontend/lib/` | Aplicación Flutter: datos, modelos, pantallas y widgets |
| `frontend/test/` | Pruebas agrupadas por inventario, movimientos, ventas, alertas, análisis, recomendaciones y autenticación |
| `frontend/test/helpers/` | Utilidades compartidas de las pruebas |
| `frontend/android/`, `frontend/web/` | Configuración de las plataformas |
| `frontend/assets/` | Fuentes y otros recursos de la aplicación |
| `docs/backend/` | Preparación del login y funcionamiento del Observer |
| `frontend/requirements-dev.md` | Herramientas necesarias para desarrollar y compilar Flutter |
| `referencias/frontend-react/` | Front anterior conservado como referencia |
| `requirements.txt` | Dependencias Python instalables desde la raíz |
| `instalar.ps1` | Prepara el entorno Python e instala las dependencias del backend y de Flutter |
| `iniciar-stockia.ps1` | Inicia backend y web y abre el navegador |
| `iniciar-backend.ps1`, `iniciar-web.ps1`, `compilar-apk.ps1` | Comandos individuales de desarrollo desde la raíz |

El backend web arranca con `server:app`. La conexión se centraliza en
`sistema/database.py`, conservando el valor de la URL configurada.

El backend y los módulos utilizan el mismo pool por proceso. La autenticación
y las consultas utilizan `sistema/` sin depender del punto de arranque. Ver [pool de conexiones](backend/DATABASE_POOL.md).
Para preparar sesiones, ejecutar desde `backend/`:

```powershell
.\.venv\Scripts\python.exe -m scripts.init_auth_db
```

## Iniciar la aplicación

Desde la raíz del repositorio, con Python y Flutter instalados, preparar las
dependencias una vez:

```powershell
.\instalar.ps1
```

Después iniciar la aplicación:

```powershell
.\iniciar-stockia.ps1
```

Inicia la API en el puerto 8000 y Flutter web en el 5173. Espera a que ambos
respondan antes de abrir `http://127.0.0.1:5173/` en el navegador predeterminado.
Mantener la terminal abierta; Ctrl+C detiene los servicios que inició el comando.
Si ya hay servicios de este proyecto en esos puertos, los reutiliza y no los
detiene al salir. Si los puertos pertenecen a otra aplicación, informa el conflicto.
Los logs quedan en `.stockia/logs/`, fuera del control de versiones.

Para iniciar sin abrir otra pestaña: `.\iniciar-stockia.ps1 -NoAbrirNavegador`.

## Pruebas

Desde `backend/`, con las dependencias de `requirements-dev.txt` instaladas:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -p "test_*.py"
```

Desde `frontend/`:

```powershell
flutter test
flutter analyze
```

Las carpetas de compilación, cachés, entornos virtuales y logs no se versionan.
Los datos de acceso de prueba se conservan fuera de este repositorio.

## Predicciones automáticas semanales

La consulta, el cálculo y la programación semanal están reunidos en
`backend/funciones/predicciones.py`. El dashboard permite
consultar los resultados guardados por producto. La generación es automática; no utiliza tablas auxiliares. Ver [funcionamiento y configuración](backend/PREDICCIONES.md).

## Gestión de usuarios

El alta, edición de identidad y listado exclusivos del administrador están en backend/acceso/usuarios.py y frontend/lib/screens/users_screen.dart. Ver [uso y validaciones](backend/USUARIOS.md).
