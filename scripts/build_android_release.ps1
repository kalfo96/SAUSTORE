[CmdletBinding()]
param(
  [string] $ConfigFile = 'config/android-production.json',
  [switch] $SkipTests,
  [switch] $SkipApiHealthCheck,
  [switch] $ApkOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectDirectory = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$configPath = (Resolve-Path -LiteralPath (Join-Path $projectDirectory $ConfigFile)).Path
$signingPath = Join-Path $projectDirectory 'android/key.properties'

if (-not (Test-Path -LiteralPath $signingPath -PathType Leaf)) {
  throw 'Android release signing is not configured. Copy android/key.properties.example to android/key.properties, create a private upload keystore, and fill in the four values.'
}

$settings = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$apiBaseUrl = [string] $settings.API_BASE_URL
$apiUri = $null
if (-not [Uri]::TryCreate($apiBaseUrl, [UriKind]::Absolute, [ref] $apiUri) -or
    $apiUri.Scheme -ne 'https' -or -not $apiUri.Host -or $apiUri.UserInfo -or
    $apiUri.Query -or $apiUri.Fragment -or -not $apiBaseUrl.EndsWith('/')) {
  throw 'The Android production API must be an absolute HTTPS URL ending in a slash.'
}

if (-not $SkipApiHealthCheck) {
  $healthUri = [Uri]::new($apiUri, 'health')
  try {
    $health = Invoke-RestMethod -Method Get -Uri $healthUri -TimeoutSec 20
  } catch {
    throw "The live API health check failed at $healthUri. Configure the private PHP backend and database before building the launch release."
  }
  if ($health.status -ne 'ok' -or $health.schemaVersion -ne 3) {
    throw 'The live API returned an unexpected health response. Do not ship this build.'
  }
}

Push-Location $projectDirectory
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed.' }

  if (-not $SkipTests) {
    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed.' }
    flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }
  }

  flutter build apk --release --dart-define-from-file=$configPath
  if ($LASTEXITCODE -ne 0) { throw 'Android release APK build failed.' }

  if (-not $ApkOnly) {
    flutter build appbundle --release --dart-define-from-file=$configPath
    if ($LASTEXITCODE -ne 0) { throw 'Android release App Bundle build failed.' }
  }

  $artifacts = @(
    (Join-Path $projectDirectory 'build/app/outputs/flutter-apk/app-release.apk')
  )
  if (-not $ApkOnly) {
    $artifacts += Join-Path $projectDirectory 'build/app/outputs/bundle/release/app-release.aab'
  }
  foreach ($artifact in $artifacts) {
    if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
      throw "Expected release artifact was not created: $artifact"
    }
    $hash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
    Write-Host "Release artifact: $artifact" -ForegroundColor Green
    Write-Host "SHA-256: $hash"
  }
} finally {
  Pop-Location
}
