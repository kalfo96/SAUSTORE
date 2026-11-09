[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string] $SourcePackageDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectDirectory = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$distDirectory = (Resolve-Path -LiteralPath (Join-Path $projectDirectory 'dist')).Path
$sourceDirectory = (Resolve-Path -LiteralPath $SourcePackageDirectory).Path
$distPrefix = [IO.Path]::GetFullPath($distDirectory).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if (-not ([IO.Path]::GetFullPath($sourceDirectory) + [IO.Path]::DirectorySeparatorChar).StartsWith(
    $distPrefix, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'SourcePackageDirectory must be an uncompressed package inside this project''s dist directory.'
}

foreach ($requiredName in @('public_html', 'dreamstore-private', 'dreamstore-tools', 'schema.sql')) {
  if (-not (Test-Path -LiteralPath (Join-Path $sourceDirectory $requiredName))) {
    throw "The source package is missing $requiredName."
  }
}

. (Join-Path $PSScriptRoot 'portable_zip.ps1')

$sourceName = Split-Path -Leaf $sourceDirectory
$suffix = $sourceName -replace '^cpanel-linux-', ''
$packageName = "directadmin-linux-$suffix"
$stagingDirectory = Join-Path $distDirectory $packageName
$archivePath = Join-Path $distDirectory "$packageName.zip"
if ((Test-Path -LiteralPath $stagingDirectory) -or (Test-Path -LiteralPath $archivePath)) {
  throw 'The DirectAdmin package already exists; existing artifacts are preserved.'
}

New-Item -ItemType Directory -Path $stagingDirectory | Out-Null

function Copy-DirectoryContents {
  param([string] $Source, [string] $Destination)
  New-Item -ItemType Directory -Path $Destination | Out-Null
  foreach ($entry in Get-ChildItem -LiteralPath $Source -Force) {
    Copy-Item -LiteralPath $entry.FullName -Destination $Destination -Recurse
  }
}

Copy-DirectoryContents `
  -Source (Join-Path $sourceDirectory 'public_html') `
  -Destination (Join-Path $stagingDirectory 'dreamstore-public')
Copy-DirectoryContents `
  -Source (Join-Path $sourceDirectory 'dreamstore-private') `
  -Destination (Join-Path $stagingDirectory 'dreamstore-private')
Copy-DirectoryContents `
  -Source (Join-Path $sourceDirectory 'dreamstore-tools') `
  -Destination (Join-Path $stagingDirectory 'dreamstore-tools')

foreach ($fileName in @('schema.sql', 'INSTALL.md', 'README.md')) {
  $sourceFile = Join-Path $sourceDirectory $fileName
  if (Test-Path -LiteralPath $sourceFile -PathType Leaf) {
    Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $stagingDirectory $fileName)
  }
}
Copy-Item -LiteralPath (Join-Path $projectDirectory 'docs/DIRECTADMIN.md') `
  -Destination (Join-Path $stagingDirectory 'INSTALL-DIRECTADMIN.md')

New-PortableZip -SourceDirectory $stagingDirectory -ArchivePath $archivePath
Assert-PortableZip -ArchivePath $archivePath -DeploymentPackage -RequiredEntries @(
  'dreamstore-public/index.html',
  'dreamstore-public/.htaccess',
  'dreamstore-public/api/index.php',
  'dreamstore-public/api/.htaccess',
  'dreamstore-private/config.example.php',
  'dreamstore-private/lib/App.php',
  'dreamstore-private/lib/Validation.php',
  'dreamstore-tools/maintenance.php',
  'schema.sql',
  'INSTALL-DIRECTADMIN.md'
)

Write-Host "DirectAdmin deployment ZIP: $archivePath" -ForegroundColor Green
Write-Host 'Upload it inside the subdomain domain folder and follow INSTALL-DIRECTADMIN.md.'
