-- =====================================================================
-- INSTALADOR COMPLETO · generado por python_scripts/armar_instalador.py
-- Pegar en Supabase → SQL Editor → Run. Ejecutar UNA sola vez en un proyecto vacío.
-- (Para reinstalar, primero hay que borrar las tablas; ver docs/PUESTA_EN_MARCHA.md)
-- =====================================================================

-- >>>>>>>>>>>>>>>>>>>> supabase/migrations/20261014000001_esquema.sql
-- =====================================================================
-- 0001 · ESQUEMA BASE
-- Sistema de evaluación adaptativa de aspirantes a practicantes.
-- Ejecutar en Supabase (SQL Editor) o con `supabase db push`.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Tipos enumerados (dominios cerrados, imposibles de "inventar") ----------
create type public.rol_usuario     as enum ('aspirante', 'docente', 'admin');
create type public.area_eval       as enum ('logica', 'programacion', 'bases_de_datos', 'actitud');
create type public.tipo_pregunta   as enum ('opcion_multiple', 'codigo_salida', 'completar_codigo',
                                            'caso_practico', 'verdadero_falso_justificado');
create type public.estado_eval     as enum ('en_curso', 'completada', 'anulada');
create type public.origen_pregunta as enum ('semilla', 'ia', 'banco');
create type public.nivel_semilla   as enum ('BAJO', 'MEDIO', 'ALTO');

-- ---------- usuarios: espejo de auth.users con el ROL ----------
-- Los aspirantes NO crean cuenta: la app los registra con "inicio de sesión anónimo" de Supabase
-- (por eso email puede ser null). Así siguen teniendo un JWT propio y la RLS los protege igual.
create table public.usuarios (
  id              uuid primary key references auth.users(id) on delete cascade,
  email           text,
  nombre_completo text not null default '',
  rol             public.rol_usuario not null default 'aspirante',
  creado_en       timestamptz not null default now()
);

-- ---------- carreras: catálogo cerrado (fuente: banco/carreras.json) ----------
-- La carrera define las 5 semillas y cuántas preguntas adaptativas van a cada área.
create table public.carreras (
  id             text primary key,                    -- ej. ingenieria_software
  nombre         text not null,
  descripcion    text not null,
  palabras_clave text[] not null,                     -- para clasificar lo que escribe el aspirante
  pesos_area     jsonb not null,                      -- {"logica":3,"programacion":6,...} suma 15
  orden          smallint not null default 0,
  activa         boolean not null default true
);

-- ---------- aspirantes: perfil extendido ----------
create table public.aspirantes (
  usuario_id     uuid primary key references public.usuarios(id) on delete cascade,
  carrera_id     text references public.carreras(id),
  carrera_texto  text,                                -- lo que escribió el aspirante, tal cual
  creado_en      timestamptz not null default now()
);

-- ---------- temas: catálogo cerrado (fuente: plantillas/catalogo_temas.json) ----------
create table public.temas (
  area           public.area_eval not null,
  tema           text not null,
  nivel_minimo   smallint not null check (nivel_minimo between 1 and 3),
  palabras_clave text[] not null,
  primary key (area, tema)
);

-- ---------- plantillas: los 5 moldes JSON que la IA SOLO rellena ----------
create table public.plantillas (
  id_plantilla     text primary key,
  tipo             public.tipo_pregunta not null unique,
  areas_permitidas public.area_eval[] not null,
  definicion       jsonb not null,          -- plantilla completa (estructura + restricciones + ejemplo)
  activa           boolean not null default true,
  actualizada_en   timestamptz not null default now()
);

-- ---------- banco_preguntas_fijo: escritas por humanos (respaldo + semillas) ----------
create table public.banco_preguntas_fijo (
  id                 uuid primary key default gen_random_uuid(),
  codigo             text not null unique,                 -- ej. BF-001, SEM-01
  id_plantilla       text not null references public.plantillas(id_plantilla),
  area               public.area_eval not null,
  tema               text not null,
  nivel              smallint not null check (nivel between 1 and 3),
  tipo               public.tipo_pregunta not null,
  contenido          jsonb not null,                       -- lo que ve el aspirante (sin respuesta)
  respuesta_correcta jsonb not null,                       -- {"opcion":"B"} o {"valor":true,"justificacion":"A"}
  explicacion        text not null,
  rasgos_opciones    jsonb,                                -- solo semillas: estilo de razonamiento por opción
  hash               text not null unique,
  es_semilla         boolean not null default false,
  activa             boolean not null default true,
  autor              text not null default 'equipo_innovacion',
  creado_en          timestamptz not null default now(),
  foreign key (area, tema) references public.temas(area, tema)
);

-- ---------- semillas_carrera: las 5 preguntas semilla de cada carrera, en orden ----------
create table public.semillas_carrera (
  carrera_id text not null references public.carreras(id) on delete cascade,
  orden      smallint not null check (orden between 1 and 5),
  banco_id   uuid not null references public.banco_preguntas_fijo(id),
  primary key (carrera_id, orden),
  unique (carrera_id, banco_id)
);

-- ---------- evaluaciones: una sesión de prueba del aspirante (sin datos sensibles) ----------
create table public.evaluaciones (
  id                    uuid primary key default gen_random_uuid(),
  aspirante_id          uuid not null references public.usuarios(id) on delete cascade,
  carrera_id            text not null references public.carreras(id),
  estado                public.estado_eval not null default 'en_curso',
  total_preguntas       smallint not null default 20,
  preguntas_respondidas smallint not null default 0,
  iniciada_en           timestamptz not null default now(),
  finalizada_en         timestamptz
);
-- Un aspirante solo puede tener UNA evaluación activa o completada (el admin puede anular).
create unique index uq_eval_vigente on public.evaluaciones (aspirante_id) where estado <> 'anulada';

-- ---------- preguntas_generadas: cada pregunta ASIGNADA a un aspirante ----------
-- Incluye semillas, generadas por IA y respaldos del banco. La respuesta correcta vive aquí,
-- pero el aspirante NUNCA lee esta tabla: solo la vista v_preguntas_aspirante (sin respuesta).
create table public.preguntas_generadas (
  id                 uuid primary key default gen_random_uuid(),
  evaluacion_id      uuid not null references public.evaluaciones(id) on delete cascade,
  aspirante_id       uuid not null references public.usuarios(id) on delete cascade,
  orden              smallint not null check (orden between 1 and 20),
  origen             public.origen_pregunta not null,
  id_plantilla       text not null references public.plantillas(id_plantilla),
  banco_id           uuid references public.banco_preguntas_fijo(id),
  area               public.area_eval not null,
  tema               text not null,
  nivel              smallint not null check (nivel between 1 and 3),
  tipo               public.tipo_pregunta not null,
  contenido          jsonb not null,
  respuesta_correcta jsonb not null,
  explicacion        text not null,
  hash               text not null,
  intentos_ia        smallint not null default 0,
  modelo_ia          text,
  creado_en          timestamptz not null default now(),
  unique (evaluacion_id, orden),
  unique (evaluacion_id, hash)
);

-- ---------- respuestas: lo único que el aspirante escribe ----------
create table public.respuestas (
  id               uuid primary key default gen_random_uuid(),
  evaluacion_id    uuid not null references public.evaluaciones(id) on delete cascade,
  pregunta_id      uuid not null unique references public.preguntas_generadas(id) on delete cascade,
  aspirante_id     uuid not null default auth.uid() references public.usuarios(id) on delete cascade,
  respuesta        jsonb not null,
  tiempo_ms        integer check (tiempo_ms >= 0),
  es_correcta      boolean not null default false,   -- lo calcula un trigger, nunca el cliente
  puntaje_obtenido smallint not null default 0,
  creado_en        timestamptz not null default now()
);

-- ---------- resultados: SOLO docente/admin ----------
create table public.resultados (
  evaluacion_id          uuid primary key references public.evaluaciones(id) on delete cascade,
  aspirante_id           uuid not null references public.usuarios(id) on delete cascade,
  aciertos_semilla       smallint,
  nivel_semilla          public.nivel_semilla,
  nivel_inicial          smallint check (nivel_inicial between 1 and 3),
  nivel_actual           smallint check (nivel_actual between 1 and 3),
  estilo_razonamiento    jsonb,          -- conteo de rasgos elegidos en semillas
  puntaje_final          numeric(5,2),   -- 0..100 ponderado por nivel
  detalle_por_tema       jsonb,          -- [{area,tema,correctas,total,porcentaje}]
  fortalezas             jsonb,
  debilidades            jsonb,
  recomendaciones_ia     jsonb,          -- {resumen, recomendaciones[], plan_practica[]}
  recomendaciones_origen text check (recomendaciones_origen in ('ia', 'plantilla')),
  calculado_en           timestamptz
);

-- ---------- alertas: nivel BAJO en semillas (3+ fallos de 5) ----------
create table public.alertas (
  id               uuid primary key default gen_random_uuid(),
  aspirante_id     uuid not null references public.usuarios(id) on delete cascade,
  evaluacion_id    uuid not null unique references public.evaluaciones(id) on delete cascade,
  tipo             text not null default 'nivel_bajo_semilla',
  aciertos_semilla smallint not null,
  fallos_semilla   smallint not null,
  mensaje          text not null,
  atendida         boolean not null default false,
  atendida_por     uuid references public.usuarios(id),
  atendida_en      timestamptz,
  nota_docente     text,
  creado_en        timestamptz not null default now()
);

-- ---------- eventos_ia: auditoría de cada intento de generación (para la sustentación) ----------
create table public.eventos_ia (
  id            uuid primary key default gen_random_uuid(),
  evaluacion_id uuid references public.evaluaciones(id) on delete cascade,
  orden         smallint,
  operacion     text not null check (operacion in ('generar_pregunta', 'retroalimentacion')),
  intento       smallint not null,
  exito         boolean not null,
  errores       text[],
  latencia_ms   integer,
  modelo        text,
  creado_en     timestamptz not null default now()
);

-- Índices para las consultas del docente (filtros por área, nivel y fecha)
create index idx_eval_aspirante   on public.evaluaciones (aspirante_id);
create index idx_eval_fecha       on public.evaluaciones (iniciada_en desc);
create index idx_preg_eval        on public.preguntas_generadas (evaluacion_id, orden);
create index idx_resp_eval        on public.respuestas (evaluacion_id);
create index idx_banco_busqueda   on public.banco_preguntas_fijo (area, nivel, tema) where activa and not es_semilla;
create index idx_alertas_abiertas on public.alertas (creado_en desc) where not atendida;

-- >>>>>>>>>>>>>>>>>>>> supabase/migrations/20261014000002_funciones_triggers.sql
-- =====================================================================
-- 0002 · FUNCIONES Y TRIGGERS
-- La calificación ocurre DENTRO de la base de datos: el cliente móvil
-- nunca envía ni recibe "es_correcta".
-- =====================================================================

-- ---------- Helpers de rol (usados por las políticas RLS) ----------
-- security definer: leen usuarios sin quedar atrapados por la propia RLS de usuarios.
create or replace function public.rol_actual()
returns public.rol_usuario
language sql stable security definer set search_path = public as $$
  select rol from public.usuarios where id = auth.uid();
$$;

create or replace function public.es_staff()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.rol_actual() in ('docente', 'admin'), false);
$$;

create or replace function public.es_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.rol_actual() = 'admin', false);
$$;

-- ---------- Alta automática: todo usuario nuevo nace como ASPIRANTE ----------
-- Incluye los usuarios anónimos que crea la app móvil (sin email).
-- El rol nunca viene del cliente; solo un admin puede promover a docente/admin.
create or replace function public.al_crear_usuario_auth()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.usuarios (id, email, nombre_completo)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'nombre_completo', ''));
  insert into public.aspirantes (usuario_id) values (new.id);
  return new;
end $$;

create trigger trg_auth_usuario_nuevo
  after insert on auth.users
  for each row execute function public.al_crear_usuario_auth();

-- ---------- Calificación (BEFORE INSERT en respuestas) ----------
create or replace function public.calificar_respuesta()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  p public.preguntas_generadas;
  v_estado public.estado_eval;
begin
  select * into p from public.preguntas_generadas where id = new.pregunta_id;
  if not found then
    raise exception 'La pregunta no existe';
  end if;
  if p.aspirante_id <> new.aspirante_id then
    raise exception 'La pregunta no está asignada a este aspirante';
  end if;

  select estado into v_estado from public.evaluaciones where id = p.evaluacion_id;
  if v_estado <> 'en_curso' then
    raise exception 'La evaluación ya fue cerrada';
  end if;

  -- Se ignora cualquier valor que el cliente intente forzar
  new.evaluacion_id := p.evaluacion_id;
  if p.tipo = 'verdadero_falso_justificado' then
    new.es_correcta := (new.respuesta -> 'valor') = (p.respuesta_correcta -> 'valor')
                   and upper(new.respuesta ->> 'justificacion') = upper(p.respuesta_correcta ->> 'justificacion');
  else
    new.es_correcta := upper(new.respuesta ->> 'opcion') = upper(p.respuesta_correcta ->> 'opcion');
  end if;
  new.es_correcta := coalesce(new.es_correcta, false);
  new.puntaje_obtenido := case when new.es_correcta then p.nivel else 0 end;  -- peso = nivel
  return new;
end $$;

create trigger trg_calificar_respuesta
  before insert on public.respuestas
  for each row execute function public.calificar_respuesta();

-- ---------- Evaluación de semillas + ALERTA DE NIVEL BAJO ----------
create or replace function public.evaluar_semilla(p_eval uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_aciertos int;
  v_total    int;
  v_asp      uuid;
  v_nivel    public.nivel_semilla;
  v_estilo   jsonb;
begin
  select count(*) filter (where r.es_correcta), count(*)
    into v_aciertos, v_total
  from public.respuestas r
  join public.preguntas_generadas p on p.id = r.pregunta_id
  where p.evaluacion_id = p_eval and p.origen = 'semilla';

  select aspirante_id into v_asp from public.evaluaciones where id = p_eval;

  if v_total < 5 then
    return;  -- aún no termina las 5 semillas
  end if;

  v_nivel := case when v_aciertos >= 5 then 'ALTO'
                  when v_aciertos >= 3 then 'MEDIO'
                  else 'BAJO' end;

  -- Estilo de razonamiento: cada opción de las semillas tiene un rasgo asociado
  select coalesce(jsonb_object_agg(rasgo, n), '{}'::jsonb) into v_estilo
  from (
    select b.rasgos_opciones ->> coalesce(r.respuesta ->> 'opcion', r.respuesta ->> 'justificacion') as rasgo,
           count(*) as n
    from public.respuestas r
    join public.preguntas_generadas p on p.id = r.pregunta_id
    join public.banco_preguntas_fijo b on b.id = p.banco_id
    where p.evaluacion_id = p_eval and p.origen = 'semilla'
    group by 1
  ) t where rasgo is not null;

  update public.resultados
     set aciertos_semilla    = v_aciertos,
         nivel_semilla       = v_nivel,
         nivel_inicial       = case v_nivel when 'ALTO' then 3 when 'MEDIO' then 2 else 1 end,
         nivel_actual        = case v_nivel when 'ALTO' then 3 when 'MEDIO' then 2 else 1 end,
         estilo_razonamiento = v_estilo
   where evaluacion_id = p_eval;

  -- Regla de negocio: 3 o más fallos de 5 => ALERTA (solo visible para docente)
  if (5 - v_aciertos) >= 3 then
    insert into public.alertas (aspirante_id, evaluacion_id, aciertos_semilla, fallos_semilla, mensaje)
    values (v_asp, p_eval, v_aciertos, 5 - v_aciertos,
            format('Nivel BAJO en preguntas semilla: %s de 5 correctas. Posible riesgo académico; '
                   'se recomienda entrevista de validación.', v_aciertos))
    on conflict (evaluacion_id) do nothing;
  end if;
end $$;

-- ---------- AFTER INSERT en respuestas: progreso + disparo de semilla ----------
create or replace function public.despues_de_responder()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_origen public.origen_pregunta;
begin
  update public.evaluaciones
     set preguntas_respondidas = (select count(*) from public.respuestas where evaluacion_id = new.evaluacion_id)
   where id = new.evaluacion_id;

  select origen into v_origen from public.preguntas_generadas where id = new.pregunta_id;
  if v_origen = 'semilla' then
    perform public.evaluar_semilla(new.evaluacion_id);
  end if;
  return null;
end $$;

create trigger trg_despues_de_responder
  after insert on public.respuestas
  for each row execute function public.despues_de_responder();

-- ---------- Cálculo del resultado final (lo invoca la Edge Function finalizar-evaluacion) ----------
create or replace function public.calcular_resultado(p_eval uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_puntaje  numeric(5,2);
  v_detalle  jsonb;
  v_fuertes  jsonb;
  v_debiles  jsonb;
begin
  -- Puntaje ponderado: una pregunta nivel 3 vale el triple que una nivel 1
  select round(100.0 * coalesce(sum(r.puntaje_obtenido), 0) / nullif(sum(p.nivel), 0), 2)
    into v_puntaje
  from public.preguntas_generadas p
  join public.respuestas r on r.pregunta_id = p.id
  where p.evaluacion_id = p_eval;

  with por_tema as (
    select p.area, p.tema,
           count(*) filter (where r.es_correcta) as correctas,
           count(*) as total,
           round(100.0 * count(*) filter (where r.es_correcta) / count(*), 0) as porcentaje
    from public.preguntas_generadas p
    join public.respuestas r on r.pregunta_id = p.id
    where p.evaluacion_id = p_eval
    group by p.area, p.tema
  )
  select coalesce(jsonb_agg(to_jsonb(t) order by t.area, t.tema), '[]'),
         coalesce(jsonb_agg(to_jsonb(t)) filter (where t.porcentaje >= 70 and t.total >= 2), '[]'),
         coalesce(jsonb_agg(to_jsonb(t)) filter (where t.porcentaje < 50), '[]')
    into v_detalle, v_fuertes, v_debiles
  from por_tema t;

  update public.resultados
     set puntaje_final    = v_puntaje,
         detalle_por_tema = v_detalle,
         fortalezas       = v_fuertes,
         debilidades      = v_debiles,
         calculado_en     = now()
   where evaluacion_id = p_eval;

  return jsonb_build_object('puntaje', v_puntaje, 'detalle', v_detalle,
                            'fortalezas', v_fuertes, 'debilidades', v_debiles);
end $$;

-- Estas funciones NO deben poder llamarse vía API (PostgREST expone /rpc/...).
revoke execute on function public.evaluar_semilla(uuid)    from public, anon, authenticated;
revoke execute on function public.calcular_resultado(uuid) from public, anon, authenticated;
grant  execute on function public.evaluar_semilla(uuid)    to service_role;
grant  execute on function public.calcular_resultado(uuid) to service_role;

-- >>>>>>>>>>>>>>>>>>>> supabase/migrations/20261014000003_rls.sql
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

-- >>>>>>>>>>>>>>>>>>>> supabase/migrations/20261014000004_tiempo_limite.sql
-- =====================================================================
-- 0004 · TIEMPO LÍMITE POR PREGUNTA (cronómetro)
-- El SERVIDOR es quien mide el tiempo: guarda cuándo se mostró cada pregunta
-- y el trigger de calificación rechaza respuestas que llegan tarde.
-- Así no sirve cerrar/reabrir la app ni cambiar la hora del celular.
-- =====================================================================

alter table public.preguntas_generadas
  add column if not exists tiempo_limite_s smallint not null default 90 check (tiempo_limite_s between 15 and 600),
  add column if not exists mostrada_en     timestamptz;          -- primera vez que se entregó al aspirante

alter table public.respuestas
  add column if not exists tiempo_agotado boolean not null default false;

-- Margen por latencia de red entre que el cronómetro llega a 0 y la respuesta llega al servidor.
create or replace function public.margen_tiempo_s() returns int language sql immutable as $$ select 8 $$;

-- Calificación con control de tiempo (reemplaza la versión de 0002)
create or replace function public.calificar_respuesta()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  p public.preguntas_generadas;
  v_estado public.estado_eval;
  v_tarde  boolean;
begin
  select * into p from public.preguntas_generadas where id = new.pregunta_id;
  if not found then
    raise exception 'La pregunta no existe';
  end if;
  if p.aspirante_id <> new.aspirante_id then
    raise exception 'La pregunta no está asignada a este aspirante';
  end if;

  select estado into v_estado from public.evaluaciones where id = p.evaluacion_id;
  if v_estado <> 'en_curso' then
    raise exception 'La evaluación ya fue cerrada';
  end if;

  new.evaluacion_id := p.evaluacion_id;

  -- ¿Llegó después del tiempo límite (+ margen)? Lo decide el reloj del servidor.
  v_tarde := p.mostrada_en is not null
             and now() > p.mostrada_en + make_interval(secs => p.tiempo_limite_s + public.margen_tiempo_s());
  new.tiempo_agotado := v_tarde or coalesce(new.tiempo_agotado, false);

  if v_tarde then
    new.es_correcta := false;
  elsif p.tipo = 'verdadero_falso_justificado' then
    new.es_correcta := (new.respuesta -> 'valor') = (p.respuesta_correcta -> 'valor')
                   and upper(new.respuesta ->> 'justificacion') = upper(p.respuesta_correcta ->> 'justificacion');
  else
    new.es_correcta := upper(new.respuesta ->> 'opcion') = upper(p.respuesta_correcta ->> 'opcion');
  end if;
  new.es_correcta := coalesce(new.es_correcta, false);   -- sin respuesta (tiempo agotado) = incorrecta
  new.puntaje_obtenido := case when new.es_correcta then p.nivel else 0 end;
  return new;
end $$;

-- Se agrega el tiempo límite a la vista del aspirante (no revela nada sensible)
create or replace view public.v_preguntas_aspirante with (security_barrier = true) as
  select p.id, p.evaluacion_id, p.orden, p.tipo, p.contenido,
         (r.id is not null) as respondida, p.tiempo_limite_s
  from public.preguntas_generadas p
  left join public.respuestas r on r.pregunta_id = p.id
  where p.aspirante_id = auth.uid();

-- >>>>>>>>>>>>>>>>>>>> supabase/seed.sql
-- =====================================================================
-- SEED GENERADO AUTOMÁTICAMENTE por python_scripts/generar_seed.py
-- NO EDITAR A MANO: editar los JSON de /plantillas y /banco y regenerar.
-- =====================================================================
begin;

-- Temas
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('logica', 'secuencias_patrones', 1, array['secuencia', 'serie', 'patron', 'siguiente', 'termino']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('logica', 'logica_proposicional', 1, array['proposicion', 'verdadero', 'falso', 'conjuncion', 'disyuncion', 'implica', 'negacion', ' and ', ' or ', ' not ']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('logica', 'conjuntos', 1, array['conjunto', 'union', 'interseccion', 'elemento', 'diferencia']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('logica', 'algoritmos_pseudocodigo', 1, array['algoritmo', 'pseudocodigo', 'paso', 'mientras', 'entonces', 'variable', 'instruccion']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('logica', 'razonamiento_deductivo', 2, array['premisa', 'conclusion', 'todos', 'algunos', 'ninguno', 'deduce', 'se concluye']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('programacion', 'variables_tipos', 1, array['variable', 'tipo', 'int', 'str', 'float', 'entero', 'cadena', 'valor']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('programacion', 'condicionales', 1, array['if', 'else', 'elif', 'condicion', 'condicional']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('programacion', 'ciclos', 1, array['for', 'while', 'ciclo', 'bucle', 'range', 'itera']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('programacion', 'funciones', 1, array['def ', 'funcion', 'return', 'parametro', 'argumento', 'retorna']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('programacion', 'listas_estructuras', 1, array['lista', 'arreglo', 'diccionario', 'indice', 'append', 'len(', 'dict']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('programacion', 'poo', 2, array['clase', 'objeto', 'class ', 'self', 'herencia', 'metodo', 'atributo', 'instancia']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('programacion', 'recursion', 2, array['recursion', 'recursiv', 'caso base', 'a si misma', 'factorial', 'fibonacci']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('bases_de_datos', 'modelo_relacional', 1, array['tabla', 'relacion', 'entidad', 'atributo', 'registro', 'fila', 'columna']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('bases_de_datos', 'claves', 1, array['clave primaria', 'clave foranea', 'primary key', 'foreign key', 'llave', 'unique']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('bases_de_datos', 'sql_select', 1, array['select', 'where', 'order by', 'from', 'consulta']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('bases_de_datos', 'sql_agregacion', 2, array['count', 'sum(', 'avg', 'group by', 'having', 'max(', 'min(']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('bases_de_datos', 'sql_join', 2, array['join', 'inner', 'left', 'combina']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('bases_de_datos', 'normalizacion', 2, array['normal', '1fn', '2fn', '3fn', 'redundancia', 'dependencia']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('actitud', 'trabajo_equipo', 1, array['equipo', 'companero', 'colabor', 'grupo']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('actitud', 'aprendizaje_autonomo', 1, array['aprend', 'investig', 'documentacion', 'desconoc', 'tecnologia', 'tutorial']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('actitud', 'comunicacion', 1, array['comunic', 'inform', 'explic', 'reunion', 'jefe', 'cliente', 'avis']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('actitud', 'etica_profesional', 1, array['etica', 'datos', 'confidencial', 'privacidad', 'copi', 'licencia', 'honest']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;
insert into public.temas (area, tema, nivel_minimo, palabras_clave) values ('actitud', 'manejo_presion', 1, array['plazo', 'entrega', 'presion', 'urgente', 'prioridad', 'tiempo']::text[]) on conflict (area, tema) do update set nivel_minimo = excluded.nivel_minimo, palabras_clave = excluded.palabras_clave;

-- Plantillas
insert into public.plantillas (id_plantilla, tipo, areas_permitidas, definicion) values ('PL-CC-01', 'completar_codigo', array['logica', 'programacion', 'bases_de_datos']::public.area_eval[], $j${"id_plantilla": "PL-CC-01", "version": 1, "tipo": "completar_codigo", "descripcion": "Código con UN hueco marcado [[HUECO]]; el aspirante elige el fragmento que lo completa correctamente.", "area": "bases_de_datos", "tema": "sql_select", "nivel": 1, "nota_parametros": "area, tema y nivel los fija el motor adaptativo. El hueco del código se marca [[HUECO]] (no '___') para no confundirlo con los campos que rellena la IA.", "areas_permitidas": ["logica", "programacion", "bases_de_datos"], "estructura": {"id_plantilla": "PL-CC-01", "area": "{{area}}", "tema": "{{tema}}", "nivel": "{{nivel}}", "tipo": "completar_codigo", "contenido": {"enunciado": "___", "lenguaje": "___", "codigo": "___", "opciones": {"A": "___", "B": "___", "C": "___", "D": "___"}}, "respuesta_correcta": {"opcion": "___"}, "explicacion": "___"}, "restricciones": {"longitud": {"enunciado": [20, 300], "codigo": [10, 600], "opcion": [1, 80], "explicacion": [20, 400]}, "lenguajes_permitidos": ["python", "pseudocodigo", "sql"], "lineas_codigo_por_nivel": {"1": [1, 6], "2": [2, 12], "3": [3, 20]}, "marcador_hueco": "[[HUECO]]", "huecos_exactos": 1, "num_opciones": 4, "una_sola_correcta": true, "tema_obligatorio": true, "opciones_distintas": true, "frases_prohibidas": ["todas las anteriores", "ninguna de las anteriores"], "reglas_texto": ["El código debe contener exactamente un [[HUECO]].", "El enunciado debe describir qué debe lograr el código completo.", "Solo una opción hace que el código cumpla el objetivo; las demás deben fallar o hacer otra cosa."]}, "ejemplo_salida": {"id_plantilla": "PL-CC-01", "area": "bases_de_datos", "tema": "sql_select", "nivel": 1, "tipo": "completar_codigo", "contenido": {"enunciado": "Complete la consulta para listar los productos con precio mayor a 50000, del más caro al más barato.", "lenguaje": "sql", "codigo": "SELECT nombre, precio\nFROM productos\nWHERE precio > 50000\n[[HUECO]];", "opciones": {"A": "ORDER BY precio ASC", "B": "GROUP BY precio", "C": "ORDER BY precio DESC", "D": "SORT BY precio DESC"}}, "respuesta_correcta": {"opcion": "C"}, "explicacion": "ORDER BY ... DESC ordena de mayor a menor. ASC haría lo contrario, GROUP BY agrupa y SORT BY no existe en SQL estándar."}}$j$::jsonb) on conflict (id_plantilla) do update set definicion = excluded.definicion, areas_permitidas = excluded.areas_permitidas, actualizada_en = now();
insert into public.plantillas (id_plantilla, tipo, areas_permitidas, definicion) values ('PL-CP-01', 'caso_practico', array['actitud', 'programacion', 'bases_de_datos']::public.area_eval[], $j${"id_plantilla": "PL-CP-01", "version": 1, "tipo": "caso_practico", "descripcion": "Situación realista del área de innovación; el aspirante elige la mejor acción entre 4.", "area": "actitud", "tema": "comunicacion", "nivel": 2, "nota_parametros": "area, tema y nivel los fija el motor adaptativo. En actitud no hay 'respuesta de libro': la correcta es la que refleja la competencia esperada por la institución (documentada en la explicación).", "areas_permitidas": ["actitud", "programacion", "bases_de_datos"], "estructura": {"id_plantilla": "PL-CP-01", "area": "{{area}}", "tema": "{{tema}}", "nivel": "{{nivel}}", "tipo": "caso_practico", "contenido": {"contexto": "___", "enunciado": "___", "opciones": {"A": "___", "B": "___", "C": "___", "D": "___"}}, "respuesta_correcta": {"opcion": "___"}, "explicacion": "___"}, "restricciones": {"longitud": {"contexto": [60, 600], "enunciado": [15, 200], "opcion": [10, 200], "explicacion": [20, 400]}, "num_opciones": 4, "una_sola_correcta": true, "tema_obligatorio": true, "opciones_distintas": true, "frases_prohibidas": ["todas las anteriores", "ninguna de las anteriores", "depende de la situacion"], "reglas_texto": ["El contexto debe ocurrir en un equipo de desarrollo o soporte de una institución universitaria.", "Sin nombres reales; usar roles (el líder del proyecto, un compañero, el usuario).", "Ninguna opción debe ser obviamente grosera o ilegal; los distractores deben ser tentadores.", "La opción correcta es la más profesional, proactiva y responsable."]}, "ejemplo_salida": {"id_plantilla": "PL-CP-01", "area": "actitud", "tema": "comunicacion", "nivel": 2, "tipo": "caso_practico", "contenido": {"contexto": "Usted lleva dos semanas en la práctica. El jefe del área le asignó un módulo que debe entregar el viernes. El miércoles descubre que depende de un servicio que otro equipo aún no termina.", "enunciado": "¿Qué es lo más adecuado hacer?", "opciones": {"A": "Esperar al viernes y explicar en la entrega por qué no se pudo terminar.", "B": "Informar hoy al jefe el bloqueo, proponer avanzar con datos simulados y acordar una nueva fecha.", "C": "Reescribir por su cuenta el servicio del otro equipo para no depender de nadie.", "D": "Pedirle a un compañero que termine el servicio sin avisar al jefe."}}, "respuesta_correcta": {"opcion": "B"}, "explicacion": "Comunicar el riesgo a tiempo, proponer una alternativa (mock) y renegociar el plazo es la conducta profesional esperada."}}$j$::jsonb) on conflict (id_plantilla) do update set definicion = excluded.definicion, areas_permitidas = excluded.areas_permitidas, actualizada_en = now();
insert into public.plantillas (id_plantilla, tipo, areas_permitidas, definicion) values ('PL-CS-01', 'codigo_salida', array['logica', 'programacion', 'bases_de_datos']::public.area_eval[], $j${"id_plantilla": "PL-CS-01", "version": 1, "tipo": "codigo_salida", "descripcion": "Se muestra un fragmento de código y el aspirante elige la salida exacta que produce.", "area": "programacion", "tema": "funciones", "nivel": 2, "nota_parametros": "area, tema y nivel los fija el motor adaptativo. La IA solo rellena los '___'.", "areas_permitidas": ["logica", "programacion", "bases_de_datos"], "estructura": {"id_plantilla": "PL-CS-01", "area": "{{area}}", "tema": "{{tema}}", "nivel": "{{nivel}}", "tipo": "codigo_salida", "contenido": {"enunciado": "___", "lenguaje": "___", "codigo": "___", "opciones": {"A": "___", "B": "___", "C": "___", "D": "___"}}, "respuesta_correcta": {"opcion": "___"}, "explicacion": "___"}, "restricciones": {"longitud": {"enunciado": [20, 300], "codigo": [10, 600], "opcion": [1, 120], "explicacion": [20, 400]}, "lenguajes_permitidos": ["python", "pseudocodigo", "sql"], "lineas_codigo_por_nivel": {"1": [1, 6], "2": [2, 12], "3": [3, 20]}, "num_opciones": 4, "una_sola_correcta": true, "tema_obligatorio": true, "opciones_distintas": true, "frases_prohibidas": ["todas las anteriores", "ninguna de las anteriores", "error de compilacion"], "reglas_texto": ["El código debe ser determinista: sin random, sin input(), sin fecha/hora, sin red ni archivos.", "La salida correcta debe ser exactamente lo que imprime el código (respetar saltos de línea con \\n).", "Si lenguaje es sql, el enunciado debe incluir los datos de la tabla.", "Los distractores deben corresponder a errores típicos (off-by-one, precedencia, mutabilidad)."]}, "ejemplo_salida": {"id_plantilla": "PL-CS-01", "area": "programacion", "tema": "funciones", "nivel": 2, "tipo": "codigo_salida", "contenido": {"enunciado": "¿Qué imprime el siguiente código en Python?", "lenguaje": "python", "codigo": "def duplicar(x):\n    return x * 2\n\nprint(duplicar('ab') + str(duplicar(3)))", "opciones": {"A": "abab6", "B": "ab26", "C": "Error de tipos", "D": "abab33"}}, "respuesta_correcta": {"opcion": "A"}, "explicacion": "duplicar('ab') repite la cadena ('abab') y duplicar(3) retorna 6; str(6) se concatena: 'abab6'."}}$j$::jsonb) on conflict (id_plantilla) do update set definicion = excluded.definicion, areas_permitidas = excluded.areas_permitidas, actualizada_en = now();
insert into public.plantillas (id_plantilla, tipo, areas_permitidas, definicion) values ('PL-OM-01', 'opcion_multiple', array['logica', 'programacion', 'bases_de_datos', 'actitud']::public.area_eval[], $j${"id_plantilla": "PL-OM-01", "version": 1, "tipo": "opcion_multiple", "descripcion": "Pregunta conceptual con 4 opciones (A-D) y exactamente una correcta.", "area": "programacion", "tema": "ciclos", "nivel": 1, "nota_parametros": "area, tema y nivel son valores por defecto. En cada solicitud los FIJA el motor adaptativo (nunca la IA) reemplazando {{area}}, {{tema}} y {{nivel}} antes de enviar la plantilla a Gemini.", "areas_permitidas": ["logica", "programacion", "bases_de_datos", "actitud"], "estructura": {"id_plantilla": "PL-OM-01", "area": "{{area}}", "tema": "{{tema}}", "nivel": "{{nivel}}", "tipo": "opcion_multiple", "contenido": {"enunciado": "___", "opciones": {"A": "___", "B": "___", "C": "___", "D": "___"}}, "respuesta_correcta": {"opcion": "___"}, "explicacion": "___"}, "restricciones": {"longitud": {"enunciado": [20, 400], "opcion": [1, 150], "explicacion": [20, 400]}, "num_opciones": 4, "una_sola_correcta": true, "tema_obligatorio": true, "opciones_distintas": true, "frases_prohibidas": ["todas las anteriores", "ninguna de las anteriores", "todas son correctas", "ninguna es correcta", "a y b", "b y c"], "reglas_texto": ["El enunciado debe tratar SOLO el tema indicado.", "Los distractores deben ser plausibles (errores típicos), no absurdos.", "Las 4 opciones deben tener longitud similar para no delatar la correcta.", "Español neutro, sin nombres reales de personas ni empresas."]}, "ejemplo_salida": {"id_plantilla": "PL-OM-01", "area": "programacion", "tema": "ciclos", "nivel": 1, "tipo": "opcion_multiple", "contenido": {"enunciado": "¿Cuántas veces se ejecuta el cuerpo del ciclo for i in range(2, 8)?", "opciones": {"A": "8 veces", "B": "6 veces", "C": "7 veces", "D": "5 veces"}}, "respuesta_correcta": {"opcion": "B"}, "explicacion": "range(2, 8) genera 2, 3, 4, 5, 6 y 7: seis valores, porque el límite superior no se incluye."}}$j$::jsonb) on conflict (id_plantilla) do update set definicion = excluded.definicion, areas_permitidas = excluded.areas_permitidas, actualizada_en = now();
insert into public.plantillas (id_plantilla, tipo, areas_permitidas, definicion) values ('PL-VF-01', 'verdadero_falso_justificado', array['logica', 'programacion', 'bases_de_datos', 'actitud']::public.area_eval[], $j${"id_plantilla": "PL-VF-01", "version": 1, "tipo": "verdadero_falso_justificado", "descripcion": "Afirmación que el aspirante marca como verdadera o falsa y luego elige la justificación correcta entre 3. Solo cuenta como correcta si acierta AMBAS partes (evita acertar por azar: probabilidad 1/6 en vez de 1/2).", "area": "bases_de_datos", "tema": "claves", "nivel": 2, "nota_parametros": "area, tema y nivel los fija el motor adaptativo. La IA solo rellena los '___'. 'valor' debe ser booleano true/false, no texto.", "areas_permitidas": ["logica", "programacion", "bases_de_datos", "actitud"], "estructura": {"id_plantilla": "PL-VF-01", "area": "{{area}}", "tema": "{{tema}}", "nivel": "{{nivel}}", "tipo": "verdadero_falso_justificado", "contenido": {"afirmacion": "___", "opciones_justificacion": {"A": "___", "B": "___", "C": "___"}}, "respuesta_correcta": {"valor": "___", "justificacion": "___"}, "explicacion": "___"}, "restricciones": {"longitud": {"afirmacion": [20, 300], "opcion": [10, 200], "explicacion": [20, 400]}, "num_opciones": 3, "una_sola_correcta": true, "tema_obligatorio": true, "opciones_distintas": true, "frases_prohibidas": ["todas las anteriores", "ninguna de las anteriores", "siempre y nunca"], "reglas_texto": ["La afirmación debe ser inequívocamente verdadera o falsa (sin 'a veces' ni 'depende').", "Exactamente una justificación explica correctamente el valor de verdad.", "Las otras dos justificaciones deben sonar técnicas pero contener un error conceptual."]}, "ejemplo_salida": {"id_plantilla": "PL-VF-01", "area": "bases_de_datos", "tema": "claves", "nivel": 2, "tipo": "verdadero_falso_justificado", "contenido": {"afirmacion": "Una tabla puede tener varias claves foráneas pero solo una clave primaria.", "opciones_justificacion": {"A": "Porque la clave primaria identifica de forma única cada fila y puede ser compuesta, mientras que cada clave foránea referencia a otra tabla.", "B": "Porque las claves foráneas no pueden repetirse dentro de la misma tabla.", "C": "Porque PostgreSQL limita a una sola clave de cualquier tipo por tabla."}}, "respuesta_correcta": {"valor": true, "justificacion": "A"}, "explicacion": "Solo existe una PRIMARY KEY (simple o compuesta) por tabla; las FOREIGN KEY pueden ser varias, una por cada relación."}}$j$::jsonb) on conflict (id_plantilla) do update set definicion = excluded.definicion, areas_permitidas = excluded.areas_permitidas, actualizada_en = now();

-- Carreras
insert into public.carreras (id, nombre, descripcion, palabras_clave, pesos_area, orden) values ('ingenieria_sistemas', 'Ingeniería de Sistemas', 'Perfil equilibrado: lógica, programación, bases de datos y actitud.', array['sistemas', 'informatica', 'computacion', 'ingenieria de sistemas']::text[], $j${"logica": 4, "programacion": 4, "bases_de_datos": 4, "actitud": 3}$j$::jsonb, 1) on conflict (id) do update set nombre = excluded.nombre, descripcion = excluded.descripcion, palabras_clave = excluded.palabras_clave, pesos_area = excluded.pesos_area, orden = excluded.orden;
insert into public.carreras (id, nombre, descripcion, palabras_clave, pesos_area, orden) values ('ingenieria_software', 'Ingeniería de Software', 'Mayor énfasis en programación y diseño orientado a objetos.', array['ingenieria de software', 'ing software', 'ingenieria software', 'software']::text[], $j${"logica": 3, "programacion": 6, "bases_de_datos": 3, "actitud": 3}$j$::jsonb, 2) on conflict (id) do update set nombre = excluded.nombre, descripcion = excluded.descripcion, palabras_clave = excluded.palabras_clave, pesos_area = excluded.pesos_area, orden = excluded.orden;
insert into public.carreras (id, nombre, descripcion, palabras_clave, pesos_area, orden) values ('tecnologia_desarrollo', 'Tecnología en Desarrollo de Software', 'Programas tecnológicos: fundamentos prácticos de programación y SQL.', array['tecnologia', 'tecnologo', 'tecnico', 'adsi', 'analisis y desarrollo', 'sena', 'desarrollo de software']::text[], $j${"logica": 4, "programacion": 5, "bases_de_datos": 3, "actitud": 3}$j$::jsonb, 3) on conflict (id) do update set nombre = excluded.nombre, descripcion = excluded.descripcion, palabras_clave = excluded.palabras_clave, pesos_area = excluded.pesos_area, orden = excluded.orden;
insert into public.carreras (id, nombre, descripcion, palabras_clave, pesos_area, orden) values ('otra_afin', 'Otra carrera afín', 'Electrónica, telecomunicaciones, industrial, matemáticas u otras: énfasis en lógica.', array['electronica', 'telecomunicaciones', 'industrial', 'matematicas', 'redes', 'mecatronica', 'fisica']::text[], $j${"logica": 5, "programacion": 4, "bases_de_datos": 3, "actitud": 3}$j$::jsonb, 4) on conflict (id) do update set nombre = excluded.nombre, descripcion = excluded.descripcion, palabras_clave = excluded.palabras_clave, pesos_area = excluded.pesos_area, orden = excluded.orden;

-- Banco fijo (semillas + respaldo)
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('SEM-01', 'PL-OM-01', 'logica', 'secuencias_patrones', 1, 'opcion_multiple', $j${"enunciado": "¿Cuál es el siguiente término de la secuencia 3, 6, 11, 18, 27, ...?", "opciones": {"A": "36", "B": "38", "C": "39", "D": "35"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'Las diferencias son 3, 5, 7, 9 (impares consecutivos); la siguiente es 11, así que 27 + 11 = 38.', $j${"A": "patron_superficial", "B": "analitico", "C": "patron_superficial", "D": "impulsivo"}$j$::jsonb, '409e8a3d989620a2f4bea780694c57f232be73c36113aa6197c1198e9edf9309', true) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('SEM-02', 'PL-CS-01', 'programacion', 'ciclos', 2, 'codigo_salida', $j${"enunciado": "¿Qué imprime el siguiente código en Python?", "lenguaje": "python", "codigo": "total = 0\nfor i in range(1, 6):\n    if i % 2 == 0:\n        continue\n    total += i\nprint(total)", "opciones": {"A": "15", "B": "6", "C": "9", "D": "4"}}$j$::jsonb, $j${"opcion": "C"}$j$::jsonb, 'continue salta los pares (2 y 4); se suman 1 + 3 + 5 = 9.', $j${"A": "lectura_superficial", "B": "confusion_continue", "C": "analitico", "D": "confusion_continue"}$j$::jsonb, '0790ac68690801ee6c2fba2c799e4f47ddd24ae8926f659a138579bc0cc99df0', true) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('SEM-03', 'PL-CC-01', 'bases_de_datos', 'sql_agregacion', 2, 'completar_codigo', $j${"enunciado": "Complete la consulta para mostrar las ciudades que tienen MÁS de 10 estudiantes registrados.", "lenguaje": "sql", "codigo": "SELECT ciudad, COUNT(*) AS cantidad\nFROM estudiantes\nGROUP BY ciudad\n[[HUECO]];", "opciones": {"A": "WHERE COUNT(*) > 10", "B": "HAVING COUNT(*) > 10", "C": "WHERE cantidad > 10", "D": "ORDER BY COUNT(*) > 10"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'Las condiciones sobre agregados se filtran con HAVING, que se evalúa después de GROUP BY; WHERE filtra filas antes de agrupar.', $j${"A": "memoristico", "B": "analitico", "C": "memoristico", "D": "intuitivo"}$j$::jsonb, '5afda3204ad4051acb9f4cbbfd86b146f153f1c603ce136677c0253556ba4a60', true) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('SEM-04', 'PL-VF-01', 'programacion', 'recursion', 3, 'verdadero_falso_justificado', $j${"afirmacion": "Una función recursiva que no tiene caso base termina igual cuando el valor del parámetro llega a cero.", "opciones_justificacion": {"A": "Falso: sin caso base nada detiene las llamadas; en Python se agota la pila y se lanza RecursionError.", "B": "Verdadero: el intérprete detecta el cero y detiene automáticamente la recursión.", "C": "Falso: la función termina, pero siempre retorna None en lugar del resultado."}}$j$::jsonb, $j${"valor": false, "justificacion": "A"}$j$::jsonb, 'El caso base es la única condición de parada de una recursión; sin él las llamadas continúan hasta exceder el límite de recursión.', $j${"A": "analitico", "B": "intuitivo", "C": "parcial"}$j$::jsonb, 'bc3c61ce1560e226095b67cd50801ae5b3054cc92e252eb691352b23671f4cdd', true) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('SEM-05', 'PL-CP-01', 'actitud', 'aprendizaje_autonomo', 2, 'caso_practico', $j${"contexto": "En su primera semana de práctica le piden integrar una API de un servicio que nunca ha usado y que el equipo tampoco conoce. La entrega es en cinco días.", "enunciado": "¿Cuál es la mejor forma de empezar?", "opciones": {"A": "Decir que no conoce esa tecnología y pedir que la asignen a otra persona.", "B": "Leer la documentación oficial, hacer una prueba mínima y compartir con el equipo lo aprendido y las dudas.", "C": "Copiar el primer ejemplo que encuentre en internet y ajustarlo hasta que funcione, sin revisar la documentación.", "D": "Esperar a que el líder le explique paso a paso cómo hacerlo."}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'Investigar en fuentes oficiales, validar con una prueba pequeña y comunicar avances refleja aprendizaje autónomo y trabajo en equipo.', $j${"A": "evitativo", "B": "proactivo", "C": "ensayo_error", "D": "dependiente"}$j$::jsonb, '5c945a1f43f052c303ab213aecd4422fb0e39f42fe7670428060e597c5747380', true) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('SEM-06', 'PL-OM-01', 'logica', 'logica_proposicional', 1, 'opcion_multiple', $j${"enunciado": "Si la proposición p es falsa, ¿cuál es el valor de verdad de la implicación p → q, sin importar el valor de q?", "opciones": {"A": "Verdadero", "B": "Falso", "C": "Depende del valor de q", "D": "No está definido"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'Una implicación solo es falsa cuando el antecedente es verdadero y el consecuente falso; con antecedente falso siempre es verdadera.', $j${"A": "analitico", "B": "intuitivo", "C": "parcial", "D": "impulsivo"}$j$::jsonb, '5e27d821def16fa5304c05abded836fc7dbe1114583137bec54f6c9daa67dec8', true) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('SEM-07', 'PL-CS-01', 'programacion', 'poo', 2, 'codigo_salida', $j${"enunciado": "¿Qué imprime el siguiente código con clases en Python?", "lenguaje": "python", "codigo": "class Animal:\n    def sonido(self):\n        return \"...\"\n\nclass Perro(Animal):\n    def sonido(self):\n        return \"Guau\"\n\nmascotas = [Animal(), Perro()]\nprint(\" \".join(m.sonido() for m in mascotas))", "opciones": {"A": "... Guau", "B": "Guau Guau", "C": "... ...", "D": "Error"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'Cada objeto usa su propio método: Animal retorna ''...'' y Perro sobrescribe sonido() para retornar ''Guau''.', $j${"A": "analitico", "B": "confusion_herencia", "C": "confusion_herencia", "D": "memoristico"}$j$::jsonb, 'a07d2a42d5f50fb69f541b32b93dd57921cd7577a27866162fe79cdbd4c50d62', true) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('SEM-08', 'PL-CS-01', 'programacion', 'condicionales', 1, 'codigo_salida', $j${"enunciado": "¿Qué imprime el siguiente código?", "lenguaje": "python", "codigo": "edad = 17\nif edad >= 18:\n    print(\"Mayor\")\nelse:\n    print(\"Menor\")", "opciones": {"A": "Mayor", "B": "Menor", "C": "Mayor Menor", "D": "No imprime nada"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, '17 >= 18 es falso, así que se ejecuta solo el bloque else.', $j${"A": "impulsivo", "B": "analitico", "C": "lectura_superficial", "D": "lectura_superficial"}$j$::jsonb, 'aa6a0c3b21881f1b0d02aea9ef747cbe7a54dcb51abebdfd92dcdac6cbd2ece1', true) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('SEM-09', 'PL-CC-01', 'bases_de_datos', 'sql_select', 1, 'completar_codigo', $j${"enunciado": "Complete la consulta para obtener todas las columnas de la tabla estudiantes.", "lenguaje": "sql", "codigo": "SELECT [[HUECO]]\nFROM estudiantes;", "opciones": {"A": "*", "B": "ALL", "C": "TODO", "D": "%"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'El asterisco (*) en SELECT indica todas las columnas; % es un comodín de LIKE y ALL/TODO no aplican aquí.', $j${"A": "analitico", "B": "intuitivo", "C": "impulsivo", "D": "confusion_conceptos"}$j$::jsonb, '72b220ab4cdb9814588274cca1180fe5c68f6dfafacef47ca0ea8bd043db4e44', true) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('SEM-10', 'PL-OM-01', 'logica', 'razonamiento_deductivo', 2, 'opcion_multiple', $j${"enunciado": "Premisas: (1) Todos los aspirantes que aprueban la prueba pasan a entrevista. (2) Un aspirante no pasó a entrevista. ¿Qué se puede concluir de ese aspirante?", "opciones": {"A": "Que no aprobó la prueba", "B": "Que aprobó, pero no se presentó", "C": "Que no se puede concluir nada", "D": "Que sí aprobó la prueba"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'Si aprobar implica pasar a entrevista y no pasó, entonces no aprobó (modus tollens).', $j${"A": "analitico", "B": "intuitivo", "C": "parcial", "D": "impulsivo"}$j$::jsonb, '22a0d5cd8310674c426519ef36daac8bbabf4e17a1d41f5af953f1dac20dd1cc', true) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-001', 'PL-OM-01', 'logica', 'secuencias_patrones', 1, 'opcion_multiple', $j${"enunciado": "¿Cuál es el siguiente término de la serie 2, 4, 8, 16, ...?", "opciones": {"A": "24", "B": "32", "C": "20", "D": "30"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'Cada término es el doble del anterior (potencias de 2): 16 x 2 = 32.', null, '00316b77fdf782846c4e061167d032810cb4a1732cf9076ba47ef3f6700e7924', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-002', 'PL-OM-01', 'logica', 'logica_proposicional', 1, 'opcion_multiple', $j${"enunciado": "Si la proposición p es verdadera y q es falsa, ¿cuál es el valor de (p ∧ q) ∨ ¬q?", "opciones": {"A": "Verdadero", "B": "Falso", "C": "No se puede determinar", "D": "Solo es verdadero si p es falso"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'p ∧ q es falso porque q es falso, pero ¬q es verdadero; una disyunción con un término verdadero es verdadera.', null, '80b18d0dcb532340e1c784781c74b55405a923f406d54a8bb60cd90340f069d3', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-003', 'PL-OM-01', 'logica', 'conjuntos', 1, 'opcion_multiple', $j${"enunciado": "Dados los conjuntos A = {1, 2, 3, 4} y B = {3, 4, 5}, ¿cuál es la intersección A ∩ B?", "opciones": {"A": "{1, 2, 3, 4, 5}", "B": "{3, 4}", "C": "{1, 2}", "D": "{5}"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'La intersección contiene solo los elementos que están en ambos conjuntos: 3 y 4. La opción A es la unión.', null, '6a9034a419990c7eeb6c5d4e25d40ca7617ef3024d4f9501ae31b4ffd20e7d0b', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-004', 'PL-CS-01', 'logica', 'algoritmos_pseudocodigo', 1, 'codigo_salida', $j${"enunciado": "¿Qué muestra el siguiente pseudocódigo?", "lenguaje": "pseudocodigo", "codigo": "x <- 5\ny <- 3\nx <- x + y\ny <- x - y\nESCRIBIR x, y", "opciones": {"A": "8, 3", "B": "8, 5", "C": "5, 3", "D": "8, 8"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'x pasa a 8; luego y = 8 - 3 = 5. Las instrucciones se ejecutan en orden y cada asignación usa el valor más reciente.', null, '522985f49a97e22b1d95be3ec192b03795d7504956ac7e9d856da97163f60dea', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-005', 'PL-VF-01', 'logica', 'razonamiento_deductivo', 2, 'verdadero_falso_justificado', $j${"afirmacion": "Premisas: todos los practicantes saben Git; algunos que saben Git saben Docker. Se concluye que algunos practicantes saben Docker.", "opciones_justificacion": {"A": "Falso: quienes saben Docker podrían ser personas que saben Git pero no son practicantes; la conclusión no se deduce.", "B": "Verdadero: si todos los practicantes saben Git, comparten todas las características de quienes saben Git.", "C": "Falso: porque de las premisas se deduce que ningún practicante sabe Docker."}}$j$::jsonb, $j${"valor": false, "justificacion": "A"}$j$::jsonb, 'Es una falacia: ''algunos que saben Git'' no tiene por qué incluir practicantes. Las premisas no garantizan la conclusión.', null, 'eb18807f6548394de7f60c5b74e5a0c4233247d530250f0d7ad7d7d88a5ddd83', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-006', 'PL-OM-01', 'logica', 'logica_proposicional', 2, 'opcion_multiple', $j${"enunciado": "¿Cuál es la negación correcta de la proposición 'todos los servidores están activos'?", "opciones": {"A": "Ningún servidor está activo", "B": "Al menos un servidor no está activo", "C": "Todos los servidores están inactivos", "D": "Algunos servidores están activos"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'La negación de ''para todo x, P(x)'' es ''existe un x tal que no P(x)'': basta un servidor inactivo.', null, '78ec61c98c58050067322631294ac78a60599a9beed2475423f5b79987ac06d3', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-007', 'PL-CC-01', 'logica', 'algoritmos_pseudocodigo', 2, 'completar_codigo', $j${"enunciado": "Complete el algoritmo para que calcule la suma de los números de 1 hasta n.", "lenguaje": "pseudocodigo", "codigo": "suma <- 0\ni <- 1\nMIENTRAS i <= n HACER\n    suma <- suma + i\n    [[HUECO]]\nFIN MIENTRAS", "opciones": {"A": "i <- i + 1", "B": "suma <- suma + 1", "C": "i <- i - 1", "D": "n <- n + 1"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'El contador i debe avanzar en cada vuelta; de lo contrario el ciclo nunca termina (C y D) o no se suma lo pedido (B).', null, 'c8811fa6176c78d40517b388fb790102e807684141ac7783e4d2c23baba7a3a9', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-008', 'PL-CS-01', 'logica', 'secuencias_patrones', 2, 'codigo_salida', $j${"enunciado": "El siguiente código genera una secuencia conocida. ¿Qué imprime?", "lenguaje": "python", "codigo": "a, b = 0, 1\nfor _ in range(6):\n    a, b = b, a + b\nprint(a)", "opciones": {"A": "13", "B": "5", "C": "8", "D": "21"}}$j$::jsonb, $j${"opcion": "C"}$j$::jsonb, 'Es Fibonacci: tras 6 iteraciones a toma los valores 1, 1, 2, 3, 5, 8.', null, '89d6d89c176141d5655293cb582dba6c08215fc28375575c20cfa635c0fb679a', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-009', 'PL-OM-01', 'logica', 'razonamiento_deductivo', 3, 'opcion_multiple', $j${"enunciado": "Premisas: (1) Si el despliegue falla, se activa la alerta. (2) La alerta no se activó. ¿Qué conclusión es válida?", "opciones": {"A": "El despliegue no falló", "B": "El despliegue falló", "C": "No se puede concluir nada", "D": "La alerta está dañada"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'Es modus tollens: si P implica Q y Q es falso, entonces P es falso.', null, '5be5f5cb1b3d56d64436b11f4321dc9b8a5578ae16194c9138e6576bd0d71085', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-010', 'PL-VF-01', 'logica', 'logica_proposicional', 3, 'verdadero_falso_justificado', $j${"afirmacion": "La proposición p → q es lógicamente equivalente a ¬q → ¬p.", "opciones_justificacion": {"A": "Verdadero: es la contrapositiva; ambas son falsas únicamente cuando p es verdadero y q es falso.", "B": "Verdadero: porque la implicación es conmutativa y p → q equivale a q → p.", "C": "Falso: la equivalente es ¬p → ¬q, que es la inversa de la implicación."}}$j$::jsonb, $j${"valor": true, "justificacion": "A"}$j$::jsonb, 'La contrapositiva conserva la tabla de verdad. La recíproca (q → p) y la inversa (¬p → ¬q) no son equivalentes.', null, 'ebfded4803442f23504e39863ab7feeb68cf7ed71690397f31f96f3e80a8a9da', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-011', 'PL-CS-01', 'logica', 'algoritmos_pseudocodigo', 3, 'codigo_salida', $j${"enunciado": "¿Qué imprime este algoritmo implementado en Python?", "lenguaje": "python", "codigo": "def misterio(n):\n    pasos = 0\n    while n != 1:\n        if n % 2 == 0:\n            n = n // 2\n        else:\n            n = 3 * n + 1\n        pasos += 1\n    return pasos\n\nprint(misterio(6))", "opciones": {"A": "8", "B": "6", "C": "9", "D": "7"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'La secuencia es 6, 3, 10, 5, 16, 8, 4, 2, 1: ocho pasos hasta llegar a 1.', null, 'bc740ff6d7cfb3f7fdc839dceda3be2342c43bdea879cd80b243a6a5566cdad2', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-012', 'PL-OM-01', 'logica', 'conjuntos', 2, 'opcion_multiple', $j${"enunciado": "Usando unión de conjuntos: en un grupo de 40 aspirantes, 25 saben Python, 18 saben SQL y 10 saben ambos. ¿Cuántos no saben ninguno de los dos?", "opciones": {"A": "7", "B": "3", "C": "17", "D": "13"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, '|Python ∪ SQL| = 25 + 18 - 10 = 33; los que no saben ninguno son 40 - 33 = 7.', null, '072b03f48b683f2f4763bcc65cc642b668bc3ffd2ef1373929adee86a9ec19aa', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-013', 'PL-OM-01', 'programacion', 'variables_tipos', 1, 'opcion_multiple', $j${"enunciado": "En Python 3, ¿qué tipo de dato retorna la expresión type(3 / 2)?", "opciones": {"A": "int", "B": "float", "C": "str", "D": "bool"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'En Python 3 el operador / siempre produce un float (1.5). La división entera es //.', null, '097304e4c0dc3988567f879c476aca1b7a400f6e2df462895a2d6ccb3666ed59', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-014', 'PL-CS-01', 'programacion', 'variables_tipos', 1, 'codigo_salida', $j${"enunciado": "Observe el tipo de cada variable. ¿Qué imprime el código?", "lenguaje": "python", "codigo": "x = \"5\"\ny = 2\nprint(x * y)", "opciones": {"A": "10", "B": "55", "C": "Error de tipos", "D": "7"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'x es una cadena; multiplicar una cadena por un entero la repite: ''5'' * 2 = ''55''.', null, '0bb3d277d4fe9ff6d63d729e0f49f1591253e4f6e4aa0e23f21e21d5012ff08a', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-015', 'PL-CS-01', 'programacion', 'condicionales', 2, 'codigo_salida', $j${"enunciado": "¿Qué imprime el siguiente código?", "lenguaje": "python", "codigo": "nota = 3.0\nif nota >= 4.0:\n    print(\"Excelente\")\nelif nota >= 3.0:\n    print(\"Aprobado\")\nelse:\n    print(\"Reprobado\")", "opciones": {"A": "Excelente", "B": "Aprobado", "C": "Reprobado", "D": "No imprime nada"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'La primera condición es falsa y la del elif es verdadera (3.0 >= 3.0); solo se ejecuta ese bloque.', null, 'c77b0b60729d8d0686553abd2a968211c748d25b10795e779a0f5ea634ea5b07', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-016', 'PL-OM-01', 'programacion', 'ciclos', 1, 'opcion_multiple', $j${"enunciado": "¿Cuál ciclo imprime los números del 10 al 1 en orden descendente?", "opciones": {"A": "for i in range(10, 0, -1): print(i)", "B": "for i in range(10, 1): print(i)", "C": "for i in range(1, 10, -1): print(i)", "D": "for i in range(10, -1, -1): print(i)"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'range(10, 0, -1) va de 10 hasta 1 (el 0 se excluye). D incluye el 0; B y C no generan ningún valor.', null, '1cb324c3ea0478052a3eea0d20e8f1f7cc857b6d8af33d891098ef331f0de534', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-017', 'PL-CC-01', 'programacion', 'funciones', 1, 'completar_codigo', $j${"enunciado": "Complete la función para que retorne el área de un rectángulo.", "lenguaje": "python", "codigo": "def area_rectangulo(base, altura):\n    [[HUECO]]\n\nprint(area_rectangulo(4, 5))  # debe imprimir 20", "opciones": {"A": "print(base * altura)", "B": "return base * altura", "C": "return base + altura", "D": "base * altura"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'Una función entrega su resultado con return. Con print (A) o sin return (D) la función retorna None.', null, 'f063888bf2b83846b97813f7ad6c55c3f8d60c2c762b39f87774a3de5d7c8361', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-018', 'PL-CS-01', 'programacion', 'listas_estructuras', 2, 'codigo_salida', $j${"enunciado": "¿Qué imprime el siguiente código sobre listas?", "lenguaje": "python", "codigo": "a = [1, 2, 3]\nb = a\nb.append(4)\nprint(len(a))", "opciones": {"A": "3", "B": "4", "C": "Error", "D": "7"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'b = a no copia la lista: ambas variables apuntan al mismo objeto, por lo que append también afecta a a.', null, '60c491f1573cec7a8b162cf58dd8285418e4c0599c356025fb9f10afe0b16862', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-019', 'PL-CS-01', 'programacion', 'funciones', 2, 'codigo_salida', $j${"enunciado": "¿Qué imprime el código? Fíjese en el parámetro por defecto.", "lenguaje": "python", "codigo": "def f(x, y=2):\n    return x ** y\n\nprint(f(3) + f(2, 3))", "opciones": {"A": "17", "B": "15", "C": "13", "D": "12"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'f(3) usa y=2: 3**2 = 9. f(2, 3) = 2**3 = 8. La suma es 17.', null, 'bf9547aabe905a7f978a1b14bc2661607bb884272e74cff6b1b29fd860e46bcc', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-020', 'PL-CC-01', 'programacion', 'listas_estructuras', 2, 'completar_codigo', $j${"enunciado": "Complete el ciclo para recorrer el diccionario obteniendo cada producto con su cantidad.", "lenguaje": "python", "codigo": "inventario = {\"teclado\": 5, \"mouse\": 8}\nfor producto, cantidad in [[HUECO]]:\n    print(producto, cantidad)", "opciones": {"A": "inventario.items()", "B": "inventario.keys()", "C": "inventario", "D": "inventario.values()"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'items() devuelve pares (clave, valor) que se desempaquetan en dos variables; keys() y values() solo entregan una parte.', null, '55fe3547f963b1e33df184d4adc0ade4c1be3a027b55a68c4af0c4803ba51b3d', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-021', 'PL-OM-01', 'programacion', 'poo', 2, 'opcion_multiple', $j${"enunciado": "En programación orientada a objetos con Python, ¿qué representa self dentro de un método de una clase?", "opciones": {"A": "La clase misma", "B": "La instancia (objeto) sobre la que se invoca el método", "C": "Una variable global del módulo", "D": "El método de la clase padre"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'self es la referencia al objeto concreto que recibe la llamada; permite acceder a sus atributos.', null, '1c010de59a2c04ae7aeda3cf0e02b33cccc0f390c1a62380dd1925a996af3f67', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-022', 'PL-CS-01', 'programacion', 'poo', 2, 'codigo_salida', $j${"enunciado": "¿Qué imprime el siguiente código con una clase?", "lenguaje": "python", "codigo": "class Contador:\n    def __init__(self):\n        self.valor = 0\n\n    def sumar(self):\n        self.valor += 1\n        return self\n\nc = Contador()\nc.sumar().sumar().sumar()\nprint(c.valor)", "opciones": {"A": "1", "B": "3", "C": "0", "D": "Error"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'sumar retorna el mismo objeto, por eso las llamadas se encadenan y el atributo valor se incrementa tres veces.', null, '7ebd2a54f5fb9d8d5cc1d5d3d7a98fa2cff0f1a0155f6e800e0c06a83c287c9f', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-023', 'PL-VF-01', 'programacion', 'variables_tipos', 2, 'verdadero_falso_justificado', $j${"afirmacion": "En Python, la expresión 0 or 'hola' produce el valor booleano True.", "opciones_justificacion": {"A": "Falso: or retorna el primer operando que sea verdadero, en este caso la cadena 'hola', no el booleano True.", "B": "Verdadero: el operador or siempre retorna un valor booleano.", "C": "Falso: la expresión lanza un error porque mezcla un entero con una cadena."}}$j$::jsonb, $j${"valor": false, "justificacion": "A"}$j$::jsonb, 'and y or en Python retornan uno de sus operandos (evaluación en cortocircuito), no necesariamente True o False.', null, '3e55910b79c5ebf91bdb6763f00056a2c67e428392e666f872055a34d76401ba', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-024', 'PL-CS-01', 'programacion', 'recursion', 3, 'codigo_salida', $j${"enunciado": "La siguiente función es recursiva. ¿Qué imprime?", "lenguaje": "python", "codigo": "def suma_digitos(n):\n    if n < 10:\n        return n\n    return n % 10 + suma_digitos(n // 10)\n\nprint(suma_digitos(4072))", "opciones": {"A": "13", "B": "4072", "C": "11", "D": "7"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'Separa el último dígito (n % 10) y se llama con el resto (n // 10): 2 + 7 + 0 + 4 = 13.', null, 'dad370110374715af42718116d1caa51073a91f88a6c2f845c2f8a9b8dd6bff7', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-025', 'PL-CS-01', 'programacion', 'listas_estructuras', 3, 'codigo_salida', $j${"enunciado": "¿Qué imprime este código que usa comprensión de listas?", "lenguaje": "python", "codigo": "matriz = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]\nresultado = [fila[i] for i, fila in enumerate(matriz)]\nprint(sum(resultado))", "opciones": {"A": "15", "B": "12", "C": "45", "D": "6"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'Toma el elemento i de la fila i: la diagonal principal 1, 5 y 9, que suma 15.', null, '640b36375ac0ff9d138172430629fbd7f1d3c910c2a5ad6dd72f328d9fd7d120', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-026', 'PL-CC-01', 'programacion', 'recursion', 3, 'completar_codigo', $j${"enunciado": "Complete el caso base para que la función factorial funcione con cualquier n >= 0, incluido el 0.", "lenguaje": "python", "codigo": "def factorial(n):\n    if [[HUECO]]:\n        return 1\n    return n * factorial(n - 1)", "opciones": {"A": "n == 0", "B": "n == 1", "C": "n > 0", "D": "n < 0"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'Con n == 0 se cubre 0! = 1. Con n == 1, factorial(0) nunca alcanza el caso base y la recursión no termina.', null, 'd1ea28f91b62eff4e513653f9b22957fdc193881aca51c6ffc24fba5ae3a90b6', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-027', 'PL-OM-01', 'programacion', 'poo', 3, 'opcion_multiple', $j${"enunciado": "¿Qué concepto de POO se aplica cuando una clase hija redefine un método heredado para que se comporte distinto?", "opciones": {"A": "Encapsulamiento", "B": "Sobrescritura de métodos (polimorfismo)", "C": "Abstracción de datos", "D": "Composición"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'Sobrescribir (override) un método heredado permite que objetos de distintas clases respondan distinto al mismo mensaje: polimorfismo.', null, '68e947276f89827d804a7f219ca653c01c9b1ebe971cdd83432c9a056463c0c5', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-028', 'PL-VF-01', 'programacion', 'funciones', 3, 'verdadero_falso_justificado', $j${"afirmacion": "En Python, usar una lista vacía como valor por defecto de un parámetro (def f(x=[])) crea una lista nueva en cada llamada a la función.", "opciones_justificacion": {"A": "Falso: el valor por defecto se evalúa una sola vez al definir la función, así que la misma lista se comparte entre llamadas.", "B": "Verdadero: Python copia los parámetros por defecto antes de cada llamada.", "C": "Falso: Python no permite usar listas como valor por defecto de un parámetro."}}$j$::jsonb, $j${"valor": false, "justificacion": "A"}$j$::jsonb, 'Es un error clásico: se recomienda usar x=None y crear la lista dentro de la función.', null, 'f441aa23210049ae5329998fd08cf7d93727457ad9111d625252306e966e4b20', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-029', 'PL-OM-01', 'bases_de_datos', 'modelo_relacional', 1, 'opcion_multiple', $j${"enunciado": "En el modelo relacional, ¿qué representa una fila de una tabla?", "opciones": {"A": "Un atributo de la entidad", "B": "Un registro, es decir, una instancia de la entidad", "C": "El tipo de dato de una columna", "D": "Una relación entre dos tablas"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'Cada fila (tupla) es un registro concreto; las columnas son los atributos.', null, '5f8a7778aad1ca104e981c5485e7c3884b2a4e036317a6fa102cc4d80299ecc2', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-030', 'PL-OM-01', 'bases_de_datos', 'claves', 1, 'opcion_multiple', $j${"enunciado": "¿Cuál es la función principal de una clave primaria en una tabla?", "opciones": {"A": "Identificar de forma única cada registro", "B": "Acelerar todas las consultas de la base", "C": "Relacionar la tabla con otra tabla", "D": "Cifrar los datos sensibles"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'La clave primaria garantiza unicidad y no nulidad. Relacionar tablas es tarea de la clave foránea.', null, '2db5e3d4127f3a9634c418b5445a7bf4e6dc259e3c0935369dfc220ea85d6f13', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-031', 'PL-CC-01', 'bases_de_datos', 'sql_select', 1, 'completar_codigo', $j${"enunciado": "Complete la consulta para listar solo los aspirantes de quinto semestre.", "lenguaje": "sql", "codigo": "SELECT nombre, correo\nFROM aspirantes\n[[HUECO]] semestre = 5;", "opciones": {"A": "WHERE", "B": "HAVING", "C": "WHEN", "D": "IF"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'WHERE filtra filas según una condición. HAVING filtra grupos; WHEN e IF no son cláusulas de SELECT.', null, 'a8a44a4ef6a2e3ca81e24234128a245d13eb699d105f43a988175711034326c7', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-032', 'PL-CS-01', 'bases_de_datos', 'sql_select', 1, 'codigo_salida', $j${"enunciado": "La tabla cursos(id, nombre, creditos) tiene las filas (1,'Lógica',3), (2,'Redes',4) y (3,'Bases',4). ¿Cuántas filas retorna la consulta?", "lenguaje": "sql", "codigo": "SELECT nombre\nFROM cursos\nWHERE creditos >= 4;", "opciones": {"A": "1", "B": "2", "C": "3", "D": "0"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'Solo ''Redes'' y ''Bases'' tienen 4 créditos o más; >= incluye el 4.', null, '067c6b01d879d985e5c948e0b0b23f1ed26e626f6dc3fa7819bac3fc5dd1f696', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-033', 'PL-VF-01', 'bases_de_datos', 'claves', 1, 'verdadero_falso_justificado', $j${"afirmacion": "Una clave foránea puede contener valores repetidos dentro de su propia tabla.", "opciones_justificacion": {"A": "Verdadero: varios registros pueden referenciar al mismo registro padre, por ejemplo muchos pedidos de un mismo cliente.", "B": "Falso: toda clave, primaria o foránea, es única por definición.", "C": "Verdadero: porque la base de datos no valida las claves foráneas."}}$j$::jsonb, $j${"valor": true, "justificacion": "A"}$j$::jsonb, 'La clave foránea modela relaciones uno a muchos; lo que se exige es que el valor exista en la tabla referenciada.', null, 'b69dbf2891a59291d1d37018beaf2cded94400c11e613c2d231a1b17e4e941a2', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-034', 'PL-CS-01', 'bases_de_datos', 'sql_agregacion', 2, 'codigo_salida', $j${"enunciado": "La tabla ventas(producto, monto) tiene las filas ('A',100), ('B',50), ('A',30), ('C',70), ('B',20). ¿Cuántas filas devuelve la consulta?", "lenguaje": "sql", "codigo": "SELECT producto, SUM(monto)\nFROM ventas\nGROUP BY producto\nHAVING SUM(monto) > 70;", "opciones": {"A": "1", "B": "2", "C": "3", "D": "5"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'Las sumas son A=130, B=70 y C=70. Solo A supera 70 (la condición es estrictamente mayor).', null, '177c750ffb0eb764f45aeded62dd51fb606e4095155ac993c0d6fcebba4dc38e', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-035', 'PL-CC-01', 'bases_de_datos', 'sql_join', 2, 'completar_codigo', $j${"enunciado": "Complete la consulta para listar TODOS los estudiantes, incluso los que no tienen programa asignado.", "lenguaje": "sql", "codigo": "SELECT e.nombre, p.nombre AS programa\nFROM estudiantes e\n[[HUECO]] programas p ON e.programa_id = p.id;", "opciones": {"A": "INNER JOIN", "B": "LEFT JOIN", "C": "RIGHT JOIN", "D": "CROSS JOIN"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'LEFT JOIN conserva todas las filas de la tabla izquierda (estudiantes) y pone NULL donde no hay programa.', null, '3a73fab05d8692b51c2ae0ecd387901d0d9716910c7adc43a283f95e91a97cb5', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-036', 'PL-OM-01', 'bases_de_datos', 'normalizacion', 2, 'opcion_multiple', $j${"enunciado": "Una tabla pedidos(pedido_id PK, cliente_id, nombre_cliente, fecha) guarda nombre_cliente, que depende de cliente_id y no directamente de pedido_id. ¿Qué forma normal se viola?", "opciones": {"A": "Primera forma normal (1FN)", "B": "Segunda forma normal (2FN)", "C": "Tercera forma normal (3FN)", "D": "No viola ninguna"}}$j$::jsonb, $j${"opcion": "C"}$j$::jsonb, 'Hay una dependencia transitiva (pedido_id → cliente_id → nombre_cliente), lo que viola 3FN. 2FN no aplica porque la clave es simple.', null, '375c8f389285b896116e5c601745c95d8f75a6b9a702d84b9d0b4dc16943f160', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-037', 'PL-OM-01', 'bases_de_datos', 'sql_agregacion', 2, 'opcion_multiple', $j${"enunciado": "¿Qué diferencia hay entre COUNT(*) y COUNT(telefono) en una consulta SQL?", "opciones": {"A": "Ninguna, son equivalentes", "B": "COUNT(telefono) no cuenta las filas donde telefono es NULL", "C": "COUNT(*) ignora las filas que tienen algún NULL", "D": "COUNT(telefono) solo cuenta valores distintos"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'COUNT(*) cuenta todas las filas; COUNT(columna) ignora los NULL. Para valores distintos se usa COUNT(DISTINCT columna).', null, '2d7897004fe39ca51328da02e767d50f0f008af5a93d921a7015e5a19404365d', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-038', 'PL-VF-01', 'bases_de_datos', 'normalizacion', 2, 'verdadero_falso_justificado', $j${"afirmacion": "Normalizar una base de datos hasta la tercera forma normal (3FN) reduce la redundancia de datos.", "opciones_justificacion": {"A": "Verdadero: separa los datos en tablas según sus dependencias, de modo que cada hecho se almacena una sola vez.", "B": "Verdadero: porque elimina la necesidad de usar claves foráneas.", "C": "Falso: la normalización solo sirve para mejorar la velocidad de lectura."}}$j$::jsonb, $j${"valor": true, "justificacion": "A"}$j$::jsonb, 'La normalización elimina redundancias y anomalías de actualización; de hecho aumenta el uso de claves foráneas.', null, '0432b7f54c6e6b42c7d8f236b14c66fd5f70b0f9dcd23eae5ac9f1d6b544c5f5', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-039', 'PL-CS-01', 'bases_de_datos', 'sql_join', 3, 'codigo_salida', $j${"enunciado": "Tablas: docentes(id, nombre) con (1,'D1'), (2,'D2'), (3,'D3'); cursos(id, docente_id) con (10,1), (11,1), (12,2). ¿Cuántas filas devuelve la consulta?", "lenguaje": "sql", "codigo": "SELECT d.nombre, COUNT(c.id)\nFROM docentes d\nLEFT JOIN cursos c ON c.docente_id = d.id\nGROUP BY d.nombre;", "opciones": {"A": "2", "B": "3", "C": "4", "D": "6"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'El LEFT JOIN conserva a D3 aunque no tenga cursos; al agrupar por docente queda una fila por cada uno: D1=2, D2=1, D3=0.', null, 'eff66158a1d7db68f1c9097bc17d50966e9f87322f308bf267d3e6d408953ec9', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-040', 'PL-CC-01', 'bases_de_datos', 'sql_agregacion', 3, 'completar_codigo', $j${"enunciado": "Complete para mostrar solo los programas cuya media sea superior a 4.0, ordenados de mayor a menor media.", "lenguaje": "sql", "codigo": "SELECT programa, AVG(promedio) AS media\nFROM estudiantes\nWHERE semestre >= 3\nGROUP BY programa\n[[HUECO]];", "opciones": {"A": "HAVING AVG(promedio) > 4.0 ORDER BY media DESC", "B": "WHERE AVG(promedio) > 4.0 ORDER BY media DESC", "C": "HAVING AVG(promedio) > 4.0 ORDER BY media ASC", "D": "ORDER BY media DESC HAVING AVG(promedio) > 4.0"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'El filtro sobre un agregado va en HAVING, y ORDER BY siempre va al final. B usa WHERE con agregado, C ordena al revés y D invierte el orden de las cláusulas.', null, 'b58e16f665db926cb8fc9a9cd755f74b8f173cecded7c9b49339aad1bf8a8a96', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-041', 'PL-CP-01', 'actitud', 'trabajo_equipo', 1, 'caso_practico', $j${"contexto": "Su equipo de tres practicantes debe entregar un prototipo en dos semanas. Un compañero casi no ha aportado y el resto del grupo está molesto.", "enunciado": "¿Qué es lo más adecuado hacer?", "opciones": {"A": "Hacer su parte y también la del compañero, sin decir nada.", "B": "Hablar en privado con el compañero, preguntar qué le impide avanzar y acordar tareas concretas.", "C": "Quejarse de inmediato con el jefe del área sin hablar antes con el compañero.", "D": "Sacarlo del grupo de mensajes del proyecto para que entienda."}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'Abordar el conflicto directamente y con respeto, buscando la causa y acuerdos concretos, es la base del trabajo en equipo.', null, '577dfb7b13002f077d54d25fca0a1f2cda1c566c4155b49f35ea372ee8879224', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-042', 'PL-CP-01', 'actitud', 'etica_profesional', 2, 'caso_practico', $j${"contexto": "Mientras corrige un error en el sistema académico, nota que tiene acceso a calificaciones y datos personales de estudiantes, aunque su tarea no lo requiere. Un compañero le pide consultar la nota de un amigo.", "enunciado": "¿Qué hace usted?", "opciones": {"A": "Consultar la nota solo esta vez, ya que no va a modificar nada.", "B": "Negarse, explicar que esos datos son confidenciales y reportar al líder que su acceso es mayor al necesario.", "C": "Prestarle sus credenciales para que él mismo la consulte.", "D": "Ignorar la petición y no mencionar el acceso excesivo a nadie."}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'Proteger la privacidad de los datos y reportar permisos excesivos (principio de mínimo privilegio) es la conducta ética esperada.', null, 'e568eccb3b70e57981ab6c7b7ae964b9823ddba941f883597627c5ca2f2409f9', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-043', 'PL-OM-01', 'actitud', 'comunicacion', 1, 'opcion_multiple', $j${"enunciado": "Debe explicar a un usuario administrativo, sin formación técnica, por qué el sistema estuvo caído. ¿Qué es lo más adecuado?", "opciones": {"A": "Usar términos técnicos precisos para demostrar dominio del tema", "B": "Explicar con lenguaje sencillo qué pasó, cómo le afectó y qué se hizo", "C": "Decirle que es un tema técnico que no va a entender", "D": "Enviarle por correo el log completo del servidor"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'Comunicar es adaptar el mensaje al receptor: claridad, impacto y acciones tomadas.', null, '2bcd03e746248e366a5a7a761f862094c0404229d6273b6933d800b3ce9366ff', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-044', 'PL-VF-01', 'actitud', 'aprendizaje_autonomo', 1, 'verdadero_falso_justificado', $j${"afirmacion": "Cuando se desconoce una tecnología, lo más profesional es esperar una capacitación formal antes de empezar a usarla.", "opciones_justificacion": {"A": "Falso: se espera iniciativa para investigar en la documentación oficial y hacer pruebas, pidiendo apoyo cuando haga falta.", "B": "Verdadero: usar una tecnología sin capacitación formal siempre genera errores graves.", "C": "Falso: porque las capacitaciones formales nunca resultan útiles."}}$j$::jsonb, $j${"valor": false, "justificacion": "A"}$j$::jsonb, 'En innovación las tecnologías cambian rápido; el aprendizaje autónomo con fuentes confiables es una competencia clave.', null, 'b7babeb5ecea5629ab5579de1549fae15f308b220a834a930584cb54b20b3db7', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-045', 'PL-CP-01', 'actitud', 'manejo_presion', 2, 'caso_practico', $j${"contexto": "Bajo presión de tiempo, faltan dos horas para una demostración ante directivos y usted descubre un error que hace fallar una función secundaria del prototipo.", "enunciado": "¿Qué hace usted en esta situación?", "opciones": {"A": "Intentar reescribir todo el módulo antes de la demostración.", "B": "Ocultar temporalmente la función, preparar la demo con lo estable y avisar al líder del error y del plan para corregirlo.", "C": "Cancelar la demostración sin consultar a nadie.", "D": "Presentar sin decir nada y esperar que nadie use esa función."}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'Bajo presión se prioriza lo estable, se reduce el riesgo y se comunica con transparencia.', null, 'de77bf12c9c833cb0172a4d2ae3fb43829f4aa2ddf69204abfda1a90a537c319', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-046', 'PL-OM-01', 'actitud', 'aprendizaje_autonomo', 2, 'opcion_multiple', $j${"enunciado": "Tras investigar durante dos horas, no logra resolver un error de configuración. ¿Qué hace?", "opciones": {"A": "Seguir solo hasta resolverlo, sin importar cuánto tarde", "B": "Documentar lo que ya intentó y pedir ayuda al equipo con una pregunta concreta", "C": "Abandonar la tarea y pasar a otra sin avisar", "D": "Copiar la configuración de otro proyecto sin entenderla"}}$j$::jsonb, $j${"opcion": "B"}$j$::jsonb, 'Saber cuándo pedir ayuda, mostrando lo ya intentado, ahorra tiempo al equipo y demuestra autonomía responsable.', null, '13d31adbb3b192f93022a3c86fa373ef882567d17c604b8bb6a0fa303644b812', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-047', 'PL-CP-01', 'actitud', 'etica_profesional', 3, 'caso_practico', $j${"contexto": "Para terminar a tiempo, encuentra en un repositorio público una librería que resuelve exactamente lo que necesita, pero su licencia prohíbe el uso comercial y el sistema se ofrecerá a otras instituciones.", "enunciado": "¿Cuál es la decisión correcta?", "opciones": {"A": "Usarla y cambiar los nombres de las funciones para que no se note.", "B": "Usarla temporalmente y reemplazarla cuando haya tiempo.", "C": "Informar al líder la restricción de la licencia y proponer alternativas con licencia compatible (MIT, Apache) o desarrollo propio.", "D": "Usarla, porque si está publicada cualquiera puede usarla."}}$j$::jsonb, $j${"opcion": "C"}$j$::jsonb, 'Que un código sea público no significa que su uso sea libre; respetar licencias es una obligación legal y ética.', null, 'e46f10d4268ff6f150a9e317564000a93e7b9b4abf612c3a5f57244c879ac096', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-048', 'PL-VF-01', 'actitud', 'trabajo_equipo', 2, 'verdadero_falso_justificado', $j${"afirmacion": "En una revisión de código (code review), señalar errores en el código de un compañero es una falta de respeto hacia su trabajo.", "opciones_justificacion": {"A": "Falso: la revisión busca mejorar la calidad del producto; hecha con respeto y argumentos es una práctica colaborativa.", "B": "Verdadero: cada desarrollador es el único responsable de su propio código.", "C": "Falso: porque en la revisión solo se revisa el estilo, nunca la lógica."}}$j$::jsonb, $j${"valor": false, "justificacion": "A"}$j$::jsonb, 'La revisión de código es una práctica estándar de equipos profesionales para compartir conocimiento y detectar errores temprano.', null, '172b162443c0bfb65c162192fcabbb45aa145ea313322de767761c5a5ba37884', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-049', 'PL-CP-01', 'actitud', 'comunicacion', 3, 'caso_practico', $j${"contexto": "Un cliente interno pide agregar una funcionalidad 'pequeña' a una semana de la entrega. Usted estima que tomaría tres días y pondría en riesgo las pruebas.", "enunciado": "¿Cómo responde?", "opciones": {"A": "Aceptar sin comentar nada para mantener la buena relación con el cliente.", "B": "Rechazar la solicitud de forma tajante.", "C": "Explicar al cliente el impacto en tiempo y riesgo, y proponer con el líder incluirla en una versión siguiente o cambiarla por otra prioridad.", "D": "Implementarla trabajando de noche y sin pruebas."}}$j$::jsonb, $j${"opcion": "C"}$j$::jsonb, 'Gestionar el alcance implica comunicar impacto con datos y negociar alternativas, sin comprometer la calidad.', null, 'aba4e2d6d0bdf2ff0d23e6e5bc00acac39068da8987457e9f422fd4d5d40807d', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;
insert into public.banco_preguntas_fijo (codigo, id_plantilla, area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, rasgos_opciones, hash, es_semilla) values ('BF-050', 'PL-OM-01', 'actitud', 'manejo_presion', 3, 'opcion_multiple', $j${"enunciado": "Según su prioridad, ordene estas tareas: (1) un error que impide a todos los usuarios ingresar al sistema, (2) un reporte solicitado para la próxima semana, (3) mejorar el diseño de un botón.", "opciones": {"A": "1, 2, 3", "B": "3, 2, 1", "C": "2, 1, 3", "D": "1, 3, 2"}}$j$::jsonb, $j${"opcion": "A"}$j$::jsonb, 'Primero lo urgente e importante (bloquea a todos), luego lo importante con fecha y al final lo cosmético.', null, 'ca9869b64364b6dd17d8e181a2644604cc4365bc43fc81955dc902584bf2374d', false) on conflict (codigo) do update set contenido = excluded.contenido, respuesta_correcta = excluded.respuesta_correcta, explicacion = excluded.explicacion, rasgos_opciones = excluded.rasgos_opciones, hash = excluded.hash, nivel = excluded.nivel, tema = excluded.tema;

-- Semillas por carrera (se reemplazan completas para reflejar el JSON)
delete from public.semillas_carrera;
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'ingenieria_sistemas', 1, id from public.banco_preguntas_fijo where codigo = 'SEM-01';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'ingenieria_sistemas', 2, id from public.banco_preguntas_fijo where codigo = 'SEM-02';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'ingenieria_sistemas', 3, id from public.banco_preguntas_fijo where codigo = 'SEM-03';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'ingenieria_sistemas', 4, id from public.banco_preguntas_fijo where codigo = 'SEM-04';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'ingenieria_sistemas', 5, id from public.banco_preguntas_fijo where codigo = 'SEM-05';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'ingenieria_software', 1, id from public.banco_preguntas_fijo where codigo = 'SEM-06';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'ingenieria_software', 2, id from public.banco_preguntas_fijo where codigo = 'SEM-02';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'ingenieria_software', 3, id from public.banco_preguntas_fijo where codigo = 'SEM-07';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'ingenieria_software', 4, id from public.banco_preguntas_fijo where codigo = 'SEM-04';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'ingenieria_software', 5, id from public.banco_preguntas_fijo where codigo = 'SEM-05';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'tecnologia_desarrollo', 1, id from public.banco_preguntas_fijo where codigo = 'SEM-01';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'tecnologia_desarrollo', 2, id from public.banco_preguntas_fijo where codigo = 'SEM-08';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'tecnologia_desarrollo', 3, id from public.banco_preguntas_fijo where codigo = 'SEM-09';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'tecnologia_desarrollo', 4, id from public.banco_preguntas_fijo where codigo = 'SEM-02';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'tecnologia_desarrollo', 5, id from public.banco_preguntas_fijo where codigo = 'SEM-05';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'otra_afin', 1, id from public.banco_preguntas_fijo where codigo = 'SEM-01';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'otra_afin', 2, id from public.banco_preguntas_fijo where codigo = 'SEM-08';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'otra_afin', 3, id from public.banco_preguntas_fijo where codigo = 'SEM-09';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'otra_afin', 4, id from public.banco_preguntas_fijo where codigo = 'SEM-10';
insert into public.semillas_carrera (carrera_id, orden, banco_id) select 'otra_afin', 5, id from public.banco_preguntas_fijo where codigo = 'SEM-05';

commit;

