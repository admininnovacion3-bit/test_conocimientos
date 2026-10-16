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
