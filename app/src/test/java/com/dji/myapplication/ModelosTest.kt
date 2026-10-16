package com.dji.myapplication

import com.dji.myapplication.data.PreguntaAspirante
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Verifica que la app interpreta bien el JSON que envía la Edge Function siguiente-pregunta. */
class ModelosTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `opciones salen ordenadas por letra aunque lleguen desordenadas`() {
        val p = json.decodeFromString<PreguntaAspirante>(
            """{"id":"1","orden":6,"total":20,"tipo":"opcion_multiple","tiempo_limite_s":60,"segundos_restantes":42,
               "contenido":{"enunciado":"¿Cuánto es 2+2?","opciones":{"C":"5","A":"4","D":"3","B":"22"}}}"""
        )
        assertEquals(listOf("A", "B", "C", "D"), p.opciones.map { it.first })
        assertEquals("4", p.opciones.first().second)
        assertEquals(42, p.segundosRestantes)
        assertFalse(p.esVerdaderoFalso)
        assertNull(p.codigo)
    }

    @Test
    fun `verdadero falso usa las opciones de justificacion`() {
        val p = json.decodeFromString<PreguntaAspirante>(
            """{"id":"2","orden":4,"total":20,"tipo":"verdadero_falso_justificado",
               "contenido":{"afirmacion":"Una PK identifica cada fila.","opciones_justificacion":{"A":"x","B":"y","C":"z"}}}"""
        )
        assertTrue(p.esVerdaderoFalso)
        assertEquals(3, p.opciones.size)
        assertEquals("Una PK identifica cada fila.", p.afirmacion)
        assertEquals(90, p.tiempoLimiteS)          // valor por defecto si el servidor no lo envía
        assertEquals(90, p.segundosRestantes)
    }

    @Test
    fun `el aspirante nunca recibe la respuesta correcta aunque el servidor la enviara`() {
        // Si por error llegara "respuesta_correcta", el modelo la ignora: la app no tiene dónde guardarla.
        val p = json.decodeFromString<PreguntaAspirante>(
            """{"id":"3","orden":1,"total":20,"tipo":"opcion_multiple","respuesta_correcta":{"opcion":"B"},
               "contenido":{"enunciado":"x","opciones":{"A":"1","B":"2"}}}"""
        )
        assertFalse(p.toString().contains("respuesta_correcta"))
    }
}
