package com.dji.myapplication.ui.pantallas

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dji.myapplication.ui.EvaluacionViewModel
import com.dji.myapplication.ui.Pantalla
import com.dji.myapplication.ui.componentes.BotonPrincipal
import com.dji.myapplication.ui.componentes.MensajeError
import com.dji.myapplication.ui.mascota.EscenaBit
import com.dji.myapplication.ui.pantallas.IntroScreen

/** Pantalla 1: Bit se presenta. */
@Composable
fun IntroScreen(vm: EvaluacionViewModel) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        EscenaBit("¡Hola! Soy Bit. Te voy a acompañar en tu evaluación para la práctica en el área de Innovación.", 190)
        Spacer(Modifier.height(28.dp))
        Text("Evaluación de aspirantes", style = MaterialTheme.typography.headlineMedium, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        Text(
            "Software y Sistemas · 20 preguntas · ~30 min",
            style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(24.dp))
        MensajeError(vm.error)
        Spacer(Modifier.height(8.dp))
        BotonPrincipal("¡Vamos!", onClick = vm::irANombre, habilitado = vm.error == null || !vm.error!!.contains("SUPABASE"))
    }
}
