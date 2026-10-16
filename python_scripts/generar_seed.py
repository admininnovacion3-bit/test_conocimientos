"""
Genera supabase/seed.sql a partir de los JSON escritos por humanos:
  plantillas/catalogo_temas.json  -> tabla temas
  plantillas/PL-*.json            -> tabla plantillas
  banco/semillas.json             -> banco_preguntas_fijo (es_semilla = true)
  banco/banco_fijo.json           -> banco_preguntas_fijo
  banco/carreras.json             -> carreras + semillas_carrera (5 semillas por carrera)

ANTES de escribir el SQL valida TODO con validador.py (incluye ejecutar el código Python
de las preguntas codigo_salida). Si algo falla, no genera nada: el banco nunca entra roto.

Uso:  python python_scripts/generar_seed.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from validador import (RAIZ, cargar_catalogo, cargar_plantillas, validar_pregunta,
                       verificar_ejecucion_python)

MINIMO_BANCO = 50
AREAS = {"logica", "programacion", "bases_de_datos", "actitud"}
PREGUNTAS_ADAPTATIVAS = 15


def sql_texto(valor: str) -> str:
    return "'" + str(valor).replace("'", "''") + "'"


def sql_json(valor) -> str:
    return "$j$" + json.dumps(valor, ensure_ascii=False) + "$j$::jsonb"


def main() -> int:
    plantillas, catalogo = cargar_plantillas(), cargar_catalogo()
    semillas = json.loads((RAIZ / "banco" / "semillas.json").read_text(encoding="utf-8"))
    banco = json.loads((RAIZ / "banco" / "banco_fijo.json").read_text(encoding="utf-8"))
    carreras = json.loads((RAIZ / "banco" / "carreras.json").read_text(encoding="utf-8"))

    # ---------- validación ----------
    errores_totales = 0
    hashes: set[str] = set()
    hash_por_codigo: dict[str, str] = {}

    # Los ejemplos de cada plantilla también deben pasar su propio validador
    for pl in plantillas.values():
        res = validar_pregunta(pl["ejemplo_salida"], pl, catalogo)
        if not res.valido:
            errores_totales += 1
            print(f"[X] ejemplo de {pl['id_plantilla']}: {res.errores}")

    for p in semillas + banco:
        pl = plantillas[p["id_plantilla"]]
        res = validar_pregunta(p, pl, catalogo, hashes_usados=hashes)
        errores = res.errores + verificar_ejecucion_python(p)
        if errores:
            errores_totales += 1
            print(f"[X] {p['codigo']}: {errores}")
        hashes.add(res.hash)
        hash_por_codigo[p["codigo"]] = res.hash

    codigos_semilla = {p["codigo"] for p in semillas}
    for c in carreras:
        problemas = []
        if len(c["semillas"]) != 5 or len(set(c["semillas"])) != 5:
            problemas.append("debe tener exactamente 5 semillas distintas")
        if faltan := [s for s in c["semillas"] if s not in codigos_semilla]:
            problemas.append(f"semillas inexistentes {faltan}")
        if set(c["pesos_area"]) != AREAS or sum(c["pesos_area"].values()) != PREGUNTAS_ADAPTATIVAS:
            problemas.append(f"pesos_area debe cubrir las 4 áreas y sumar {PREGUNTAS_ADAPTATIVAS}")
        if problemas:
            errores_totales += 1
            print(f"[X] carrera {c['id']}: {problemas}")
    if len(banco) < MINIMO_BANCO:
        errores_totales += 1
        print(f"[X] el banco fijo debe tener al menos {MINIMO_BANCO} preguntas (hay {len(banco)})")

    if errores_totales:
        print(f"\nSe encontraron {errores_totales} problemas. No se generó seed.sql.")
        return 1

    # ---------- generación ----------
    lineas = [
        "-- =====================================================================",
        "-- SEED GENERADO AUTOMÁTICAMENTE por python_scripts/generar_seed.py",
        "-- NO EDITAR A MANO: editar los JSON de /plantillas y /banco y regenerar.",
        "-- =====================================================================",
        "begin;",
        "",
        "-- Temas",
    ]
    for area, temas in catalogo.items():
        for tema, info in temas.items():
            claves = "array[" + ", ".join(sql_texto(k) for k in info["palabras_clave"]) + "]::text[]"
            lineas.append(
                f"insert into public.temas (area, tema, nivel_minimo, palabras_clave) values "
                f"({sql_texto(area)}, {sql_texto(tema)}, {info['nivel_minimo']}, {claves}) "
                f"on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;"
            )

    lineas += ["", "-- Plantillas"]
    for pl in plantillas.values():
        areas = "array[" + ", ".join(sql_texto(a) for a in pl["areas_permitidas"]) + "]::public.area_eval[]"
        lineas.append(
            f"insert into public.plantillas (id_plantilla, tipo, areas_permitidas, definicion) values "
            f"({sql_texto(pl['id_plantilla'])}, {sql_texto(pl['tipo'])}, {areas}, {sql_json(pl)}) "
            f"on conflict (id_plantilla) do update set definicion = excluded.definicion, "
            f"areas_permitidas = excluded.areas_permitidas, actualizada_en = now();"
        )

    lineas += ["", "-- Carreras"]
    for i, c in enumerate(carreras, start=1):
        claves = "array[" + ", ".join(sql_texto(k) for k in c["palabras_clave"]) + "]::text[]"
        lineas.append(
            f"insert into public.carreras (id, nombre, descripcion, palabras_clave, pesos_area, orden) values "
            f"({sql_texto(c['id'])}, {sql_texto(c['nombre'])}, {sql_texto(c['descripcion'])}, {claves}, "
            f"{sql_json(c['pesos_area'])}, {i}) on conflict (id) do update set nombre = excluded.nombre, "
            f"descripcion = excluded.descripcion, palabras_clave = excluded.palabras_clave, "
            f"pesos_area = excluded.pesos_area, orden = excluded.orden;"
        )

    lineas += ["", "-- Banco fijo (semillas + respaldo)"]
    for p in semillas + banco:
        es_semilla = p["codigo"] in codigos_semilla
        lineas.append(
            "insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, "
            "respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ("
            f"{sql_texto(p['codigo'])}, {sql_texto(p['id_plantilla'])}, {sql_texto(p['area'])}, {sql_texto(p['tema'])}, "
            f"{p['nivel']}, {sql_texto(p['tipo'])}, {sql_json(p['contenido'])}, {sql_json(p['respuesta_correcta'])}, "
            f"{sql_texto(p['explicacion'])}, {sql_json(p['rasgos_opciones']) if p.get('rasgos_opciones') else 'null'}, "
            f"{sql_texto(hash_por_codigo[p['codigo']])}, {'true' if es_semilla else 'false'}) "
            "on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, "
            "explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, "
            "nivel = excluded.nivel, tema = excluded.tema;"
        )

    lineas += ["", "-- Semillas por carrera (se reemplazan completas para reflejar el JSON)"]
    lineas.append("delete from public.semillas_carrera;")
    for c in carreras:
        for orden, codigo in enumerate(c["semillas"], start=1):
            lineas.append(
                f"insert into public.semillas_carrera (carrera_id, orden, banco_id) "
                f"select {sql_texto(c['id'])}, {orden}, id from public.banco_preguntas_fijo where codigo = {sql_texto(codigo)};"
            )
    lineas += ["", "commit;", ""]

    destino = RAIZ / "supabase" / "seed.sql"
    destino.write_text("\n".join(lineas), encoding="utf-8")

    # Resumen de cobertura (útil para saber dónde faltan preguntas de respaldo)
    print(f"OK: {len(semillas)} semillas, {len(carreras)} carreras y {len(banco)} preguntas de banco validadas.")
    print(f"Escrito {destino.relative_to(RAIZ)}\n\nCobertura del banco (área x nivel):")
    for area in catalogo:
        fila = [sum(1 for p in banco if p["area"] == area and p["nivel"] == n) for n in (1, 2, 3)]
        print(f"  {area:<16} N1={fila[0]:>2}  N2={fila[1]:>2}  N3={fila[2]:>2}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
