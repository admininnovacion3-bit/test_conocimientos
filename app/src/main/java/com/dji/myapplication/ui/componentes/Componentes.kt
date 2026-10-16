package com.dji.myapplication.ui.componentes

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dji.myapplication.ui.componentes.BloqueCodigo
import com.dji.myapplication.ui.componentes.BotonPrincipal
import com.dji.myapplication.ui.componentes.ChipSeleccion
import com.dji.myapplication.ui.componentes.Cronometro
import com.dji.myapplication.ui.componentes.EspacioVertical
import com.dji.myapplication.ui.componentes.MensajeError
import com.dji.myapplication.ui.componentes.TarjetaOpcion
import com.dji.myapplication.ui.theme.FondoCodigo
import com.dji.myapplication.ui.theme.Naranja
import com.dji.myapplication.ui.theme.TextoCodigo
import com.dji.myapplication.ui.theme.Violeta
import com.dji.myapplication.ui.theme.VioletaSuave

/** Botón principal violeta, ancho completo, como "Let's Start" de la referencia. */
@Composable
fun BotonPrincipal(texto: String, onClick: () -> Unit, habilitado: Boolean = true, cargando: Boolean = false) {
    Button(
        onClick = onClick,
        enabled = habilitado && !cargando,
        modifier = Modifier.fillMaxWidth().height(56.dp),
        shape = RoundedCornerShape(16.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Violeta),
    ) {
        if (cargando) {
            CircularProgressIndicator(Modifier.size(22.dp), color = MaterialTheme.colorScheme.onPrimary, strokeWidth = 2.dp)
        } else {
            Text(texto, style = MaterialTheme.typography.labelLarge)
        }
    }
}

/** Tarjeta de opción seleccionable (letra en círculo + texto). */
@Composable
fun TarjetaOpcion(letra: String, texto: String, seleccionada: Boolean, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(16.dp),
        color = if (seleccionada) VioletaSuave else MaterialTheme.colorScheme.surface,
        border = BorderStroke(if (seleccionada) 2.dp else 1.dp, if (seleccionada) Violeta else VioletaSuave),
        shadowElevation = if (seleccionada) 0.dp else 1.dp,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(32.dp).clip(CircleShape).background(if (seleccionada) Violeta else VioletaSuave),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    letra, fontWeight = FontWeight.Bold,
                    color = if (seleccionada) MaterialTheme.colorScheme.onPrimary else Violeta,
                )
            }
            Text(texto, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(start = 12.dp))
        }
    }
}

/** Bloque de código monoespaciado con scroll horizontal (no se rompen las líneas). */
@Composable
fun BloqueCodigo(codigo: String, lenguaje: String?) {
    Surface(color = FondoCodigo, shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth()) {
        Box(Modifier.padding(14.dp)) {
            Text(
                text = codigo.replace("[[HUECO]]", "  ______  "),
                fontFamily = FontFamily.Monospace,
                fontSize = 14.sp,
                lineHeight = 20.sp,
                color = TextoCodigo,
                modifier = Modifier.horizontalScroll(rememberScrollState()),
            )
        }
    }
    lenguaje?.let {
        Text(it.uppercase(), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun ChipSeleccion(texto: String, seleccionado: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(14.dp),
        color = if (seleccionado) Violeta else VioletaSuave,
        modifier = modifier.height(52.dp),
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                texto, style = MaterialTheme.typography.titleMedium,
                color = if (seleccionado) MaterialTheme.colorScheme.onPrimary else Violeta,
            )
        }
    }
}

val EspacioVertical = Arrangement.spacedBy(12.dp)

/**
 * Cronómetro circular: anillo que se vacía + segundos en el centro.
 * Violeta con tiempo de sobra, naranja bajo el 40 %, rojo y "latiendo" en los últimos 10 s.
 */
@Composable
fun Cronometro(restantes: Int, limite: Int, modifier: Modifier = Modifier) {
    val fraccion = if (limite > 0) restantes.toFloat() / limite else 0f
    val progreso by animateFloatAsState(fraccion, tween(900, easing = LinearEasing), label = "cronometro")
    val color = when {
        restantes <= 10 -> Color(0xFFE5484D)
        fraccion < 0.4f -> Naranja
        else -> Violeta
    }
    val latido = rememberInfiniteTransition(label = "latido")
    val escala by latido.animateFloat(
        initialValue = 1f, targetValue = if (restantes in 1..10) 1.12f else 1f,
        animationSpec = infiniteRepeatable(tween(500), RepeatMode.Reverse), label = "escala",
    )
    Box(
        modifier.size(58.dp).graphicsLayer { scaleX = escala; scaleY = escala }
            .semantics { contentDescription = "Quedan $restantes segundos" },
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator(
            progress = { progreso }, modifier = Modifier.fillMaxSize(),
            color = color, trackColor = VioletaSuave, strokeWidth = 5.dp,
        )
        val min = restantes / 60
        val seg = restantes % 60
        Text(
            if (min > 0) "$min:${seg.toString().padStart(2, '0')}" else "$seg",
            fontWeight = FontWeight.Bold, color = color, fontSize = if (min > 0) 14.sp else 17.sp,
        )
    }
}

/** Caja roja de error. Recibe el texto (o null para no mostrar nada). */
@Composable
fun MensajeError(error: String?) {
    error?.let {
        Surface(color = Color(0xFFFFE9EC), shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth()) {
            Text(it, color = Color(0xFFB3261E), modifier = Modifier.padding(12.dp), style = MaterialTheme.typography.bodyMedium)
        }
    }
}
