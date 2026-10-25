# Organización de StockIA

- [Instalación e inicio](INSTALACION.md).
- [Diagrama de componentes y estructura de archivos](backend/COMPONENTES_ACTUALES.md).

| Carpeta o archivo | Contenido |
| --- | --- |
| `backend/main.py` | Backend original y conexión a la base; se conserva sin cambios |
| `backend/server.py` | Arranque web y registro de los módulos |
| `backend/modules/` | Autenticación, consultas de predicciones y recomendaciones y Observer de alertas |
| `backend/alert_events.py` | Compatibilidad con los imports del backend original |
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
| `iniciar-stockia.ps1` | Inicia backend y web y abre el navegador |
| `iniciar-backend.ps1`, `iniciar-web.ps1`, `compilar-apk.ps1` | Comandos individuales de desarrollo desde la raíz |

El backend web arranca con `server:app`. Se conserva el backend original en
`main.py` y su configuración de base de datos.

Los módulos siguen utilizando `main.obtener_conexion()`. La conexión no se
extrajo a otro archivo. Para preparar sesiones, ejecutar desde `backend/`:

```powershell
.\.venv\Scripts\python.exe -m scripts.init_auth_db
```

## Iniciar la aplicación

Desde la raíz del repositorio, con Python y Flutter ya preparados:

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
