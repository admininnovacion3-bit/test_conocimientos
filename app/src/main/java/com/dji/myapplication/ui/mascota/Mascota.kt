package com.dji.myapplication.ui.mascota

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.dji.myapplication.ui.mascota.EscenaBit
import com.dji.myapplication.ui.mascota.GloboDialogo
import com.dji.myapplication.ui.mascota.GuiaEnEsquina
import com.dji.myapplication.ui.mascota.Mascota
import com.dji.myapplication.ui.mascota.Tip
import com.dji.myapplication.ui.theme.Violeta
import com.dji.myapplication.ui.theme.VioletaSuave
import kotlinx.coroutines.delay

// =====================================================================
// "BIT": mascota pixel art ORIGINAL de la app (18 x 25 píxeles, estilo chibi).
// Se dibuja con Canvas a partir de una matriz de letras: no usa imágenes,
// así que pesa casi nada, escala sin perder nitidez y no tiene derechos de terceros.
// =====================================================================

private val PALETA = mapOf(
    'O' to Color(0xFF1A1A24), // contorno
    'H' to Color(0xFF6B4226), // pelo
    'h' to Color(0xFF9A643A), // brillo del pelo
    'S' to Color(0xFFF5C9A3), // piel
    'W' to Color(0xFFFFFFFF), // brillo de los ojos
    'R' to Color(0xFFF49AA8), // mejillas
    'V' to Violeta,           // bufanda y capa (color de la marca)
    'B' to Color(0xFF2F3361), // camisa
    'K' to Color(0xFF6B3E1F), // cinturón y botas
    'G' to Color(0xFFF2B640), // botones y hebilla
    'P' to Color(0xFF3D4170), // pantalón
)

private val QUIETO = listOf(
    "...O..OO..O.O.....",
    "..OHO.OHOOHOHO....",
    "..OHHOHHHHHHHHO...",
    ".OHHHHHHHHhHHHHO..",
    ".OHHhHHHHHHHHhHHO.",
    "OHHHHHHHHHHHHHHHO.",
    "OHHHSSSSSSSSSSHHO.",
    ".OHSSSSSSSSSSSSHO.",
    ".OHSSOOSSSSOOSSHO.",
    ".OHSSWOSSSSWOSSO..",
    ".OHSSOOSSSSOOSSO..",
    "..OSRRSSSSSSRRSO..",
    "..OSSSSSOOSSSSO...",
    "...OOSSSSSSSSOO...",
    "..OVVOOOSSOOOVVO..",
    ".OVVVVVVVVVVVVVVO.",
    "OVVOBBBBGGBBBBOVVO",
    "OVOSOBBBBBBBBOSOVO",
    "OVOSOBBBBBBBBOSOVO",
    ".OVOKKKKGGKKKKOVO.",
    "..OVOPPPPPPPPOVO..",
    "...OPPPPOOPPPPO...",
    "...OKKKKO.OKKKKO..",
    "..OKKKKKO.OKKKKKO.",
    "..OOOOOOO.OOOOOOO.",
)

/** Mismo cuerpo con el brazo derecho levantado (saluda mientras habla). */
private val SALUDO = QUIETO.toMutableList().apply {
    this[8] = ".OHSSOOSSSSOOSSHOO"
    this[9] = ".OHSSWOSSSSWOSSOSO"
    this[10] = ".OHSSOOSSSSOOSSOSO"
    this[11] = "..OSRRSSSSSSRRSOBO"
    this[12] = "..OSSSSSOOSSSSO.BO"
    this[13] = "...OOSSSSSSSSOO.BO"
    this[14] = "..OVVOOOSSOOOVVOBO"
    this[15] = ".OVVVVVVVVVVVVVVBO"
    this[16] = "OVVOBBBBGGBBBBBBO."
    this[17] = "OVOSOBBBBBBBBOVVO."
    this[18] = "OVOSOBBBBBBBBOOVO."
}

/** Ojos cerrados: los 2x3 píxeles de cada ojo pasan a piel, con una línea oscura en el centro. */
private val COLUMNAS_OJOS = listOf(5, 6, 11, 12)
private fun conOjosCerrados(base: List<String>) = base.mapIndexed { fila, linea ->
    if (fila !in 8..10) linea
    else linea.toCharArray().also { c -> COLUMNAS_OJOS.forEach { c[it] = if (fila == 9) 'O' else 'S' } }.concatToString()
}

private const val COLUMNAS = 18
private const val FILAS = 25

/**
 * Dibuja a Bit. [hablando] alterna entre saludo y reposo; siempre "respira" (sube y baja 1 píxel)
 * y parpadea cada pocos segundos para sentirse vivo.
 */
@Composable
fun Mascota(modifier: Modifier = Modifier, alto: Dp = 96.dp, hablando: Boolean = false) {
    var respiro by remember { mutableIntStateOf(0) }
    var parpadeo by remember { mutableStateOf(false) }
    var brazoArriba by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { while (true) { delay(450); respiro = 1 - respiro } }
    LaunchedEffect(Unit) {
        while (true) {
            delay((2500L..4500L).random()); parpadeo = true
            delay(140); parpadeo = false
        }
    }
    LaunchedEffect(hablando) {
        brazoArriba = false
        while (hablando) { delay(320); brazoArriba = !brazoArriba }
    }

    val base = if (brazoArriba) SALUDO else QUIETO
    val sprite = if (parpadeo) conOjosCerrados(base) else base
    val ancho = alto * (COLUMNAS.toFloat() / (FILAS + 1))

    Canvas(modifier.size(ancho, alto).semantics { contentDescription = "Bit, tu guía" }) {
        val px = size.height / (FILAS + 1)          // +1 fila libre para el movimiento de respiración
        val dy = if (respiro == 1) px else 0f
        sprite.forEachIndexed { fila, linea ->
            linea.forEachIndexed { col, c ->
                PALETA[c]?.let {
                    // +0.5 px evita líneas finas entre píxeles por redondeo
                    drawRect(it, Offset(col * px, fila * px + dy), Size(px + 0.5f, px + 0.5f))
                }
            }
        }
    }
}

/** Globo de diálogo blanco con borde violeta. */
@Composable
fun GloboDialogo(texto: String, modifier: Modifier = Modifier) {
    Surface(
        shape = RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp, bottomEnd = 18.dp, bottomStart = 4.dp),
        color = MaterialTheme.colorScheme.surface,
        border = BorderStroke(2.dp, VioletaSuave),
        shadowElevation = 3.dp,
        modifier = modifier,
    ) {
        Text(texto, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp))
    }
}

/**
 * Bit en la esquina inferior izquierda durante las preguntas: muestra tips y anuncios.
 * Al tocarlo da otro tip. El globo se oculta solo a los pocos segundos.
 */
@Composable
fun GuiaEnEsquina(tip: Tip?, onToque: () -> Unit, onOcultar: () -> Unit, modifier: Modifier = Modifier) {
    LaunchedEffect(tip?.id) {
        if (tip != null) { delay(7000); onOcultar() }
    }
    Row(modifier, verticalAlignment = Alignment.Bottom) {
        Mascota(
            alto = 72.dp,
            hablando = tip != null,
            modifier = Modifier.clickable(
                interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onToque,
            ),
        )
        AnimatedVisibility(
            visible = tip != null,
            enter = fadeIn() + scaleIn(spring(Spring.DampingRatioMediumBouncy), initialScale = 0.6f, transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0f, 1f)),
            exit = fadeOut() + scaleOut(targetScale = 0.8f),
        ) {
            GloboDialogo(tip?.texto.orEmpty(), Modifier.padding(start = 6.dp, bottom = 40.dp).widthIn(max = 250.dp))
        }
    }
}

/** Bit grande con su globo de diálogo: la "conversación" de las pantallas iniciales. */
@Composable
fun EscenaBit(mensaje: String, altoMascota: Int = 150) {
    // Al cambiar el mensaje, Bit "habla" (saluda) un par de segundos
    var hablando by remember(mensaje) { mutableStateOf(true) }
    LaunchedEffect(mensaje) { delay(2200); hablando = false }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        GloboDialogo(mensaje, Modifier.fillMaxWidth())
        Spacer(Modifier.height(12.dp))
        Mascota(alto = altoMascota.dp, hablando = hablando)
    }
}
