-- =====================================================================
-- Arboleda Fest: actualización 4 (precios, combos nuevos y temporadas desde el panel)
-- Pégalo completo en Supabase > SQL Editor > New query > Run.
-- Es seguro ejecutarlo más de una vez. Antes debes haber corrido setup.sql y el archivo 02.
-- =====================================================================

-- ---------- 1. Precios de las piezas originales (se guardan aquí para poder cambiarlos desde el panel) ----------
update public.inventario i
   set precio = v.p
  from (values
    ('arco-romano', 10), ('aro-circular', 10), ('cilindros', 18), ('mesitas', 14),
    ('esc2', 5), ('esc4', 12), ('bandejas', 3), ('mesa', 7), ('silla', 0.5),
    ('neon-g', 8), ('neon-p', 3), ('boygirl', 5), ('grama', 3), ('bomba', 5)
  ) as v(id, p)
 where i.item_id = v.id and i.precio is null and i.categoria is null;

-- ---------- 2. Combos ----------
create table if not exists public.combos (
  id text primary key check (id ~ '^[a-z0-9][a-z0-9-]{0,40}$'),
  nombre text not null check (char_length(nombre) between 1 and 60 and nombre !~ '[<>"&]'),
  precio numeric(8,2) not null check (precio >= 0 and precio <= 1000),
  items jsonb not null check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) between 1 and 40),
  foto text check (foto is null or (foto ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' and char_length(foto) <= 250000)),
  activo boolean not null default true,
  orden int not null default 100,
  creada timestamptz not null default now()
);

insert into public.combos (id, nombre, precio, items, orden) values
  ('c1', 'Combo #1', 35, '["aro-circular","mesitas","grama","esc4","esc2","bandejas","neon-p"]', 1),
  ('c2', 'Combo #2', 25, '["aro-circular","mesitas","grama","bandejas"]', 2),
  ('c3', 'Combo #3', 12, '["aro-circular","grama"]', 3),
  ('c4', 'Combo #4', 40, '["arco-romano","cilindros","grama","esc4","esc2","bandejas","neon-p"]', 4),
  ('c5', 'Combo #5', 30, '["arco-romano","cilindros","grama","bandejas"]', 5),
  ('c6', 'Combo #6', 12, '["arco-romano","grama"]', 6)
on conflict (id) do nothing;

-- ---------- 3. Temporadas (ajuste en porcentaje según la fecha del evento) ----------
create table if not exists public.temporadas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (char_length(nombre) between 1 and 60 and nombre !~ '[<>"&]'),
  desde date not null,
  hasta date not null check (hasta >= desde),
  porcentaje numeric(5,1) not null check (porcentaje between -90 and 200 and porcentaje <> 0),
  activo boolean not null default true,
  creada timestamptz not null default now()
);

-- ---------- 4. Seguridad ----------
alter table public.combos     enable row level security;
alter table public.temporadas enable row level security;
revoke all on public.combos, public.temporadas from anon;
grant select, insert, update, delete on public.combos, public.temporadas to authenticated;

drop policy if exists combos_admin on public.combos;
create policy combos_admin on public.combos for all to authenticated
  using (public.es_admin()) with check (public.es_admin());
drop policy if exists temporadas_admin on public.temporadas;
create policy temporadas_admin on public.temporadas for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- ---------- 5. Lo que el cotizador público puede leer ----------
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
               'precio', precio, 'cat', categoria, 'cuenta', cuenta_descuento, 'foto', foto)
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

revoke all on function public.catalogo_publico() from public;
grant execute on function public.catalogo_publico() to anon, authenticated;
