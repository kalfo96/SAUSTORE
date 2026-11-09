[CmdletBinding()]
param(
  # Leave empty for /api/ on the same HTTPS domain as the web application.
  # Native Android/iOS builds need an explicit HTTPS API URL separately.
  [string] $ApiBaseUrl = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectDirectory = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$buildDirectory = Join-Path $projectDirectory 'build/web'
$distDirectory = Join-Path $projectDirectory 'dist'
. (Join-Path $PSScriptRoot 'portable_zip.ps1')

function Assert-ChildPath {
  param([string] $Path, [string] $Parent)
  $resolvedChild = [IO.Path]::GetFullPath($Path)
  $resolvedParent = [IO.Path]::GetFullPath($Parent).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  if (-not $resolvedChild.StartsWith($resolvedParent, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe packaging path outside the intended directory: $resolvedChild"
  }
}

function Copy-SourceTree {
  param(
    [string] $Source,
    [string] $Destination,
    [switch] $PrivateSource,
    [switch] $BackendPublicSource
  )
  Assert-ChildPath -Path $Source -Parent $projectDirectory
  Assert-ChildPath -Path $Destination -Parent $script:stagingDirectory
  $sourcePrefix = [IO.Path]::GetFullPath($Source).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  foreach ($sourceFile in Get-ChildItem -LiteralPath $Source -File -Recurse -Force) {
    if (($sourceFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Refusing to package a linked file: $($sourceFile.FullName)"
    }
    $relativeFile = $sourceFile.FullName.Substring($sourcePrefix.Length)
    if ($BackendPublicSource -and
        ($sourceFile.Name -eq 'private_path.php' -or $sourceFile.Name -like 'config.php*' -or $sourceFile.Name -like '.env*')) {
      continue
    }
    if ($PrivateSource) {
      # Only source and example configuration; no live credentials or runtime data.
      if ($sourceFile.Name -like 'config.php*' -or
          ($sourceFile.Extension -notin @('.php', '.md') -and $sourceFile.Name -ne '.htaccess') -or
          $relativeFile -match '(^|[\\/])(runtime|sessions|logs)([\\/]|$)') {
        continue
      }
    }
    $destinationFile = Join-Path $Destination $relativeFile
    Assert-ChildPath -Path $destinationFile -Parent $Destination
    New-Item -ItemType Directory -Path (Split-Path -Parent $destinationFile) -Force | Out-Null
    Copy-Item -LiteralPath $sourceFile.FullName -Destination $destinationFile
  }
}

# Reject linked source directories as well as linked files, including private
# sources, so an unexpected link cannot pull credentials into a release ZIP.
foreach ($sourceDirectory in @('web', 'backend/public', 'backend/private', 'backend/tools')) {
  $sourceRoot = Join-Path $projectDirectory $sourceDirectory
  foreach ($directoryEntry in @((Get-Item -LiteralPath $sourceRoot)) + @(Get-ChildItem -LiteralPath $sourceRoot -Directory -Recurse -Force)) {
    if (($directoryEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Refusing to package a linked source directory: $($directoryEntry.FullName)"
    }
  }
}

if ($ApiBaseUrl) {
  $validatedApiUri = $null
  if (-not [Uri]::TryCreate($ApiBaseUrl, [UriKind]::Absolute, [ref]$validatedApiUri) -or
      $validatedApiUri.Scheme -ne 'https' -or -not $validatedApiUri.Host -or
      $validatedApiUri.UserInfo -or $validatedApiUri.Query -or $validatedApiUri.Fragment -or
      -not $ApiBaseUrl.EndsWith('/') -or $ApiBaseUrl -match '\s') {
    throw 'ApiBaseUrl must be an HTTPS URL ending in a slash without credentials, query, or fragment, for example https://stock.example.com/api/.'
  }
}

$requiredSources = @(
  'config/cpanel.json',
  'scripts/portable_zip.ps1',
  'backend/public/index.php',
  'backend/public/private_path.example.php',
  'backend/private/config.example.php',
  'backend/schema.sql',
  'backend/tools',
  'docs/CPANEL.md',
  'hosting/cpanel/PACKAGE.md',
  'hosting/cpanel/private.htaccess'
)
foreach ($requiredSource in $requiredSources) {
  $requiredPath = Join-Path $projectDirectory $requiredSource
  Assert-ChildPath -Path $requiredPath -Parent $projectDirectory
  if (-not (Test-Path -LiteralPath $requiredPath)) {
    throw "Missing cPanel deployment source: $requiredSource"
  }
}

Push-Location $projectDirectory
try {
  & (Join-Path $PSScriptRoot 'tests/portable_zip_test.ps1')
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed.' }
  flutter analyze
  if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed.' }
  flutter test
  if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }
  if (Get-Command php -ErrorAction SilentlyContinue) {
    foreach ($phpSource in Get-ChildItem -LiteralPath (Join-Path $projectDirectory 'backend') -File -Recurse -Filter '*.php') {
      & php -n -l $phpSource.FullName
      if ($LASTEXITCODE -ne 0) { throw 'PHP syntax check failed.' }
    }
    & php -n backend/tests/run.php
    if ($LASTEXITCODE -ne 0) { throw 'PHP validation/security tests failed.' }
    & php -n backend/tests/boundaries.php
    if ($LASTEXITCODE -ne 0) { throw 'PHP request-boundary tests failed.' }
  } else {
    Write-Warning 'PHP CLI is unavailable. Run backend PHP syntax and security checks on a PHP-enabled machine before deployment.'
  }
  $buildArguments = @(
    'build', 'web', '--release', '--no-web-resources-cdn', '--no-wasm-dry-run',
    '--dart-define-from-file=config/cpanel.json'
  )
  if ($ApiBaseUrl) { $buildArguments += "--dart-define=API_BASE_URL=$ApiBaseUrl" }
  & flutter @buildArguments
  if ($LASTEXITCODE -ne 0) { throw 'Flutter cPanel web build failed.' }

  Assert-ChildPath -Path $buildDirectory -Parent $projectDirectory
  Assert-ChildPath -Path $distDirectory -Parent $projectDirectory
  if (-not (Test-Path -LiteralPath (Join-Path $buildDirectory 'index.html'))) {
    throw 'The Flutter build did not produce build/web/index.html.'
  }
  New-Item -ItemType Directory -Path $distDirectory -Force | Out-Null
  $packageName = 'cpanel-linux-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ([Guid]::NewGuid().ToString('N').Substring(0, 8))
  $script:stagingDirectory = Join-Path $distDirectory $packageName
  $archivePath = Join-Path $distDirectory ($packageName + '.zip')
  Assert-ChildPath -Path $script:stagingDirectory -Parent $distDirectory
  Assert-ChildPath -Path $archivePath -Parent $distDirectory
  if ((Test-Path -LiteralPath $script:stagingDirectory) -or (Test-Path -LiteralPath $archivePath)) {
    throw 'A deployment package with this name already exists; it will not be overwritten.'
  }
  New-Item -ItemType Directory -Path $script:stagingDirectory | Out-Null

  $publicDirectory = Join-Path $script:stagingDirectory 'public_html'
  $privateDirectory = Join-Path $script:stagingDirectory 'dreamstore-private'
  Copy-SourceTree -Source $buildDirectory -Destination $publicDirectory
  Copy-SourceTree -Source (Join-Path $projectDirectory 'backend/public') -Destination (Join-Path $publicDirectory 'api') -BackendPublicSource
  Copy-SourceTree -Source (Join-Path $projectDirectory 'backend/private') -Destination $privateDirectory -PrivateSource
  Copy-SourceTree -Source (Join-Path $projectDirectory 'backend/tools') -Destination (Join-Path $script:stagingDirectory 'dreamstore-tools') -PrivateSource
  Copy-Item -LiteralPath (Join-Path $projectDirectory 'hosting/cpanel/private.htaccess') -Destination (Join-Path $privateDirectory '.htaccess')
  Copy-Item -LiteralPath (Join-Path $projectDirectory 'backend/schema.sql') -Destination (Join-Path $script:stagingDirectory 'schema.sql')
  Copy-Item -LiteralPath (Join-Path $projectDirectory 'docs/CPANEL.md') -Destination (Join-Path $script:stagingDirectory 'INSTALL.md')
  Copy-Item -LiteralPath (Join-Path $projectDirectory 'hosting/cpanel/PACKAGE.md') -Destination (Join-Path $script:stagingDirectory 'README.md')

  if (Test-Path -LiteralPath (Join-Path $privateDirectory 'config.php')) {
    throw 'Refusing to package a live private configuration.'
  }
  # Explicit forward-slash entry names preserve nested directories on Linux;
  # enumerating with -Force also preserves Apache dotfiles.
  New-PortableZip -SourceDirectory $script:stagingDirectory -ArchivePath $archivePath
  Assert-PortableZip -ArchivePath $archivePath -DeploymentPackage -RequiredEntries @(
    'public_html/index.html', 'public_html/main.dart.js', 'public_html/flutter_bootstrap.js',
    'public_html/.htaccess', 'public_html/api/.htaccess', 'public_html/api/index.php',
    'public_html/api/private_path.example.php', 'dreamstore-private/config.example.php',
    'dreamstore-private/lib/App.php', 'dreamstore-private/.htaccess',
    'dreamstore-tools/reset_admin_password.php', 'schema.sql', 'INSTALL.md'
  )
  # A public-only ZIP can be extracted directly into an already configured
  # subdomain web root. It never contains private PHP configuration or SQL.
  $publicArchivePath = Join-Path $distDirectory ('dreamstore-public-linux-' + $packageName.Substring('cpanel-linux-'.Length) + '.zip')
  Assert-ChildPath -Path $publicArchivePath -Parent $distDirectory
  New-PortableZip -SourceDirectory $publicDirectory -ArchivePath $publicArchivePath
  Assert-PortableZip -ArchivePath $publicArchivePath -DeploymentPackage -RequiredEntries @(
    'index.html', 'main.dart.js', 'flutter_bootstrap.js', '.htaccess', 'api/.htaccess', 'api/index.php'
  )
  Write-Host "cPanel deployment ZIP: $archivePath" -ForegroundColor Green
  Write-Host "Public-only ZIP (extract directly into the subdomain web root): $publicArchivePath" -ForegroundColor Green
  Write-Host "Uncompressed package: $script:stagingDirectory"
  Write-Host 'Follow INSTALL.md. Upload public_html contents only to the public document root; keep private files outside it.'
} finally {
  Pop-Location
}
