# ADR-0009 · Sistema de diseño base

| Campo | Valor |
|---|---|
| Estado | Aceptado |
| Fecha | 2026-10-06 |
| Requisitos y decisiones | ERS 6.5, RNF-MAN-007, RF-I18N-007, DEC-015, DEC-017, DEC-025 |

## Decisión

- **Sin daisyUI ni heroicons** (DEC-015). Tailwind v4 con tokens propios en `assets/css/app.css`: variables CSS para claro y oscuro, expuestas como utilidades con `@theme inline` (`bg-paper`, `text-ink`, `bg-anil-soft`…).
- **Biblioteca única** (`AmautaWeb.CoreComponents`): botón, botón de ícono, ícono, insignia, avatar, tecla, separador, tarjeta, estado vacío, encabezado, aviso, campos de formulario, tabla y lista. Las pantallas no llevan estilos sueltos: si falta algo, se agrega a la biblioteca con su historia.
- **Catálogo vivo con PhoenixStorybook**, solo en desarrollo. Usa el mismo `app.css` que la aplicación, así no hay dos hojas de estilo que se desincronicen. Las rutas se agregan con `AmautaWeb.StorybookRoutes`, una macro que no hace nada si la dependencia no está (test y producción).
- **Fuentes e íconos versionados en `priv/static`**, generados con `mix amauta.assets.vendor` desde `assets/node_modules`. Producción no necesita Node.
- **Contraste verificado en la CI** contra los valores de `app.css`.
- **Propiedades lógicas de CSS** (`ps`, `pe`, `ms`, `me`, `start`, `end`) en los componentes, para soportar escritura de derecha a izquierda (RF-I18N-007).

Las decisiones visuales concretas y lo que falta de la exploración están en `docs/diseno/README.md`.

## Consecuencias

- El contenedor de desarrollo corre como el dueño del montaje (`root` en Windows y macOS; el usuario del host en Linux, vía `bin/dev`). Si no, Mix no puede fijar la fecha de los archivos que recompila por dependencia (`File.touch!/2` falla con «not owner»). Esto reemplaza en parte el ADR-0002.
- **Pendientes:** la elección de la tipografía display, la firma visual (ilustraciones y patrones), la regresión visual automática y el resto de los componentes del ERS 6.5.7 (superposiciones, navegación, datos y dominio), que se suman a medida que las pantallas los necesiten.
