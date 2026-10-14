[CmdletBinding()]
param([string]$PackageRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$conf=Join-Path $PackageRoot 'SOURCES.txt'
$state=Join-Path $PackageRoot 'STATE'
$reports=Join-Path $PackageRoot 'REPORTS'
[IO.Directory]::CreateDirectory($state)|Out-Null
[IO.Directory]::CreateDirectory($reports)|Out-Null
$roots=@([IO.File]::ReadAllLines($conf) | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ -and -not $_.StartsWith('#') })
if($roots.Count -lt 1){throw 'NO_SOURCES'}
$overall=0
foreach($root in $roots){
  Write-Host ('SOURCE=' + $root)
  if(-not [IO.Directory]::Exists($root)){
    Write-Host ('SOURCE_UNAVAILABLE=' + $root)
    $overall=4
    continue
  }
  $hash=[Security.Cryptography.SHA256]::Create()
  try{$key=[BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant()))).Replace('-','').Substring(0,16)}
  finally{$hash.Dispose()}
  $sourceState=Join-Path $state $key
  $sourceReports=Join-Path $reports $key
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'SHA_Inventory.ps1') -Root $root -StateDir $sourceState -OutputDir $sourceReports
  if($LASTEXITCODE -ne 0){ $overall=4; Write-Host ('SOURCE_EXIT=' + $LASTEXITCODE) }
}
Write-Host ('ALL_SOURCES_EXIT=' + $overall)
exit $overall
