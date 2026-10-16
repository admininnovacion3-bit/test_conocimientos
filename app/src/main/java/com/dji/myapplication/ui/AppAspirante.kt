package com.dji.myapplication.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.dji.myapplication.ui.EvaluacionViewModel
import com.dji.myapplication.ui.Pantalla
import com.dji.myapplication.ui.pantallas.CarreraScreen
import com.dji.myapplication.ui.pantallas.ConfirmarCarreraScreen
import com.dji.myapplication.ui.pantallas.FinalScreen
import com.dji.myapplication.ui.pantallas.IntroScreen
import com.dji.myapplication.ui.pantallas.NombreScreen
import com.dji.myapplication.ui.pantallas.PreguntaScreen
import com.dji.myapplication.ui.theme.Violeta

/** Raíz de la interfaz: muestra la pantalla que indica el ViewModel, con una transición suave. */
@Composable
fun AppAspirante(vm: EvaluacionViewModel) {
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).safeDrawingPadding()) {
        AnimatedContent(
            targetState = vm.pantalla,
            // Solo se anima el cambio de "tipo" de pantalla; entre preguntas se reemplaza sin animar el bloque entero.
            contentKey = { it::class },
            transitionSpec = { (slideInHorizontally { it / 4 } + fadeIn()) togetherWith fadeOut() },
            label = "pantallas",
        ) { p ->
            when (p) {
                Pantalla.Cargando -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = Violeta) }
                Pantalla.Intro -> IntroScreen(vm)
                Pantalla.Nombre -> NombreScreen(vm)
                is Pantalla.ElegirCarrera -> CarreraScreen(vm, p.opciones)
                is Pantalla.ConfirmarCarrera -> ConfirmarCarreraScreen(vm, p)
                is Pantalla.Pregunta -> PreguntaScreen(vm, (vm.pantalla as? Pantalla.Pregunta)?.pregunta ?: p.pregunta)
                Pantalla.Final -> FinalScreen()
            }
        }
    }
}
