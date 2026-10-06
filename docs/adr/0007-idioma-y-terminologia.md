# ADR-0007 · Idioma, formatos y terminología

| Campo | Valor |
|---|---|
| Estado | Aceptado |
| Fecha | 2026-10-06 |
| Requisitos y decisiones | RF-I18N-001 a 007 y 009, ERS 4.9, Anexo E, DEC-011 |

## Decisión

- **Gettext con el español rioplatense como base** (`"es"`, idioma por defecto del backend). Los `msgid` están en inglés y el inglés (`"en"`) queda como segundo idioma sin traducción propia: muestra los `msgid`.
- **Traducción obligatoria:** `mix amauta.gettext.check` falla si hay mensajes del español sin traducir o marcados como `fuzzy`, y `mix gettext.extract --check-up-to-date` falla si los catálogos no están al día con el código. Los dos corren en la CI y en `mix precommit`.
- **Mensajes de validación propios:** se declaran con `dgettext_noop` en `AmautaWeb.ErrorMessages`, para que se extraigan.
- **Resolución del idioma** (`Amauta.Locale`): persona (`users.locale`), institución (`institutions.locale`) e instancia. `AmautaWeb.Locale` la aplica como plug y como `on_mount`. Los emails se escriben con el idioma de quien los recibe.
- **Formatos con CLDR** (`ex_cldr`): el backend `Amauta.Cldr` usa `es-AR` para el español. Los datos se descargan al compilar y en tiempo de ejecución no se consulta la red. `AmautaWeb.Format` convierte de UTC a la zona horaria pedida antes de formatear.
- **Terminología** (`Amauta.Terminology`): presets del Anexo E (genérico, universidad, terciario y posgrado) más los ajustes de cada institución (`institutions.terminology_preset` y `institutions.terminology`). Cada término tiene singular, plural y género. La cohorte y el período, que el Anexo E no detalla, usan los términos genéricos en todos los presets.
- **Concordancia:** `gettext_term/4` elige entre dos traducciones del mismo mensaje, con contexto `masculine` o `feminine`, según el género del término. Las variables `%{term}` y `%{terms}` están siempre disponibles.
- **Guía de redacción:** `docs/guia-de-redaccion.md`.

## Consecuencias

- Los tests usan instituciones en inglés y comparan contra los `msgid`; el español tiene sus propios tests de interfaz y de emails.
- La compilación del backend de CLDR tarda unos 20 segundos. Solo pasa cuando cambia su configuración.
- **Pendientes:** la zona horaria de cada persona llega con su perfil (H1), y las propiedades lógicas de CSS (RF-I18N-007) con el sistema de diseño.
