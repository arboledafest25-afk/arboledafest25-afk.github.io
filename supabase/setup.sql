-- =====================================================================
-- Arboleda Fest: base de datos de cotizaciones y reservas (Supabase)
-- Pégalo completo en Supabase > SQL Editor > New query > Run.
-- Es seguro ejecutarlo más de una vez.
-- =====================================================================

-- ---------- 1. Tablas ----------

create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

create table if not exists public.config (
  clave text primary key,
  valor text not null
);
insert into public.config (clave, valor) values
  ('dias_antes', '1'),              -- el mobiliario se entrega 1 día antes del evento
  ('dias_despues', '1'),            -- y se devuelve 1 día después
  ('max_cotizaciones_hora', '8')    -- límite por conexión, contra abusos
on conflict (clave) do nothing;

create table if not exists public.inventario (
  item_id text primary key,
  nombre text not null,
  unidades int not null check (unidades >= 0),
  activo boolean not null default true
);
-- Unidades de EJEMPLO: cámbialas por las que realmente tienes (en el panel o aquí).
insert into public.inventario (item_id, nombre, unidades) values
  ('arco-romano',  'Arco romano', 2),
  ('aro-circular', 'Aro circular', 2),
  ('cilindros',    'Set de 3 cilindros', 2),
  ('mesitas',      'Set de 4 mesitas doradas', 2),
  ('esc2',         'Escalera de 2 niveles', 2),
  ('esc4',         'Escalera de 4 niveles', 1),
  ('bandejas',     'Set de base y bandejas', 3),
  ('mesa',         'Mesa plegable chocolate', 4),
  ('silla',        'Silla plástica', 32),
  ('neon-g',       'Letrero LED Happy Birthday grande', 1),
  ('neon-p',       'Letrero LED Happy Birthday pequeño', 2),
  ('boygirl',      'Letrero LED Boy or Girl', 1),
  ('grama',        'Alfombra de grama', 3),
  ('bomba',        'Bomba eléctrica para globos', 1)
on conflict (item_id) do nothing;

create table if not exists public.cotizaciones (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  creada timestamptz not null default now(),
  actualizada timestamptz not null default now(),
  nombre text not null,
  instagram text not null,
  fecha_evento date not null,
  tipo_evento text,
  entrega text not null check (entrega in ('retiro', 'delivery')),
  zona text,
  notas text,
  ref text,
  total numeric(8,2) not null check (total >= 0),
  detalle jsonb not null default '[]'::jsonb,
  estado text not null default 'nueva'
    check (estado in ('nueva', 'fecha_confirmada', 'abonada', 'entregada', 'devuelta', 'cancelada')),
  abono numeric(8,2) not null default 0 check (abono >= 0),
  notas_internas text,
  ip_hash text
);
create index if not exists cotizaciones_fecha_idx on public.cotizaciones (fecha_evento);
create index if not exists cotizaciones_estado_idx on public.cotizaciones (estado);
create index if not exists cotizaciones_ip_idx on public.cotizaciones (ip_hash, creada);

create table if not exists public.cotizacion_items (
  cotizacion_id uuid not null references public.cotizaciones(id) on delete cascade,
  item_id text not null references public.inventario(item_id),
  cantidad int not null check (cantidad > 0),
  primary key (cotizacion_id, item_id)
);
create index if not exists cotizacion_items_item_idx on public.cotizacion_items (item_id);

create or replace function public.tocar_actualizada() returns trigger
language plpgsql as $$
begin
  new.actualizada := now();
  return new;
end $$;
drop trigger if exists cotizaciones_actualizada on public.cotizaciones;
create trigger cotizaciones_actualizada before update on public.cotizaciones
  for each row execute function public.tocar_actualizada();

-- ---------- 2. Quién es administrador ----------

create or replace function public.es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- ---------- 3. Funciones públicas (lo único que puede usar el cliente) ----------

-- 3a. Guardar una cotización
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
    if not exists (select 1 from public.inventario i where i.item_id = r.item_id and i.activo) then
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

  insert into public.cotizacion_items (cotizacion_id, item_id, cantidad)
  select v_id, key, value::int from jsonb_each_text(v_items);

  return jsonb_build_object('codigo', v_codigo, 'id', v_id);
end $$;

-- 3b. Consultar disponibilidad de una fecha para las piezas elegidas
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
    select i.item_id, i.nombre, i.unidades,
           (p_items ->> i.item_id)::int as pedidas,
           coalesce((
             select sum(ci.cantidad)
             from public.cotizacion_items ci
             join public.cotizaciones c on c.id = ci.cotizacion_id
             where ci.item_id = i.item_id
               and c.estado in ('fecha_confirmada', 'abonada', 'entregada')
               and (c.fecha_evento - v_antes) <= (p_fecha + v_desp)
               and (p_fecha - v_antes) <= (c.fecha_evento + v_desp)
           ), 0) as comprometidas
    from public.inventario i
    where i.activo and (p_items ? i.item_id)
  loop
    v_libres := r.unidades - r.comprometidas;
    if r.pedidas > v_libres then v_ok := false; end if;
    v_res := v_res || jsonb_build_object(
      'item_id', r.item_id, 'nombre', r.nombre, 'pedidas', r.pedidas,
      'libres', greatest(v_libres, 0), 'ok', r.pedidas <= v_libres);
  end loop;
  return jsonb_build_object('ok', v_ok, 'items', v_res);
end $$;

-- ---------- 4. Seguridad ----------

alter table public.admins            enable row level security;
alter table public.config            enable row level security;
alter table public.inventario        enable row level security;
alter table public.cotizaciones      enable row level security;
alter table public.cotizacion_items  enable row level security;

-- Nadie anónimo toca las tablas directamente.
revoke all on public.admins, public.config, public.inventario, public.cotizaciones, public.cotizacion_items from anon;

grant usage on schema public to anon, authenticated;
grant select on public.admins to authenticated;
grant select, update on public.config to authenticated;
grant select, insert, update, delete on public.inventario, public.cotizaciones, public.cotizacion_items to authenticated;

drop policy if exists admins_ver_propio on public.admins;
create policy admins_ver_propio on public.admins for select to authenticated using (user_id = auth.uid());

drop policy if exists config_admin on public.config;
create policy config_admin on public.config for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists inventario_admin on public.inventario;
create policy inventario_admin on public.inventario for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists cotizaciones_admin on public.cotizaciones;
create policy cotizaciones_admin on public.cotizaciones for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists cotizacion_items_admin on public.cotizacion_items;
create policy cotizacion_items_admin on public.cotizacion_items for all to authenticated using (public.es_admin()) with check (public.es_admin());

-- Funciones: solo las dos públicas son llamables por visitantes.
revoke all on function public.crear_cotizacion(jsonb) from public;
revoke all on function public.disponibilidad(date, jsonb) from public;
revoke all on function public.es_admin() from public;
grant execute on function public.crear_cotizacion(jsonb) to anon, authenticated;
grant execute on function public.disponibilidad(date, jsonb) to anon, authenticated;
grant execute on function public.es_admin() to authenticated;

-- =====================================================================
-- PASO FINAL (después de crear tu usuario en Authentication > Users):
-- cambia el correo por el tuyo y ejecuta SOLO esta línea:
--
--   insert into public.admins (user_id)
--   select id from auth.users where email = 'tu-correo@ejemplo.com';
-- =====================================================================
