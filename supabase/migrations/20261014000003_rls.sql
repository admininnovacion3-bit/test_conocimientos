-- =====================================================================
-- 0003 · ROW LEVEL SECURITY
-- Principio: "denegar por defecto". Al activar RLS, una tabla sin
-- política es invisible para anon/authenticated. Solo abrimos lo mínimo.
-- Las Edge Functions usan service_role (salta RLS) y validan el rol en código.
--
-- Resumen de permisos
--   tabla                  aspirante                    docente               admin
--   usuarios               leer su fila                 leer todas            todo
--   carreras               leer (activas)               leer                  todo
--   aspirantes             leer/editar su perfil        leer todos            todo
--   temas/plantillas/banco —                            leer                  todo
--   evaluaciones           leer la suya (sin notas)     leer todas            todo
--   preguntas_generadas    — (usa vista sin respuesta)  leer todas            todo
--   respuestas             SOLO insertar las suyas      leer todas            todo
--   resultados             —                            leer todos            todo
--   alertas                —                            leer + marcar atendida todo
--   eventos_ia             —                            leer                  todo
-- =====================================================================

alter table public.usuarios             enable row level security;
alter table public.aspirantes           enable row level security;
alter table public.temas                enable row level security;
alter table public.carreras             enable row level security;
alter table public.semillas_carrera     enable row level security;
alter table public.plantillas           enable row level security;
alter table public.banco_preguntas_fijo enable row level security;
alter table public.evaluaciones         enable row level security;
alter table public.preguntas_generadas  enable row level security;
alter table public.respuestas           enable row level security;
alter table public.resultados           enable row level security;
alter table public.alertas              enable row level security;
alter table public.eventos_ia           enable row level security;

-- El rol anónimo no toca nada del sistema.
revoke all on all tables in schema public from anon;

-- ---------------- usuarios ----------------
create policy usuarios_select on public.usuarios for select to authenticated
  using (id = auth.uid() or public.es_staff());
create policy usuarios_admin on public.usuarios for all to authenticated
  using (public.es_admin()) with check (public.es_admin());
-- Nadie (salvo admin) puede hacer UPDATE: así un aspirante no se auto-asciende a docente.

-- ---------------- aspirantes ----------------
create policy aspirantes_select on public.aspirantes for select to authenticated
  using (usuario_id = auth.uid() or public.es_staff());
create policy aspirantes_update_propio on public.aspirantes for update to authenticated
  using (usuario_id = auth.uid()) with check (usuario_id = auth.uid());
create policy aspirantes_admin on public.aspirantes for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- ---------------- carreras: lista pública para que el aspirante elija la suya ----------------
create policy carreras_lectura on public.carreras for select to authenticated using (activa or public.es_staff());
create policy carreras_admin   on public.carreras for all    to authenticated using (public.es_admin()) with check (public.es_admin());

create policy semillas_carrera_staff on public.semillas_carrera for select to authenticated using (public.es_staff());
create policy semillas_carrera_admin on public.semillas_carrera for all    to authenticated using (public.es_admin()) with check (public.es_admin());

-- ---------------- catálogos: temas, plantillas, banco (contienen respuestas) ----------------
create policy temas_staff on public.temas for select to authenticated using (public.es_staff());
create policy temas_admin on public.temas for all    to authenticated using (public.es_admin()) with check (public.es_admin());

create policy plantillas_staff on public.plantillas for select to authenticated using (public.es_staff());
create policy plantillas_admin on public.plantillas for all    to authenticated using (public.es_admin()) with check (public.es_admin());

create policy banco_staff on public.banco_preguntas_fijo for select to authenticated using (public.es_staff());
create policy banco_admin on public.banco_preguntas_fijo for all    to authenticated using (public.es_admin()) with check (public.es_admin());

-- ---------------- evaluaciones ----------------
-- Solo contiene estado y progreso (no puntaje). La crea la Edge Function iniciar-evaluacion.
create policy eval_select on public.evaluaciones for select to authenticated
  using (aspirante_id = auth.uid() or public.es_staff());
create policy eval_admin on public.evaluaciones for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- ---------------- preguntas_generadas ----------------
-- El aspirante NO tiene política aquí: la tabla guarda respuesta_correcta, nivel y tema.
create policy preg_staff on public.preguntas_generadas for select to authenticated using (public.es_staff());
create policy preg_admin on public.preguntas_generadas for all    to authenticated using (public.es_admin()) with check (public.es_admin());

-- Vista segura para el aspirante: SOLO columnas inofensivas y SOLO sus filas.
-- Corre con permisos del dueño (postgres) a propósito; el filtro auth.uid() es la barrera.
create view public.v_preguntas_aspirante with (security_barrier = true) as
  select p.id, p.evaluacion_id, p.orden, p.tipo, p.contenido,
         (r.id is not null) as respondida
  from public.preguntas_generadas p
  left join public.respuestas r on r.pregunta_id = p.id
  where p.aspirante_id = auth.uid();
revoke all on public.v_preguntas_aspirante from anon;
grant select on public.v_preguntas_aspirante to authenticated;

-- ---------------- respuestas ----------------
-- Aspirante: INSERT únicamente. Sin SELECT => no puede ver es_correcta ni puntaje.
-- (El cliente debe insertar con Prefer: return=minimal, que es lo que hace supabase-flutter sin .select()).
create policy resp_insert_aspirante on public.respuestas for insert to authenticated
  with check (aspirante_id = auth.uid() and public.rol_actual() = 'aspirante');
create policy resp_staff on public.respuestas for select to authenticated using (public.es_staff());
create policy resp_admin on public.respuestas for all    to authenticated using (public.es_admin()) with check (public.es_admin());
-- Ni UPDATE ni DELETE para el aspirante: una respuesta enviada es definitiva.

-- ---------------- resultados (núcleo de la regla "el aspirante nunca ve resultados") ----------------
create policy res_staff on public.resultados for select to authenticated using (public.es_staff());
create policy res_admin on public.resultados for all    to authenticated using (public.es_admin()) with check (public.es_admin());

-- ---------------- alertas ----------------
create policy alertas_staff_select on public.alertas for select to authenticated using (public.es_staff());
create policy alertas_docente_atender on public.alertas for update to authenticated
  using (public.es_staff()) with check (public.es_staff());
create policy alertas_admin on public.alertas for all to authenticated
  using (public.es_admin()) with check (public.es_admin());
-- El docente solo puede cambiar columnas de seguimiento:
revoke update on public.alertas from authenticated;
grant  update (atendida, atendida_por, atendida_en, nota_docente) on public.alertas to authenticated;

-- ---------------- eventos_ia ----------------
create policy eventos_staff on public.eventos_ia for select to authenticated using (public.es_staff());
