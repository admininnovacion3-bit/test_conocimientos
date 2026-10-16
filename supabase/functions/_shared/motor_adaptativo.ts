// =====================================================================
// MOTOR ADAPTATIVO — funciones puras (sin BD ni IA), fáciles de probar y explicar.
// Decide área, tema, nivel y tipo de la siguiente pregunta. La IA nunca decide esto.
// =====================================================================
import type { Area, Catalogo, Plantilla, Solicitud, Tipo } from "./validador.ts";

export interface ItemHistorial {
  orden: number;
  origen: "semilla" | "ia" | "banco";
  area: Area;
  tema: string;
  nivel: number;
  tipo: Tipo;
  es_correcta: boolean;
}

export const AREAS: Area[] = ["logica", "programacion", "bases_de_datos", "actitud"];
export const MAX_VECES_TEMA = 3;

/** Nivel inicial a partir de las 5 semillas: 5 aciertos → 3, 3-4 → 2, 0-2 → 1 (y alerta). */
export function nivelInicial(aciertosSemilla: number): 1 | 2 | 3 {
  return aciertosSemilla >= 5 ? 3 : aciertosSemilla >= 3 ? 2 : 1;
}

/**
 * Regla de dificultad: 2 aciertos seguidos → sube un nivel; 2 fallos seguidos → baja un nivel.
 * Se exige racha de 2 para que un acierto por azar no dispare la dificultad (histéresis).
 */
export function nivelActual(inicial: 1 | 2 | 3, adaptativas: ItemHistorial[]): 1 | 2 | 3 {
  let nivel: number = inicial;
  let rachaAciertos = 0;
  let rachaFallos = 0;
  for (const r of adaptativas) {
    if (r.es_correcta) {
      rachaAciertos++; rachaFallos = 0;
      if (rachaAciertos === 2) { nivel = Math.min(3, nivel + 1); rachaAciertos = 0; }
    } else {
      rachaFallos++; rachaAciertos = 0;
      if (rachaFallos === 2) { nivel = Math.max(1, nivel - 1); rachaFallos = 0; }
    }
  }
  return nivel as 1 | 2 | 3;
}

/** Elemento con el menor puntaje (cada puntaje se calcula una sola vez). */
function menor<T>(items: T[], puntaje: (x: T) => number): T {
  return items.map((x) => ({ x, p: puntaje(x) })).reduce((a, b) => (b.p < a.p ? b : a)).x;
}

function aciertoPorTema(historial: ItemHistorial[]) {
  const mapa = new Map<string, { ok: number; total: number }>();
  for (const h of historial) {
    const k = `${h.area}/${h.tema}`;
    const s = mapa.get(k) ?? { ok: 0, total: 0 };
    s.total++; if (h.es_correcta) s.ok++;
    mapa.set(k, s);
  }
  return mapa;
}

/** Temas con acierto < 50 % (para el contexto que se envía a la IA y al docente). */
export function debilidades(historial: ItemHistorial[]): string[] {
  return [...aciertoPorTema(historial).entries()]
    .filter(([, s]) => s.ok / s.total < 0.5)
    .map(([k]) => k.split("/")[1]);
}

/** Cuántas de las 15 preguntas adaptativas van a cada área. Lo define la CARRERA (tabla carreras). */
export type PesosArea = Record<Area, number>;
export const PESOS_EQUILIBRADOS: PesosArea = { logica: 4, programacion: 4, bases_de_datos: 4, actitud: 3 };

export function elegirSiguiente(
  pesos: PesosArea,
  historial: ItemHistorial[],
  nivel: 1 | 2 | 3,
  catalogo: Catalogo,
  plantillas: Plantilla[],
): Solicitud & { plantilla: Plantilla } {
  const adaptativas = historial.filter((h) => h.origen !== "semilla");
  const stats = aciertoPorTema(historial);
  const ultima = historial.at(-1);

  // 1) ÁREA: la que tenga más cupo pendiente según la carrera (ej. Software: 6 de programación).
  //    Entre empatadas, la más débil.
  const puntaje = (a: Area) => {
    const pendientes = (pesos[a] ?? 0) - adaptativas.filter((h) => h.area === a).length;
    const delArea = historial.filter((h) => h.area === a);
    const acierto = delArea.length ? delArea.filter((h) => h.es_correcta).length / delArea.length : 0.5;
    return -pendientes * 10 + acierto;
  };
  const area: Area = menor(AREAS, puntaje);

  // 2) TEMA: del catálogo, permitido para el nivel; prioriza debilidades y temas no evaluados.
  let candidatos = Object.entries(catalogo[area])
    .filter(([, info]) => info.nivel_minimo <= nivel)
    .map(([tema]) => tema)
    .filter((t) => (stats.get(`${area}/${t}`)?.total ?? 0) < MAX_VECES_TEMA);
  if (candidatos.length > 1 && ultima?.area === area) candidatos = candidatos.filter((t) => t !== ultima.tema);
  if (!candidatos.length) candidatos = Object.keys(catalogo[area]).filter((t) => catalogo[area][t].nivel_minimo <= nivel);

  const prioridad = (t: string) => {
    const s = stats.get(`${area}/${t}`);
    const acierto = s ? s.ok / s.total : 0.5;            // no evaluado = 50 %
    return acierto * 10 + (s?.total ?? 0) + Math.random(); // azar solo como desempate
  };
  const tema = menor(candidatos, prioridad);

  // 3) TIPO: plantillas compatibles con el área; no repetir el tipo anterior; el menos usado.
  let opciones = plantillas.filter((p) => p.areas_permitidas.includes(area));
  if (opciones.length > 1 && ultima) opciones = opciones.filter((p) => p.tipo !== ultima.tipo);
  const usos = (t: Tipo) => historial.filter((h) => h.tipo === t).length + Math.random();
  const plantilla = menor(opciones, (p) => usos(p.tipo));

  return { area, tema, nivel, plantilla };
}
