# ZIP entry names must use '/', even when this script runs on Windows
# PowerShell/.NET Framework. Linux extractors treat '\' as a literal character.
Set-StrictMode -Version Latest

function Assert-PortableZip {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string] $ArchivePath,
    [string[]] $RequiredEntries = @(),
    [switch] $DeploymentPackage
  )
  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $portableArchive = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($ArchivePath))
  try {
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $exactNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($archiveEntry in $portableArchive.Entries) {
      # Inspect RAW names. Normalizing them here would hide a broken archive.
      $entryName = $archiveEntry.FullName
      if (-not $entryName -or $entryName.Contains('\') -or
          $entryName.StartsWith('/') -or $entryName.Contains(':') -or
          $entryName -match '(^|/)\.{1,2}(/|$)' -or $entryName.Contains('//') -or
          $entryName -match '[\x00-\x1f]') {
        throw "Unsafe or non-portable ZIP entry: $entryName"
      }
      if (-not $names.Add($entryName)) { throw "Duplicate ZIP entry: $entryName" }
      $exactNames.Add($entryName) | Out-Null
      if ($DeploymentPackage -and
          $entryName -match '(?i)(^|/)(config\.php[^/]*|private_path\.php|\.env[^/]*)$') {
        throw "Refusing a deployment ZIP containing private runtime configuration: $entryName"
      }
    }
    foreach ($requiredEntry in $RequiredEntries) {
      if (-not $exactNames.Contains($requiredEntry)) { throw "ZIP is missing $requiredEntry" }
    }
  } finally {
    $portableArchive.Dispose()
  }
}

function New-PortableZip {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string] $SourceDirectory,
    [Parameter(Mandatory = $true)][string] $ArchivePath
  )
  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $sourceRoot = (Resolve-Path -LiteralPath $SourceDirectory -ErrorAction Stop).Path
  $sourceItem = Get-Item -LiteralPath $sourceRoot -Force
  if (-not $sourceItem.PSIsContainer) { throw 'ZIP source must be a directory.' }
  $sourcePrefix = [IO.Path]::GetFullPath($sourceRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  $destination = [IO.Path]::GetFullPath($ArchivePath)
  if ($destination.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'ZIP output must be outside the source directory.'
  }
  foreach ($directory in @($sourceItem) + @(Get-ChildItem -LiteralPath $sourceRoot -Directory -Recurse -Force)) {
    if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Refusing to archive a linked directory: $($directory.FullName)"
    }
  }
  $sourceFiles = @(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force)
  foreach ($sourceFile in $sourceFiles) {
    if (($sourceFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Refusing to archive a linked file: $($sourceFile.FullName)"
    }
  }
  # CreateNew protects existing deployment artifacts from accidental overwrite.
  $zipStream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try {
    $zipWriter = [IO.Compression.ZipArchive]::new($zipStream, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
      foreach ($sourceFile in $sourceFiles) {
        $entryName = $sourceFile.FullName.Substring($sourcePrefix.Length).Replace('\', '/')
        if ($entryName -match '(^|/)\.{1,2}(/|$)' -or $entryName.Contains(':') -or $entryName -match '[\x00-\x1f]') {
          throw "Unsafe ZIP source path: $entryName"
        }
        $zipEntry = $zipWriter.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
        $inputStream = [IO.File]::OpenRead($sourceFile.FullName)
        try {
          $outputStream = $zipEntry.Open()
          try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
        } finally {
          $inputStream.Dispose()
        }
      }
    } finally {
      $zipWriter.Dispose()
    }
  } finally {
    $zipStream.Dispose()
  }
  Assert-PortableZip -ArchivePath $destination
}
