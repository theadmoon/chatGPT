[CmdletBinding()]
param([string]$PackageRoot='.')
$ErrorActionPreference='Stop'
$pkg=[IO.Path]::GetFullPath($PackageRoot)
$sourceFile=Join-Path $pkg 'SOURCE_ROOT.txt'
if(-not [IO.File]::Exists($sourceFile)){throw 'SOURCE_CONFIG_NOT_FOUND'}
$rows=@([IO.File]::ReadAllLines($sourceFile) | ForEach-Object {$_.Trim().Trim('"')} | Where-Object {$_ -and -not $_.StartsWith('#')})
if($rows.Count -ne 1){throw 'ONE_SOURCE_REQUIRED'}
$root=$rows[0]
Write-Host ('L2F Vera video SHA: '+$root)
Write-Host 'Read only; partial downloads skipped; results auto-resume.'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg 'APP\Scan.ps1') -Root $root -OutputDir (Join-Path $pkg 'REPORTS') -StateDir (Join-Path $pkg 'STATE')
exit $LASTEXITCODE
