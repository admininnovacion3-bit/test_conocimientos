import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

// Solo la app Android llama a estas funciones: no se necesita CORS (es un mecanismo de navegadores web).
export const json = (cuerpo: unknown, status = 200) =>
  new Response(JSON.stringify(cuerpo), { status, headers: { "Content-Type": "application/json" } });

/**
 * Clave secreta que Supabase inyecta automáticamente en las Edge Functions.
 * Proyectos con claves nuevas: SUPABASE_SECRET_KEYS (JSON {"default":"sb_secret_..."});
 * proyectos con claves antiguas: SUPABASE_SERVICE_ROLE_KEY. Nunca se escribe a mano ni sale del servidor.
 */
function claveSecreta(): string {
  const nuevas = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (nuevas) {
    try {
      const mapa = JSON.parse(nuevas) as Record<string, string>;
      const clave = mapa.default ?? Object.values(mapa)[0];
      if (clave) return clave;
    } catch { /* se usa la clave antigua */ }
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
}

/** Cliente con privilegios de servidor: salta RLS. Solo vive en el servidor. */
export const admin = (): SupabaseClient =>
  createClient(Deno.env.get("SUPABASE_URL")!, claveSecreta(), {
    auth: { persistSession: false },
  });

export interface Llamante { id: string; rol: "aspirante" | "docente" | "admin" }

/** Identifica al usuario a partir de su JWT y lee su rol desde la tabla usuarios. */
export async function obtenerLlamante(req: Request, db: SupabaseClient): Promise<Llamante | null> {
  const token = req.headers.get("Authorization")?.replace("Bearer ", "");
  if (!token) return null;
  const { data, error } = await db.auth.getUser(token);
  if (error || !data.user) return null;
  const { data: u } = await db.from("usuarios").select("rol").eq("id", data.user.id).single();
  return u ? { id: data.user.id, rol: u.rol } : null;
}
