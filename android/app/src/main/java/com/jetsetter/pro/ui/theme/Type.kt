package com.jetsetter.pro.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// iOS uses SF system fonts: `.rounded` for display weights, `.default` for body text.
// Android has no system "rounded" face, so Roboto (FontFamily.Default) is used for both.
// To match the iOS rounded look, bundle Nunito (OFL) under res/font and set Rounded = that
// family — see docs/DESIGN_SYSTEM.md.
private val Default = FontFamily.Default
private val Rounded = FontFamily.Default

/** Named text styles ported from `JetsetterTheme.Typography`. */
@Immutable
data class JetTypography(
    val heroTitle: TextStyle = TextStyle(fontFamily = Rounded, fontSize = 38.sp, fontWeight = FontWeight.Bold),
    val displayTitle: TextStyle = TextStyle(fontFamily = Rounded, fontSize = 28.sp, fontWeight = FontWeight.Bold),
    val pageTitle: TextStyle = TextStyle(fontFamily = Rounded, fontSize = 22.sp, fontWeight = FontWeight.Bold),
    val cardTitle: TextStyle = TextStyle(fontFamily = Default, fontSize = 17.sp, fontWeight = FontWeight.SemiBold),
    val bodyMedium: TextStyle = TextStyle(fontFamily = Default, fontSize = 15.sp, fontWeight = FontWeight.Medium),
    val metric: TextStyle = TextStyle(fontFamily = Rounded, fontSize = 34.sp, fontWeight = FontWeight.Bold),
    val label: TextStyle = TextStyle(fontFamily = Rounded, fontSize = 12.sp, fontWeight = FontWeight.SemiBold),
    val caption: TextStyle = TextStyle(fontFamily = Default, fontSize = 11.sp, fontWeight = FontWeight.Medium),
)

val LocalJetTypography = staticCompositionLocalOf { JetTypography() }

/** Material 3 type scale mapped onto the JetSetter sizes (used by stock M3 components). */
val JetMaterialTypography = Typography(
    titleLarge = TextStyle(fontFamily = Rounded, fontSize = 22.sp, fontWeight = FontWeight.Bold),
    titleMedium = TextStyle(fontFamily = Default, fontSize = 17.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontFamily = Default, fontSize = 15.sp, fontWeight = FontWeight.Normal),
    bodyMedium = TextStyle(fontFamily = Default, fontSize = 15.sp, fontWeight = FontWeight.Medium),
    labelMedium = TextStyle(fontFamily = Rounded, fontSize = 12.sp, fontWeight = FontWeight.SemiBold),
)
