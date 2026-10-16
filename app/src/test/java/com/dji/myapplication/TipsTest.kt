package com.dji.myapplication

import com.dji.myapplication.ui.mascota.Tips
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/** Reglas de los mensajes de Bit. */
class TipsTest {
    private val tipos = listOf(
        "opcion_multiple", "codigo_salida", "completar_codigo", "caso_practico", "verdadero_falso_justificado",
    )

    @Test
    fun `ningun mensaje revela si el aspirante acerto`() {
        val prohibidas = listOf("correct", "incorrect", "acert", "fall", "bien hecho", "error tuyo", "puntaje alto")
        val mensajes = buildSet {
            repeat(300) { tipos.forEach { add(Tips.alTocar(it)) } }
            (1..20).forEach { orden -> tipos.forEach { Tips.alLlegar(orden, 20, it)?.let(::add) } }
            add(Tips.TIEMPO_AGOTADO)
            (0..120).forEach { Tips.porTiempo(it, 120)?.let(::add) }
        }
        for (m in mensajes) for (p in prohibidas) {
            assertFalse("El tip \"$m\" contiene \"$p\"", m.lowercase().contains(p))
        }
    }

    @Test
    fun `avisos del cronometro a mitad de tiempo y en los ultimos 10 segundos`() {
        assertNotNull(Tips.porTiempo(30, 60))
        assertEquals("¡Últimos 10 segundos!", Tips.porTiempo(10, 60))
        assertNull(Tips.porTiempo(25, 60))
    }

    @Test
    fun `hitos de la evaluacion`() {
        assertNotNull(Tips.alLlegar(1, 20, "opcion_multiple"))   // inicio
        assertNotNull(Tips.alLlegar(6, 20, "opcion_multiple"))   // empiezan las adaptativas
        assertNotNull(Tips.alLlegar(20, 20, "opcion_multiple"))  // última
    }
}
