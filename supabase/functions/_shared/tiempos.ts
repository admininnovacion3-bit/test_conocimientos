// Tiempo límite por pregunta, en segundos, según el TIPO (no según el nivel,
// para que el cronómetro no le revele al aspirante en qué dificultad va).
import type { Tipo } from "./validador.ts";

export const TIEMPO_LIMITE_S: Record<Tipo, number> = {
  opcion_multiple: 60,               // leer y elegir
  verdadero_falso_justificado: 75,   // decidir + justificar
  caso_practico: 90,                 // leer un contexto más largo
  completar_codigo: 100,             // entender el objetivo y probar opciones
  codigo_salida: 120,                // trazar el código paso a paso
};

export const tiempoPara = (tipo: Tipo) => TIEMPO_LIMITE_S[tipo] ?? 90;

/** Segundos que le quedan al aspirante, medidos con el reloj del servidor. */
export function segundosRestantes(limite: number, mostradaEn: string | null): number {
  if (!mostradaEn) return limite;
  const transcurridos = Math.floor((Date.now() - new Date(mostradaEn).getTime()) / 1000);
  return Math.max(0, limite - transcurridos);
}
