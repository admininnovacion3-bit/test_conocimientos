package com.dji.myapplication.ui.pantallas

import android.app.Activity
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dji.myapplication.ui.Pantalla
import com.dji.myapplication.ui.componentes.BotonPrincipal
import com.dji.myapplication.ui.mascota.GloboDialogo
import com.dji.myapplication.ui.mascota.Mascota
import com.dji.myapplication.ui.pantallas.FinalScreen

/** Pantalla 6: cierre. Nunca muestra puntaje. */
@Composable
fun FinalScreen() {
    BackHandler { }
    val actividad = LocalContext.current as? Activity
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        // Bit celebra el esfuerzo, nunca el resultado (el aspirante no conoce su puntaje).
        GloboDialogo("¡Gracias por tu esfuerzo! Fue un gusto acompañarte.", Modifier.fillMaxWidth())
        Spacer(Modifier.height(12.dp))
        Mascota(alto = 170.dp, hablando = true)
        Spacer(Modifier.height(28.dp))
        // Mensaje único y fijo: sin puntaje, fortalezas, debilidades ni recomendaciones.
        Text(
            "Proceso completado.\nValida con tu profesor.",
            style = MaterialTheme.typography.headlineMedium, textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(36.dp))
        BotonPrincipal("Salir", onClick = { actividad?.finish() })
    }
}
