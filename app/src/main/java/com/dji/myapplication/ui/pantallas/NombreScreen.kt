package com.dji.myapplication.ui.pantallas

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.dji.myapplication.ui.EvaluacionViewModel
import com.dji.myapplication.ui.Pantalla
import com.dji.myapplication.ui.componentes.BotonPrincipal
import com.dji.myapplication.ui.componentes.MensajeError
import com.dji.myapplication.ui.mascota.EscenaBit
import com.dji.myapplication.ui.pantallas.NombreScreen

/** Pantalla 2: el aspirante escribe su nombre (crea la sesión anónima). */
@Composable
fun NombreScreen(vm: EvaluacionViewModel) {
    var nombre by rememberSaveable { mutableStateOf(vm.nombre) }
    val valido = nombre.trim().length >= 3 && nombre.trim().all { it.isLetter() || it == ' ' || it == '.' || it == '\'' || it == '-' }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().padding(24.dp), verticalArrangement = Arrangement.Center) {
        EscenaBit("Primero lo primero: ¿cómo te llamas?")
        Spacer(Modifier.height(24.dp))
        OutlinedTextField(
            value = nombre, onValueChange = { if (it.length <= 80) nombre = it; vm.limpiarError() },
            label = { Text("Tu nombre completo") }, singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Next),
            keyboardActions = KeyboardActions(onNext = { if (valido) vm.confirmarNombre(nombre) }),
            shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(16.dp))
        MensajeError(vm.error)
        Spacer(Modifier.height(8.dp))
        BotonPrincipal("Continuar", onClick = { vm.confirmarNombre(nombre) }, habilitado = valido, cargando = vm.ocupado)
    }
}
