package com.dji.myapplication.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Lo que el servidor envía al aspirante. Nótese lo que NO existe aquí:
// respuesta correcta, nivel, tema, puntaje. La app no puede mostrar lo que nunca recibe.

@Serializable
data class IniciarRespuesta(
    @SerialName("evaluacion_id") val evaluacionId: String? = null,
    val estado: String,            // en_curso | completada | sin_evaluacion
)

/** Carrera del catálogo (tabla carreras, lectura pública para usuarios autenticados). */
@Serializable
data class Carrera(
    val id: String,
    val nombre: String,
    val descripcion: String,
)

/** Respuesta de la función clasificar-carrera (palabras clave o IA sobre una lista cerrada). */
@Serializable
data class ClasificacionCarrera(
    @SerialName("carrera_id") val carreraId: String,
    val nombre: String,
    val metodo: String,
)

@Serializable
data class SiguienteRespuesta(
    val fin: Boolean,
    val pregunta: PreguntaAspirante? = null,
)

@Serializable
data class PreguntaAspirante(
    val id: String,
    val orden: Int,
    val total: Int,
    val tipo: String,
    val contenido: JsonObject,
    /** Tiempo total de la pregunta y lo que queda según el RELOJ DEL SERVIDOR (si se reabre la app, sigue corriendo). */
    @SerialName("tiempo_limite_s") val tiempoLimiteS: Int = 90,
    @SerialName("segundos_restantes") val segundosRestantes: Int = tiempoLimiteS,
) {
    private fun texto(campo: String) = contenido[campo]?.jsonPrimitive?.contentOrNull

    val contexto get() = texto("contexto")
    val enunciado get() = texto("enunciado")
    val afirmacion get() = texto("afirmacion")
    val codigo get() = texto("codigo")
    val lenguaje get() = texto("lenguaje")
    val esVerdaderoFalso get() = tipo == "verdadero_falso_justificado"

    /** Opciones ordenadas por letra (A, B, C, D). */
    val opciones: List<Pair<String, String>>
        get() {
            val campo = if (esVerdaderoFalso) "opciones_justificacion" else "opciones"
            return contenido[campo]?.jsonObject?.entries
                ?.map { it.key to (it.value as JsonPrimitive).content }
                ?.sortedBy { it.first }
                .orEmpty()
        }
}

/** Fila que el aspirante inserta en la tabla respuestas (RLS: solo INSERT). */
@Serializable
data class NuevaRespuesta(
    @SerialName("pregunta_id") val preguntaId: String,
    val respuesta: JsonObject,
    @SerialName("tiempo_ms") val tiempoMs: Long,
    @SerialName("tiempo_agotado") val tiempoAgotado: Boolean = false,
)
