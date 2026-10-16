import { normalizar } from "./validador.ts";

export interface Carrera { id: string; nombre: string; descripcion: string; palabras_clave: string[] }

/**
 * Clasificación sin IA: suma coincidencias de palabras clave (las frases largas pesan más:
 * "desarrollo de software" es más específico que "software").
 * Devuelve el id solo si UNA carrera gana claramente; con empate o sin coincidencias, null.
 */
export function clasificarPorPalabras(texto: string, carreras: Carrera[]): string | null {
  const t = ` ${normalizar(texto)} `;
  const puntajes = carreras.map((c) => ({
    id: c.id,
    p: c.palabras_clave.filter((k) => t.includes(k)).reduce((s, k) => s + k.split(" ").length, 0),
  })).sort((a, b) => b.p - a.p);
  if (!puntajes.length || puntajes[0].p === 0) return null;
  if (puntajes.length > 1 && puntajes[0].p === puntajes[1].p) return null;
  return puntajes[0].id;
}
