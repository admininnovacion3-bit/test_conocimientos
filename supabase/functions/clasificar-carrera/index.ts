// POST /functions/v1/clasificar-carrera   body: { "texto": "ing de sofware" }
// La mascota pregunta "¿Qué carrera estudias?" y el aspirante escribe libremente.
// 1) Coincidencia por palabras clave (rápida y gratis).  2) Si es ambigua → Gemini elige de la LISTA CERRADA.
// 3) Si todo falla → "otra_afin". La IA nunca inventa una carrera nueva.
import { admin, json, obtenerLlamante } from "../_shared/supabase.ts";
import { type Carrera, clasificarPorPalabras } from "../_shared/carreras.ts";
import { promptClasificarCarrera, SISTEMA_CLASIFICAR_CARRERA } from "../_shared/prompt.ts";
import { geminiDisponible, llamarGeminiJSON } from "../_shared/gemini.ts";

const RESPALDO = "otra_afin";

Deno.serve(async (req) => {
  const db = admin();
  const yo = await obtenerLlamante(req, db);
  if (!yo) return json({ error: "No autenticado" }, 401);

  const { texto = "" } = await req.json().catch(() => ({}));
  const limpio = String(texto).trim().slice(0, 100);
  if (limpio.length < 2) return json({ error: "Escribe el nombre de tu carrera" }, 400);

  const { data } = await db.from("carreras").select("id, nombre, descripcion, palabras_clave").eq("activa", true).order("orden");
  const carreras = (data ?? []) as Carrera[];

  let carreraId = clasificarPorPalabras(limpio, carreras);
  let metodo: "palabras_clave" | "ia" | "respaldo" = "palabras_clave";

  if (!carreraId) {
    metodo = "respaldo";
    if (geminiDisponible()) {
      try {
        const r = await llamarGeminiJSON(
          SISTEMA_CLASIFICAR_CARRERA, promptClasificarCarrera(limpio, carreras), 0,
        ) as { carrera_id?: string };
        if (carreras.some((c) => c.id === r.carrera_id)) { carreraId = r.carrera_id!; metodo = "ia"; }
      } catch { /* se usa el respaldo */ }
    }
  }
  carreraId ??= RESPALDO;

  const carrera = carreras.find((c) => c.id === carreraId);
  return json({ carrera_id: carreraId, nombre: carrera?.nombre ?? "Otra carrera afín", metodo });
});
