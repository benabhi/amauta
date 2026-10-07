# Guía de redacción de la interfaz

Cómo escribir los textos de Amauta en español (RF-I18N-009, DEC-011). Vale para la interfaz, los emails y los mensajes de error.

## Tono

- **Cercano y con voseo:** «Entregá tu TP», «Escribí algo para tu clase», «Volvé a entrar». Nunca «usted» ni «tú».
- **Claro antes que técnico:** «No encontramos la conexión a internet», no «Error de red».
- **Breve:** una idea por frase. Los botones dicen la acción («Guardar la contraseña»), no «Aceptar».
- **Sin culpar a la persona:** «El enlace no es válido o ya venció», no «Ingresaste un enlace inválido».
- **Neutro en género cuando se puede:** «Te damos la bienvenida» en lugar de «Bienvenido/a». Si no se puede, se reformula.

## Forma

- **Mayúscula solo al principio** de títulos y botones: «Ajustes de la cuenta», no «Ajustes De La Cuenta».
- **Puntos suspensivos con el carácter `…`** en los estados de carga: «Guardando…».
- **Comillas latinas** «así» para citar textos de la interfaz.
- **Signos de apertura** en preguntas y exclamaciones: «¿Querés salir?», «¡Listo!».
- **Fechas y números con los formatos del idioma** (`AmautaWeb.Format`): nunca se arman a mano.

## Terminología

- Los niveles, las comisiones, las unidades, las etapas, las cohortes y los períodos **no se escriben fijos**: se piden a `term/3` o `gettext_term/4` (ERS 4.9), porque cada institución los nombra a su manera.
- Si el texto cambia con el género del término («Nuevo curso» / «Nueva materia»), se usa `gettext_term/4`. Cada mensaje lleva entonces dos traducciones, con contexto `masculine` y `feminine`.

## En el código

- Todo texto visible pasa por Gettext. El `msgid` va en inglés (es parte del código) y la traducción al español es obligatoria: la CI falla si falta (`mix amauta.gettext.check`).
- Se usan dominios para separar: `default` (interfaz), `emails` y `errors` (validaciones).
- Después de agregar o cambiar textos: `mix gettext.extract --merge`, completar las traducciones en `priv/gettext/es/LC_MESSAGES/` y revisar que no queden entradas `fuzzy`.
