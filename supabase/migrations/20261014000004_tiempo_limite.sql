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
