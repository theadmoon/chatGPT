[CmdletBinding()]
param([string]$PackageRoot='.')
$ErrorActionPreference='Stop'
$pkg=[IO.Path]::GetFullPath($PackageRoot)
$sourceFile=Join-Path $pkg 'SOURCE_ROOT.txt'
if(-not [IO.File]::Exists($sourceFile)){throw 'SOURCE_CONFIG_NOT_FOUND'}
$rows=@([IO.File]::ReadAllLines($sourceFile) | ForEach-Object {$_.Trim().Trim('"')} | Where-Object {$_ -and -not $_.StartsWith('#')})
if($rows.Count -ne 1){throw 'SOURCE_CONFIG_MUST_HAVE_ONE_PATH'}
$root=$rows[0]
Write-Host ('L2F Vera Quick Inventory: '+$root)
Write-Host 'NO SHA256 / NO MODIFICATION OF SOURCE'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg 'APP\Inventory.ps1') -Root $root -OutputDir (Join-Path $pkg 'REPORTS')
exit $LASTEXITCODE
