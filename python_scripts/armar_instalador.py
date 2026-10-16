"""
Une las 3 migraciones + seed.sql en supabase/INSTALAR_TODO.sql para pegarlo UNA vez en el SQL Editor de Supabase.
Uso:  python python_scripts/generar_seed.py && python python_scripts/armar_instalador.py
"""
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
PARTES = [
    "supabase/migrations/20261014000001_esquema.sql",
    "supabase/migrations/20261014000002_funciones_triggers.sql",
    "supabase/migrations/20261014000003_rls.sql",
    "supabase/migrations/20261014000004_tiempo_limite.sql",
    "supabase/seed.sql",
]

salida = [
    "-- =====================================================================",
    "-- INSTALADOR COMPLETO · generado por python_scripts/armar_instalador.py",
    "-- Pegar en Supabase → SQL Editor → Run. Ejecutar UNA sola vez en un proyecto vacío.",
    "-- (Para reinstalar, primero hay que borrar las tablas; ver docs/PUESTA_EN_MARCHA.md)",
    "-- =====================================================================",
    "",
]
for parte in PARTES:
    salida += [f"-- >>>>>>>>>>>>>>>>>>>> {parte}", (RAIZ / parte).read_text(encoding="utf-8").strip(), ""]

destino = RAIZ / "supabase" / "INSTALAR_TODO.sql"
destino.write_text("\n".join(salida) + "\n", encoding="utf-8")
print(f"Escrito {destino.relative_to(RAIZ)} ({destino.stat().st_size // 1024} KB)")
