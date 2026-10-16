// Cliente mínimo de la API de Gemini (nivel gratuito) usando fetch, sin SDK.
// La clave vive en los secretos de Supabase (GEMINI_API_KEY); nunca llega al celular.

const MODELO = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
const URL_BASE = "https://generativelanguage.googleapis.com/v1beta/models";

export const geminiDisponible = () => Boolean(Deno.env.get("GEMINI_API_KEY"));
export const modeloGemini = () => MODELO;

export async function llamarGeminiJSON(sistema: string, usuario: string, temperatura = 0.7): Promise<unknown> {
  const clave = Deno.env.get("GEMINI_API_KEY");
  if (!clave) throw new Error("GEMINI_API_KEY no configurada");

  const resp = await fetch(`${URL_BASE}/${MODELO}:generateContent`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": clave },
    signal: AbortSignal.timeout(25_000),
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: sistema }] },
      contents: [{ role: "user", parts: [{ text: usuario }] }],
      generationConfig: {
        temperature: temperatura,
        responseMimeType: "application/json", // obliga a Gemini a responder JSON
        maxOutputTokens: 2048,
      },
    }),
  });
  if (!resp.ok) throw new Error(`Gemini HTTP ${resp.status}: ${(await resp.text()).slice(0, 300)}`);

  const datos = await resp.json();
  const texto: string | undefined = datos?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!texto) throw new Error("Gemini no devolvió texto");
  // Defensa extra por si el modelo envuelve el JSON en ```json ... ```
  const limpio = texto.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
  return JSON.parse(limpio);
}
