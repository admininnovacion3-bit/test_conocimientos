package com.dji.myapplication.data

import com.dji.myapplication.BuildConfig
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order
import io.ktor.client.statement.bodyAsText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * Única puerta de la app hacia Supabase.
 * - Auth ANÓNIMA: el aspirante no crea cuenta ni contraseña; Supabase le da una identidad
 *   invisible (JWT) que la RLS usa para que solo escriba SUS respuestas y nunca lea resultados.
 * - Edge Functions: clasificar carrera (IA), iniciar/reanudar, siguiente pregunta y finalizar.
 * - Postgrest: lectura de carreras e INSERT de respuestas.
 */
object EvaluacionRepositorio {

    val configurado = BuildConfig.SUPABASE_URL.isNotBlank() && BuildConfig.SUPABASE_ANON_KEY.isNotBlank()

    private val cliente by lazy {
        createSupabaseClient(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_ANON_KEY) {
            install(Auth)
            install(Postgrest)
            install(Functions)
        }
    }

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun haySesion(): Boolean {
        if (!configurado) return false
        cliente.auth.awaitInitialization()
        return cliente.auth.currentSessionOrNull() != null
    }

    /** Crea la identidad anónima la primera vez. La sesión queda guardada en el teléfono. */
    suspend fun entrarComoAspirante(nombre: String) {
        if (haySesion()) return
        cliente.auth.signInAnonymously(data = buildJsonObject { put("nombre_completo", JsonPrimitive(nombre)) })
    }

    suspend fun carreras(): List<Carrera> =
        cliente.from("carreras").select { order("orden", Order.ASCENDING) }.decodeList<Carrera>()

    suspend fun clasificarCarrera(texto: String): ClasificacionCarrera =
        llamar("clasificar-carrera", buildJsonObject { put("texto", JsonPrimitive(texto)) })

    /** Al reabrir la app: ¿hay una evaluación en curso o ya terminada en este teléfono? */
    suspend fun reanudar(): IniciarRespuesta =
        llamar("iniciar-evaluacion", buildJsonObject { put("reanudar", JsonPrimitive(true)) })

    suspend fun iniciarEvaluacion(nombre: String, carreraId: String, carreraTexto: String): IniciarRespuesta =
        llamar("iniciar-evaluacion", buildJsonObject {
            put("nombre", JsonPrimitive(nombre))
            put("carrera_id", JsonPrimitive(carreraId))
            put("carrera_texto", JsonPrimitive(carreraTexto))
        })

    suspend fun siguientePregunta(evaluacionId: String): SiguienteRespuesta =
        llamar("siguiente-pregunta", buildJsonObject { put("evaluacion_id", JsonPrimitive(evaluacionId)) })

    /** INSERT sin SELECT: el servidor califica con un trigger y el aspirante nunca ve el resultado. */
    suspend fun responder(preguntaId: String, respuesta: JsonObject, tiempoMs: Long, tiempoAgotado: Boolean) {
        cliente.from("respuestas").insert(NuevaRespuesta(preguntaId, respuesta, tiempoMs, tiempoAgotado))
    }

    suspend fun finalizar(evaluacionId: String) {
        cliente.functions.invoke(
            function = "finalizar-evaluacion",
            body = buildJsonObject { put("evaluacion_id", JsonPrimitive(evaluacionId)) },
        )
    }

    private suspend inline fun <reified T> llamar(funcion: String, cuerpo: JsonObject): T {
        val respuesta = cliente.functions.invoke(function = funcion, body = cuerpo)
        return json.decodeFromString(respuesta.bodyAsText())
    }
}
