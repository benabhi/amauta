# Comandos estandarizados del entorno de desarrollo (RNF-DEV-006).
# Equivalente en bash: bin/dev
param(
  [Parameter(Position = 0)][string]$Command = 'help',
  [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest = @()
)

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

# Ejecuta en el contenedor de la app: usa el que está corriendo o uno efímero.
function Invoke-InApp {
  param([string[]]$Arguments)
  $running = docker compose ps --status running --quiet app 2>$null
  if ($running) { docker compose exec app @Arguments }
  else { docker compose run --rm app @Arguments }
}

function Show-Usage {
  @'
Uso: bin\dev.ps1 <comando> [argumentos]

  up          Levanta todo el entorno en segundo plano
  down        Detiene el entorno (los datos se conservan)
  logs        Muestra los logs (por defecto, de la app) en vivo
  iex         Consola IEx conectada al nodo en ejecución
  shell       Bash dentro del contenedor de la app
  mix …       Ejecuta una tarea de mix
  test …      Ejecuta los tests
  migrate     Aplica las migraciones pendientes
  seed        Carga los datos de ejemplo
  reset       Borra y recrea la base con migraciones y datos de ejemplo
  format      Formatea el código
  lint        Verifica formato y advertencias de compilación
  precommit   Lo que corre antes de cada commit
  ci          Los mismos pasos que la integración continua, en MIX_ENV=test
  e2e         Pruebas en navegador (levanta Playwright en su contenedor)
  destroy     Detiene el entorno y BORRA sus volúmenes (base, archivos, deps)
'@
}

$cookie = if ($env:ERLANG_COOKIE) { $env:ERLANG_COOKIE } else { 'amauta-dev' }

switch ($Command) {
  'up' {
    docker compose up -d --build @Rest
    Write-Host 'App: http://localhost:4000 · Mailpit: http://localhost:8025'
  }
  'down'      { docker compose down @Rest }
  'logs'      { if ($Rest.Count -eq 0) { $Rest = @('app') }; docker compose logs -f @Rest }
  'iex'       { docker compose exec app iex --sname "console$PID" --cookie $cookie --remsh amauta@app }
  'shell'     { Invoke-InApp @('bash') }
  'mix'       { Invoke-InApp (@('mix') + $Rest) }
  'test'      { Invoke-InApp (@('mix', 'test') + $Rest) }
  'migrate'   { Invoke-InApp @('mix', 'ecto.migrate') }
  'seed'      { Invoke-InApp @('mix', 'run', 'priv/repo/seeds.exs') }
  'reset'     { Invoke-InApp @('mix', 'ecto.reset') }
  'format'    { Invoke-InApp @('mix', 'format') }
  'lint'      { Invoke-InApp @('mix', 'do', 'format', '--check-formatted', '+', 'compile', '--warnings-as-errors', '--force') }
  'precommit' { Invoke-InApp @('mix', 'precommit') }
  'ci'        { docker compose exec -e MIX_ENV=test app bash -c 'mix deps.unlock --check-unused && mix compile --warnings-as-errors && mix format --check-formatted && mix gettext.extract --check-up-to-date && mix amauta.gettext.check && mix test --warnings-as-errors' }
  'e2e'       {
    docker compose --profile e2e up -d playwright
    if ($LASTEXITCODE -eq 0) {
      docker compose exec -e MIX_ENV=test -e E2E=1 app mix test --only e2e @Rest
    }
  }
  'destroy'   { docker compose down --volumes }
  { $_ -in 'help', '-h', '--help' } { Show-Usage }
  default {
    Write-Error "Comando desconocido: $Command"
    Show-Usage
    exit 1
  }
}
exit $LASTEXITCODE
