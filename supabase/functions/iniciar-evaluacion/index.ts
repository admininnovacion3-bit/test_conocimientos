// POST /functions/v1/iniciar-evaluacion
//   body: { "nombre": "Ana Pérez", "carrera_id": "ingenieria_software", "carrera_texto": "ing. software" }
//   body: { "reanudar": true }   → solo consulta si ya existe una evaluación (al reabrir la app)
// El aspirante entra SIN cuenta (sesión anónima de Supabase). Aquí se guarda su nombre y carrera,
// se crea la evaluación y se asignan las 5 semillas DE SU CARRERA (orden 1-5).
import { admin, json, obtenerLlamante } from "../_shared/supabase.ts";
import { tiempoPara } from "../_shared/tiempos.ts";

const NOMBRE_VALIDO = /^[\p{L}][\p{L} .'-]{1,79}$/u;

Deno.serve(async (req) => {
  const db = admin();
  const yo = await obtenerLlamante(req, db);
  if (!yo) return json({ error: "No autenticado" }, 401);
  if (yo.rol !== "aspirante") return json({ error: "Solo los aspirantes presentan la evaluación" }, 403);

  const cuerpo = await req.json().catch(() => ({}));

  // ¿Ya tiene una evaluación? Solo se permite una por dispositivo/sesión.
  const { data: existente } = await db.from("evaluaciones")
    .select("id, estado").eq("aspirante_id", yo.id).neq("estado", "anulada").maybeSingle();
  if (existente) return json({ evaluacion_id: existente.id, estado: existente.estado });
  if (cuerpo.reanudar) return json({ evaluacion_id: null, estado: "sin_evaluacion" });

  const nombre = String(cuerpo.nombre ?? "").trim().replace(/\s+/g, " ");
  if (!NOMBRE_VALIDO.test(nombre)) return json({ error: "Nombre inválido" }, 400);
  const { data: carrera } = await db.from("carreras").select("id").eq("id", cuerpo.carrera_id).eq("activa", true).maybeSingle();
  if (!carrera) return json({ error: "Carrera inválida" }, 400);

  await db.from("usuarios").update({ nombre_completo: nombre }).eq("id", yo.id);
  await db.from("aspirantes").update({
    carrera_id: carrera.id,
    carrera_texto: String(cuerpo.carrera_texto ?? "").trim().slice(0, 100) || null,
  }).eq("usuario_id", yo.id);

  const { data: ev, error } = await db.from("evaluaciones")
    .insert({ aspirante_id: yo.id, carrera_id: carrera.id }).select("id").single();
  if (error) return json({ error: "No se pudo crear la evaluación" }, 500);

  await db.from("resultados").insert({ evaluacion_id: ev.id, aspirante_id: yo.id });

  // Las semillas NO se barajan: sus opciones tienen rasgos de razonamiento asociados por letra.
  const { data: semillas } = await db.from("semillas_carrera")
    .select("orden, banco:banco_preguntas_fijo(*)").eq("carrera_id", carrera.id).order("orden");
  if (!semillas || semillas.length !== 5) return json({ error: "Semillas de la carrera incompletas" }, 500);

  const { error: errSem } = await db.from("preguntas_generadas").insert(semillas.map(({ orden, banco }) => {
    // deno-lint-ignore no-explicit-any
    const s = banco as any;
    return {
      evaluacion_id: ev.id, aspirante_id: yo.id, orden, origen: "semilla",
      id_plantilla: s.id_plantilla, banco_id: s.id, area: s.area, tema: s.tema, nivel: s.nivel, tipo: s.tipo,
      contenido: s.contenido, respuesta_correcta: s.respuesta_correcta, explicacion: s.explicacion, hash: s.hash,
      tiempo_limite_s: tiempoPara(s.tipo),   // mostrada_en se fija cuando se entrega por primera vez
    };
  }));
  if (errSem) return json({ error: "No se pudieron asignar las semillas" }, 500);

  return json({ evaluacion_id: ev.id, estado: "en_curso" });
});
