// Ejecutar desde supabase/functions:  deno test --allow-read tests/
// Garantiza que el validador TS acepta lo mismo que el validador Python (banco + semillas + ejemplos)
// y que el motor adaptativo respeta sus reglas.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { barajarOpciones, type Catalogo, type Plantilla, type Pregunta, validarPregunta } from "../_shared/validador.ts";
import { elegirSiguiente, type ItemHistorial, nivelActual, nivelInicial, type PesosArea } from "../_shared/motor_adaptativo.ts";
import { type Carrera, clasificarPorPalabras } from "../_shared/carreras.ts";

const raiz = new URL("../../../", import.meta.url);
const leer = async (ruta: string) => JSON.parse(await Deno.readTextFile(new URL(ruta, raiz)));

const plantillas: Plantilla[] = await Promise.all([
  "PL-OM-01_opcion_multiple", "PL-CS-01_codigo_salida", "PL-CC-01_completar_codigo",
  "PL-CP-01_caso_practico", "PL-VF-01_verdadero_falso_justificado",
].map((n) => leer(`plantillas/${n}.json`)));
const porId = Object.fromEntries(plantillas.map((p) => [p.id_plantilla, p]));
const { _descripcion: _, ...catalogo } = await leer("plantillas/catalogo_temas.json");

Deno.test("ejemplos de las 5 plantillas son válidos", async () => {
  for (const p of plantillas) {
    const r = await validarPregunta(p.ejemplo_salida, p, catalogo as Catalogo);
    assert(r.valido, `${p.id_plantilla}: ${r.errores}`);
  }
});

Deno.test("semillas + banco fijo (60) pasan el validador TS igual que el Python", async () => {
  const todas: Pregunta[] = [...await leer("banco/semillas.json"), ...await leer("banco/banco_fijo.json")];
  const vistos = new Set<string>();
  for (const q of todas) {
    const r = await validarPregunta(q, porId[q.id_plantilla], catalogo as Catalogo, undefined, vistos);
    assert(r.valido, `${(q as unknown as { codigo: string }).codigo}: ${r.errores}`);
    vistos.add(r.hash!);
  }
  assertEquals(todas.length, 60);
});

Deno.test("rechaza huecos, opciones repetidas y nivel incoherente", async () => {
  const pl = porId["PL-OM-01"];
  const malo = structuredClone(pl.ejemplo_salida);
  malo.contenido.opciones = { A: "___", B: "6 veces", C: "6 VECES", D: "Todas las anteriores" };
  const r = await validarPregunta(malo, pl, catalogo as Catalogo, { area: "programacion", tema: "ciclos", nivel: 2 });
  assert(r.errores.some((e) => e.includes("huecos")));
  assert(r.errores.some((e) => e.includes("repetidas")));
  assert(r.errores.some((e) => e.includes("prohibida")));
  assert(r.errores.some((e) => e.startsWith("nivel")));
});

Deno.test("barajar conserva la respuesta correcta", () => {
  const ej = porId["PL-OM-01"].ejemplo_salida;
  const textoCorrecto = (ej.contenido.opciones as Record<string, string>)[ej.respuesta_correcta.opcion!];
  for (let i = 0; i < 20; i++) {
    const b = barajarOpciones(ej);
    assertEquals((b.contenido.opciones as Record<string, string>)[b.respuesta_correcta.opcion!], textoCorrecto);
  }
});

Deno.test("motor: nivel inicial y rachas", () => {
  assertEquals(nivelInicial(5), 3);
  assertEquals(nivelInicial(3), 2);
  assertEquals(nivelInicial(2), 1);
  const h = (ok: boolean): ItemHistorial =>
    ({ orden: 0, origen: "ia", area: "logica", tema: "conjuntos", nivel: 1, tipo: "opcion_multiple", es_correcta: ok });
  assertEquals(nivelActual(1, [h(true)]), 1);                 // un acierto no basta
  assertEquals(nivelActual(1, [h(true), h(true)]), 2);        // dos seguidos sube
  assertEquals(nivelActual(3, [h(false), h(false)]), 2);      // dos fallos baja
  assertEquals(nivelActual(2, [h(true), h(false), h(true)]), 2);
});

Deno.test("motor: respeta área elegida, nivel mínimo del tema y no repite tipo", () => {
  const historial: ItemHistorial[] = [
    { orden: 6, origen: "ia", area: "bases_de_datos", tema: "claves", nivel: 1, tipo: "opcion_multiple", es_correcta: true },
  ];
  for (let i = 0; i < 30; i++) {
    const soloBD: PesosArea = { logica: 0, programacion: 0, bases_de_datos: 15, actitud: 0 };
    const s = elegirSiguiente(soloBD, historial, 1, catalogo as Catalogo, plantillas);
    assertEquals(s.area, "bases_de_datos");
    assert(["modelo_relacional", "sql_select"].includes(s.tema), s.tema); // nivel 1 y no repite 'claves'
    assert(s.plantilla.tipo !== "opcion_multiple");
    assert(s.plantilla.areas_permitidas.includes("bases_de_datos"));
  }
});

Deno.test("motor: la carrera reparte las 15 adaptativas según sus pesos", async () => {
  const carreras = await leer("banco/carreras.json");
  for (const c of carreras) {
    const historial: ItemHistorial[] = [];
    for (let i = 0; i < 15; i++) {
      const s = elegirSiguiente(c.pesos_area, historial, 2, catalogo as Catalogo, plantillas);
      historial.push({ orden: 6 + i, origen: "ia", area: s.area, tema: s.tema, nivel: 2, tipo: s.plantilla.tipo, es_correcta: i % 2 === 0 });
    }
    for (const [area, n] of Object.entries(c.pesos_area)) {
      assertEquals(historial.filter((h) => h.area === area).length, n, `${c.id}/${area}`);
    }
  }
});

Deno.test("carrera: clasificación por palabras clave (sin IA)", async () => {
  const carreras: Carrera[] = await leer("banco/carreras.json");
  const casos: [string, string | null][] = [
    ["Ingeniería de Sistemas", "ingenieria_sistemas"],
    ["ing. de sistemas y computación", "ingenieria_sistemas"],
    ["Ingeniería de Software", "ingenieria_software"],
    ["Tecnólogo en desarrollo de software", "tecnologia_desarrollo"],
    ["ADSI en el SENA", "tecnologia_desarrollo"],
    ["Ingeniería Electrónica", "otra_afin"],
    ["sofware", null],          // error de ortografía → lo resuelve la IA
    ["Medicina", null],         // sin coincidencia → IA o respaldo
  ];
  for (const [texto, esperado] of casos) assertEquals(clasificarPorPalabras(texto, carreras), esperado, texto);
});
