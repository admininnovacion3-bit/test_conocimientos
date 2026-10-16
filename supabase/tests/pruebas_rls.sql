-- =====================================================================
-- PRUEBAS DE RLS (evidencia para la sustentación)
-- Ejecutar en el SQL Editor de un proyecto de PRUEBAS (o `supabase db reset` local)
-- DESPUÉS de las migraciones y del seed. Todo corre dentro de una transacción
-- que termina en ROLLBACK: no deja datos. Usuarios 100% ficticios.
-- =====================================================================
begin;

-- 1) Usuarios ficticios (el trigger los crea como aspirantes).
--    El aspirante es ANÓNIMO, igual que en la app móvil: sin email ni contraseña.
insert into auth.users (id, email, raw_user_meta_data, aud, role, is_anonymous)
values ('00000000-0000-0000-0000-0000000000a1', null, '{"nombre_completo":"Aspirante Prueba"}', 'authenticated', 'authenticated', true);
insert into auth.users (id, email, raw_user_meta_data, aud, role)
values
       ('00000000-0000-0000-0000-0000000000d1', 'docente.prueba@ejemplo.test',   '{"nombre_completo":"Docente Prueba"}',   'authenticated', 'authenticated');
update public.usuarios set rol = 'docente' where id = '00000000-0000-0000-0000-0000000000d1';

-- 2) Una evaluación con una pregunta semilla asignada y su fila de resultados
insert into public.evaluaciones (id, aspirante_id, carrera_id)
values ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a1', 'ingenieria_software');
insert into public.resultados (evaluacion_id, aspirante_id, puntaje_final)
values ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a1', 88);
insert into public.preguntas_generadas (id, evaluacion_id, aspirante_id, orden, origen, id_plantilla, banco_id,
                                        area, tema, nivel, tipo, contenido, respuesta_correcta, explicacion, hash)
select '00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1',
       '00000000-0000-0000-0000-0000000000a1', 1, 'semilla', b.id_plantilla, b.id,
       b.area, b.tema, b.nivel, b.tipo, b.contenido, b.respuesta_correcta, b.explicacion, b.hash
from public.banco_preguntas_fijo b where b.codigo = 'SEM-01';

-- 3) Actuar como el ASPIRANTE
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

do $$
begin
  if (select count(*) from public.resultados) <> 0 then
    raise exception 'FALLO: el aspirante puede leer resultados';
  end if;
  if (select count(*) from public.preguntas_generadas) <> 0 then
    raise exception 'FALLO: el aspirante puede leer preguntas con respuesta correcta';
  end if;
  if (select count(*) from public.alertas) <> 0 then
    raise exception 'FALLO: el aspirante puede leer alertas';
  end if;
  if (select count(*) from public.banco_preguntas_fijo) <> 0 then
    raise exception 'FALLO: el aspirante puede leer el banco fijo';
  end if;
  if (select count(*) from public.v_preguntas_aspirante) <> 1 then
    raise exception 'FALLO: el aspirante no ve su pregunta asignada';
  end if;
  if exists (select 1 from information_schema.columns
             where table_name = 'v_preguntas_aspirante' and column_name in ('respuesta_correcta', 'nivel', 'tema')) then
    raise exception 'FALLO: la vista expone columnas sensibles';
  end if;
  if (select count(*) from public.carreras) = 0 then
    raise exception 'FALLO: el aspirante no puede ver la lista de carreras';
  end if;
  if (select count(*) from public.semillas_carrera) <> 0 then
    raise exception 'FALLO: el aspirante puede ver qué semillas tiene cada carrera';
  end if;
  raise notice 'OK aspirante: no ve resultados, alertas, banco ni respuestas correctas; sí ve su pregunta y las carreras';
end $$;

-- 3b) El aspirante puede INSERTAR su respuesta, pero no leerla
insert into public.respuestas (pregunta_id, respuesta, tiempo_ms)
values ('00000000-0000-0000-0000-0000000000f1', '{"opcion":"A"}', 12000);
do $$
begin
  if (select count(*) from public.respuestas) <> 0 then
    raise exception 'FALLO: el aspirante puede leer respuestas (y su es_correcta)';
  end if;
  raise notice 'OK aspirante: insertó su respuesta y no puede leerla';
end $$;

-- 3c) Intento de escalar privilegios
update public.usuarios set rol = 'docente' where id = auth.uid();
do $$
begin
  if (select rol from public.usuarios where id = auth.uid()) <> 'aspirante' then
    raise exception 'FALLO: el aspirante se auto-asignó otro rol';
  end if;
  raise notice 'OK aspirante: no puede cambiar su rol';
end $$;

-- 4) Actuar como DOCENTE
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);
do $$
begin
  if (select count(*) from public.resultados) <> 1 then
    raise exception 'FALLO: el docente no ve resultados';
  end if;
  if (select count(*) from public.respuestas) <> 1 then
    raise exception 'FALLO: el docente no ve el historial de respuestas';
  end if;
  raise notice 'OK docente: ve resultados e historial';
end $$;

rollback;
