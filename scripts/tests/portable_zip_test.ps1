[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $projectRoot 'scripts/portable_zip.ps1')
$fixtureRoot = Join-Path $PSScriptRoot 'fixtures/portable_zip'
$testRoot = Join-Path $projectRoot ('build/packaging-tests/' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$testArchive = Join-Path $testRoot 'portable.zip'
$required = @('public_html/index.html', 'public_html/.htaccess', 'public_html/api/index.php', 'dreamstore-private/config.example.php', 'schema.sql')
New-PortableZip -SourceDirectory $fixtureRoot -ArchivePath $testArchive
Assert-PortableZip -ArchivePath $testArchive -RequiredEntries $required -DeploymentPackage

$extractedRoot = Join-Path $testRoot 'extracted'
[IO.Compression.ZipFile]::ExtractToDirectory($testArchive, $extractedRoot)
$fixturePrefix = [IO.Path]::GetFullPath($fixtureRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
foreach ($file in Get-ChildItem -LiteralPath $fixtureRoot -File -Recurse -Force) {
  $relative = $file.FullName.Substring($fixturePrefix.Length)
  $extractedFile = Join-Path $extractedRoot $relative
  if (-not (Test-Path -LiteralPath $extractedFile -PathType Leaf) -or
      (Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $extractedFile).Hash) {
    throw "ZIP extraction changed or lost $relative"
  }
}
Write-Host 'PASS forward-slash paths, real nested directories, dotfiles, and byte-perfect round trip.'

$overwriteRefused = $false
try { New-PortableZip -SourceDirectory $fixtureRoot -ArchivePath $testArchive } catch { $overwriteRefused = $true }
if (-not $overwriteRefused) { throw 'ZIP writer must not overwrite an existing artifact.' }
Assert-PortableZip -ArchivePath $testArchive -RequiredEntries $required
Write-Host 'PASS existing artifact is preserved.'

function New-MalformedTestArchive {
  param([string[]] $Names, [string] $Path)
  $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
  try {
    $writer = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
    try { foreach ($name in $Names) { $writer.CreateEntry($name) | Out-Null } } finally { $writer.Dispose() }
  } finally { $stream.Dispose() }
}
$rejectedCases = @(
  @{ Label = 'Windows backslash regression'; Names = @('public_html\index.html') },
  @{ Label = 'absolute path'; Names = @('/index.html') },
  @{ Label = 'drive path'; Names = @('C:/index.html') },
  @{ Label = 'parent traversal'; Names = @('public_html/../config.php') },
  @{ Label = 'duplicate names'; Names = @('index.html', 'index.html') },
  @{ Label = 'case collision'; Names = @('Index.html', 'index.html') },
  @{ Label = 'wrong-case required filename'; Names = @('Index.html'); Required = @('index.html') },
  @{ Label = 'live DB configuration'; Names = @('dreamstore-private/config.php') },
  @{ Label = 'DB configuration backup'; Names = @('dreamstore-private/config.php.bak') },
  @{ Label = 'server-specific path'; Names = @('public_html/api/private_path.php') },
  @{ Label = 'environment secrets'; Names = @('public_html/.env.production') }
)
foreach ($case in $rejectedCases) {
  $malformedPath = Join-Path $testRoot ([Guid]::NewGuid().ToString('N') + '.zip')
  New-MalformedTestArchive -Names $case.Names -Path $malformedPath
  $refused = $false
  $caseRequired = @()
  if ($case.ContainsKey('Required')) { $caseRequired = $case.Required }
  try { Assert-PortableZip -ArchivePath $malformedPath -DeploymentPackage -RequiredEntries $caseRequired } catch { $refused = $true }
  if (-not $refused) { throw "ZIP validation failed to reject: $($case.Label)" }
  Write-Host "PASS rejects $($case.Label)."
}
Write-Host "13 portable ZIP checks passed. Test artifacts retained at $testRoot"
