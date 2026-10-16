package com.dji.myapplication.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.dji.myapplication.data.Carrera
import com.dji.myapplication.data.EvaluacionRepositorio
import com.dji.myapplication.data.PreguntaAspirante
import com.dji.myapplication.ui.EvaluacionViewModel
import com.dji.myapplication.ui.Pantalla
import com.dji.myapplication.ui.mascota.Tip
import com.dji.myapplication.ui.mascota.Tips
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject

/** Pantallas del aspirante como una máquina de estados simple (sin login ni registro). */
sealed interface Pantalla {
    data object Cargando : Pantalla
    data object Intro : Pantalla
    data object Nombre : Pantalla
    data class ElegirCarrera(val opciones: List<Carrera>) : Pantalla
    data class ConfirmarCarrera(val carrera: Carrera, val texto: String, val porIA: Boolean) : Pantalla
    data class Pregunta(val pregunta: PreguntaAspirante, val mostradaEn: Long = System.currentTimeMillis()) : Pantalla
    data object Final : Pantalla
}

class EvaluacionViewModel : ViewModel() {
    private val repo = EvaluacionRepositorio

    var pantalla by mutableStateOf<Pantalla>(Pantalla.Cargando)
        private set
    var ocupado by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set
    var tip by mutableStateOf<Tip?>(null)
        private set
    var nombre by mutableStateOf("")
        private set

    private var evaluacionId: String? = null
    private var carreras: List<Carrera> = emptyList()

    val primerNombre get() = nombre.trim().substringBefore(' ')

    init {
        viewModelScope.launch {
            if (!repo.configurado) {
                error = "Falta configurar SUPABASE_URL y SUPABASE_ANON_KEY en local.properties."
                pantalla = Pantalla.Intro
                return@launch
            }
            // Si la app se cerró a mitad de camino, se retoma donde iba (misma sesión anónima).
            pantalla = try {
                if (!repo.haySesion()) Pantalla.Intro else {
                    val r = repo.reanudar()
                    evaluacionId = r.evaluacionId
                    when (r.estado) {
                        "completada" -> Pantalla.Final
                        "en_curso" -> { cargarSiguiente(); pantalla }
                        else -> Pantalla.Intro
                    }
                }
            } catch (e: Exception) {
                error = traducirError(e); Pantalla.Intro
            }
        }
    }

    fun limpiarError() { error = null }

    fun irANombre() { pantalla = Pantalla.Nombre }

    fun confirmarNombre(valor: String) = ejecutar {
        nombre = valor.trim().replace(Regex("\\s+"), " ")
        repo.entrarComoAspirante(nombre)
        if (carreras.isEmpty()) carreras = repo.carreras()
        pantalla = Pantalla.ElegirCarrera(carreras)
    }

    /** El aspirante escribió su carrera: la IA (o las palabras clave) la ubica en el catálogo. */
    fun interpretarCarrera(texto: String) = ejecutar {
        val r = repo.clasificarCarrera(texto)
        val carrera = carreras.firstOrNull { it.id == r.carreraId } ?: Carrera(r.carreraId, r.nombre, "")
        pantalla = Pantalla.ConfirmarCarrera(carrera, texto.trim(), porIA = true)
    }

    /** Atajo: tocó una de las carreras sugeridas. */
    fun elegirCarrera(carrera: Carrera) {
        pantalla = Pantalla.ConfirmarCarrera(carrera, carrera.nombre, porIA = false)
    }

    fun corregirCarrera() { pantalla = Pantalla.ElegirCarrera(carreras) }

    fun empezar(confirmada: Pantalla.ConfirmarCarrera) = ejecutar {
        val r = repo.iniciarEvaluacion(nombre, confirmada.carrera.id, confirmada.texto)
        evaluacionId = r.evaluacionId
        if (r.estado == "completada") pantalla = Pantalla.Final else cargarSiguiente()
    }

    /**
     * Envía la respuesta y pide la siguiente. La app nunca sabe si acertó.
     * [preguntaId] evita que un toque tardío o el fin del cronómetro respondan la pregunta equivocada.
     */
    fun responder(preguntaId: String, respuesta: JsonObject, tiempoAgotado: Boolean = false) {
        val actual = pantalla as? Pantalla.Pregunta ?: return
        // Ya se está enviando esta pregunta (tocó "Siguiente" justo al llegar a 0): no se envía dos veces
        if (actual.pregunta.id != preguntaId || ocupado) return
        if (tiempoAgotado) decir(Tips.TIEMPO_AGOTADO)
        ejecutar {
            repo.responder(preguntaId, respuesta, System.currentTimeMillis() - actual.mostradaEn, tiempoAgotado)
            cargarSiguiente()
        }
    }

    // ---------------- Tips de Bit ----------------
    fun tocarMascota() {
        val tipo = (pantalla as? Pantalla.Pregunta)?.pregunta?.tipo
        decir(Tips.alTocar(tipo))
    }

    fun ocultarTip() { tip = null }

    fun avisarTiempo(segundosRestantes: Int, limite: Int) {
        Tips.porTiempo(segundosRestantes, limite)?.let(::decir)
    }

    private fun decir(texto: String) { tip = Tip(System.nanoTime(), texto) }

    private suspend fun cargarSiguiente() {
        val id = evaluacionId ?: return
        val siguiente = repo.siguientePregunta(id)
        val pregunta = siguiente.pregunta
        if (siguiente.fin || pregunta == null) {
            repo.finalizar(id)
            tip = null
            pantalla = Pantalla.Final
        } else {
            pantalla = Pantalla.Pregunta(pregunta)
            Tips.alLlegar(pregunta.orden, pregunta.total, pregunta.tipo)?.let(::decir)
            // Reabrió la app con el tiempo ya vencido: se envía vacía y se sigue
            if (pregunta.segundosRestantes <= 0) {
                repo.responder(pregunta.id, JsonObject(emptyMap()), 0, tiempoAgotado = true)
                cargarSiguiente()
            }
        }
    }

    private fun ejecutar(accion: suspend () -> Unit) {
        if (ocupado) return
        viewModelScope.launch {
            ocupado = true
            error = null
            try {
                accion()
            } catch (e: Exception) {
                error = traducirError(e)
            } finally {
                ocupado = false
            }
        }
    }

    private fun traducirError(e: Exception): String {
        val m = e.message.orEmpty()
        return when {
            "Unable to resolve host" in m || "timeout" in m.lowercase() -> "Sin conexión. Revisa tu internet e inténtalo de nuevo."
            "anonymous" in m.lowercase() -> "El acceso de aspirantes no está habilitado. Avísale a tu profesor."
            "Nombre inválido" in m -> "Escribe tu nombre usando solo letras."
            else -> "Ocurrió un problema. Inténtalo de nuevo."
        }
    }
}
