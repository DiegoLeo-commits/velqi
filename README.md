<p align="center">
  <img src="assets/brand/ICON_velqi.png" width="180" alt="Velqi" />
</p>

<h1 align="center">Velqi</h1>

<div align="center">

Cliente de YouTube Music para Android y escritorio, escrito en Flutter.

[![Release](https://img.shields.io/badge/release-v1.3.1-7C3AED?style=flat-square)](https://velqi.netlify.app)
[![Flutter](https://img.shields.io/badge/Flutter-3.47.8-02569B?style=flat-square&logo=flutter)](https://flutter.dev)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue?style=flat-square)](LICENSE)

[Web oficial](https://velqi.netlify.app) · [Repositorio](https://github.com/DiegoLeo-commits/velqi)

</div>

---

## Estado

Velqi vuelve a estar mantenida. La app abandonó el backend Python embebido y ahora
usa **InnerTube en Dart puro**, sin servidor local ni proceso auxiliar.

Esta entrega se centra en el **backend de YouTube Music**: sesión por cookies,
cuenta, biblioteca, continuaciones reales de radio/búsqueda/artista y resolución
de audio. La interfaz **sigue siendo la Material 2 de Velqi**; no se ha migrado a
Material 3 ni se ha copiado el diseño de Meredith.

APK de prueba generado y ejecutado en Waydroid (Android 13, x86_64):

```text
build/app/outputs/flutter-apk/app-debug.apk
```

---

## Qué cambió en este ciclo

- **Sesión real de cuenta**: las cookies de YouTube Music ya no son un no-op.
  Se aceptan `cookies.txt` (Netscape), una cabecera `Cookie:` o JSON exportado,
  se normalizan, se firma `SAPISIDHASH` y se crea un cliente autenticado.
- **Validación de cuenta**: al aplicar cookies se consulta `account/account_menu`.
  Los ajustes muestran el nombre de la cuenta o un error explícito; las cookies
  inválidas no se guardan.
- **Biblioteca de cuenta** (API lista): playlists, canciones gustadas, álbumes,
  artistas, suscripciones e historial, con paginación por continuaciones.
- **Mutaciones de cuenta** (API lista): like/dislike, suscripción a artistas,
  crear/renombrar/borrar playlists, añadir y quitar canciones.
- **Radio sin corte a 24 canciones**: se conserva el token real de `next`
  (`nextRadioContinuationData`) y se pagina indefinidamente. Verificado con tres
  páginas consecutivas.
- **“Ver todo” de artista**: álbumes/singles vía `getArtistAlbums`; canciones y
  videos con token de `browse` real, no con el stub que devolvía listas vacías.
- **Búsqueda paginada**: el scroll de cada pestaña devuelve resultados nuevos en
  vez de `ctoken=null`. La implementación reconsulta con límite creciente y
  recorta por offset; no expone el token crudo de YouTube.
- **Streams**: fallback de clientes `ANDROID` → `ANDROID_VR` → `IOS`, `visitorData`
  cacheado y cookie de cuenta en la petición `player`.
- **Caché de URLs coherente**: solo se reutiliza `itag 18`, que es el formato que
  ExoPlayer puede abrir directamente. Entradas adaptativas viejas se re-resuelven.
- **Arreglo de reproducción**: se restauró `itag 18` como formato de reproducción
  Android. Los formatos adaptativos 139/140/251 devuelven **HTTP 403** ante el
  `Range: bytes=0-` que usa ExoPlayer; el progresivo acepta GET, rango abierto y
  rangos de 2 MiB (200/206). Verificado en Waydroid sin errores 403.

---

## Funciones

- Streaming de YouTube Music sin cuenta obligatoria.
- Reproducción en segundo plano y controles en la notificación.
- Búsqueda con sugerencias, filtros y scroll paginado.
- Home por secciones, radio automática, quick picks y recomendaciones.
- Letras sincronizadas (LRCLIB) con fallback a letras de YouTube Music.
- Descarga y caché local de canciones.
- Playlists locales, favoritos, artistas y álbumes guardados.
- Importación desde enlaces de YouTube/YouTube Music.
- Ecualizador, temporizador, normalización y control de calidad.
- 50 idiomas en `localization/`.
- Diseño Material 2 original de Velqi, tema dinámico por portada.

---

## Backend InnerTube

| Capacidad | Estado |
|---|---|
| Home, búsqueda, sugerencias, artista, álbum, playlist | ✅ verificado en vivo |
| Resolución de audio y reproducción Android | ✅ verificado en Waydroid |
| Continuación de radio (`next`) | ✅ verificada, 3 páginas |
| Paginación de “ver todo” en artista | ✅ implementada |
| Cookies, `SAPISIDHASH`, `account/account_menu` | ✅ implementado; falta prueba E2E con una cuenta real |
| Biblioteca de cuenta (likes/playlists/álbumes/artistas/historial) | ✅ API implementada; aún no expuesta en la UI |
| Mutaciones de cuenta (like, subscribe, CRUD de playlist) | ✅ API implementada; la UI sigue siendo local-first |
| Letras | ✅ LRCLIB + endpoint de YouTube Music |
| PoToken / descifrado de `signatureCipher` | ⚠️ no implementado; hoy los clientes nativos entregan URL directa |
| Streams adaptativos directos en Android | ❌ 403 de googlevideo con rangos de ExoPlayer; se usa `itag 18` |

### Archivos clave

```text
lib/services/innertube_extras.dart   Cookies, auth, cuenta, biblioteca,
                                     mutaciones y continuación de radio
lib/services/music_service.dart      Fachada usada por la UI, paginación de
                                     búsqueda y de secciones de artista
lib/services/stream_service.dart     Clientes InnerTube y selección de audio
lib/services/audio_handler.dart      just_audio + audio_service, caché de URLs
lib/services/downloader.dart         Descarga offline
lib/ui/                              Interfaz Material 2 existente
```

---

## Requisitos

- Flutter **3.47.8** (stable) / Dart 3.13.
- JDK **21** (`/usr/lib/jvm/java-21-openjdk` en Arch).
- Android SDK 36/37 y NDK **28.2.13676358**.
- Para Waydroid: ADB por TCP y el dispositivo visible con `flutter devices`.

```bash
export PATH="$HOME/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH"
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
flutter doctor
```

---

## Compilar y depurar

```bash
flutter pub get
flutter run -d <device-id>          # debug + hot reload
flutter build apk --debug           # APK de prueba
```

En Waydroid:

```bash
adb connect 192.168.240.112:5555
flutter devices
flutter run -d 192.168.240.112:5555 --debug
```

Dentro de `flutter run`: `r` hot reload, `R` hot restart, `q` salir.

APK de prueba:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

---

## Conectar la cuenta

1. Inicia sesión en <https://music.youtube.com>.
2. Exporta las cookies de `music.youtube.com` con una extensión como
   *Get cookies.txt LOCALLY*. También se acepta pegar la cabecera `Cookie:` o un
   JSON con la clave `cookie`.
3. En Velqi: **Ajustes → YouTube cookies → pegar → Apply**.
4. La cookie debe incluir `__Secure-3PAPISID` (o `SAPISID`). Si falta, Velqi
   muestra `cookiesNotAccepted`.
5. Al validar, el nombre de la cuenta aparece en el ajuste y en el diálogo.

La cookie se guarda localmente en Hive (`AppPrefs/userCookiesContent`) y se borra
con **Clear**. No se envía a ningún servidor de Velqi; solo se usa contra
YouTube/Google.

---

## Limitaciones conocidas

- **Calidad adaptativa directa**: googlevideo rechaza rangos abiertos/grandes en
  los itags 139/140/251. Para habilitar audio-only de mayor calidad hace falta un
  proxy local que fragmente los `Range` o descargar antes de reproducir. Hoy se
  reproduce con `itag 18` (AAC 128 kbps muxado).
- **Sin PoToken/cipher**: si YouTube empieza a exigir PoToken a los clientes
  nativos, habrá que portar la lógica de `zemer-cipher`/InnerTubeX. El resolver
  actual falla con un mensaje claro en ese caso.
- **Biblioteca de cuenta sin UI**: los métodos existen en `MusicServices`, pero
  la pantalla de biblioteca sigue leyendo Hive local. Falta convertirla a
  local+online y mapear likes/suscripciones.
- **Descargas no re-verificadas** después de estos cambios; usan `itag 18`.
- **Escritorio** no se re-verificó en esta sesión (Android/Waydroid sí).

---

## Verificación de esta entrega

- `flutter analyze lib`: sin errores (solo avisos/infos heredados).
- `flutter build apk --debug`: correcto.
- Waydroid Android 13 x86_64:
  - Home carga secciones reales.
  - Sugerencias y resultados de búsqueda cargan.
  - MediaSession en estado `playing`, posición avanzando, sin 403.
  - Cola de radio con 70 canciones.
- Login/biblioteca no se probaron E2E por no disponer de cookies de una cuenta
  real en el entorno de pruebas.

---

## Créditos

- **Lupyther** — creador original de Velqi.
- **Meredith / Metrolist** — referencia de paridad InnerTube y de los endpoints
  de cuenta, biblioteca y radio.
- **ytmusicapi_dart** — cliente WEB_REMIX usado para metadatos.
- Comunidad de Flutter, just_audio, audio_service y flutter_lyric.

## Licencia

El código se distribuye bajo **GPL-3.0**. Consulta [`LICENSE`](LICENSE).

Velqi no está afiliado a YouTube ni a Google. Todo el contenido accedido
pertenece a sus respectivos titulares.

---

<details>
<summary>English summary</summary>

Velqi is a Flutter YouTube Music client. The abandoned Python backend is gone:
metadata now comes from InnerTube through `ytmusicapi_dart`, and the account
layer lives in `lib/services/innertube_extras.dart` (cookie normalization,
SAPISIDHASH auth, account info, library, playlist mutations, radio tokens).
Playback uses `itag 18` because googlevideo returns 403 for ExoPlayer's
open-ended Range requests on adaptive audio formats. The Material 2 UI is
unchanged. Debug APK and Waydroid playback were verified.

</details>
