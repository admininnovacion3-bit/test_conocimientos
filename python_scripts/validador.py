"""
Validador de preguntas (versión Python, para pruebas offline y generación del banco fijo).

Es el gemelo de supabase/functions/_shared/validador.ts: mismas reglas, mismos mensajes.
Solo usa la biblioteca estándar (sin dependencias pagas ni externas).

Reglas:
  1. Estructura completa (todos los campos de la plantilla, sin '___' sin rellenar)
  2. Exactamente una respuesta correcta
  3. Tema obligatorio presente (pertenece al catálogo y aparece en el texto)
  4. Longitud dentro de límites
  5. No repetida (hash SHA-256 del texto normalizado)
  6. Coherencia con el nivel declarado

Extra solo en Python (offline): si la pregunta es codigo_salida en python, se EJECUTA
el código en un subproceso aislado y se compara la salida real con la opción correcta.
"""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import tempfile
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
HUECO_IA = "___"
TIPOS_CON_OPCIONES_4 = {"opcion_multiple", "codigo_salida", "completar_codigo", "caso_practico"}


@dataclass
class Resultado:
    valido: bool
    errores: list[str] = field(default_factory=list)
    hash: str | None = None


# ----------------------------------------------------------------- utilidades
def normalizar(texto: str) -> str:
    """Minúsculas, sin tildes y con espacios colapsados (para hash y búsqueda de temas)."""
    texto = unicodedata.normalize("NFD", texto or "")
    texto = "".join(c for c in texto if unicodedata.category(c) != "Mn")
    return re.sub(r"\s+", " ", texto.lower()).strip()


def texto_completo(p: dict) -> str:
    c = p.get("contenido") or {}
    partes = [c.get("contexto", ""), c.get("enunciado", ""), c.get("afirmacion", ""), c.get("codigo", "")]
    opciones = c.get("opciones") or c.get("opciones_justificacion") or {}
    partes += [str(v) for v in opciones.values()]
    return " ".join(str(x) for x in partes if x)


def hash_pregunta(p: dict) -> str:
    """El hash usa solo el 'núcleo' de la pregunta: dos preguntas con el mismo enunciado y código son la misma."""
    c = p.get("contenido") or {}
    base = "|".join(normalizar(str(c.get(k, ""))) for k in ("contexto", "enunciado", "afirmacion", "codigo"))
    return hashlib.sha256(base.encode("utf-8")).hexdigest()


def contiene_hueco(valor) -> bool:
    return HUECO_IA in json.dumps(valor, ensure_ascii=False)


def frase_prohibida(texto: str, frases: list[str]) -> str | None:
    t = normalizar(texto)
    for f in frases:
        if re.search(r"\b" + re.escape(normalizar(f)) + r"\b", t):
            return f
    return None


def lineas_codigo(codigo: str) -> int:
    return len([l for l in (codigo or "").splitlines() if l.strip()])


# ----------------------------------------------------------------- validador
def validar_pregunta(
    p: dict,
    plantilla: dict,
    catalogo: dict,
    solicitud: dict | None = None,
    hashes_usados: set[str] | None = None,
) -> Resultado:
    """
    p           : pregunta rellenada (dict) devuelta por la IA o escrita por un humano.
    plantilla   : plantilla JSON de su tipo.
    catalogo    : catalogo_temas.json.
    solicitud   : {"area","tema","nivel"} que pidió el motor adaptativo (None = no comparar).
    hashes_usados: hashes ya vistos por este aspirante / en el banco.
    """
    errores: list[str] = []
    r = plantilla.get("restricciones", {})
    longitudes = r.get("longitud", {})

    # ---------- 1. ESTRUCTURA ----------
    if not isinstance(p, dict):
        return Resultado(False, ["estructura: la respuesta no es un objeto JSON"])
    for campo in ("id_plantilla", "area", "tema", "nivel", "tipo", "contenido", "respuesta_correcta", "explicacion"):
        if campo not in p or p[campo] in (None, "", {}):
            errores.append(f"estructura: falta el campo '{campo}'")
    if errores:
        return Resultado(False, errores)
    if contiene_hueco(p):
        errores.append("estructura: quedan huecos '___' sin rellenar")
    if p["id_plantilla"] != plantilla["id_plantilla"]:
        errores.append("estructura: id_plantilla no coincide con la plantilla usada")
    if p["tipo"] != plantilla["tipo"]:
        errores.append("estructura: el tipo no coincide con la plantilla")

    estructura_contenido = plantilla["estructura"]["contenido"]
    contenido = p["contenido"] if isinstance(p["contenido"], dict) else {}
    for campo, molde in estructura_contenido.items():
        valor = contenido.get(campo)
        if isinstance(molde, dict):
            if not isinstance(valor, dict) or set(valor.keys()) != set(molde.keys()):
                errores.append(f"estructura: '{campo}' debe tener exactamente las claves {sorted(molde.keys())}")
        elif not isinstance(valor, str) or not valor.strip():
            errores.append(f"estructura: '{campo}' vacío o no es texto")
    extras = set(contenido.keys()) - set(estructura_contenido.keys())
    if extras:
        errores.append(f"estructura: campos no permitidos en contenido {sorted(extras)}")

    if "lenguaje" in estructura_contenido and contenido.get("lenguaje") not in r.get("lenguajes_permitidos", []):
        errores.append(f"estructura: lenguaje '{contenido.get('lenguaje')}' no permitido")

    if plantilla["tipo"] == "completar_codigo":
        marcador = r.get("marcador_hueco", "[[HUECO]]")
        if (contenido.get("codigo") or "").count(marcador) != r.get("huecos_exactos", 1):
            errores.append(f"estructura: el código debe tener exactamente {r.get('huecos_exactos', 1)} {marcador}")

    # ---------- 2. EXACTAMENTE UNA CORRECTA ----------
    opciones = contenido.get("opciones") or contenido.get("opciones_justificacion") or {}
    rc = p["respuesta_correcta"] if isinstance(p["respuesta_correcta"], dict) else {}
    if plantilla["tipo"] == "verdadero_falso_justificado":
        if not isinstance(rc.get("valor"), bool):
            errores.append("correcta: 'valor' debe ser booleano true/false")
        if rc.get("justificacion") not in opciones:
            errores.append("correcta: 'justificacion' debe ser una de las letras de opciones_justificacion")
        if set(rc.keys()) != {"valor", "justificacion"}:
            errores.append("correcta: respuesta_correcta solo admite 'valor' y 'justificacion'")
    else:
        if rc.get("opcion") not in opciones:
            errores.append("correcta: 'opcion' debe ser una de las letras A-D")
        if set(rc.keys()) != {"opcion"}:
            errores.append("correcta: respuesta_correcta solo admite 'opcion'")
    if isinstance(opciones, dict) and len(opciones) != r.get("num_opciones", len(opciones)):
        errores.append(f"correcta: se esperaban {r.get('num_opciones')} opciones")
    normalizadas = [normalizar(str(v)) for v in opciones.values()] if isinstance(opciones, dict) else []
    if len(set(normalizadas)) != len(normalizadas):
        errores.append("correcta: hay opciones repetidas (podría haber más de una correcta)")
    for letra, texto in (opciones.items() if isinstance(opciones, dict) else []):
        f = frase_prohibida(str(texto), r.get("frases_prohibidas", []))
        if f:
            errores.append(f"correcta: la opción {letra} usa la frase prohibida '{f}'")

    # ---------- 3. TEMA OBLIGATORIO ----------
    area, tema = p["area"], p["tema"]
    if area not in plantilla.get("areas_permitidas", []):
        errores.append(f"tema: el área '{area}' no está permitida para {plantilla['tipo']}")
    info_tema = (catalogo.get(area) or {}).get(tema)
    if not info_tema:
        errores.append(f"tema: '{tema}' no existe en el catálogo del área '{area}'")
    else:
        texto = " " + normalizar(texto_completo(p)) + " "
        # Las palabras clave del catálogo ya están en minúsculas y sin tildes; algunas
        # llevan espacios a propósito (" and ", "def ") para no coincidir dentro de otra palabra.
        if not any(k in texto for k in info_tema["palabras_clave"]):
            errores.append(f"tema: el texto no menciona ningún concepto del tema '{tema}'")
    if solicitud:
        if area != solicitud.get("area"):
            errores.append("tema: el área no es la solicitada por el motor")
        if tema != solicitud.get("tema"):
            errores.append("tema: el tema no es el solicitado por el motor")

    # ---------- 4. LONGITUD ----------
    for campo, (minimo, maximo) in longitudes.items():
        if campo == "opcion":
            for letra, texto in (opciones.items() if isinstance(opciones, dict) else []):
                if not (minimo <= len(str(texto).strip()) <= maximo):
                    errores.append(f"longitud: opción {letra} fuera de [{minimo},{maximo}] caracteres")
            continue
        valor = p.get("explicacion") if campo == "explicacion" else contenido.get(campo)
        if isinstance(valor, str) and not (minimo <= len(valor.strip()) <= maximo):
            errores.append(f"longitud: '{campo}' tiene {len(valor.strip())} caracteres, fuera de [{minimo},{maximo}]")

    # ---------- 5. NO REPETIDA ----------
    h = hash_pregunta(p)
    if hashes_usados is not None and h in hashes_usados:
        errores.append("repetida: ya existe una pregunta con el mismo enunciado/código")

    # ---------- 6. COHERENCIA CON EL NIVEL ----------
    nivel = p["nivel"]
    if not isinstance(nivel, int) or isinstance(nivel, bool) or nivel not in (1, 2, 3):
        errores.append("nivel: debe ser el entero 1, 2 o 3")
    else:
        if solicitud and nivel != solicitud.get("nivel"):
            errores.append("nivel: no coincide con el nivel solicitado por el motor")
        if info_tema and nivel < info_tema["nivel_minimo"]:
            errores.append(f"nivel: el tema '{tema}' exige nivel mínimo {info_tema['nivel_minimo']}")
        rango = (r.get("lineas_codigo_por_nivel") or {}).get(str(nivel))
        if rango and contenido.get("codigo"):
            n = lineas_codigo(contenido["codigo"])
            if not (rango[0] <= n <= rango[1]):
                errores.append(f"nivel: {n} líneas de código no corresponden al nivel {nivel} (esperado {rango[0]}-{rango[1]})")

    return Resultado(not errores, errores, h)


# ------------------------------------------- verificación por ejecución (offline)
def verificar_ejecucion_python(p: dict, timeout: float = 3.0) -> list[str]:
    """Ejecuta el código de una pregunta codigo_salida/python y compara con la opción correcta.
    Solo para el banco escrito por humanos en la máquina del desarrollador; NUNCA en producción."""
    c = p.get("contenido", {})
    if p.get("tipo") != "codigo_salida" or c.get("lenguaje") != "python":
        return []
    with tempfile.TemporaryDirectory() as carpeta:
        script = Path(carpeta) / "pregunta.py"
        script.write_text(c["codigo"], encoding="utf-8")
        try:
            salida = subprocess.run([sys.executable, "-I", str(script)], cwd=carpeta,
                                    capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            return ["ejecucion: el código no terminó (¿ciclo infinito?)"]
    real = salida.stdout.strip() if salida.returncode == 0 else "ERROR"
    esperada = str(c["opciones"].get(p["respuesta_correcta"].get("opcion"), "")).strip()
    esperada = esperada.replace("\\n", "\n")
    if real != esperada and not (real == "ERROR" and "error" in esperada.lower()):
        return [f"ejecucion: la salida real es {real!r} pero la opción correcta dice {esperada!r}"]
    return []


# ----------------------------------------------------------------- carga
def cargar_plantillas() -> dict[str, dict]:
    plantillas = {}
    for archivo in sorted((RAIZ / "plantillas").glob("PL-*.json")):
        pl = json.loads(archivo.read_text(encoding="utf-8"))
        plantillas[pl["id_plantilla"]] = pl
    return plantillas


def cargar_catalogo() -> dict:
    datos = json.loads((RAIZ / "plantillas" / "catalogo_temas.json").read_text(encoding="utf-8"))
    return {k: v for k, v in datos.items() if not k.startswith("_")}


def validar_archivo(ruta: Path, ejecutar: bool = True) -> int:
    """Valida un archivo JSON con una lista de preguntas. Devuelve el número de preguntas inválidas."""
    plantillas, catalogo = cargar_plantillas(), cargar_catalogo()
    preguntas = json.loads(ruta.read_text(encoding="utf-8"))
    vistos: set[str] = set()
    malas = 0
    for p in preguntas:
        pl = plantillas.get(p.get("id_plantilla"))
        if not pl:
            print(f"[X] {p.get('codigo', '?')}: plantilla desconocida {p.get('id_plantilla')}")
            malas += 1
            continue
        res = validar_pregunta(p, pl, catalogo, hashes_usados=vistos)
        errores = res.errores + (verificar_ejecucion_python(p) if ejecutar else [])
        if errores:
            malas += 1
            print(f"[X] {p.get('codigo', '?')}")
            for e in errores:
                print(f"      - {e}")
        if res.hash:
            vistos.add(res.hash)
    print(f"\n{len(preguntas) - malas}/{len(preguntas)} preguntas válidas en {ruta.name}")
    return malas


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Uso: python validador.py <archivo.json> [--sin-ejecutar]")
        sys.exit(2)
    sys.exit(1 if validar_archivo(Path(sys.argv[1]), ejecutar="--sin-ejecutar" not in sys.argv) else 0)
