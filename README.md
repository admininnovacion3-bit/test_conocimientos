# APP_E · Evaluación adaptativa de aspirantes a practicantes (Innovación)

**App Android del aspirante** en Kotlin + Jetpack Compose. Es este proyecto de Android Studio (carpeta `app/`). No hay login: el aspirante escribe su nombre, la IA interpreta su carrera y la mascota pixel art **Bit** lo acompaña con tips y un cronómetro por pregunta.

No hay aplicación web: el docente revisa resultados y alertas en el panel de Supabase.

El backend es **Supabase** (PostgreSQL + RLS + Auth + Edge Functions) y la IA es **Gemini** (plan gratuito). La IA solo rellena plantillas. Si falla dos veces, se usa un banco de preguntas escrito por humanos.

**El aspirante nunca ve su resultado.** Al terminar solo aparece: *"Proceso completado. Valida con tu profesor."*

| Documento | Contenido |
|---|---|
| [ESTRUCTURA.md](ESTRUCTURA.md) | Qué hay en cada carpeta y qué hace cada archivo |
| [docs/DISENO_SISTEMA.md](docs/DISENO_SISTEMA.md) | Las 9 partes del diseño, cada decisión con su justificación |
| [docs/PUESTA_EN_MARCHA.md](docs/PUESTA_EN_MARCHA.md) | Pasos para desplegar y probar |
