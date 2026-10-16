// POST /functions/v1/siguiente-pregunta   body: { "evaluacion_id": "uuid" }
// Devuelve la siguiente pregunta SIN respuesta correcta, nivel ni tema.
//   1-5   : semillas ya asignadas.
//   6-20  : el motor adaptativo elige área/tema/nivel/tipo → Gemini rellena la plantilla →
//           el validador la revisa → si falla 2 veces se usa el banco fijo.
import { admin, json, obtenerLlamante } from "../_shared/supabase.ts";
import { barajarOpciones, type Catalogo, type Plantilla, type Pregunta, validarPregunta } from "../_shared/validador.ts";
import {
  debilidades, elegirSiguiente, type ItemHistorial, nivelActual, PESOS_EQUILIBRADOS, type PesosArea,
} from "../_shared/motor_adaptativo.ts";
import { promptGenerarPregunta, SISTEMA_GENERADOR } from "../_shared/prompt.ts";
import { geminiDisponible, llamarGeminiJSON, modeloGemini } from "../_shared/gemini.ts";
import { segundosRestantes, tiempoPara } from "../_shared/tiempos.ts";

const MAX_INTENTOS_IA = 2;

// deno-lint-ignore no-explicit-any
const paraAspirante = (p: any, total: number) => ({
  fin: false,
  pregunta: {
    id: p.id, orden: p.orden, total, tipo: p.tipo, contenido: p.contenido,
    tiempo_limite_s: p.tiempo_limite_s,
    segundos_restantes: segundosRestantes(p.tiempo_limite_s, p.mostrada_en),
  },
});

// respuestas.pregunta_id es UNIQUE → PostgREST devuelve un objeto (o null), no una lista.
// deno-lint-ignore no-explicit-any
const respuestaDe = (p: any): { es_correcta: boolean } | null =>
  Array.isArray(p.respuestas) ? (p.respuestas[0] ?? null) : (p.respuestas ?? null);

Deno.serve(async (req) => {
  const db = admin();
  const yo = await obtenerLlamante(req, db);
  if (!yo) return json({ error: "No autenticado" }, 401);

  const { evaluacion_id } = await req.json().catch(() => ({}));
  const { data: ev } = await db.from("evaluaciones").select("*").eq("id", evaluacion_id).single();
  if (!ev || ev.aspirante_id !== yo.id) return json({ error: "Evaluación no encontrada" }, 404);
  if (ev.estado !== "en_curso") return json({ fin: true });

  // Preguntas asignadas + si ya fueron respondidas
  const { data: asignadas } = await db.from("preguntas_generadas")
    .select("*, respuestas(es_correcta)").eq("evaluacion_id", ev.id).order("orden");
  const lista = asignadas ?? [];
  const pendiente = lista.find((p) => !respuestaDe(p));
  if (pendiente) {
    // El cronómetro empieza la PRIMERA vez que se entrega la pregunta (reloj del servidor).
    if (!pendiente.mostrada_en) {
      pendiente.mostrada_en = new Date().toISOString();
      await db.from("preguntas_generadas").update({ mostrada_en: pendiente.mostrada_en })
        .eq("id", pendiente.id).is("mostrada_en", null);
    }
    return json(paraAspirante(pendiente, ev.total_preguntas));
  }
  if (lista.length >= ev.total_preguntas) return json({ fin: true });

  // ---------- Motor adaptativo ----------
  const historial: ItemHistorial[] = lista.map((p) => ({
    orden: p.orden, origen: p.origen, area: p.area, tema: p.tema, nivel: p.nivel, tipo: p.tipo,
    es_correcta: Boolean(respuestaDe(p)?.es_correcta),
  }));
  const { data: res } = await db.from("resultados").select("nivel_inicial, nivel_semilla").eq("evaluacion_id", ev.id).single();
  const nivel = nivelActual((res?.nivel_inicial ?? 1) as 1 | 2 | 3, historial.filter((h) => h.origen !== "semilla"));
  await db.from("resultados").update({ nivel_actual: nivel }).eq("evaluacion_id", ev.id);

  const [{ data: filasPl }, { data: filasTemas }, { data: carrera }] = await Promise.all([
    db.from("plantillas").select("definicion").eq("activa", true),
    db.from("temas").select("*"),
    db.from("carreras").select("pesos_area").eq("id", ev.carrera_id).single(),
  ]);
  const plantillas: Plantilla[] = (filasPl ?? []).map((f) => f.definicion);
  const catalogo: Catalogo = {};
  for (const t of filasTemas ?? []) {
    (catalogo[t.area] ??= {})[t.tema] = { nivel_minimo: t.nivel_minimo, palabras_clave: t.palabras_clave };
  }

  // La carrera decide cuántas preguntas adaptativas van a cada área (ej. Software: 6 de programación)
  const pesos = (carrera?.pesos_area ?? PESOS_EQUILIBRADOS) as PesosArea;
  const solicitud = elegirSiguiente(pesos, historial, nivel, catalogo, plantillas);
  const orden = lista.length + 1;
  const hashesUsados = new Set<string>(lista.map((p) => p.hash));
  const usadas = lista.map((p) => String(p.contenido.enunciado ?? p.contenido.afirmacion ?? "").slice(0, 160));

  // ---------- Generación con IA (máx. 2 intentos) ----------
  let pregunta: Pregunta | null = null;
  let hash = "";
  let intentos = 0;
  let errores: string[] = [];
  if (geminiDisponible()) {
    while (!pregunta && intentos < MAX_INTENTOS_IA) {
      intentos++;
      const inicio = Date.now();
      try {
        const salida = await llamarGeminiJSON(
          SISTEMA_GENERADOR,
          promptGenerarPregunta(solicitud.plantilla, solicitud, {
            nivelDetectado: nivel,
            nivelSemilla: res?.nivel_semilla ?? null,
            debilidades: debilidades(historial),
            ultimasRespuestas: historial.slice(-5).map((h) => ({ tema: h.tema, nivel: h.nivel, correcta: h.es_correcta })),
          }, usadas, errores),
        ) as Pregunta;
        const v = await validarPregunta(salida, solicitud.plantilla, catalogo, solicitud, hashesUsados);
        errores = v.errores;
        if (v.valido) { pregunta = barajarOpciones(salida); hash = v.hash!; }
      } catch (e) {
        errores = [`ia: ${(e as Error).message}`];
      }
      await db.from("eventos_ia").insert({
        evaluacion_id: ev.id, orden, operacion: "generar_pregunta", intento: intentos,
        exito: Boolean(pregunta), errores: pregunta ? null : errores, latencia_ms: Date.now() - inicio, modelo: modeloGemini(),
      });
    }
  }

  // ---------- Respaldo: banco fijo escrito por humanos ----------
  let origen: "ia" | "banco" = "ia";
  let bancoId: string | null = null;
  if (!pregunta) {
    origen = "banco";
    const { data: banco } = await db.from("banco_preguntas_fijo").select("*").eq("activa", true).eq("es_semilla", false);
    const libres = (banco ?? []).filter((b) => !hashesUsados.has(b.hash));
    const criterios = [
      (b: typeof libres[0]) => b.area === solicitud.area && b.tema === solicitud.tema && b.nivel === nivel,
      (b: typeof libres[0]) => b.area === solicitud.area && b.nivel === nivel,
      (b: typeof libres[0]) => b.area === solicitud.area && Math.abs(b.nivel - nivel) === 1,
      (b: typeof libres[0]) => b.area === solicitud.area,
      () => true,
    ];
    let elegida = null;
    for (const c of criterios) {
      const grupo = libres.filter(c);
      if (grupo.length) { elegida = grupo[Math.floor(Math.random() * grupo.length)]; break; }
    }
    if (!elegida) return json({ error: "No hay preguntas disponibles" }, 500);
    bancoId = elegida.id;
    hash = elegida.hash;
    pregunta = {
      id_plantilla: elegida.id_plantilla, area: elegida.area, tema: elegida.tema, nivel: elegida.nivel, tipo: elegida.tipo,
      contenido: elegida.contenido, respuesta_correcta: elegida.respuesta_correcta, explicacion: elegida.explicacion,
    };
  }

  const { data: nueva, error } = await db.from("preguntas_generadas").insert({
    evaluacion_id: ev.id, aspirante_id: yo.id, orden, origen, id_plantilla: pregunta.id_plantilla, banco_id: bancoId,
    area: pregunta.area, tema: pregunta.tema, nivel: pregunta.nivel, tipo: pregunta.tipo,
    contenido: pregunta.contenido, respuesta_correcta: pregunta.respuesta_correcta, explicacion: pregunta.explicacion,
    hash, intentos_ia: intentos, modelo_ia: origen === "ia" ? modeloGemini() : null,
    tiempo_limite_s: tiempoPara(pregunta.tipo), mostrada_en: new Date().toISOString(),
  }).select("*").single();

  if (error) {
    // Doble toque en el celular: otra petición ya creó la pregunta de este orden → devolver esa.
    const { data: ya } = await db.from("preguntas_generadas").select("*").eq("evaluacion_id", ev.id).eq("orden", orden).single();
    if (ya) return json(paraAspirante(ya, ev.total_preguntas));
    return json({ error: "No se pudo guardar la pregunta" }, 500);
  }
  return json(paraAspirante(nueva, ev.total_preguntas));
});
