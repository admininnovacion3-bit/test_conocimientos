"""Pruebas unitarias del validador.  Ejecutar:  python -m unittest discover -s python_scripts/tests -v"""
import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from validador import (cargar_catalogo, cargar_plantillas, hash_pregunta,  # noqa: E402
                       validar_pregunta, verificar_ejecucion_python)

PLANTILLAS = cargar_plantillas()
CATALOGO = cargar_catalogo()


def ejemplo(id_plantilla: str) -> dict:
    return copy.deepcopy(PLANTILLAS[id_plantilla]["ejemplo_salida"])


class TestValidador(unittest.TestCase):
    def validar(self, p, id_pl, **kw):
        return validar_pregunta(p, PLANTILLAS[id_pl], CATALOGO, **kw)

    def test_ejemplos_de_las_5_plantillas_son_validos(self):
        for id_pl in PLANTILLAS:
            with self.subTest(id_pl):
                res = self.validar(ejemplo(id_pl), id_pl)
                self.assertTrue(res.valido, res.errores)

    # 1. Estructura
    def test_hueco_sin_rellenar(self):
        p = ejemplo("PL-OM-01")
        p["contenido"]["opciones"]["C"] = "___"
        self.assertIn("estructura: quedan huecos '___' sin rellenar", self.validar(p, "PL-OM-01").errores)

    def test_campo_faltante(self):
        p = ejemplo("PL-OM-01")
        del p["explicacion"]
        self.assertFalse(self.validar(p, "PL-OM-01").valido)

    def test_ia_inventa_campos(self):
        p = ejemplo("PL-OM-01")
        p["contenido"]["pista"] = "piense en range"
        self.assertTrue(any("no permitidos" in e for e in self.validar(p, "PL-OM-01").errores))

    def test_ia_agrega_quinta_opcion(self):
        p = ejemplo("PL-OM-01")
        p["contenido"]["opciones"]["E"] = "9 veces"
        self.assertFalse(self.validar(p, "PL-OM-01").valido)

    # 2. Una sola correcta
    def test_opciones_duplicadas(self):
        p = ejemplo("PL-OM-01")
        p["contenido"]["opciones"]["D"] = "6 Veces"
        self.assertTrue(any("repetidas" in e for e in self.validar(p, "PL-OM-01").errores))

    def test_letra_correcta_inexistente(self):
        p = ejemplo("PL-OM-01")
        p["respuesta_correcta"] = {"opcion": "F"}
        self.assertFalse(self.validar(p, "PL-OM-01").valido)

    def test_todas_las_anteriores(self):
        p = ejemplo("PL-OM-01")
        p["contenido"]["opciones"]["D"] = "Todas las anteriores"
        self.assertTrue(any("prohibida" in e for e in self.validar(p, "PL-OM-01").errores))

    def test_vf_valor_como_texto(self):
        p = ejemplo("PL-VF-01")
        p["respuesta_correcta"]["valor"] = "true"
        self.assertFalse(self.validar(p, "PL-VF-01").valido)

    # 3. Tema
    def test_tema_fuera_de_catalogo(self):
        p = ejemplo("PL-OM-01")
        p["tema"] = "blockchain"
        self.assertFalse(self.validar(p, "PL-OM-01").valido)

    def test_tema_distinto_al_solicitado(self):
        p = ejemplo("PL-OM-01")
        sol = {"area": "programacion", "tema": "funciones", "nivel": 1}
        self.assertTrue(any("solicitado" in e for e in self.validar(p, "PL-OM-01", solicitud=sol).errores))

    def test_texto_no_habla_del_tema(self):
        p = ejemplo("PL-OM-01")
        p["tema"] = "poo"
        p["nivel"] = 2
        self.assertTrue(any("no menciona" in e for e in self.validar(p, "PL-OM-01").errores))

    # 4. Longitud
    def test_enunciado_muy_largo(self):
        p = ejemplo("PL-OM-01")
        p["contenido"]["enunciado"] = "¿Cuántas veces se ejecuta el ciclo? " * 20
        self.assertTrue(any(e.startswith("longitud") for e in self.validar(p, "PL-OM-01").errores))

    # 5. Repetida
    def test_repetida_por_hash(self):
        p = ejemplo("PL-OM-01")
        usados = {hash_pregunta(p)}
        self.assertTrue(any(e.startswith("repetida") for e in self.validar(p, "PL-OM-01", hashes_usados=usados).errores))

    def test_hash_ignora_mayusculas_y_tildes(self):
        a, b = ejemplo("PL-OM-01"), ejemplo("PL-OM-01")
        b["contenido"]["enunciado"] = b["contenido"]["enunciado"].upper().replace("Á", "A")
        self.assertEqual(hash_pregunta(a), hash_pregunta(b))

    # 6. Nivel
    def test_nivel_menor_al_minimo_del_tema(self):
        p = ejemplo("PL-CS-01")
        p["tema"], p["nivel"] = "recursion", 1
        p["contenido"]["enunciado"] = "¿Qué imprime esta función recursiva?"
        self.assertTrue(any("nivel mínimo" in e for e in self.validar(p, "PL-CS-01").errores))

    def test_codigo_demasiado_largo_para_nivel_1(self):
        p = ejemplo("PL-CS-01")
        p["nivel"] = 1
        p["contenido"]["codigo"] = "\n".join(f"x{i} = {i}" for i in range(10)) + "\nprint('abab6')"
        self.assertTrue(any(e.startswith("nivel") for e in self.validar(p, "PL-CS-01").errores))

    # Ejecución offline
    def test_ejecucion_detecta_respuesta_incorrecta(self):
        p = ejemplo("PL-CS-01")
        p["respuesta_correcta"] = {"opcion": "B"}
        self.assertTrue(verificar_ejecucion_python(p))

    def test_ejecucion_confirma_respuesta_correcta(self):
        self.assertEqual(verificar_ejecucion_python(ejemplo("PL-CS-01")), [])


if __name__ == "__main__":
    unittest.main()
