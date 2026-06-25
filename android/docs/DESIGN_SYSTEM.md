# JetSetter Pro — Android Design System

Android (Jetpack Compose + Material 3) port of the iOS design system defined in
`JetSetter Pro/UI/Theme/JetsetterTheme.swift`.

This is the single source of truth for colors, typography, gradients, shapes,
spacing, and the core themed components. All hex values are copied verbatim from
the Swift file. The iOS theme defaults to **dark ("executive") mode** on first
launch (`ColorSchemePreference.dark`), so the dark palette is the primary one;
the light palette is the contrast-corrected adaptive variant.

- **Package:** `com.jetsetter.pro.ui.theme`
- **Material baseline:** Material 3 (`androidx.compose.material3`)
- **minSdk 26** (dynamic color / Material You is API 31+, so it is **not** used — JetSetter ships a fixed brand palette in both modes)

---

## 1. Color tokens

iOS resolves each color at runtime via `UIColor { trait in ... }`. On Android the
equivalent split is **`values/colors.xml` (light)** + **`values-night/colors.xml` (dark)**,
or a `darkColorScheme()` / `lightColorScheme()` pair in Compose.

| Token | iOS role | Dark hex | Light hex |
|---|---|---|---|
| `background` | App canvas (deep navy) | `#10131E` | `#EFF1F8` |
| `surface` | Card / elevated surface | `#161929` | `#FFFFFF` |
| `surfaceElevated` | Inputs, inner cards | `#1D2235` | `#F4F5FB` |
| `primary` | Deep-navy brand identifier | `#1C3555` | `#0A2040` |
| `accent` | Primary accent (buttons, tints, highlights) | `#3B9EF0` | `#0055CC` |
| `blue` | Secondary informational accent | `#4E8FD4` | `#1A5FA8` |
| `success` | On-time / success (emerald) | `#1DB97D` | `#0C7A4E` |
| `warning` | Delayed / warning (amber) | `#E8A020` | `#B07010` |
| `danger` | Cancelled / error (crimson) | `#E84040` | `#C42020` |
| `textPrimary` | Primary text | `#ECEEF4` | `#0A0C18` |
| `textSecondary` | Secondary text | `#8B92A8` | `#52587A` |
| `separator` | Borders / separators | `#1E2136` | `#DDE0EE` |

> Note: the historic name `gold*` (e.g. `goldGradient`, `goldText()`, `GoldTag`)
> is a legacy label. The palette is **sky/royal blue**, not gold. Keep the
> Android names descriptive (`accentGradient`, `AccentTag`) but alias the old
> names in comments so the iOS↔Android mapping stays searchable.

### 1a. Compose representation — `Color.kt`

```kotlin
package com.jetsetter.pro.ui.theme

import androidx.compose.ui.graphics.Color

// ── Dark (primary / "executive" mode) ───────────────────────────────
val BackgroundDark      = Color(0xFF10131E)
val SurfaceDark         = Color(0xFF161929)
val SurfaceElevatedDark = Color(0xFF1D2235)
val PrimaryDark         = Color(0xFF1C3555)
val AccentDark          = Color(0xFF3B9EF0)
val BlueDark            = Color(0xFF4E8FD4)
val SuccessDark         = Color(0xFF1DB97D)
val WarningDark         = Color(0xFFE8A020)
val DangerDark          = Color(0xFFE84040)
val TextPrimaryDark     = Color(0xFFECEEF4)
val TextSecondaryDark   = Color(0xFF8B92A8)
val SeparatorDark       = Color(0xFF1E2136)

// ── Light (adaptive) ────────────────────────────────────────────────
val BackgroundLight      = Color(0xFFEFF1F8)
val SurfaceLight         = Color(0xFFFFFFFF)
val SurfaceElevatedLight = Color(0xFFF4F5FB)
val PrimaryLight         = Color(0xFF0A2040)
val AccentLight          = Color(0xFF0055CC)
val BlueLight            = Color(0xFF1A5FA8)
val SuccessLight         = Color(0xFF0C7A4E)
val WarningLight         = Color(0xFFB07010)
val DangerLight          = Color(0xFFC42020)
val TextPrimaryLight     = Color(0xFF0A0C18)
val TextSecondaryLight   = Color(0xFF52587A)
val SeparatorLight       = Color(0xFFDDE0EE)
```

Because the brand introduces tokens Material 3 has no slot for (`accent`,
`success`, `warning`, `separator`, `surfaceElevated`, `textSecondary`), expose
them through a custom `JetColors` holder provided via `CompositionLocal`, and map
the closest ones onto the Material `ColorScheme` for stock components:

```kotlin
@Immutable
data class JetColors(
    val background: Color,
    val surface: Color,
    val surfaceElevated: Color,
    val primary: Color,
    val accent: Color,
    val blue: Color,
    val success: Color,
    val warning: Color,
    val danger: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val separator: Color,
)

val DarkJetColors = JetColors(
    background = BackgroundDark, surface = SurfaceDark, surfaceElevated = SurfaceElevatedDark,
    primary = PrimaryDark, accent = AccentDark, blue = BlueDark,
    success = SuccessDark, warning = WarningDark, danger = DangerDark,
    textPrimary = TextPrimaryDark, textSecondary = TextSecondaryDark, separator = SeparatorDark,
)

val LightJetColors = JetColors(
    background = BackgroundLight, surface = SurfaceLight, surfaceElevated = SurfaceElevatedLight,
    primary = PrimaryLight, accent = AccentLight, blue = BlueLight,
    success = SuccessLight, warning = WarningLight, danger = DangerLight,
    textPrimary = TextPrimaryLight, textSecondary = TextSecondaryLight, separator = SeparatorLight,
)

val LocalJetColors = staticCompositionLocalOf { DarkJetColors }

private fun darkScheme() = darkColorScheme(
    background = BackgroundDark, surface = SurfaceDark, surfaceVariant = SurfaceElevatedDark,
    primary = AccentDark, secondary = BlueDark, error = DangerDark,
    onBackground = TextPrimaryDark, onSurface = TextPrimaryDark, outline = SeparatorDark,
)

private fun lightScheme() = lightColorScheme(
    background = BackgroundLight, surface = SurfaceLight, surfaceVariant = SurfaceElevatedLight,
    primary = AccentLight, secondary = BlueLight, error = DangerLight,
    onBackground = TextPrimaryLight, onSurface = TextPrimaryLight, outline = SeparatorLight,
)

@Composable
fun JetTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),  // override from UserPreferences.colorScheme
    content: @Composable () -> Unit,
) {
    val jetColors = if (darkTheme) DarkJetColors else LightJetColors
    CompositionLocalProvider(LocalJetColors provides jetColors) {
        MaterialTheme(
            colorScheme = if (darkTheme) darkScheme() else lightScheme(),
            typography = JetTypography,
            shapes = JetShapes,
            content = content,
        )
    }
}

// Usage in composables:
//   val jet = LocalJetColors.current
//   Text("…", color = jet.accent)
```

> The `darkTheme` flag must be driven by the persisted preference, not just
> `isSystemInDarkTheme()`. Mirror iOS `ColorSchemePreference` (`system`/`light`/`dark`)
> from DataStore — see `API_REFERENCE.md` (UserPreferences) — defaulting to **dark**.

### 1b. `res/values/colors.xml` (light)

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="jet_background">#FFEFF1F8</color>
    <color name="jet_surface">#FFFFFFFF</color>
    <color name="jet_surface_elevated">#FFF4F5FB</color>
    <color name="jet_primary">#FF0A2040</color>
    <color name="jet_accent">#FF0055CC</color>
    <color name="jet_blue">#FF1A5FA8</color>
    <color name="jet_success">#FF0C7A4E</color>
    <color name="jet_warning">#FFB07010</color>
    <color name="jet_danger">#FFC42020</color>
    <color name="jet_text_primary">#FF0A0C18</color>
    <color name="jet_text_secondary">#FF52587A</color>
    <color name="jet_separator">#FFDDE0EE</color>
</resources>
```

### 1c. `res/values-night/colors.xml` (dark)

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="jet_background">#FF10131E</color>
    <color name="jet_surface">#FF161929</color>
    <color name="jet_surface_elevated">#FF1D2235</color>
    <color name="jet_primary">#FF1C3555</color>
    <color name="jet_accent">#FF3B9EF0</color>
    <color name="jet_blue">#FF4E8FD4</color>
    <color name="jet_success">#FF1DB97D</color>
    <color name="jet_warning">#FFE8A020</color>
    <color name="jet_danger">#FFE84040</color>
    <color name="jet_text_primary">#FFECEEF4</color>
    <color name="jet_text_secondary">#FF8B92A8</color>
    <color name="jet_separator">#FF1E2136</color>
</resources>
```

---

## 2. Gradients

iOS uses `LinearGradient(stops:startPoint:.topLeading, endPoint:.bottomTrailing)`.
The Compose equivalent is `Brush.linearGradient(colorStops, start = Offset.Zero,
end = Offset.Infinite)` — top-leading → bottom-trailing diagonal. Use
`colorStops` (the `Pair<Float, Color>` overload) to preserve the exact stop
locations.

```kotlin
package com.jetsetter.pro.ui.theme

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

object JetGradients {

    /** Accent shimmer — hero elements, labels, logo text (iOS goldGradient). */
    val accentGradient = Brush.linearGradient(
        colorStops = arrayOf(
            0.00f to Color(0xFF1A72E8),
            0.45f to Color(0xFF5BBAFF),
            0.75f to Color(0xFF3A9AF0),
            1.00f to Color(0xFF1A72E8),
        ),
        start = Offset.Zero,
        end = Offset.Infinite, // top-leading → bottom-trailing
    )

    /** Deep dark gradient — onboarding & hero backgrounds (iOS heroGradient). */
    val heroGradient = Brush.linearGradient(
        colorStops = arrayOf(
            0.0f to Color(0xFF06070D),
            0.5f to Color(0xFF0D1425),
            1.0f to Color(0xFF091530),
        ),
        start = Offset.Zero,
        end = Offset.Infinite,
    )

    /** Subtle card inner glow for depth — DARK MODE ONLY (iOS cardInnerGlow). */
    val cardInnerGlow = Brush.linearGradient(
        colorStops = arrayOf(
            0.0f to Color.White.copy(alpha = 0.04f),
            1.0f to Color.Transparent,
        ),
        start = Offset.Zero,
        end = Offset.Infinite,
    )

    /** Accent card border shimmer — DARK MODE (iOS goldBorderGradient). */
    val accentBorderGradient = Brush.linearGradient(
        colorStops = arrayOf(
            0.0f to Color(0xFF3B9EF0).copy(alpha = 0.30f),
            0.5f to Color.White.copy(alpha = 0.05f),
            1.0f to Color(0xFF3B9EF0).copy(alpha = 0.15f),
        ),
        start = Offset.Zero,
        end = Offset.Infinite,
    )
}
```

The iOS `goldText()` modifier paints text with `accentGradient`. In Compose, fill
text with a brush via `TextStyle(brush = ...)`:

```kotlin
Text(
    text = "JetSetter Pro",
    style = JetTypography.headlineLarge.copy(brush = JetGradients.accentGradient),
)
```

---

## 3. Typography

iOS `JetsetterTheme.Typography` uses the SF system font with two designs:

- `.rounded` → **no stock Android equivalent.** Bundle **Nunito** (SIL Open Font
  License 1.1) as the closest rounded-geometric match. Place the `.ttf`/variable
  font in `res/font/` and build a `FontFamily`.
- `.default` → **Roboto** (the platform default — no asset needed).

| iOS token | Size (sp) | Weight | iOS design | Android family | Material 3 slot (suggested) |
|---|---|---|---|---|---|
| `heroTitle` | 38 | Bold (700) | rounded | Nunito | `displaySmall` |
| `displayTitle` | 28 | Bold (700) | rounded | Nunito | `headlineMedium` |
| `pageTitle` | 22 | Bold (700) | rounded | Nunito | `headlineSmall` |
| `cardTitle` | 17 | SemiBold (600) | default | Roboto | `titleMedium` |
| `bodyMedium` | 15 | Medium (500) | default | Roboto | `bodyLarge` |
| `metric` | 34 | Bold (700) | rounded | Nunito | `displayMedium` |
| `label` | 12 | SemiBold (600) | rounded | Nunito | `labelMedium` |
| `caption` | 11 | Medium (500) | default | Roboto | `labelSmall` |

> iOS uses **points**; Compose uses **sp** for text. Use the same numeric values
> (38pt → 38.sp) for visual parity at the default scale.

### 3a. Font families — `Type.kt`

```kotlin
package com.jetsetter.pro.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.jetsetter.pro.R

// Rounded design → Nunito (OFL). Add res/font/nunito_*.ttf
val Nunito = FontFamily(
    Font(R.font.nunito_medium,   FontWeight.Medium),
    Font(R.font.nunito_semibold, FontWeight.SemiBold),
    Font(R.font.nunito_bold,     FontWeight.Bold),
)

// Default design → Roboto (platform default)
val DefaultSans = FontFamily.Default

val JetTypography = Typography(
    displaySmall   = TextStyle(fontFamily = Nunito,      fontWeight = FontWeight.Bold,     fontSize = 38.sp), // heroTitle
    displayMedium  = TextStyle(fontFamily = Nunito,      fontWeight = FontWeight.Bold,     fontSize = 34.sp), // metric
    headlineMedium = TextStyle(fontFamily = Nunito,      fontWeight = FontWeight.Bold,     fontSize = 28.sp), // displayTitle
    headlineSmall  = TextStyle(fontFamily = Nunito,      fontWeight = FontWeight.Bold,     fontSize = 22.sp), // pageTitle
    titleMedium    = TextStyle(fontFamily = DefaultSans, fontWeight = FontWeight.SemiBold, fontSize = 17.sp), // cardTitle
    bodyLarge      = TextStyle(fontFamily = DefaultSans, fontWeight = FontWeight.Medium,   fontSize = 15.sp), // bodyMedium
    labelMedium    = TextStyle(fontFamily = Nunito,      fontWeight = FontWeight.SemiBold, fontSize = 12.sp), // label
    labelSmall     = TextStyle(fontFamily = DefaultSans, fontWeight = FontWeight.Medium,   fontSize = 11.sp), // caption
)
```

> `res/font/` files must be lowercase + underscores only (`nunito_bold.ttf`).
> Prefer the **variable** Nunito font with `Font(R.font.nunito_variable, weight)`
> if you want a single asset; the discrete weights above are the conservative path.

---

## 4. Shape & spacing

iOS constants: card `cornerRadius 18`, card `padding 16`; spacing scale
`xsmall 4 / small 8 / medium 16 / large 24 / xlarge 32`.

```kotlin
package com.jetsetter.pro.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp

object JetDimens {
    val cardCornerRadius = 18.dp
    val cardPadding      = 16.dp
    val inputCornerRadius = 12.dp   // premiumInput / PremiumInputStyle
    val tagCornerRadius   = 999.dp  // Capsule → fully rounded
}

object JetSpacing {
    val xsmall = 4.dp
    val small  = 8.dp
    val medium = 16.dp
    val large  = 24.dp
    val xlarge = 32.dp
}

// Material 3 Shapes — card radius drives medium/large
val JetShapes = Shapes(
    small      = RoundedCornerShape(12.dp),
    medium     = RoundedCornerShape(18.dp),
    large      = RoundedCornerShape(18.dp),
    extraLarge = RoundedCornerShape(28.dp),
)
```

> iOS uses `RoundedRectangle(style: .continuous)` (squircle corners). Compose has
> no continuous-corner shape built in; `RoundedCornerShape` (circular arcs) is the
> standard substitute. The visual difference at 18 dp is negligible. If exactness
> matters later, an `AbsoluteSmoothCornerShape` (community lib) can approximate it.

---

## 5. Components

### 5a. `jetCard()` — glass card

iOS `CardStyle` (the `.jetCard()` modifier) composes four layers:

1. **Fill** — dark: `.ultraThinMaterial` (a *blur-behind* translucent material);
   light: solid white.
2. **Inner glow** (dark only) — `cardInnerGlow` gradient overlay.
3. **Border** — 0.6 pt stroke; dark: `accentBorderGradient`; light: `black @ 6%`.
4. **Shadow** — dark: `black @ 55%`, radius 24, y +12; light: `black @ 6%`,
   radius 10, y +4.

**Compose blur caveat:** there is **no real backdrop/material blur** in Compose
on `minSdk 26`. `Modifier.blur()` blurs the *content of a node*, not what is
behind it, and is only hardware-accelerated on API 31+ (it becomes a no-op /
falls back below that). So the iOS `.ultraThinMaterial` is approximated with a
**translucent surface fill** (e.g. `surface @ ~70–85%` over the gradient
background) plus the inner-glow gradient and the gradient border. Genuine
backdrop blur, if desired, requires API 31+ via a `RenderEffect` on the
background layer or a `HazeBlur`-style community library — treat it as an
optional enhancement, not a parity requirement.

```kotlin
package com.jetsetter.pro.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color

/** Android equivalent of iOS `.jetCard()`. Apply to a card container. */
fun Modifier.jetCard(dark: Boolean, jet: JetColors): Modifier = this
    .shadow(
        elevation = if (dark) 24.dp else 10.dp,
        shape = RoundedCornerShape(JetDimens.cardCornerRadius),
        ambientColor = Color.Black.copy(alpha = if (dark) 0.55f else 0.06f),
        spotColor = Color.Black.copy(alpha = if (dark) 0.55f else 0.06f),
    )
    .clip(RoundedCornerShape(JetDimens.cardCornerRadius))
    .background(
        // dark: translucent surface (≈ ultraThinMaterial); light: solid white
        if (dark) jet.surface.copy(alpha = 0.78f) else Color.White,
        RoundedCornerShape(JetDimens.cardCornerRadius),
    )
    .then(
        if (dark) Modifier.background(JetGradients.cardInnerGlow, RoundedCornerShape(JetDimens.cardCornerRadius))
        else Modifier
    )
    .border(
        width = 0.6.dp,
        brush = if (dark) JetGradients.accentBorderGradient
                else SolidColor(Color.Black.copy(alpha = 0.06f)),
        shape = RoundedCornerShape(JetDimens.cardCornerRadius),
    )
    .padding(JetDimens.cardPadding)
```

> `shadow()` ambient/spot colors only render colored shadows on API 28+; below
> that the elevation still casts the default shadow. Acceptable for minSdk 26.

### 5b. `GoldTag` → `AccentTag` — accent capsule

iOS `GoldTag(text:icon:)`: `label` typography, horizontal 10 / vertical 5 padding,
fill `accent @ 15%`, foreground `accent`, `Capsule` clip, `accent @ 30%` 0.5 pt
border. Optional leading SF Symbol.

```kotlin
@Composable
fun AccentTag(
    text: String,
    icon: ImageVector? = null,
    modifier: Modifier = Modifier,
) {
    val jet = LocalJetColors.current
    Row(
        modifier = modifier
            .clip(CircleShape) // capsule
            .background(jet.accent.copy(alpha = 0.15f))
            .border(0.5.dp, jet.accent.copy(alpha = 0.30f), CircleShape)
            .padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (icon != null) Icon(icon, null, tint = jet.accent, modifier = Modifier.size(11.dp))
        Text(text, style = JetTypography.labelMedium, color = jet.accent)
    }
}
```

### 5c. `premiumInput()` — rounded field

iOS `PremiumInputStyle`: horizontal 14 / vertical 13 padding, `cornerRadius 12`,
fill dark `#141726` / light `#F4F5FB`, border dark `accent @ 18%` / light
`black @ 6%`, 0.5 pt. (Note the dark fill `#141726` is intentionally a touch
darker than `surface`.)

```kotlin
@Composable
fun PremiumTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String = "",
    modifier: Modifier = Modifier,
) {
    val dark = isSystemInDarkTheme()
    val jet = LocalJetColors.current
    val fill   = if (dark) Color(0xFF141726) else Color(0xFFF4F5FB)
    val stroke = if (dark) jet.accent.copy(alpha = 0.18f) else Color.Black.copy(alpha = 0.06f)

    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        textStyle = JetTypography.bodyLarge.copy(color = jet.textPrimary),
        cursorBrush = SolidColor(jet.accent),
        modifier = modifier
            .clip(RoundedCornerShape(JetDimens.inputCornerRadius))
            .background(fill)
            .border(0.5.dp, stroke, RoundedCornerShape(JetDimens.inputCornerRadius))
            .padding(horizontal = 14.dp, vertical = 13.dp),
        decorationBox = { inner ->
            if (value.isEmpty()) Text(placeholder, style = JetTypography.bodyLarge, color = jet.textSecondary)
            inner()
        },
    )
}
```

---

## 6. `flightStatusColor` mapping

iOS extends `String.flightStatusColor` (case-insensitive). Port as a helper that
returns a brand color from the active palette.

| Status string (lowercased) | Color token |
|---|---|
| `on time`, `scheduled`, `active` | `success` |
| `delayed` | `warning` |
| `cancelled`, `diverted` | `danger` |
| *(anything else / default)* | `textSecondary` |

```kotlin
@Composable
fun flightStatusColor(status: String): Color {
    val jet = LocalJetColors.current
    return when (status.lowercase()) {
        "on time", "scheduled", "active" -> jet.success
        "delayed"                        -> jet.warning
        "cancelled", "diverted"          -> jet.danger
        else                             -> jet.textSecondary
    }
}

// Non-composable variant when you already hold a JetColors instance:
fun JetColors.flightStatusColor(status: String): Color = when (status.lowercase()) {
    "on time", "scheduled", "active" -> success
    "delayed"                        -> warning
    "cancelled", "diverted"          -> danger
    else                             -> textSecondary
}
```

---

## 7. Per-model accent hexes (reference)

Several iOS models carry their own `colorHex`/`color` strings (independent of the
theme palette) for category chips. Port these as `Color(0xFF……)` constants
alongside each enum so list rows match iOS exactly. Examples:

- **`ItineraryItemType.color`** — flight `#0066CC`, hotel `#0A7A5E`, activity
  `#C8860A`, transport `#1A2E40`, restaurant `#CC3B1E`.
- **`ExpenseCategory.colorHex`** — food `#CC3B1E`, transport `#0066CC`,
  accommodation `#0A7A5E`, entertainment `#C8860A`, business `#1A2E40`, shopping
  `#7B2D8B`, medical `#E5383B`, mileage `#4E9AF1`, other `#888888`.
- **`WalletItemType.colorHex`**, **`BagStatus.colorHex`**, **`DocumentType.colorHex`**,
  **`DisruptionType.colorHex`** — see the respective models in `API_REFERENCE.md`.

Keep these literal (do not remap onto theme tokens) so category coloring stays
1:1 with iOS.
