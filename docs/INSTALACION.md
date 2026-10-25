# Instalación e inicio de StockIA

Guía para Windows y PowerShell, con la estructura actual del proyecto.

## 1. Herramientas necesarias

| Herramienta | Uso | Entorno comprobado |
| --- | --- | --- |
| Git | Descargar y actualizar el repositorio | Git para Windows |
| Python | Ejecutar el backend | 3.14.0 |
| Flutter | Ejecutar la web y compilar Android | 3.47.8, con Dart 3.13.7 |
| Navegador | Usar la aplicación web | Chrome o Edge |
| Android Studio, SDK y Java | Solo para desarrollar o probar Android | Ver requisitos del frontend |

Git, Python y Flutter deben estar disponibles en el PATH. Después de instalarlos,
reabrir PowerShell y comprobar:

```powershell
git --version
python --version
flutter --version
flutter doctor -v
```

La instalación de Flutter y Android, sus rutas y versiones están detalladas en
[Requisitos de desarrollo del frontend](../frontend/requirements-dev.md).

También se necesita acceso a la base Supabase del proyecto y una cuenta de
StockIA. La conexión ya está configurada en el backend. Las tablas de negocio
deben existir: la preparación de sesiones no crea una base completa desde cero.

## 2. Descargar el proyecto

Desde la carpeta donde se quiera guardar:

```powershell
git clone --branch integracion-front-back https://github.com/GonzaloEduardoGil/StockIA.git
cd StockIA
```

Si el repositorio es privado, Git solicitará autenticarse con una cuenta que
tenga acceso. Si ya se dispone de la carpeta, abrir PowerShell en esa carpeta
y continuar sin volver a clonar.

## 3. Instalar el backend

Desde la raíz `StockIA/`:

```powershell
python -m venv backend\.venv
.\backend\.venv\Scripts\python.exe -m pip install -r backend\requirements.txt
```

Los comandos usan directamente el Python del entorno virtual; no es necesario
activarlo en la terminal.

### Preparación de sesiones

Si la base del proyecto todavía no tiene preparada la autenticación, ejecutar
una vez desde `StockIA/backend/`:

```powershell
cd backend
.\.venv\Scripts\python.exe -m scripts.init_auth_db
cd ..
```

Aplica `backend/sql/auth_schema.sql`: crea sesiones e índice si faltan, activa
RLS y restringe el acceso público a usuarios y sesiones. Requiere la conexión
de servicio del backend. No crea usuarios ni modifica sus contraseñas.

En la base que ya se preparó para este proyecto, este paso ya está realizado.
Los accesos de las cuentas se comparten por separado; no están guardados en Git.

Más detalles: [Autenticación](backend/AUTH_SETUP.md).

## 4. Instalar las dependencias del frontend

Desde la raíz `StockIA/`:

```powershell
cd frontend
flutter pub get
cd ..
```

Se conserva `pubspec.lock` para reproducir las versiones del proyecto.

## 5. Iniciar todo con un comando

Desde la raíz `StockIA/`:

```powershell
.\iniciar-stockia.ps1
```

El script inicia la API y Flutter web, espera la compilación y abre la página:

| Servicio | Dirección |
| --- | --- |
| Aplicación web | http://127.0.0.1:5173/ |
| API | http://127.0.0.1:8000/ |
| Documentación de la API | http://127.0.0.1:8000/docs |

Mantener la terminal abierta. **Ctrl+C** detiene los procesos que inició ese
comando. Si encuentra servicios del proyecto ya encendidos, los reutiliza y no
los detiene al salir. Si los puertos pertenecen a otra aplicación, informa el
conflicto. Los logs quedan en `.stockia/logs/`, excluidos de Git.

Para no abrir otra pestaña del navegador:

```powershell
.\iniciar-stockia.ps1 -NoAbrirNavegador
```

## 6. Iniciar cada parte por separado

Desde la raíz, abrir dos terminales.

**Terminal 1 — backend:**

```powershell
.\iniciar-backend.ps1
```

**Terminal 2 — frontend:**

```powershell
.\iniciar-web.ps1
```

Abrir http://127.0.0.1:5173/. En este modo cada terminal controla su servicio.

Para un backend alojado en otra dirección:

```powershell
.\iniciar-web.ps1 -ApiUrl 'https://TU_BACKEND'
```

El backend debe permitir el origen de la web mediante `CORS_ORIGINS`. Por
defecto admite `http://localhost:5173` y `http://127.0.0.1:5173`.

## 7. Generar la APK de desarrollo

Con las herramientas Android instaladas, desde la raíz:

```powershell
.\compilar-apk.ps1
```

El archivo se genera en:

```text
frontend/build/app/outputs/flutter-apk/app-debug.apk
```

La configuración predeterminada de esa APK usa `http://10.0.2.2:8000` para
acceder al backend del equipo desde el emulador. Para probarla, dejar el backend
encendido y tener el emulador abierto. Para un backend público:

```powershell
.\compilar-apk.ps1 -ApiUrl 'https://TU_BACKEND'
```

Para un celular físico en la misma red, indicar una IP accesible del equipo en
`-ApiUrl` y arrancar la API con `.\iniciar-backend.ps1 -HostApi '0.0.0.0'`.
La red y el firewall deben permitir esa conexión. La APK generada es de depuración.

## 8. Ejecutar las pruebas

**Backend**, desde la raíz:

```powershell
.\backend\.venv\Scripts\python.exe -m pip install -r backend\requirements-dev.txt
cd backend
.\.venv\Scripts\python.exe -m unittest discover -s tests -p "test_*.py"
cd ..
```

**Frontend**, desde la raíz:

```powershell
cd frontend
flutter test
flutter analyze
cd ..
```

Las pruebas automatizadas del backend no necesitan cuentas ni conexión a la
base real. Los tests de Flutter están agrupados por módulo en `frontend/test/`.

## 9. Ejecutar solo el backend en un servicio web

Configurar `backend/` como directorio raíz del servicio.

**Instalación:**

```bash
pip install -r requirements.txt
```

**Arranque en una plataforma Linux que define `PORT`:**

```bash
uvicorn server:app --host 0.0.0.0 --port $PORT
```

Si la plataforma define el puerto de otra forma, adaptar ese argumento.
El despliegue usa `server:app`, que incluye autenticación y Observer. Los `.ps1`
son herramientas locales de Windows; el servicio ejecuta Uvicorn directamente.

Configurar `CORS_ORIGINS` con la URL pública de la web. El frontend se compila
apuntando a la API pública mediante `API_BASE_URL`; por ejemplo, desde `frontend/`:

```powershell
flutter build web --dart-define=API_BASE_URL=https://TU_BACKEND
```

Para las alertas, el alojamiento debe permitir streaming SSE sin buffering.
LISTEN requiere conexión PostgreSQL directa o pooler en modo sesión; se puede
indicar una conexión separada mediante `ALERTS_DATABASE_URL`. Para el despliegue
usar HTTPS en la dirección pública del backend.

Detalle del mecanismo: [Observer de alertas](backend/ALERTAS_OBSERVER.md).
Diagrama del proyecto: [Componentes actuales](backend/COMPONENTES_ACTUALES.md).
