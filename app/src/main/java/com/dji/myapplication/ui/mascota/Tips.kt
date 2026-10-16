package com.dji.myapplication.ui.mascota



/**
 * Mensajes de Bit durante la evaluación.
 * REGLA: los tips son de estrategia y ánimo. NUNCA dicen si una respuesta fue correcta,
 * ni dan pistas del contenido, ni revelan el nivel (el aspirante no debe ver resultados).
 */
data class Tip(val id: Long, val texto: String)

object Tips {
    private val generales = listOf(
        "Lee el enunciado completo antes de mirar las opciones.",
        "Si dudas, descarta primero las opciones que seguro no son.",
        "Una vez enviada, la respuesta no se puede cambiar. Revisa antes de tocar \"Siguiente\".",
        "Respira. Esto muestra cómo piensas, no se trata de ser perfecto.",
        "Responde tú solo, sin buscar en internet: queremos conocer tu nivel real.",
        "Mira el cronómetro de arriba: cuando llega a cero, pasa sola a la siguiente.",
    )

    private val porTipo = mapOf(
        "codigo_salida" to listOf(
            "Recorre el código línea por línea, como si fueras la computadora.",
            "Lleva la cuenta del valor de cada variable en cada paso.",
            "Fíjate en los detalles: comillas, sangrías y dónde termina cada ciclo.",
        ),
        "completar_codigo" to listOf(
            "Primero entiende qué debe lograr el código completo.",
            "Prueba mentalmente cada opción en el hueco y mira qué pasaría.",
        ),
        "caso_practico" to listOf(
            "Ponte en la situación: ¿qué pasaría una semana después con cada opción?",
            "Piensa en el equipo y en el proyecto, no solo en ti.",
        ),
        "verdadero_falso_justificado" to listOf(
            "Primero decide si la afirmación es verdadera o falsa; luego busca el porqué.",
            "Aquí cuentan las dos partes: el valor y la justificación.",
        ),
        "opcion_multiple" to listOf(
            "Busca la palabra clave del enunciado: suele definir la respuesta.",
            "Cuidado con las opciones parecidas: lee cada una hasta el final.",
        ),
    )

    private fun hito(orden: Int, total: Int): String? = when (orden) {
        1 -> "¡Empecemos! Las primeras 5 preguntas me ayudan a conocerte."
        6 -> "Ahora las preguntas se ajustan a tu ritmo. ¡Adelante!"
        total / 2 + 1 -> "¡Ya vas por la mitad!"
        total - 3 -> "Quedan pocas, ¡ya casi terminas!"
        total -> "¡Última pregunta! Tómate tu tiempo."
        else -> null
    }

    const val TIEMPO_AGOTADO = "¡Se acabó el tiempo! Vamos con la siguiente."

    /** Avisos del cronómetro: a mitad de tiempo y en los últimos 10 segundos. */
    fun porTiempo(restantes: Int, limite: Int): String? = when (restantes) {
        limite / 2 -> "Te queda la mitad del tiempo. Si dudas, elige la que mejor razones."
        10 -> "¡Últimos 10 segundos!"
        else -> null
    }

    /** Tip automático al llegar una pregunta: un hito si lo hay; si no, a veces un tip del tipo. */
    fun alLlegar(orden: Int, total: Int, tipo: String): String? =
        hito(orden, total) ?: if (orden % 3 == 0) porTipo[tipo]?.random() else null

    /** Tip al tocar a Bit. */
    fun alTocar(tipo: String?): String =
        ((tipo?.let { porTipo[it] } ?: emptyList()) + generales).random()
}
