$ErrorActionPreference = 'Stop'

Push-Location (Join-Path $PSScriptRoot '..')
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed.' }
  flutter analyze
  if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed.' }
  flutter test
  if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }
  flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/production.json
  if ($LASTEXITCODE -ne 0) { throw 'Flutter production web build failed.' }
  Write-Host 'Production web bundle is ready in build/web.' -ForegroundColor Green
} finally {
  Pop-Location
}
