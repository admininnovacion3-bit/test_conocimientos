// POST /functions/v1/finalizar-evaluacion   body: { "evaluacion_id": "uuid" }
// Calcula el resultado (SQL), pide a Gemini la retroalimentación PARA EL DOCENTE y cierra la evaluación.
// Al aspirante solo se le responde: "Proceso completado. Valida con tu profesor."
import { admin, json, obtenerLlamante } from "../_shared/supabase.ts";
import { promptRetroalimentacion, SISTEMA_RETROALIMENTACION } from "../_shared/prompt.ts";
import { geminiDisponible, llamarGeminiJSON, modeloGemini } from "../_shared/gemini.ts";

const MENSAJE_FINAL = "Proceso completado. Valida con tu profesor.";

interface Retro { resumen: string; recomendaciones: string[]; plan_practica: string[]; sugerencia_entrevista: string }

function retroValida(x: unknown): x is Retro {
  const r = x as Retro;
  const listaTextos = (l: unknown) => Array.isArray(l) && l.length >= 1 && l.length <= 5 &&
    l.every((s) => typeof s === "string" && s.length >= 10 && s.length <= 400);
  return typeof r?.resumen === "string" && r.resumen.length >= 20 && r.resumen.length <= 600 &&
    listaTextos(r.recomendaciones) && listaTextos(r.plan_practica) && typeof r.sugerencia_entrevista === "string";
}

// Respaldo sin IA: texto armado con plantillas a partir de las métricas.
// deno-lint-ignore no-explicit-any
function retroPlantilla(r: any): Retro {
  const temas = (l: { tema: string }[] | null) => (l ?? []).map((t) => t.tema.replaceAll("_", " ")).join(", ");
  const debiles = temas(r.debilidades) || "sin debilidades marcadas";
  return {
    resumen: `Puntaje ponderado ${r.puntaje_final}/100. Resultado en semillas: ${r.nivel_semilla ?? "sin dato"}. ` +
      `Fortalezas: ${temas(r.fortalezas) || "no concluyentes"}. Debilidades: ${debiles}.` +
      (r.nivel_semilla === "BAJO" ? " ALERTA: nivel bajo en preguntas semilla." : ""),
    recomendaciones: [`Reforzar: ${debiles}.`, "Resolver ejercicios guiados semanales y revisar resultados con el tutor."],
    plan_practica: ["Asignar tareas iniciales en sus temas fuertes.", "Acompañamiento con un par experimentado el primer mes."],
    sugerencia_entrevista: "Pida al aspirante explicar en voz alta cómo resolvería una de las preguntas que falló.",
  };
}

Deno.serve(async (req) => {
  const db = admin();
  const yo = await obtenerLlamante(req, db);
  if (!yo) return json({ error: "No autenticado" }, 401);

  const { evaluacion_id } = await req.json().catch(() => ({}));
  const { data: ev } = await db.from("evaluaciones").select("*").eq("id", evaluacion_id).single();
  const esDueno = ev?.aspirante_id === yo.id;
  if (!ev || (!esDueno && yo.rol === "aspirante")) return json({ error: "Evaluación no encontrada" }, 404);
  if (ev.preguntas_respondidas < ev.total_preguntas) return json({ error: "La evaluación aún no termina" }, 409);

  // Idempotente: si ya se calculó, no se repite.
  const { data: previo } = await db.from("resultados").select("recomendaciones_ia").eq("evaluacion_id", ev.id).single();
  if (ev.estado === "completada" && previo?.recomendaciones_ia) return json({ mensaje: MENSAJE_FINAL });

  const { error: errCalc } = await db.rpc("calcular_resultado", { p_eval: ev.id });
  if (errCalc) return json({ error: "No se pudo calcular el resultado" }, 500);
  const { data: r } = await db.from("resultados").select("*").eq("evaluacion_id", ev.id).single();

  let retro: Retro | null = null;
  if (geminiDisponible()) {
    for (let intento = 1; intento <= 2 && !retro; intento++) {
      const inicio = Date.now();
      let errores: string[] | null = null;
      try {
        const salida = await llamarGeminiJSON(SISTEMA_RETROALIMENTACION, promptRetroalimentacion({
          puntaje: Number(r.puntaje_final), nivelSemilla: r.nivel_semilla, nivelFinal: r.nivel_actual,
          estilo: r.estilo_razonamiento, fortalezas: r.fortalezas, debilidades: r.debilidades, detalle: r.detalle_por_tema,
        }), 0.4);
        if (retroValida(salida)) retro = salida; else errores = ["formato de retroalimentación inválido"];
      } catch (e) {
        errores = [(e as Error).message];
      }
      await db.from("eventos_ia").insert({
        evaluacion_id: ev.id, operacion: "retroalimentacion", intento, exito: Boolean(retro),
        errores, latencia_ms: Date.now() - inicio, modelo: modeloGemini(),
      });
    }
  }

  await db.from("resultados").update({
    recomendaciones_ia: retro ?? retroPlantilla(r),
    recomendaciones_origen: retro ? "ia" : "plantilla",
  }).eq("evaluacion_id", ev.id);
  await db.from("evaluaciones").update({ estado: "completada", finalizada_en: new Date().toISOString() }).eq("id", ev.id);

  return json({ mensaje: MENSAJE_FINAL });
});
