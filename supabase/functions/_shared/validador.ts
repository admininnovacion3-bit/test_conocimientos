// =====================================================================
// Validador de preguntas (producción, Supabase Edge Functions / Deno).
// Gemelo de python_scripts/validador.py: mismas 6 reglas y mismos mensajes.
// Toda pregunta generada por IA pasa por aquí ANTES de guardarse o mostrarse.
// =====================================================================

export type Area = "logica" | "programacion" | "bases_de_datos" | "actitud";
export type Tipo =
  | "opcion_multiple" | "codigo_salida" | "completar_codigo"
  | "caso_practico" | "verdadero_falso_justificado";

export interface Plantilla {
  id_plantilla: string;
  tipo: Tipo;
  areas_permitidas: Area[];
  estructura: { contenido: Record<string, unknown> } & Record<string, unknown>;
  restricciones: {
    longitud?: Record<string, [number, number]>;
    lineas_codigo_por_nivel?: Record<string, [number, number]>;
    lenguajes_permitidos?: string[];
    marcador_hueco?: string;
    huecos_exactos?: number;
    num_opciones?: number;
    frases_prohibidas?: string[];
    reglas_texto?: string[];
  };
  ejemplo_salida: Pregunta;
}

export interface InfoTema { nivel_minimo: number; palabras_clave: string[] }
export type Catalogo = Record<string, Record<string, InfoTema>>;

export interface Pregunta {
  id_plantilla: string;
  area: Area;
  tema: string;
  nivel: number;
  tipo: Tipo;
  contenido: Record<string, unknown>;
  respuesta_correcta: { opcion?: string; valor?: boolean; justificacion?: string };
  explicacion: string;
}

export interface Solicitud { area: Area; tema: string; nivel: number }
export interface ResultadoValidacion { valido: boolean; errores: string[]; hash: string | null }

const HUECO_IA = "___";

// ----------------------------------------------------------------- utilidades
export function normalizar(texto: string): string {
  return (texto ?? "")
    .normalize("NFD").replace(/\p{Mn}/gu, "")
    .toLowerCase().replace(/\s+/g, " ").trim();
}

function textoCompleto(p: Pregunta): string {
  const c = p.contenido ?? {};
  const opciones = (c.opciones ?? c.opciones_justificacion ?? {}) as Record<string, string>;
  return [c.contexto, c.enunciado, c.afirmacion, c.codigo, ...Object.values(opciones)]
    .filter(Boolean).map(String).join(" ");
}

export async function hashPregunta(p: Pregunta): Promise<string> {
  const c = p.contenido ?? {};
  const base = ["contexto", "enunciado", "afirmacion", "codigo"]
    .map((k) => normalizar(String(c[k] ?? ""))).join("|");
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(base));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function escaparRegex(s: string) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function fraseProhibida(texto: string, frases: string[]): string | null {
  const t = normalizar(texto);
  for (const f of frases) {
    if (new RegExp(`\\b${escaparRegex(normalizar(f))}\\b`).test(t)) return f;
  }
  return null;
}

const lineasCodigo = (codigo: string) =>
  (codigo ?? "").split(/\r?\n/).filter((l) => l.trim()).length;

const esObjeto = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);

// ----------------------------------------------------------------- validador
export async function validarPregunta(
  p: Pregunta,
  plantilla: Plantilla,
  catalogo: Catalogo,
  solicitud?: Solicitud,
  hashesUsados?: Set<string>,
): Promise<ResultadoValidacion> {
  const errores: string[] = [];
  const r = plantilla.restricciones ?? {};

  // ---------- 1. ESTRUCTURA ----------
  if (!esObjeto(p)) return { valido: false, errores: ["estructura: la respuesta no es un objeto JSON"], hash: null };
  for (const campo of ["id_plantilla", "area", "tema", "nivel", "tipo", "contenido", "respuesta_correcta", "explicacion"]) {
    const v = (p as unknown as Record<string, unknown>)[campo];
    if (v === undefined || v === null || v === "" || (esObjeto(v) && Object.keys(v).length === 0)) {
      errores.push(`estructura: falta el campo '${campo}'`);
    }
  }
  if (errores.length) return { valido: false, errores, hash: null };
  if (JSON.stringify(p).includes(HUECO_IA)) errores.push("estructura: quedan huecos '___' sin rellenar");
  if (p.id_plantilla !== plantilla.id_plantilla) errores.push("estructura: id_plantilla no coincide con la plantilla usada");
  if (p.tipo !== plantilla.tipo) errores.push("estructura: el tipo no coincide con la plantilla");

  const molde = plantilla.estructura.contenido;
  const contenido = esObjeto(p.contenido) ? p.contenido : {};
  for (const [campo, forma] of Object.entries(molde)) {
    const valor = contenido[campo];
    if (esObjeto(forma)) {
      const esperadas = Object.keys(forma).sort().join(",");
      if (!esObjeto(valor) || Object.keys(valor).sort().join(",") !== esperadas) {
        errores.push(`estructura: '${campo}' debe tener exactamente las claves [${esperadas}]`);
      }
    } else if (typeof valor !== "string" || !valor.trim()) {
      errores.push(`estructura: '${campo}' vacío o no es texto`);
    }
  }
  const extras = Object.keys(contenido).filter((k) => !(k in molde));
  if (extras.length) errores.push(`estructura: campos no permitidos en contenido [${extras.sort().join(",")}]`);

  if ("lenguaje" in molde && !(r.lenguajes_permitidos ?? []).includes(String(contenido.lenguaje))) {
    errores.push(`estructura: lenguaje '${contenido.lenguaje}' no permitido`);
  }
  if (plantilla.tipo === "completar_codigo") {
    const marcador = r.marcador_hueco ?? "[[HUECO]]";
    const n = String(contenido.codigo ?? "").split(marcador).length - 1;
    if (n !== (r.huecos_exactos ?? 1)) errores.push(`estructura: el código debe tener exactamente ${r.huecos_exactos ?? 1} ${marcador}`);
  }

  // ---------- 2. EXACTAMENTE UNA CORRECTA ----------
  const opciones = (esObjeto(contenido.opciones) ? contenido.opciones
    : esObjeto(contenido.opciones_justificacion) ? contenido.opciones_justificacion : {}) as Record<string, string>;
  const rc = esObjeto(p.respuesta_correcta) ? p.respuesta_correcta : {};
  const clavesRc = Object.keys(rc).sort().join(",");
  if (plantilla.tipo === "verdadero_falso_justificado") {
    if (typeof rc.valor !== "boolean") errores.push("correcta: 'valor' debe ser booleano true/false");
    if (!(String(rc.justificacion) in opciones)) errores.push("correcta: 'justificacion' debe ser una de las letras de opciones_justificacion");
    if (clavesRc !== "justificacion,valor") errores.push("correcta: respuesta_correcta solo admite 'valor' y 'justificacion'");
  } else {
    if (!(String(rc.opcion) in opciones)) errores.push("correcta: 'opcion' debe ser una de las letras A-D");
    if (clavesRc !== "opcion") errores.push("correcta: respuesta_correcta solo admite 'opcion'");
  }
  if (r.num_opciones && Object.keys(opciones).length !== r.num_opciones) {
    errores.push(`correcta: se esperaban ${r.num_opciones} opciones`);
  }
  const normalizadas = Object.values(opciones).map((v) => normalizar(String(v)));
  if (new Set(normalizadas).size !== normalizadas.length) {
    errores.push("correcta: hay opciones repetidas (podría haber más de una correcta)");
  }
  for (const [letra, texto] of Object.entries(opciones)) {
    const f = fraseProhibida(String(texto), r.frases_prohibidas ?? []);
    if (f) errores.push(`correcta: la opción ${letra} usa la frase prohibida '${f}'`);
  }

  // ---------- 3. TEMA OBLIGATORIO ----------
  if (!plantilla.areas_permitidas.includes(p.area)) {
    errores.push(`tema: el área '${p.area}' no está permitida para ${plantilla.tipo}`);
  }
  const infoTema = catalogo[p.area]?.[p.tema];
  if (!infoTema) {
    errores.push(`tema: '${p.tema}' no existe en el catálogo del área '${p.area}'`);
  } else {
    const texto = ` ${normalizar(textoCompleto(p))} `;
    if (!infoTema.palabras_clave.some((k) => texto.includes(k))) {
      errores.push(`tema: el texto no menciona ningún concepto del tema '${p.tema}'`);
    }
  }
  if (solicitud) {
    if (p.area !== solicitud.area) errores.push("tema: el área no es la solicitada por el motor");
    if (p.tema !== solicitud.tema) errores.push("tema: el tema no es el solicitado por el motor");
  }

  // ---------- 4. LONGITUD ----------
  for (const [campo, [min, max]] of Object.entries(r.longitud ?? {})) {
    if (campo === "opcion") {
      for (const [letra, texto] of Object.entries(opciones)) {
        const n = String(texto).trim().length;
        if (n < min || n > max) errores.push(`longitud: opción ${letra} fuera de [${min},${max}] caracteres`);
      }
      continue;
    }
    const valor = campo === "explicacion" ? p.explicacion : contenido[campo];
    if (typeof valor === "string") {
      const n = valor.trim().length;
      if (n < min || n > max) errores.push(`longitud: '${campo}' tiene ${n} caracteres, fuera de [${min},${max}]`);
    }
  }

  // ---------- 5. NO REPETIDA ----------
  const hash = await hashPregunta(p);
  if (hashesUsados?.has(hash)) errores.push("repetida: ya existe una pregunta con el mismo enunciado/código");

  // ---------- 6. COHERENCIA CON EL NIVEL ----------
  if (!Number.isInteger(p.nivel) || p.nivel < 1 || p.nivel > 3) {
    errores.push("nivel: debe ser el entero 1, 2 o 3");
  } else {
    if (solicitud && p.nivel !== solicitud.nivel) errores.push("nivel: no coincide con el nivel solicitado por el motor");
    if (infoTema && p.nivel < infoTema.nivel_minimo) {
      errores.push(`nivel: el tema '${p.tema}' exige nivel mínimo ${infoTema.nivel_minimo}`);
    }
    const rango = r.lineas_codigo_por_nivel?.[String(p.nivel)];
    if (rango && contenido.codigo) {
      const n = lineasCodigo(String(contenido.codigo));
      if (n < rango[0] || n > rango[1]) {
        errores.push(`nivel: ${n} líneas de código no corresponden al nivel ${p.nivel} (esperado ${rango[0]}-${rango[1]})`);
      }
    }
  }

  return { valido: errores.length === 0, errores, hash };
}

// ------------------------------------------------- barajar opciones
// Los LLM tienden a poner la correcta en la "A". Tras validar, el backend baraja
// las opciones y re-mapea la letra correcta (Fisher-Yates).
export function barajarOpciones(p: Pregunta): Pregunta {
  const copia: Pregunta = structuredClone(p);
  const campo = copia.tipo === "verdadero_falso_justificado" ? "opciones_justificacion" : "opciones";
  const opciones = copia.contenido[campo] as Record<string, string>;
  const letras = Object.keys(opciones).sort();
  const claveCorrecta = copia.tipo === "verdadero_falso_justificado"
    ? copia.respuesta_correcta.justificacion! : copia.respuesta_correcta.opcion!;
  const textos = letras.map((l) => ({ texto: opciones[l], correcta: l === claveCorrecta }));
  for (let i = textos.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [textos[i], textos[j]] = [textos[j], textos[i]];
  }
  const nuevas: Record<string, string> = {};
  textos.forEach((t, i) => {
    nuevas[letras[i]] = t.texto;
    if (t.correcta) {
      if (copia.tipo === "verdadero_falso_justificado") copia.respuesta_correcta.justificacion = letras[i];
      else copia.respuesta_correcta.opcion = letras[i];
    }
  });
  copia.contenido[campo] = nuevas;
  return copia;
}
