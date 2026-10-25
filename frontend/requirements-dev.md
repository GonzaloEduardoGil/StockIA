# Requisitos de desarrollo del frontend de StockIA

El frontend actual utiliza **Flutter para web y Android**. Este archivo describe
las herramientas que debe tener cada desarrollador; no se instala con `pip`.
Las librerías de Dart están en `pubspec.yaml` y sus versiones resueltas en
`pubspec.lock`. El frontend React anterior está en `referencias/frontend-react/`.

## Herramientas

| Herramienta | Para qué se necesita | Versión utilizada y comprobada |
| --- | --- | --- |
| Git | Descargar el repositorio y trabajar con ramas | Git para Windows |
| Flutter SDK, canal estable | Desarrollar y compilar web y Android | **3.47.8** |
| Dart | Lenguaje de la aplicación; viene incluido con Flutter | **3.13.7** |
| VS Code con extensiones Flutter y Dart | Editor recomendado | Extensiones `Dart-Code.flutter` y `Dart-Code.dart-code` |
| Chrome o Edge | Ejecutar y probar la versión web | Navegador instalado |
| Android Studio | Herramientas de Android y Java incluido | Rabbit 1 / 2026.2.1 |
| Java de Android Studio (JBR) | Compilar Android | OpenJDK **25.0.3**, incluido con la instalación comprobada |
| Android SDK Platform | Plataforma contra la que compila la aplicación | **Android 16 / API 36** |
| Android SDK Build-Tools | Herramientas para construir la APK | **36.0.0** |
| Android SDK Platform-Tools | `adb`, instalación y depuración en dispositivos | **37.0.1** |
| Android SDK Command-line Tools | Administrar el SDK y sus licencias | Paquete instalado desde Android Studio / SDK Manager |
| Android NDK | Compilación nativa de Flutter para Android | **28.2.13676358** |
| CMake | Herramienta de compilación nativa del entorno instalado | **3.22.1** |

Estas son las versiones con las que se compiló este proyecto, no una afirmación
de que cualquier versión anterior o posterior sea compatible. Para reproducir el
entorno, usar la misma versión de Flutter y conservar `pubspec.lock`.

Para trabajar **solo en web**, no hace falta instalar Android Studio ni el SDK
de Android. Para probar Android, se necesita un teléfono físico o un emulador.

Gradle **9.3.1**, Android Gradle Plugin **9.1.0** y Kotlin **2.4.0** están definidos
en el proyecto. Gradle y los complementos se descargan automáticamente al
compilar; no hace falta instalarlos por separado.

No se necesita Node.js ni npm para este frontend Flutter. Visual Studio con C++
corresponde a aplicaciones de escritorio Windows, que este proyecto no genera.

## Preparar el equipo en Windows

1. Instalar [Git](https://git-scm.com/downloads/win).
2. Instalar [Flutter](https://docs.flutter.dev/install/manual) y agregar su carpeta
   `bin` al PATH. Dart ya viene incluido. Conviene guardar el SDK en una carpeta
   sin espacios, por ejemplo `C:\Users\TU_USUARIO\develop\flutter`.
3. Instalar [VS Code](https://code.visualstudio.com/) y la extensión Flutter,
   que también instala la extensión Dart:

   ```powershell
   code --install-extension Dart-Code.flutter
   ```

4. Para Android, instalar [Android Studio](https://developer.android.com/studio)
   y seleccionar los componentes de la tabla desde **SDK Manager**. Usar el Java
   incluido en Android Studio; una instalación antigua de Java 8 no sustituye a
   ese entorno.
5. Si Flutter no encuentra el SDK o Java, indicar sus rutas reales. Ejemplo para
   las ubicaciones predeterminadas de Android Studio:

   ```powershell
   flutter config --android-sdk "$env:LOCALAPPDATA\Android\Sdk"
   flutter config --jdk-dir 'C:\Program Files\Android\Android Studio\jbr'
   ```

6. Revisar y aceptar las licencias necesarias del SDK:

   ```powershell
   flutter doctor --android-licenses
   ```

7. Reabrir la terminal y VS Code después de modificar el PATH. Verificar:

   ```powershell
   flutter --version
   dart --version
   flutter doctor -v
   ```

La comprobación debe reconocer Flutter y el navegador; para generar APK también
debe reconocer la cadena de herramientas de Android.

### Ubicaciones de este equipo

En el equipo donde se preparó el proyecto se utilizaron estas ubicaciones:

```text
Flutter:       C:\Users\ELEVEN\develop\flutter
Android SDK:   C:\Users\ELEVEN\develop\android-sdk
Java:          C:\Program Files\Android\Android Studio\jbr
```

Cada desarrollador debe configurar sus propias rutas. `android/local.properties`
es local y está excluido de Git; no se deben copiar las rutas de otro equipo.

## Instalar las librerías del proyecto

Desde la raíz del repositorio:

```powershell
.\instalar.ps1
```

Este comando prepara el backend y ejecuta `flutter pub get` en el frontend.
Para trabajar únicamente con Flutter, también se puede hacer por separado:

```powershell
cd frontend
flutter pub get
flutter analyze
flutter test
```

Las pruebas están en `test/`, agrupadas por módulo. Las utilidades compartidas
están en `test/helpers/`. `flutter test` ejecuta todos los grupos; para uno solo,
por ejemplo, usar `flutter test test/alerts/`.

`flutter pub get` instala `http`, las herramientas de pruebas y las demás
dependencias declaradas. No hace falta un `requirements.txt` de Python dentro
del frontend. Al descargar el proyecto por primera vez se necesita conexión para
obtener los paquetes y las herramientas de compilación.

## Ejecutar y conectar con el backend

Para iniciar todo y abrir el navegador, desde la raíz del repositorio:

```powershell
.\iniciar-stockia.ps1
```

El comando espera a que la API y la web estén listas. Mantener la terminal
abierta y usar Ctrl+C para detener los servicios que inició. Reutiliza los
servicios del proyecto que ya estén ejecutándose. Los logs se guardan en
`.stockia/logs/`. Con `-NoAbrirNavegador` no abre otra pestaña.

También se pueden iniciar por separado:

El backend se ejecuta por separado y tiene sus propias dependencias en
`backend/requirements.txt`. Para consultar datos reales debe estar encendido.

Desde la raíz del repositorio, en una terminal:

```powershell
.\iniciar-backend.ps1
```

En otra terminal, también desde la raíz:

```powershell
.\iniciar-web.ps1
```

Abrir `http://127.0.0.1:5173/`. El script web utiliza
`http://127.0.0.1:8000` como dirección predeterminada de la API. Para otra API:

```powershell
.\iniciar-web.ps1 -ApiUrl 'https://TU_BACKEND'
```

El backend debe permitir el origen de la web. `backend/server.py` permite
`http://localhost:5173` y `http://127.0.0.1:5173` de forma predeterminada; otros
orígenes se configuran mediante `CORS_ORIGINS` antes de iniciar ese servicio.
La aplicación Flutter nunca necesita la URL ni la contraseña de PostgreSQL.

## Probar Android

### Emulador opcional

Instalar **Android Emulator** y una imagen de sistema desde Android Studio.
El dispositivo preparado para este proyecto es `StockIA_Pixel_6`, con perfil
Pixel 6 e imagen AOSP Android 16 / API 36, arquitectura `x86_64`.

En Windows, el emulador necesita virtualización compatible. El entorno comprobado
utiliza **Plataforma de hipervisor de Windows**. Si se habilita esa característica,
Windows puede pedir un reinicio. No hace falta un emulador si se usa un celular.

Con el emulador abierto y el backend encendido:

```powershell
cd frontend
flutter devices
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Usar el identificador que devuelva `flutter devices` si no es `emulator-5554`.
`10.0.2.2` permite al emulador acceder al backend local de la computadora.

### Celular físico

Activar las opciones de desarrollador y la depuración USB en el teléfono y
autorizar la conexión desde el propio dispositivo. Elegirlo en `flutter devices`.
La API debe ser accesible desde el teléfono: `localhost` y `10.0.2.2` no apuntan
al backend del equipo en un celular físico. Usar una API HTTPS o una dirección de
red accesible y permitida por la configuración del backend y del firewall.

## Generar las compilaciones

Web, desde `frontend/`:

```powershell
flutter build web --dart-define=API_BASE_URL=https://TU_BACKEND
```

Resultado: `frontend/build/web/`.

APK de prueba para el emulador, desde la raíz del repositorio:

```powershell
.\compilar-apk.ps1
```

Para una API diferente:

```powershell
.\compilar-apk.ps1 -ApiUrl 'https://TU_BACKEND'
```

Resultado: `frontend/build/app/outputs/flutter-apk/app-debug.apk`.
El script genera una APK **debug**, sin configurar publicación ni firma de
distribución. La configuración de desarrollo permite HTTP local; para producción
se debe utilizar HTTPS. Cambiar `API_BASE_URL` requiere volver a ejecutar o
compilar la aplicación.

## Archivos que se comparten

- Versionar `pubspec.yaml`, `pubspec.lock`, el código y la configuración del proyecto.
- Conservar `.metadata`, que administra Flutter.
- No versionar SDK instalados, contraseñas, `build/`, `.dart_tool/`, `.gradle/` ni
  `android/local.properties`; los temporales están excluidos por `.gitignore`.

Fuentes: [instalación de Flutter](https://docs.flutter.dev/install/manual),
[configuración Android](https://docs.flutter.dev/platform-integration/android/setup)
y [aceleración del emulador](https://developer.android.com/studio/run/emulator-acceleration).
