package com.dji.myapplication.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.lightColorScheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp

// Esquema fijo (sin color dinámico): la identidad visual debe ser igual en todos los celulares.
private val Esquema = lightColorScheme(
    primary = Violeta,
    onPrimary = Blanco,
    primaryContainer = VioletaSuave,
    onPrimaryContainer = Violeta,
    secondary = Rosa,
    tertiary = Naranja,
    background = Lavanda,
    onBackground = TextoFuerte,
    surface = Blanco,
    onSurface = TextoFuerte,
    onSurfaceVariant = TextoSuave,
    surfaceVariant = VioletaSuave,
)

private val Formas = Shapes(
    small = RoundedCornerShape(10.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(24.dp),
)

@Composable
fun EvaluacionTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = Esquema, typography = Typography, shapes = Formas, content = content)
}
