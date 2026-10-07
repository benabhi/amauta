# Amauta

Plataforma educativa (LMS) open source, autoalojada y minimalista, construida con Elixir, Phoenix LiveView y PostgreSQL.

- Requisitos: [docs/ERS.md](docs/ERS.md)
- Alcance del MVP: [docs/MVP.md](docs/MVP.md)
- Decisiones de arquitectura: [docs/adr/](docs/adr/README.md)
- Sistema de diseño: [docs/diseno/](docs/diseno/README.md)
- Guía de redacción: [docs/guia-de-redaccion.md](docs/guia-de-redaccion.md)

## Desarrollo

Solo hace falta Docker (en Windows, Docker Desktop). Elixir, PostgreSQL y el resto corren en contenedores.

```bash
bin/dev up        # en PowerShell: .\bin\dev.ps1 up
```

| Servicio | Dirección |
|---|---|
| Amauta | http://localhost:4000 |
| Mailpit (correos capturados) | http://localhost:8025 |
| Catálogo de componentes | http://localhost:4000/storybook |
| Garage (S3) | http://localhost:3900 |
| PostgreSQL | `localhost:5432`, usuario y contraseña `postgres` |

La primera vez tarda un par de minutos, mientras descarga dependencias y compila. Los cambios en el código se recargan solos en el navegador.

Comandos frecuentes (iguales en `bin/dev` y `bin\dev.ps1`):

| Comando | Qué hace |
|---|---|
| `up` / `down` | Levanta o detiene el entorno |
| `logs` | Logs de la app en vivo |
| `iex` | Consola conectada al nodo en ejecución |
| `test` | Tests (acepta los argumentos de `mix test`) |
| `migrate` / `seed` / `reset` | Migraciones, datos de ejemplo, recrear la base |
| `format` / `lint` / `precommit` | Calidad de código |
| `mix …` / `shell` | Cualquier tarea de mix, o bash en el contenedor |
| `destroy` | Detiene el entorno y borra sus volúmenes |

Ejecutá `bin/dev help` para ver la lista completa. Los detalles del entorno están en el [ADR-0002](docs/adr/0002-entorno-de-desarrollo.md).

Licencia: [AGPL-3.0](LICENSE).
