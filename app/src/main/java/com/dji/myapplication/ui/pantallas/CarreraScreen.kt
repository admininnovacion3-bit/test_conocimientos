package com.dji.myapplication.ui.pantallas

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.dji.myapplication.data.Carrera
import com.dji.myapplication.ui.EvaluacionViewModel
import com.dji.myapplication.ui.Pantalla
import com.dji.myapplication.ui.componentes.BotonPrincipal
import com.dji.myapplication.ui.componentes.MensajeError
import com.dji.myapplication.ui.mascota.EscenaBit
import com.dji.myapplication.ui.pantallas.CarreraScreen
import com.dji.myapplication.ui.pantallas.ConfirmarCarreraScreen
import com.dji.myapplication.ui.theme.Violeta
import com.dji.myapplication.ui.theme.VioletaSuave

/** Pantallas 3 y 4: la carrera (texto libre que interpreta la IA o carreras sugeridas) y su confirmación. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CarreraScreen(vm: EvaluacionViewModel, opciones: List<Carrera>) {
    var texto by rememberSaveable { mutableStateOf("") }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().padding(24.dp), verticalArrangement = Arrangement.Center) {
        EscenaBit("Mucho gusto, ${vm.primerNombre}. ¿Qué carrera estudias? Escríbela como quieras, yo la entiendo.")
        Spacer(Modifier.height(24.dp))
        OutlinedTextField(
            value = texto, onValueChange = { if (it.length <= 100) texto = it; vm.limpiarError() },
            label = { Text("Ej: ing. de sistemas, tecnólogo ADSI…") }, singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { if (texto.isNotBlank()) vm.interpretarCarrera(texto) }),
            shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(12.dp))
        BotonPrincipal("Continuar", onClick = { vm.interpretarCarrera(texto) }, habilitado = texto.trim().length >= 2, cargando = vm.ocupado)
        Spacer(Modifier.height(20.dp))
        Text("O elige una:", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(8.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            opciones.forEach { c ->
                Surface(onClick = { vm.elegirCarrera(c) }, shape = RoundedCornerShape(12.dp), color = VioletaSuave) {
                    Text(c.nombre, color = Violeta, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp))
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        MensajeError(vm.error)
    }
}

@Composable
fun ConfirmarCarreraScreen(vm: EvaluacionViewModel, p: Pantalla.ConfirmarCarrera) {
    val mensaje = if (p.porIA) "¡Entendido! Por lo que escribiste, estudias ${p.carrera.nombre}. ¿Es correcto?"
    else "¡Genial, ${p.carrera.nombre}! Prepararé preguntas pensadas para tu carrera."
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.Center) {
        EscenaBit(mensaje)
        Spacer(Modifier.height(20.dp))
        Surface(color = MaterialTheme.colorScheme.surface, shape = RoundedCornerShape(18.dp), modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Antes de empezar", style = MaterialTheme.typography.titleMedium)
                listOf(
                    "Son 20 preguntas: las 5 primeras son básicas y luego se ajustan a ti.",
                    "Cada pregunta tiene cronómetro: si llega a cero, pasa sola a la siguiente.",
                    "Una vez enviada, la respuesta no se puede cambiar.",
                    "Responde solo, sin buscar en internet.",
                    "Al final no verás puntaje: tu profesor lo revisará contigo.",
                ).forEach { regla ->
                    Row {
                        Box(Modifier.padding(top = 8.dp).size(6.dp).clip(RoundedCornerShape(3.dp)).background(Violeta))
                        Text(regla, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(start = 10.dp))
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        MensajeError(vm.error)
        Spacer(Modifier.height(8.dp))
        BotonPrincipal(if (p.porIA) "Sí, empezar" else "Empezar", onClick = { vm.empezar(p) }, cargando = vm.ocupado)
        TextButton(onClick = vm::corregirCarrera, modifier = Modifier.fillMaxWidth(), enabled = !vm.ocupado) {
            Text(if (p.porIA) "No, quiero corregirla" else "Cambiar carrera")
        }
    }
}
