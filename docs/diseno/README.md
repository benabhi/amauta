# Sistema de diseño

Decisiones visuales de Amauta (ERS 6.5). El catálogo vivo, con cada componente, sus variantes y sus estados, está en **http://localhost:4000/storybook** (solo en desarrollo).

## Dónde vive cada cosa

| Qué | Dónde |
|---|---|
| Tokens (color, tipografía, radios, sombras, movimiento) | `assets/css/app.css` |
| Componentes | `lib/amauta_web/components/core_components.ex` |
| Historias del catálogo | `storybook/` |
| Fuentes e íconos (generados) | `priv/static/fonts/`, `priv/static/images/icons.svg` |
| Lista de íconos | `assets/icons.exs` |

Para sumar fuentes o íconos: editar `assets/package.json` o `assets/icons.exs`, correr `npm install` en `assets/` y después `mix amauta.assets.vendor` (desde `bin/dev shell`).

## Decisiones tomadas

- **Color:** los valores del modo claro son los del ERS 6.5.2. Los del oscuro se derivaron en OKLCH, con el mismo tono de cada familia: fondos con luminosidad 0,31 y textos con 0,86. El primario `#3F57C6` se usa igual en los dos modos (6,2:1 con texto blanco). `test/amauta_web/design_tokens_test.exs` verifica en la CI que todos los pares de texto y fondo superen 4,5:1.
- **Modo oscuro:** lo decide el atributo `data-theme` (o la clase `dark`, que usa el catálogo). El selector de la barra superior ofrece sistema, claro y oscuro, y lo recuerda en el navegador.
- **Tipografía:** Atkinson Hyperlegible Next (interfaz) y Mono (código y datos), variables, autoalojadas y recortadas a latín y latín extendido.
- **Íconos:** Phosphor, en un sprite SVG con solo los que se usan. Peso regular en la interfaz y duotone en los estados vacíos.
- **Elevación:** sombras teñidas de cálido en tres niveles (`shadow-sm`, `shadow-md`, `shadow-lg`). En oscuro, casi no se ven: la elevación la da la superficie.
- **Movimiento:** tokens de duración (80 a 500 ms) y curvas (estándar, entrada, salida y resorte). Con «reducir movimiento», las transiciones se anulan.

## Pendiente de la exploración visual

- **Tipografía display:** Fraunces es la provisoria. La página «Tipografía» del catálogo la compara con Bricolage Grotesque; la elección final se hace en la exploración visual (ERS 6.5.8).
- **Firma visual:** las ilustraciones y los patrones inspirados en tocapus, los estados de error (404 y 500) y el logo todavía no existen. Por ahora, el ícono del birrete ocupa el lugar del logo.
- **Regresión visual automática** de componentes y pantallas (RNF-TST-001).
