-- =====================================================================
-- Arboleda Fest: actualización 2 (piezas nuevas desde el panel)
-- Pégalo completo en Supabase > SQL Editor > New query > Run.
-- Es seguro ejecutarlo más de una vez. Antes debes haber corrido setup.sql.
-- =====================================================================

alter table public.inventario
  add column if not exists descripcion text,
  add column if not exists precio numeric(8,2),
  add column if not exists categoria text,
  add column if not exists cuenta_descuento boolean not null default true,
  add column if not exists foto text,
  add column if not exists creada timestamptz not null default now();

-- Reglas para lo que se escribe en el panel
alter table public.inventario drop constraint if exists inventario_id_chk;
alter table public.inventario add constraint inventario_id_chk
  check (item_id ~ '^[a-z0-9][a-z0-9-]{1,40}$');

alter table public.inventario drop constraint if exists inventario_precio_chk;
alter table public.inventario add constraint inventario_precio_chk
  check (precio is null or (precio >= 0 and precio <= 500));

alter table public.inventario drop constraint if exists inventario_categoria_chk;
alter table public.inventario add constraint inventario_categoria_chk
  check (categoria is null or categoria in ('arcos', 'bases', 'mesas', 'luces', 'extras'));

alter table public.inventario drop constraint if exists inventario_texto_chk;
alter table public.inventario add constraint inventario_texto_chk
  check (char_length(nombre) between 1 and 80 and nombre !~ '[<>"&]'
         and coalesce(descripcion, '') !~ '[<>"&]' and char_length(coalesce(descripcion, '')) <= 200);

alter table public.inventario drop constraint if exists inventario_foto_chk;
alter table public.inventario add constraint inventario_foto_chk
  check (foto is null or (foto ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' and char_length(foto) <= 250000));

-- Catálogo de piezas nuevas: lo único que el cotizador público puede leer del inventario.
-- Las piezas originales del cotizador no tienen precio en la tabla, así que no aparecen aquí.
create or replace function public.catalogo_extra()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', item_id, 'nombre', nombre, 'desc', coalesce(descripcion, ''),
           'precio', precio, 'cat', categoria, 'cuenta', cuenta_descuento, 'foto', foto)
         order by creada, nombre), '[]'::jsonb)
  from public.inventario
  where activo and precio is not null and categoria is not null;
$$;

revoke all on function public.catalogo_extra() from public;
grant execute on function public.catalogo_extra() to anon, authenticated;
