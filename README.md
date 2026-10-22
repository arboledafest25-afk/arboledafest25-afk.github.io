# Arboleda Fest: cotizador con base de datos y panel de reservas

Qué incluye este paquete:

| Archivo | Para qué sirve |
|---|---|
| `index.html` | La página que ven tus clientes (el cotizador). |
| `admin.html` | Tu panel privado: cotizaciones, calendario de reservas, inventario y piezas nuevas. |
| `config.js` | Aquí pegas los datos de tu proyecto de Supabase. |
| `pdf.js` y `vendor/` | Generan la cotización en PDF (la librería viene incluida, no depende de internet). |
| `supabase/setup.sql` | Crea la base de datos con sus reglas de seguridad (se corre primero). |
| `supabase/02-piezas-nuevas-y-pdf.sql` | Agrega lo necesario para crear piezas nuevas desde el panel (se corre después). |
| `logo/` | Tu logo en vector y PNG. |

Si dejas `config.js` vacío, el cotizador sigue funcionando como antes (solo envía por WhatsApp, sin guardar nada).

---

## Parte 1. Crear la base de datos en Supabase (unos 15 minutos)

Los nombres de los menús de Supabase pueden cambiar un poco con el tiempo; si algo no aparece donde dice, búscalo por su nombre.

1. Entra a **supabase.com**, crea una cuenta y toca **New project**. Ponle de nombre `arboleda-fest`, elige una región cercana (por ejemplo East US) y anota la contraseña de la base de datos en un lugar seguro.
2. En el menú izquierdo abre **SQL Editor**, toca **New query**, pega TODO el contenido de `supabase/setup.sql` y toca **Run**. Debe terminar sin errores. Es seguro ejecutarlo dos veces.
3. Crea tu usuario: **Authentication, Users, Add user, Create new user**. Escribe tu correo y una contraseña larga y marca la opción de confirmar el usuario automáticamente.
4. Busca en Authentication la opción **Allow new users to sign up** y desactívala. Así nadie más puede crear cuentas. (Aunque alguien lo lograra, las reglas de seguridad no le darían acceso a nada.)
5. Hazte administradora. En **SQL Editor** ejecuta esto, cambiando el correo por el tuyo:

   ```sql
   insert into public.admins (user_id)
   select id from auth.users where email = 'tu-correo@ejemplo.com';
   ```
6. Copia dos datos del proyecto: la **Project URL** (algo como `https://abcdxyz.supabase.co`) y la **clave pública** (en la sección de API Keys, la "Publishable key", que empieza con `sb_publishable_`; si no existe, toca "Create new API keys"). Abre `config.js` y pégalas ahí.

> La clave `sb_publishable_` es pública por diseño: puede estar en GitHub. **Nunca** pegues en el proyecto una clave `secret` ni `service_role`.

## Parte 2. Publicar la página en GitHub Pages (gratis)

1. En GitHub crea un repositorio nuevo (por ejemplo `cotizador`).
2. Sube TODOS los archivos de esta carpeta, incluidos `.nojekyll`, `supabase/` y `logo/`.
3. En el repositorio: **Settings, Pages, Deploy from a branch**, rama `main`, carpeta `/ (root)`, **Save**.
4. En unos minutos tendrás: `https://TU-USUARIO.github.io/cotizador/` (clientes) y `https://TU-USUARIO.github.io/cotizador/admin.html` (tu panel).

Con un repositorio público, GitHub Pages es gratis. Con uno privado, depende de tu plan de GitHub.

## Parte 3. Primera prueba

1. Abre el panel (`admin.html`), entra con tu correo y contraseña y ve a **Inventario**. Las unidades que trae son **de ejemplo**: pon las que realmente tienes y toca Guardar en cada pieza.
2. Abre el cotizador, arma una cotización de prueba, elige una fecha y toca el botón de WhatsApp. Debe abrir tu chat con el mensaje, y en el panel debe aparecer la cotización con el mismo código.
3. En el panel toca **Fecha libre, confirmar**. Esa cotización ya bloquea sus piezas: en el cotizador, otra persona que elija esa fecha (o un día antes o después) verá un aviso de que hay piezas reservadas.

---

## Cómo funciona

- Cuando el cliente toca el botón, la cotización se **guarda primero** con su código (por ejemplo `AF-261018-X7K`) y **después** se abre WhatsApp con ese mismo código. Si la conexión falla, abre WhatsApp igual y el mensaje dice "(Cotización no registrada en línea)".
- Una cotización cuenta como real cuando el código que llega a tu WhatsApp coincide con uno guardado en el panel.
- Las cotizaciones nuevas **no** bloquean piezas. Solo bloquean las que tú pasas a **Fecha confirmada**, **Abono recibido** o **Entregada**.
- Cada reserva ocupa sus piezas desde 1 día antes hasta 1 día después del evento (cámbialo en Inventario, "Entrega y devolución").
- Estados: Nueva, Fecha confirmada, Abono recibido, Entregada, Devuelta y Cancelada. Una cotización cancelada libera las piezas.

## Seguridad: lo que sí y lo que no

- Los visitantes solo pueden hacer dos cosas: enviar una cotización y preguntar si una fecha está disponible. No pueden leer cotizaciones, nombres ni usuarios de nadie.
- Hay límites contra abusos (máximo de cotizaciones por hora por conexión y por usuario de Instagram) y un campo trampa para robots.
- El total de la cotización lo calcula el navegador del cliente y la base de datos solo lo guarda. Es informativo: el precio real lo confirmas tú por WhatsApp.
- Esta versión no verifica pagos ni que la cuenta de Instagram escrita sea real.
- Guardas nombre, usuario de Instagram y datos de la fiesta de tus clientes. Conviene tener un aviso de privacidad y revisar con alguien que conozca la norma lo que aplique en Panamá (por ejemplo, la Ley 81 de 2019 de protección de datos personales).
- Usa una contraseña larga y exclusiva para el panel. El panel pide inicio de sesión y no aparece en buscadores, pero igual no compartas su dirección.

## Cambios frecuentes

- **Precios, combos y descuentos:** abre `index.html`, busca el bloque `CONFIGURACIÓN` y edita `ITEMS`, `COMBOS` y `CONFIG.tiers`.
- **Una pieza nueva:** agrégala en `ITEMS` de `index.html` Y como fila nueva en la tabla `inventario` (el `item_id` debe ser idéntico), por ejemplo:
  `insert into public.inventario (item_id, nombre, unidades) values ('arco-nuevo', 'Arco nuevo', 2);`
- **Número de WhatsApp:** en `config.js`.
- **Etiquetas para anuncios:** agrega al enlace `?utm_source=instagram&utm_medium=anuncio&utm_campaign=combos`. Cada cotización guarda de dónde vino.

## Si algo falla

- **El cotizador no muestra el aviso de disponibilidad ni guarda:** revisa que `config.js` tenga la URL y la clave bien pegadas, sin espacios.
- **El panel dice "no es administrador":** falta el paso 5 de la Parte 1 (o el correo no coincide).
- **"Permission denied" o "relation does not exist":** el `setup.sql` no se ejecutó completo; vuelve a correrlo.
- **Un cliente recibe "demasiadas solicitudes":** es el límite por hora; puedes subirlo en la tabla `config` (`max_cotizaciones_hora`).

---

## Actualización 2: PDF y piezas nuevas

**PDF de la cotización**
- En el cotizador, el botón **Descargar o compartir PDF** genera la cotización con tu logo, el detalle, el total y las reglas de reserva. En teléfonos que lo permiten abre el menú de compartir, donde puedes elegir WhatsApp y el PDF va adjunto. En los demás, se descarga.
- Un enlace de WhatsApp solo puede llevar texto, nunca un archivo. Por eso el botón verde sigue enviando el mensaje, y el PDF se adjunta aparte en el chat.
- En el navegador interno de Instagram las descargas a veces no funcionan: el PDF se intenta abrir en una pestaña nueva. Si no se ve, conviene abrir el cotizador en Chrome o Safari.
- En el panel, cada cotización tiene **Descargar PDF**. Esa versión incluye el estado de la reserva, el abono recibido y el saldo pendiente, y es la que conviene mandar al cliente por WhatsApp cuando confirmas su fecha.

**Piezas nuevas sin tocar código**
1. Ejecuta una sola vez `supabase/02-piezas-nuevas-y-pdf.sql` en el SQL Editor de Supabase.
2. En el panel, pestaña **Inventario**, sección **Piezas nuevas**: escribe nombre, descripción, precio, unidades y categoría, y sube una foto (opcional). Toca **Agregar al cotizador**.
3. La pieza aparece en el cotizador al recargarlo. Puedes cambiar su precio y unidades, ocultarla (desmarcando "visible en el cotizador") o eliminarla si nunca se usó en una cotización.
- Las piezas nuevas se cotizan y reservan igual que las demás, y el calendario las cuenta.
- Los **combos** siguen definidos en `index.html`. Una pieza nueva no entra en un combo hasta que se edite el archivo.
- Las piezas originales se siguen editando solo en sus unidades; sus precios están en `index.html`.

**Eliminar cotizaciones:** el panel tiene un botón **Eliminar** en cada una (pide confirmación). Sirve para pruebas y duplicadas.

### Cómo instalar esta actualización
1. En Supabase, SQL Editor, pestaña nueva: pega `supabase/02-piezas-nuevas-y-pdf.sql` y toca Run (si aparece la advertencia de "operaciones destructivas", toca Run query).
2. En tu repositorio de GitHub: Add file, Upload files. Sube estos archivos y confirma con Commit changes:
   `index.html`, `admin.html` y `pdf.js` (reemplazan o agregan), la carpeta `vendor/` con sus dos archivos, y `supabase/02-piezas-nuevas-y-pdf.sql`.
3. **No subas ni reemplaces `config.js`**: ya tiene tus datos.
4. Espera 1 o 2 minutos y recarga las dos páginas con Ctrl + F5.

---

## Actualización 3: cambiar la foto de las piezas originales

- En el panel, pestaña **Inventario**, cada pieza original tiene debajo una fila de foto. Elige una imagen y se guarda sola; para volver a la foto de siempre toca **Volver a la original**.
- Las fotos se reducen en tu equipo antes de guardarse (unos 480 píxeles). Usa fotos con la pieza sola, buena luz y fondo liso.
- El cotizador toma la foto nueva al cargarse; recarga la página para verla.
- Los **precios** y los **combos** de las piezas originales siguen estando en `index.html`.
- Para instalarla: corre una vez `supabase/03-fotos-piezas-originales.sql` en el SQL Editor de Supabase y sube `index.html` y `admin.html` a GitHub.

---

## Actualización 4: precios, combos nuevos y temporadas

Todo se maneja desde el panel, en tres pestañas nuevas:

- **Precios:** el precio de cada pieza, para cambiarlo cuando cambie la temporada. Las filas modificadas se marcan, y se guardan juntas con **Guardar todos los cambios**.
- **Combos:** cambia el precio, las piezas, el nombre y la foto de cualquier combo, oculta los que no quieras mostrar y crea combos nuevos. Un combo solo aparece en el cotizador si su precio es menor o igual que la suma de sus piezas por separado (el panel te avisa).
- **Temporadas:** un recargo o un descuento en porcentaje que se aplica al total según la **fecha del evento** que escribe el cliente (por ejemplo, +15 % en diciembre o -10 % en una oferta). Se ve como una línea aparte en la cotización, en el mensaje de WhatsApp y en el PDF. Si dos temporadas se cruzan, se usa la que empieza más tarde.

Cosas a tener en cuenta:
- Los cambios se ven al recargar el cotizador.
- Si cambias el precio de una pieza, el "por separado" y el ahorro de los combos se recalculan solos. El precio del combo no cambia por sí mismo.
- Las cotizaciones guardadas conservan el total con el que se hicieron.
- Los flyers de Instagram no se actualizan solos: si cambias un precio que sale en un flyer, hay que cambiar el flyer.
- Para instalarla: corre una vez `supabase/04-precios-combos-temporadas.sql` en el SQL Editor de Supabase y sube `index.html` y `admin.html` a GitHub. Este archivo ya incluye lo de la actualización 3.

---

## Actualización 5: piezas que se pueden pedir por unidad

Algunas piezas vienen en sets (el set de 3 cilindros y el set de 4 mesitas). Ahora el cliente puede pedir **una sola pieza**, y el precio de cada una sale del precio del set dividido entre las piezas que trae (por ejemplo, set de cilindros $18 ÷ 3 = $6 cada uno; set de mesitas $14 ÷ 4 = $3.50 cada una).

- En el cotizador aparece una tarjeta nueva debajo de cada set, por ejemplo "Cilindro blanco (unidad)". La cotización, el mensaje de WhatsApp y el PDF dicen exactamente lo que el cliente pidió ("2 × Cilindro blanco (unidad)"), nunca el set completo.
- En **Combos** puedes armar un combo con una sola mesita o un solo cilindro: en el editor de piezas aparecen las dos opciones, el set y la unidad.
- Si cambias el precio de un set en **Precios**, el precio de la unidad se actualiza solo.
- En **Inventario**, bajo cada pieza, la fila **Cada set trae N piezas** define cuántas piezas trae un set y cómo se llama una unidad. Con 1 pieza por set, la pieza solo se vende completa. También puedes definirlo al agregar una pieza nueva.
- **La disponibilidad se cuenta en piezas.** Las unidades que escribes en Inventario siguen siendo sets (2 sets de cilindros = 6 piezas). Si alguien reserva 1 cilindro suelto, quedan 5 piezas libres para esa fecha, ya sea para unidades o para un set. El calendario del panel también muestra las piezas.
- Para instalarla: corre una vez `supabase/05-piezas-por-unidad.sql` en el SQL Editor de Supabase (después del 04) y sube `index.html` y `admin.html` a GitHub.

---

## Actualización 6: una sola tarjeta para los sets

Las piezas que vienen en sets (cilindros, mesitas) ahora aparecen en **una sola tarjeta**. El contador va de 1 en 1 en piezas, y el precio de cada pieza es el del set dividido entre sus piezas. Cuando el cliente completa un set, el cotizador se lo dice ("Elegiste 1 set de 3 piezas"); si pasa de un set, dice por ejemplo "1 set de 3 piezas + 1 pieza suelta".

- En la cotización, el mensaje de WhatsApp y el PDF las líneas siguen siendo claras: "1 × Set de 3 cilindros" para el set y "2 × Cilindro blanco (unidad)" para las piezas sueltas.
- Para los descuentos por cantidad, un set cuenta como 1 pieza y cada pieza suelta cuenta como una fracción, así que pedir más piezas nunca baja el avance del medidor.
- No hay que correr ningún SQL nuevo: solo sube `index.html` a GitHub.
