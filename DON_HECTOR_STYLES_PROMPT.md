# DON HÉCTOR LICORERA — DESIGN SYSTEM PROMPT

Usa este documento como referencia de marca para cualquier pantalla, componente o vista que desarrolles para el sistema de gestión "Don Héctor Licorera". Respeta todos los tokens sin excepción.

---

## IDENTIDAD

- **Nombre del negocio:** Don Héctor Licorera
- **Tono visual:** Sobrio, nocturno, minimalista editorial. Elegancia sin decoración innecesaria.
- **NO usar:** efectos neón, glow, sombras de color, gradientes, transparencias decorativas, bordes redondeados grandes.

---

## COLORES — CSS VARIABLES

Declara siempre estas variables en `:root`. No uses ningún color fuera de esta lista.

```css
:root {
  --negro:       #0C0C0C;   /* fondo principal */
  --superficie:  #161616;   /* tarjetas, paneles, inputs */
  --borde:       #262626;   /* líneas divisorias, bordes de componentes */
  --magenta:     #C8245E;   /* acento primario: CTA, alertas activas, stock bajo */
  --magenta-cl:  #E84A80;   /* hover sobre magenta */
  --verde:       #4F9122;   /* estados positivos: disponible, pagado, confirmado */
  --verde-cl:    #6AB830;   /* hover / énfasis sobre verde */
  --blanco:      #EDE9E0;   /* texto principal */
  --blanco-dim:  #8C8880;   /* texto secundario, etiquetas, placeholders */
  --gris:        #3A3A3A;   /* elementos inactivos, barras de gráfica apagadas */
}
```

**Proporciones de uso:**
- Negro: 70% (fondos, contenedores)
- Magenta: 20% (botón principal, un elemento destacado por pantalla)
- Verde: 10% (confirmaciones, stock OK, deltas positivos)

---

## TIPOGRAFÍA

### Fuentes (Google Fonts)

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;0,600;1,300;1,400&family=DM+Mono:wght@300;400;500&display=swap" rel="stylesheet">
```

### Escala tipográfica

| Uso | Fuente | Tamaño | Peso | Estilo | Color |
|---|---|---|---|---|---|
| Nombre de marca / hero | Cormorant Garamond | 64–88px | 300 | italic | `--blanco` o `--magenta` |
| Titulares de módulo | Cormorant Garamond | 28–36px | 400 | normal | `--blanco` |
| Nombres de producto | Cormorant Garamond | 17px | 400 | normal | `--blanco` |
| Valores y cifras (COP, stock) | DM Mono | 14–28px | 400 | normal | `--blanco` |
| Etiquetas y metadatos | DM Mono | 9–11px | 300 | normal | `--blanco-dim` |
| Alertas de estado | DM Mono | 10–12px | 500 | normal | `--verde` o `--magenta` |
| Botones | DM Mono | 11px | 400 | normal | según variante |

**Reglas tipográficas:**
- `letter-spacing: 0.2em` en todas las etiquetas DM Mono uppercase.
- `line-height: 0.9–0.95` en display Cormorant Garamond.
- **Nunca** usar Inter, Roboto, Arial o cualquier sans-serif genérica.
- **Nunca** usar bold 600–700 en Cormorant Garamond.

---

## FONDOS Y SUPERFICIES

```css
body                { background: var(--negro); color: var(--blanco); }
.card, .panel       { background: var(--superficie); }
.input, .field      { background: transparent; border-bottom: 1px solid var(--borde); }
.divider            { height: 1px; background: var(--borde); }
```

Usa `border: 1px solid var(--borde)` — siempre `1px`, nunca `2px` salvo en el botón primario activo.  
`border-radius` máximo permitido: `4px` en componentes internos, `0px` preferido en contenedores grandes.

---

## COMPONENTES

### Botón primario
```css
.btn-primary {
  background: var(--magenta);
  color: #fff;
  font-family: 'DM Mono', monospace;
  font-size: 11px;
  font-weight: 400;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  padding: 12px 28px;
  border: none;
  border-radius: 0;
}
```

### Botón outline
```css
.btn-outline {
  background: transparent;
  border: 1px solid var(--borde);
  color: var(--blanco);
  /* misma fuente y tamaño que btn-primary */
}
```

### Botón ghost (texto)
```css
.btn-ghost {
  background: transparent;
  color: var(--blanco-dim);
  border: none;
  padding-left: 0;
  /* misma fuente */
}
```

### Tarjeta de producto / lista
```css
.item-card {
  background: var(--superficie);
  border: 1px solid var(--borde);
  padding: 20px 24px;
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  border-radius: 0;
}
.item-name     { font-family: 'Cormorant Garamond', serif; font-size: 17px; color: var(--blanco); }
.item-category { font-family: 'DM Mono', monospace; font-size: 9px; letter-spacing: 0.2em;
                 text-transform: uppercase; color: var(--blanco-dim); }
.item-price    { font-family: 'DM Mono', monospace; font-size: 14px; color: var(--blanco); }
.item-stock-ok { font-size: 9px; color: var(--verde); }
.item-stock-low{ font-size: 9px; color: var(--magenta); }
```

### Tarjeta de métrica (stat card)
```css
.stat-card {
  background: var(--superficie);
  border: 1px solid var(--borde);
  padding: 20px 24px;
}
.stat-label { font-family: 'DM Mono', monospace; font-size: 9px; letter-spacing: 0.2em;
              text-transform: uppercase; color: var(--blanco-dim); display: block; margin-bottom: 8px; }
.stat-value { font-family: 'Cormorant Garamond', serif; font-size: 28px; font-weight: 300;
              color: var(--blanco); display: block; }
.delta-up   { font-size: 10px; color: var(--verde); }
.delta-down { font-size: 10px; color: var(--magenta); }
```

### Etiqueta / badge
```css
.badge {
  font-family: 'DM Mono', monospace;
  font-size: 9px;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  padding: 3px 10px;
  border-radius: 0;
}
.badge-alerta     { border: 1px solid var(--magenta); color: var(--magenta); }
.badge-disponible { border: 1px solid var(--verde);   color: var(--verde); }
.badge-neutro     { border: 1px solid var(--borde);   color: var(--blanco-dim); }
```

### Campo de formulario
```css
.field-label {
  font-family: 'DM Mono', monospace;
  font-size: 9px;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: var(--blanco-dim);
  display: block;
  margin-bottom: 8px;
}
.field-input {
  width: 100%;
  background: transparent;
  border: none;
  border-bottom: 1px solid var(--borde);
  padding: 8px 0;
  font-family: 'DM Mono', monospace;
  font-size: 13px;
  color: var(--blanco);
  outline: none;
}
.field-input::placeholder { color: var(--gris); }
.field-input:focus { border-bottom-color: var(--magenta); }
```

### Etiqueta de sección
```css
.section-label {
  font-family: 'DM Mono', monospace;
  font-size: 10px;
  letter-spacing: 0.25em;
  text-transform: uppercase;
  color: var(--blanco-dim);
  display: flex;
  align-items: center;
  gap: 16px;
  margin-bottom: 32px;
}
.section-label::after {
  content: '';
  flex: 1;
  height: 1px;
  background: var(--borde);
}
```

---

## ICONOGRAFÍA

- Usa **Tabler Icons** (outline únicamente). No usar filled.
- Tamaño: 16–20px inline, 24px decorativo máximo.
- Color: heredado del texto del contenedor (`currentColor`).
- Carga: `<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@tabler/icons-webfont@latest/tabler-icons.min.css">`

---

## LOGOTIPO (texto)

Siempre compuesto por dos elementos:

```html
<div class="logotipo">
  <span class="logo-don">Don</span>
  <span class="logo-hector">Héctor</span>
</div>
```

```css
.logotipo      { font-family: 'Cormorant Garamond', serif; font-weight: 300; line-height: 0.95; }
.logo-don      { font-size: 11px; letter-spacing: 0.25em; text-transform: uppercase;
                 font-family: 'DM Mono', monospace; color: var(--blanco-dim); display: block; }
.logo-hector   { font-size: 36–88px; font-style: italic; color: var(--blanco); display: block; }
```

Subtítulo opcional: `"Licorera · 24 horas"` en DM Mono 9px, `--blanco-dim`, `letter-spacing: 0.2em`.

---

## REGLAS DE ORO (nunca romper)

1. **Fondo siempre oscuro.** `--negro` o `--superficie`. Jamás fondos blancos salvo en variante de logo.
2. **Magenta = acento único.** Un solo elemento por pantalla lleva magenta como protagonista.
3. **Verde = confirmación.** Solo para estados positivos: pagado, disponible, correcto.
4. **Sin gradientes.** Ninguno. Colores planos siempre.
5. **Sin glow ni neón.** `box-shadow` solo permitido como focus ring (`0 0 0 2px var(--magenta)`).
6. **Cormorant Garamond = marca y contenido.** DM Mono = interfaz funcional y datos.
7. **Bordes de 1px.** `border: 1px solid var(--borde)`. Nunca 2px en contenedores.
8. **Texto en mayúsculas solo en etiquetas DM Mono.** Cormorant Garamond siempre en title case o minúsculas.
9. **border-radius: 0** en la mayoría de componentes. Máximo `4px` en badges o inputs si se desea suavidad mínima.
10. **Formatear valores COP con punto de miles:** `$1.240.000` — usar `Intl.NumberFormat('es-CO')`.

---

## FLUTTER — EQUIVALENCIA DE TOKENS

Si el componente es Flutter, usa este `ThemeData`:

```dart
const negro      = Color(0xFF0C0C0C);
const superficie = Color(0xFF161616);
const borde      = Color(0xFF262626);
const magenta    = Color(0xFFC8245E);
const verde      = Color(0xFF4F9122);
const blanco     = Color(0xFFEDE9E0);
const blancoD    = Color(0xFF8C8880);
const gris       = Color(0xFF3A3A3A);

ThemeData donHectorTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: negro,
  cardColor: superficie,
  colorScheme: ColorScheme.dark(
    primary: magenta,
    secondary: verde,
    surface: superficie,
    background: negro,
    onPrimary: Colors.white,
    onSurface: blanco,
  ),
  dividerColor: borde,
  textTheme: TextTheme(
    // Titulares de módulo
    headlineLarge: TextStyle(
      fontFamily: 'CormorantGaramond',
      fontWeight: FontWeight.w300,
      fontSize: 48,
      fontStyle: FontStyle.italic,
      color: blanco,
    ),
    headlineMedium: TextStyle(
      fontFamily: 'CormorantGaramond',
      fontWeight: FontWeight.w400,
      fontSize: 28,
      color: blanco,
    ),
    // Nombres de producto
    titleMedium: TextStyle(
      fontFamily: 'CormorantGaramond',
      fontWeight: FontWeight.w400,
      fontSize: 17,
      color: blanco,
    ),
    // Valores numéricos
    bodyLarge: TextStyle(
      fontFamily: 'DMMonoLight',
      fontWeight: FontWeight.w400,
      fontSize: 14,
      color: blanco,
    ),
    // Etiquetas
    labelSmall: TextStyle(
      fontFamily: 'DMMono',
      fontWeight: FontWeight.w300,
      fontSize: 10,
      letterSpacing: 2.0,
      color: blancoD,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: false,
    enabledBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: borde, width: 1),
    ),
    focusedBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: magenta, width: 1),
    ),
    hintStyle: TextStyle(color: gris, fontFamily: 'DMMono', fontSize: 13),
    labelStyle: TextStyle(
      color: blancoD,
      fontFamily: 'DMMono',
      fontSize: 10,
      letterSpacing: 2.0,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: magenta,
      foregroundColor: Colors.white,
      textStyle: TextStyle(
        fontFamily: 'DMMono',
        fontSize: 11,
        fontWeight: FontWeight.w400,
        letterSpacing: 2.0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      padding: EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      elevation: 0,
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: blanco,
      side: BorderSide(color: borde, width: 1),
      textStyle: TextStyle(
        fontFamily: 'DMMono',
        fontSize: 11,
        fontWeight: FontWeight.w400,
        letterSpacing: 2.0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      padding: EdgeInsets.symmetric(horizontal: 28, vertical: 14),
    ),
  ),
  cardTheme: CardTheme(
    color: superficie,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
      side: BorderSide(color: borde, width: 1),
    ),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: negro,
    elevation: 0,
    titleTextStyle: TextStyle(
      fontFamily: 'CormorantGaramond',
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w300,
      fontSize: 24,
      color: blanco,
    ),
    iconTheme: IconThemeData(color: blanco),
    bottom: PreferredSize(
      preferredSize: Size.fromHeight(1),
      child: Divider(height: 1, color: borde),
    ) as PreferredSizeWidget,
  ),
);
```

**Fuentes en pubspec.yaml:**
```yaml
fonts:
  - family: CormorantGaramond
    fonts:
      - asset: assets/fonts/CormorantGaramond-Light.ttf
        weight: 300
      - asset: assets/fonts/CormorantGaramond-Regular.ttf
        weight: 400
      - asset: assets/fonts/CormorantGaramond-LightItalic.ttf
        weight: 300
        style: italic
      - asset: assets/fonts/CormorantGaramond-Italic.ttf
        weight: 400
        style: italic
  - family: DMMono
    fonts:
      - asset: assets/fonts/DMMono-Light.ttf
        weight: 300
      - asset: assets/fonts/DMMono-Regular.ttf
        weight: 400
      - asset: assets/fonts/DMMono-Medium.ttf
        weight: 500
```

---

*Don Héctor Licorera — Design System v1.0 — 2026*
