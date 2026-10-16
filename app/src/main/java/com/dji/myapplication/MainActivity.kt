package com.dji.myapplication

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.viewmodel.compose.viewModel
import com.dji.myapplication.ui.AppAspirante
import com.dji.myapplication.ui.EvaluacionViewModel
import com.dji.myapplication.ui.theme.EvaluacionTheme

/**
 * Punto de entrada de la app del ASPIRANTE.
 * Flujo: intro → nombre → carrera (IA) → 20 preguntas con cronómetro → "Proceso completado".
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            EvaluacionTheme {
                val vm: EvaluacionViewModel = viewModel()
                AppAspirante(vm)
            }
        }
    }
}
