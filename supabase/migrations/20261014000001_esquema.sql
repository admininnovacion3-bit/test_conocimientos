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
