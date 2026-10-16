package com.dji.myapplication.ui.pantallas

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.dji.myapplication.data.PreguntaAspirante
import com.dji.myapplication.ui.EvaluacionViewModel
import com.dji.myapplication.ui.Pantalla
import com.dji.myapplication.ui.componentes.BloqueCodigo
import com.dji.myapplication.ui.componentes.BotonPrincipal
import com.dji.myapplication.ui.componentes.ChipSeleccion
import com.dji.myapplication.ui.componentes.Cronometro
import com.dji.myapplication.ui.componentes.EspacioVertical
import com.dji.myapplication.ui.componentes.MensajeError
import com.dji.myapplication.ui.componentes.TarjetaOpcion
import com.dji.myapplication.ui.mascota.GuiaEnEsquina
import com.dji.myapplication.ui.pantallas.PreguntaScreen
import com.dji.myapplication.ui.theme.Violeta
import com.dji.myapplication.ui.theme.VioletaSuave
import kotlinx.coroutines.delay
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/** Pantalla 5: una pregunta con cronómetro y Bit dando tips en la esquina. */
@Composable
fun PreguntaScreen(vm: EvaluacionViewModel, p: PreguntaAspirante) {
    BackHandler { /* No se permite volver atrás durante la evaluación */ }
    var opcion by remember(p.id) { mutableStateOf<String?>(null) }
    var valor by remember(p.id) { mutableStateOf<Boolean?>(null) }
    val completa = opcion != null && (!p.esVerdaderoFalso || valor != null)
    val ultima = p.orden == p.total

    // Lo que esté marcado en este momento (puede estar incompleto si se acaba el tiempo)
    fun respuestaActual() = buildJsonObject {
        if (p.esVerdaderoFalso) {
            valor?.let { put("valor", JsonPrimitive(it)) }
            opcion?.let { put("justificacion", JsonPrimitive(it)) }
        } else {
            opcion?.let { put("opcion", JsonPrimitive(it)) }
        }
    }

    // CRONÓMETRO: parte de lo que dice el servidor; al llegar a 0 envía lo marcado y pasa a la siguiente.
    var restantes by remember(p.id) { mutableIntStateOf(p.segundosRestantes) }
    LaunchedEffect(p.id) {
        while (restantes > 0) {
            delay(1000)
            restantes--
            vm.avisarTiempo(restantes, p.tiempoLimiteS)
        }
        vm.responder(p.id, respuestaActual(), tiempoAgotado = true)
    }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            Column(Modifier.padding(horizontal = 24.dp, vertical = 16.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Column {
                        Text("Pregunta ${p.orden} de ${p.total}", style = MaterialTheme.typography.titleMedium)
                        Text("${(p.orden * 100) / p.total}% completado", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Cronometro(restantes, p.tiempoLimiteS)
                }
                Spacer(Modifier.height(10.dp))
                LinearProgressIndicator(
                    progress = { (p.orden - 1).toFloat() / p.total },
                    modifier = Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(4.dp)),
                    color = Violeta, trackColor = VioletaSuave,
                )
            }
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp),
                verticalArrangement = EspacioVertical,
            ) {
                p.contexto?.let {
                    Surface(color = MaterialTheme.colorScheme.surface, shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth()) {
                        Text(it, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(16.dp))
                    }
                }
                (p.enunciado ?: p.afirmacion)?.let { Text(it, style = MaterialTheme.typography.titleLarge) }
                p.codigo?.let { BloqueCodigo(it, p.lenguaje) }

                if (p.esVerdaderoFalso) {
                    if (p.enunciado != null) p.afirmacion?.let { Text(it, style = MaterialTheme.typography.titleMedium) }
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        ChipSeleccion("Verdadero", valor == true, { valor = true }, Modifier.weight(1f))
                        ChipSeleccion("Falso", valor == false, { valor = false }, Modifier.weight(1f))
                    }
                    Text("¿Por qué?", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp))
                }
                p.opciones.forEach { (letra, texto) ->
                    TarjetaOpcion(letra, texto, opcion == letra) { opcion = letra }
                }
                MensajeError(vm.error)
                Spacer(Modifier.height(110.dp)) // espacio para que Bit no tape la última opción
            }
            Row(Modifier.padding(start = 96.dp, end = 24.dp, top = 8.dp, bottom = 20.dp)) {
                BotonPrincipal(
                    if (ultima) "Finalizar" else "Siguiente",
                    onClick = { vm.responder(p.id, respuestaActual()) },
                    habilitado = completa, cargando = vm.ocupado,
                )
            }
        }
        GuiaEnEsquina(
            tip = vm.tip, onToque = vm::tocarMascota, onOcultar = vm::ocultarTip,
            modifier = Modifier.align(Alignment.BottomStart).padding(start = 20.dp, bottom = 16.dp),
        )
    }
}
