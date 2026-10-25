# Organización de StockIA

| Carpeta o archivo | Contenido |
| --- | --- |
| `backend/` | API Python, autenticación, consultas y Observer de alertas |
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
| `iniciar-backend.ps1`, `iniciar-web.ps1`, `compilar-apk.ps1` | Comandos de desarrollo desde la raíz |

El backend web arranca con `server:app`. Se conserva el backend original en
`main.py` y su configuración de base de datos.

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
