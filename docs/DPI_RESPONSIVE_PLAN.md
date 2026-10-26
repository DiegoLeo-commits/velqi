# Velqi — Plan de adaptación a Densidades (DPI) y tamaños de pantalla

**Objetivo**: que la app se vea correcta en CUALQUIER densidad configurada en
Opciones de desarrollador (`wm density`: 320 / 480 / 560 / 640+) y en
cualquier tamaño físico de teléfono, sin overflow, sin texto gigante rompiendo
filas, y sin áreas muertas.

---

## Diagnóstico del problema real

El "DPI de desarrollador" en Android cambia **2 cosas a la vez**:

1. **devicePixelRatio** → más píxeles físicos por píxel lógico (los `width: 158`
   lógicos ocupan más espacio FÍSICO, no más lógico).
2. **textScaler / fuente del sistema** → Flutter escala el texto con
   `MediaQuery.textScalerOf(context)`, que puede llegar a **2.0**.

Nuestros bugs típicos (franja amarilla, botones apretados, filas cortadas)
vienen casi siempre del **texto escalado** dentro de filas de altura fija, y
de **anchos hardcodeados** (`SizedBox(width: 72)`, `itemExtent: 120`, etc.)
que no dejan crecer el contenido.

---

## Reglas de oro (aplicar en todo touch de UI)

1. **Ninguna fila con altura fija** (`itemExtent`, `SizedBox(height: X)`) que
   contenga texto. Usar alturas mínimas (`ConstrainedBox(minHeight:)`) y dejar
   que el texto respire.
2. **Todo texto en filas: `maxLines` + `TextOverflow.ellipsis`** — el texto
   nunca empuja al layout (el bug de "RIGHT OVERFLOWED" ya lo vivimos).
3. **Anchos fijos solo para iconos/avatares**, nunca para bloques con texto.
   Para columnas de contenido usar `Expanded`/`Flexible`.
4. **Usar `MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4)`** en
   zonas densas (miniplayer, navbar, filas de resultados): el texto crece
   hasta 1.4× pero nunca rompe la fila.
5. **Breakpoints por ancho LÓGICO**, no físico:
   `< 600` = teléfono · `600–840` = tablet/fold · `> 840` = desktop. Ya existe
   `context.isLandscape` y `isWideScreen (width > 800)` — consolidar ahí.
6. **Iconos y paddings escalables**: `iconSize * clamp(dpr, 0.85, 1.3)` donde
   importa, en vez de números sueltos.

---

## Fases de implementación

### Fase 0 — Auditoría (media sesión)
- `grep -rn "itemExtent\|SizedBox(height:" lib/ui` → inventario de alturas fijas.
- `grep -rn "width: [0-9]" lib/ui` → inventario de anchos fijos.
- Clasificar cada uno: seguro (icono) / riesgoso (contiene texto).

### Fase 1 — Infraestructura (1 sesión)
- Crear `lib/ui/utils/responsive.dart` con:
  - `double dp(BuildContext, double)` — escala suave por densidad con clamp.
  - `TextScaler` saneado para zonas densas.
  - `enum ScreenClass { phone, tablet, desktop }` + helper global.
- Migrar `isWideScreen` y `context.isLandscape` a ese archivo (una sola fuente
  de verdad).

### Fase 2 — Superficies críticas (1–2 sesiones, por prioridad)
1. **Miniplayer + navbar flotante** (visible SIEMPRE — el más importante).
2. **Filas de búsqueda/tabs** (SortWidget, SongListTile, ListWidget).
3. **Biblioteca de tarjetas** (CoverCardRow: `cardWidth` ya es parámetro —
   hacerlo dependiente del ancho de pantalla: `min(158, width/2.6)`).
4. **Reproductor completo** (ya tiene LayoutBuilder en desktop; portar a móvil).
5. **Ajustes** (los tiles `_borderedTile` son los más expuestos al texto grande).

### Fase 3 — Matriz de pruebas (media sesión)
Probar con `adb shell wm density` en el emulador/Bluestacks:

```bash
adb shell wm density 320   # pequeño
adb shell wm density 480   # default
adb shell wm density 600   # grande
adb shell wm density reset # volver
```

Checklist por densidad: home, búsqueda (overview + tabs), biblioteca (4 tabs),
reproductor completo, miniplayer, ajustes (cada categoría), notificación.

### Fase 4 — Retoques visuales
- En densidades bajas reducir `cardWidth` y paddings globales.
- En densidades altas permitir 2 líneas en subtítulos de filas.

---

## Riesgos y candados
- **No tocar** la lógica de audio en esta campaña (solo presentación).
- Cada fase se compila y prueba en Bluestacks ANTES de pasar a la siguiente
  (regla del proyecto: nada de cambios grandes a ciegas).
- Desktop queda como está (ya tiene LayoutBuilder en el player).

*Documento creado tras la campaña de Android v1.3.x — lo puede retomar
cualquier IA o humano.*
