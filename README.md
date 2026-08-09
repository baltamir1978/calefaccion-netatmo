# Calefacción Netatmo

App de iOS/iPadOS en SwiftUI para controlar la calefacción de varias casas con termostato **Netatmo**, usando la [API Energy](https://dev.netatmo.com/apidocumentation/energy) oficial.

Nace de una necesidad concreta: gestionar dos casas a la vez desde una sola pantalla, sin tener que ir cambiando de hogar dentro de la app oficial, y poder subir la temperatura desde un widget en la pantalla de inicio.

## Funcionalidades

**App**

- **Inicio multi-casa** — tarjetas compactas con el estado de todas tus casas a la vez: temperatura actual, objetivo, y si la caldera está encendida. Control vertical `+ / objetivo / −` que evoca el termostato físico.
- **Modos del hogar** — programación, ausente y antihielo.
- **Ajuste manual con duración** — fija una temperatura durante un tiempo configurable (o deja que Netatmo decida cuándo expira).
- **Horario semanal** — vista de la programación completa: una barra de 24 h por día coloreada por zona, desplegable para ver a qué hora empieza cada franja y con qué temperatura. De solo lectura, por ahora.
- **Editor de horarios** — cambia las temperaturas de las zonas de un horario manteniendo intactas las franjas horarias, con vista previa y confirmación antes de guardar.
- **Batería** — nivel de cada termostato y válvula con un indicador de barras, y aviso en el inicio cuando alguno se queda bajo.
- **Consumo** — gráficas (Swift Charts) del histórico de temperatura y del tiempo de caldera encendida por habitación.
- **Ocultar casas** — quita del inicio las casas que no te interesen.

**Widgets**

- **Estado** — anillo con temperatura actual y objetivo, configurable por casa. Fondo blanco con la caldera apagada, degradado naranja cuando está calentando.
- **Tengo frío** — botón que sube el objetivo 1 °C sobre la temperatura actual durante 2 horas, sin abrir la app (App Intent ejecutado en el propio widget).

## Requisitos

| | |
|---|---|
| Xcode | 26 o superior |
| Deployment target | iOS 26.5 (`IPHONEOS_DEPLOYMENT_TARGET`) |
| Dispositivos | iPhone y iPad |
| Cuenta | Netatmo con termostato + app registrada en [dev.netatmo.com](https://dev.netatmo.com) |

Sin dependencias externas: solo SwiftUI, WidgetKit, AppIntents, Swift Charts y `AuthenticationServices`.

## Puesta en marcha

### 1. Registra tu app en Netatmo Connect

En [dev.netatmo.com/apps](https://dev.netatmo.com/apps) crea una aplicación y anota su `client_id` y `client_secret`. Añade como **Redirect URI**:

```
calefaccion-netatmo://oauth-callback
```

Debe coincidir **exactamente**, carácter a carácter.

### 2. Crea tu NetatmoConfig.swift

El archivo con las credenciales no está en el repositorio. Copia la plantilla:

```bash
cp "Calefaccion Netatmo/Config/NetatmoConfig.example.swift" \
   "Calefaccion Netatmo/Config/NetatmoConfig.swift"
```

y rellena `clientID` y `clientSecret`. `NetatmoConfig.swift` está en `.gitignore`.

> También puedes dejar los placeholders y meter las credenciales desde **Ajustes** dentro de la app: se guardan en el Keychain. Los valores del archivo son solo el arranque por defecto.

### 3. Ajusta el firmado

Abre `Calefaccion Netatmo.xcodeproj` y, en ambos targets (app y `CalefaccionWidgetExtension`), cambia el equipo de desarrollo y los identificadores por los tuyos:

- Bundle ID de la app: `Altamirano.Calefaccion-Netatmo`
- Bundle ID del widget: `Altamirano.Calefaccion-Netatmo.CalefaccionWidget`
- App Group: `group.Altamirano.Calefaccion-Netatmo`

El App Group y el Keychain access group compartido tienen que estar activos en **los dos** targets: son lo que permite al widget leer el token y la caché. Si los cambias, actualiza también las constantes en `Calefaccion Netatmo/Config/SharedStore.swift` y en `CalefaccionWidget/WidgetShared.swift` — deben coincidir.

### 4. Compila y ejecuta

Inicia sesión con tu cuenta de Netatmo mediante el flujo OAuth que se abre en `ASWebAuthenticationSession`.

## Arquitectura

```
Calefaccion Netatmo/
├── App/            AppModel (contenedor de dependencias) + RootView
├── Auth/           AuthManager, OAuthWebSession, TokenStore (Keychain)
├── Config/         AppSettings, NetatmoConfig, SharedStore (App Group)
├── Models/         Home, HomeStatus, RoomMeasure, SchedulePayload, ScheduleWeek, BatteryStatus, ThermMode…
├── Networking/     NetatmoAPIClient, NetatmoEndpoint, APIError
├── Services/       EnergyService — fachada de la API Energy
├── ViewModels/     Uno por pantalla (@Observable)
├── Views/          Login, HomeOverview, HomeDetail, ScheduleWeek, ScheduleEdit, Consumption, Settings
└── Utilities/      Formatters

CalefaccionWidget/
├── CalefaccionWidget.swift    Widget de estado (anillo)
├── WarmUpWidget.swift         Widget "Tengo frío"
├── WarmUpIntent.swift         App Intent que ejecuta la subida de 1 °C
├── AppIntent.swift            Configuración (selector de casa)
└── WidgetShared.swift         Cliente HTTP mínimo + acceso al Keychain compartido
```

Patrón MVVM con el macro `@Observable` de Swift Observation. `AppModel` construye `AppSettings → AuthManager → EnergyService` y los inyecta en el entorno de SwiftUI.

La extensión de widgets **no** comparte código con la app: lleva su propio cliente HTTP reducido (`WidgetShared.swift`) que lee las credenciales y el token del Keychain access group compartido y refresca el token por su cuenta. Es duplicación deliberada, para mantener la extensión ligera.

### Endpoints de la API Energy usados

`homesdata` · `homestatus` · `setroomthermpoint` · `setthermmode` · `switchhomeschedule` · `synchomeschedule` · `getroommeasure`

### Nota sobre los horarios

`synchomeschedule` exige reenviar el horario **completo**. `EnergyService.syncScheduleTemperatures` parte del horario que ya trajo `homesdata`, sustituye solo las temperaturas indicadas y lo reenvía con la `timetable` intacta, para no perder las franjas horarias.

Netatmo describe la semana como una lista de cambios: cada entrada de la `timetable` lleva un `m_offset` en minutos desde el lunes a las 00:00 y la zona que pasa a regir hasta el siguiente cambio. `ScheduleWeek.days(from:)` expande esa lista a franjas por día, teniendo en cuenta que la semana es cíclica: lo que hay antes del primer cambio lo cubre la última zona de la lista. Es la base sobre la que se dibuja el horario semanal, y la que hará falta invertir cuando las horas se puedan editar.

## Seguridad

- El `access_token` y el `refresh_token` se guardan en el Keychain (`kSecAttrAccessibleAfterFirstUnlock`), nunca en `UserDefaults`.
- Las credenciales de Netatmo Connect también van al Keychain, en un access group compartido con el widget.
- `NetatmoConfig.swift` está excluido del repositorio.

Aun así, ten en cuenta que **cualquier `client_secret` embebido en una app de cliente es extraíble del binario**. Es un compromiso aceptable para uso personal, no para una app distribuida públicamente. Netatmo no ofrece PKCE en su flujo OAuth.

## Estado

Proyecto personal, versión 1.0. Funciona a diario contra dos casas reales. No está en la App Store.

## Licencia

MIT. Consulta [LICENSE](LICENSE).

---

No afiliado a Netatmo ni a Legrand. «Netatmo» es marca registrada de sus respectivos propietarios.
