-- =====================================================================
-- Arboleda Fest: actualización 5 (vender por unidad las piezas que vienen en sets)
-- Pégalo completo en Supabase > SQL Editor > New query > Run.
-- Es seguro ejecutarlo más de una vez. Antes debes haber corrido setup.sql, el 02 y el 04.
-- =====================================================================

-- ---------- 1. Cuántas piezas trae cada set y cómo se llama una unidad ----------
alter table public.inventario
  add column if not exists pack int not null default 1,
  add column if not exists nombre_unidad text;

alter table public.inventario drop constraint if exists inventario_pack_chk;
alter table public.inventario add constraint inventario_pack_chk
  check (pack between 1 and 50 and (nombre_unidad is null or (char_length(nombre_unidad) between 1 and 60 and nombre_unidad !~ '[<>"&]')));

-- Los identificadores no pueden llevar dos guiones seguidos (el sufijo --u marca "una unidad")
alter table public.inventario drop constraint if exists inventario_id_chk;
alter table public.inventario add constraint inventario_id_chk
  check (item_id ~ '^[a-z0-9][a-z0-9-]{1,40}$' and item_id !~ '--');

update public.inventario set pack = 3, nombre_unidad = 'Cilindro blanco' where item_id = 'cilindros' and pack = 1 and nombre_unidad is null;
update public.inventario set pack = 4, nombre_unidad = 'Mesita dorada'  where item_id = 'mesitas'   and pack = 1 and nombre_unidad is null;

-- ---------- 2. Las cotizaciones recuerdan si una línea es un set o una unidad ----------
alter table public.cotizacion_items add column if not exists en_unidades boolean not null default false;
alter table public.cotizacion_items drop constraint if exists cotizacion_items_pkey;
alter table public.cotizacion_items add primary key (cotizacion_id, item_id, en_unidades);

-- ---------- 3. Guardar una cotización (ahora acepta unidades sueltas: id--u) ----------
create or replace function public.crear_cotizacion(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hoy date := (now() at time zone 'America/Panama')::date;
  v_codigo text := upper(btrim(coalesce(p->>'codigo', '')));
  v_nombre text := btrim(coalesce(p->>'nombre', ''));
  v_ig text := lower(regexp_replace(btrim(coalesce(p->>'instagram', '')), '^@', ''));
  v_fecha date;
  v_entrega text := coalesce(p->>'entrega', '');
  v_total numeric;
  v_items jsonb := coalesce(p->'items', '{}'::jsonb);
  v_headers json;
  v_ip text;
  v_iph text;
  v_max int := coalesce((select valor::int from public.config where clave = 'max_cotizaciones_hora'), 8);
  v_id uuid;
  r record;
  n int := 0;
begin
  -- trampa para robots: este campo debe venir vacío
  if coalesce(p->>'website', '') <> '' then raise exception 'solicitud no valida'; end if;

  begin
    v_fecha := (p->>'fecha_evento')::date;
  exception when others then
    raise exception 'fecha no valida';
  end;
  if v_fecha is null or v_fecha < v_hoy or v_fecha > v_hoy + 730 then raise exception 'fecha no valida'; end if;

  if char_length(v_nombre) < 2 or char_length(v_nombre) > 80 then raise exception 'nombre no valido'; end if;
  if v_ig !~ '^[a-z0-9._]{2,30}$' then raise exception 'usuario de instagram no valido'; end if;
  if v_entrega not in ('retiro', 'delivery') then raise exception 'entrega no valida'; end if;
  if v_codigo !~ '^AF-[0-9]{6}-[A-Z0-9]{3,6}$' then raise exception 'codigo no valido'; end if;

  begin
    v_total := (p->>'total')::numeric;
  exception when others then
    raise exception 'total no valido';
  end;
  if v_total is null or v_total < 0 or v_total > 5000 then raise exception 'total no valido'; end if;

  if jsonb_typeof(v_items) <> 'object' then raise exception 'piezas no validas'; end if;
  for r in select key as item_id, value as q from jsonb_each_text(v_items) loop
    if r.item_id like '%--u' then
      -- una unidad suelta de una pieza que se vende en sets
      if not exists (select 1 from public.inventario i
                      where i.item_id = left(r.item_id, length(r.item_id) - 3)
                        and i.activo and i.pack > 1 and i.nombre_unidad is not null) then
        raise exception 'pieza desconocida: %', r.item_id;
      end if;
    elsif not exists (select 1 from public.inventario i where i.item_id = r.item_id and i.activo) then
      raise exception 'pieza desconocida: %', r.item_id;
    end if;
    if r.q !~ '^[0-9]{1,2}$' or r.q::int < 1 then raise exception 'cantidad no valida'; end if;
    n := n + 1;
  end loop;
  if n = 0 or n > 30 then raise exception 'piezas no validas'; end if;

  -- límite por conexión (cabecera que agrega la plataforma)
  begin
    v_headers := current_setting('request.headers', true)::json;
  exception when others then
    v_headers := '{}'::json;
  end;
  v_ip := btrim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1));
  v_iph := case when v_ip = '' then null else md5(v_ip || 'arboleda-fest') end;
  if v_iph is not null and
     (select count(*) from public.cotizaciones where ip_hash = v_iph and creada > now() - interval '1 hour') >= v_max then
    raise exception 'demasiadas solicitudes, intenta mas tarde';
  end if;
  if (select count(*) from public.cotizaciones where instagram = v_ig and creada > now() - interval '1 hour') >= 6 then
    raise exception 'demasiadas solicitudes, intenta mas tarde';
  end if;

  -- reenvío del mismo código por la misma persona: se actualiza, no se duplica
  select id into v_id from public.cotizaciones where codigo = v_codigo;
  if v_id is not null then
    if exists (select 1 from public.cotizaciones where id = v_id and instagram = v_ig and estado = 'nueva') then
      update public.cotizaciones set
        nombre = v_nombre, fecha_evento = v_fecha, tipo_evento = left(coalesce(p->>'tipo_evento', ''), 40),
        entrega = v_entrega, zona = left(coalesce(p->>'zona', ''), 120), notas = left(coalesce(p->>'notas', ''), 500),
        ref = left(coalesce(p->>'ref', ''), 200), total = v_total, detalle = coalesce(p->'detalle', '[]'::jsonb)
      where id = v_id;
      delete from public.cotizacion_items where cotizacion_id = v_id;
    else
      v_codigo := 'AF-' || to_char(now() at time zone 'America/Panama', 'YYMMDD') || '-' || upper(substr(md5(random()::text), 1, 4));
      v_id := null;
    end if;
  end if;

  if v_id is null then
    insert into public.cotizaciones
      (codigo, nombre, instagram, fecha_evento, tipo_evento, entrega, zona, notas, ref, total, detalle, ip_hash)
    values
      (v_codigo, v_nombre, v_ig, v_fecha, left(coalesce(p->>'tipo_evento', ''), 40), v_entrega,
       left(coalesce(p->>'zona', ''), 120), left(coalesce(p->>'notas', ''), 500), left(coalesce(p->>'ref', ''), 200),
       v_total, coalesce(p->'detalle', '[]'::jsonb), v_iph)
    returning id into v_id;
  end if;

  insert into public.cotizacion_items (cotizacion_id, item_id, cantidad, en_unidades)
  select v_id,
         case when key like '%--u' then left(key, length(key) - 3) else key end,
         value::int,
         key like '%--u'
    from jsonb_each_text(v_items);

  return jsonb_build_object('codigo', v_codigo, 'id', v_id);
end $$;

-- ---------- 4. Disponibilidad, contando en piezas ----------
create or replace function public.disponibilidad(p_fecha date, p_items jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_antes int := coalesce((select valor::int from public.config where clave = 'dias_antes'), 1);
  v_desp int := coalesce((select valor::int from public.config where clave = 'dias_despues'), 1);
  v_res jsonb := '[]'::jsonb;
  v_ok boolean := true;
  r record;
  v_libres int;
begin
  if p_fecha is null or jsonb_typeof(coalesce(p_items, '{}'::jsonb)) <> 'object' then
    raise exception 'consulta no valida';
  end if;
  for r in
    select i.item_id, i.nombre, i.pack,
           i.unidades * i.pack as stock,
           (select coalesce(sum(e.value::int * case when e.key like '%--u' then 1 else i.pack end), 0)
              from jsonb_each_text(p_items) e
             where (case when e.key like '%--u' then left(e.key, length(e.key) - 3) else e.key end) = i.item_id) as pedidas,
           coalesce((
             select sum(ci.cantidad * case when ci.en_unidades then 1 else i.pack end)
               from public.cotizacion_items ci
               join public.cotizaciones c on c.id = ci.cotizacion_id
              where ci.item_id = i.item_id
                and c.estado in ('fecha_confirmada', 'abonada', 'entregada')
                and (c.fecha_evento - v_antes) <= (p_fecha + v_desp)
                and (p_fecha - v_antes) <= (c.fecha_evento + v_desp)
           ), 0) as comprometidas
      from public.inventario i
     where i.activo
  loop
    continue when r.pedidas = 0;
    v_libres := r.stock - r.comprometidas;
    if r.pedidas > v_libres then v_ok := false; end if;
    v_res := v_res || jsonb_build_object(
      'item_id', r.item_id, 'nombre', r.nombre, 'pedidas', r.pedidas,
      'libres', greatest(v_libres, 0), 'ok', r.pedidas <= v_libres);
  end loop;
  return jsonb_build_object('ok', v_ok, 'items', v_res);
end $$;

-- ---------- 5. Lo que el cotizador público puede leer (ahora con las piezas por set) ----------
create or replace function public.catalogo_publico()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'piezas', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', item_id, 'nombre', nombre, 'desc', coalesce(descripcion, ''),
               'precio', precio, 'cat', categoria, 'cuenta', cuenta_descuento, 'foto', foto,
               'pack', pack, 'unidad', nombre_unidad)
             order by creada, nombre), '[]'::jsonb)
        from public.inventario
       where activo and (precio is not null or foto is not null)),
    'combos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', id, 'nombre', nombre, 'precio', precio, 'items', items, 'foto', foto, 'activo', activo)
             order by orden, creada), '[]'::jsonb)
        from public.combos),
    'temporadas', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'nombre', nombre, 'desde', desde, 'hasta', hasta, 'pct', porcentaje)
             order by desde), '[]'::jsonb)
        from public.temporadas
       where activo and hasta >= ((now() at time zone 'America/Panama')::date - 1))
  );
$$;

revoke all on function public.crear_cotizacion(jsonb) from public;
revoke all on function public.disponibilidad(date, jsonb) from public;
revoke all on function public.catalogo_publico() from public;
grant execute on function public.crear_cotizacion(jsonb) to anon, authenticated;
grant execute on function public.disponibilidad(date, jsonb) to anon, authenticated;
grant execute on function public.catalogo_publico() to anon, authenticated;
