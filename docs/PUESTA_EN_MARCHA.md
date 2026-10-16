# Puesta en marcha (todo en planes gratuitos)

## 1. Supabase
1. Crea un proyecto en <https://supabase.com> (plan Free).
2. En **SQL Editor** ejecuta, en este orden:
   1. `supabase/migrations/20261014000001_esquema.sql`
   2. `supabase/migrations/20261014000002_funciones_triggers.sql`
   3. `supabase/migrations/20261014000003_rls.sql`
   4. `supabase/seed.sql` (plantillas, temas, 4 carreras, 10 semillas y 50 preguntas del banco)
3. *(Opcional, como evidencia)* ejecuta `supabase/tests/pruebas_rls.sql`. Debe mostrar solo avisos `OK ...` y termina en ROLLBACK, así que no deja datos.
4. **Authentication → Sign In / Providers:** activa **"Allow anonymous sign-ins"**. Los aspirantes entran sin cuenta: solo escriben su nombre y su carrera. Recomendado en producción: activa también el CAPTCHA de Supabase para limitar abusos.
5. Los docentes sí usan correo. Créalos en **Authentication → Users → Add user** y luego cámbiales el rol (todo usuario nuevo nace como `aspirante`):
   ```sql
   update public.usuarios set rol = 'docente' where email = 'docente@ejemplo.test';
   ```

## 2. Edge Functions + Gemini
1. Crea una API key gratis en <https://aistudio.google.com/apikey>.
2. Con la CLI de Supabase (`npx supabase ...`):
   ```bash
   npx supabase login
   npx supabase link --project-ref TU_REF
   npx supabase secrets set GEMINI_API_KEY=tu_clave GEMINI_MODEL=gemini-2.5-flash
   npx supabase functions deploy clasificar-carrera
   npx supabase functions deploy iniciar-evaluacion
   npx supabase functions deploy siguiente-pregunta
   npx supabase functions deploy finalizar-evaluacion
   ```
   Sin `GEMINI_API_KEY` el sistema **funciona igual**: usa el banco fijo, una retroalimentación por plantilla y clasifica la carrera solo por palabras clave (lo que no entienda queda como "Otra carrera afín").

## 3. App móvil (Android Studio)
Agrega al final de `local.properties` (ese archivo no se sube a git):
```
SUPABASE_URL=https://TU_REF.supabase.co
SUPABASE_ANON_KEY=tu_anon_key
```
Luego **Sync Gradle → Run**. La anon key es pública por diseño: lo que protege los datos es la RLS.

## 4. Banco de preguntas (Python 3.10+, sin dependencias)
```bash
python python_scripts/validador.py banco/banco_fijo.json     # valida (y ejecuta el código de las preguntas)
python python_scripts/generar_seed.py                       # valida todo y regenera supabase/seed.sql
python -m unittest discover -s python_scripts/tests -v      # 19 pruebas
```
Para agregar preguntas, edita `banco/banco_fijo.json`, regenera el seed y vuelve a ejecutar `seed.sql`. Es idempotente (`on conflict do update`).

## 5. Pruebas del backend (Deno)
```bash
cd supabase/functions
npx deno test --allow-read tests/   # 8 pruebas
```
