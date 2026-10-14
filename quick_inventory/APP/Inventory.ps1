[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$OutputDir
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
$outPath = [System.IO.Path]::GetFullPath($OutputDir).TrimEnd('\', '/')
if (-not [System.IO.Directory]::Exists($rootPath)) {
    [Console]::Error.WriteLine('SOURCE_NOT_FOUND: ' + $rootPath)
    exit 2
}
if ($outPath.Equals($rootPath, [System.StringComparison]::OrdinalIgnoreCase) -or
    $outPath.StartsWith($rootPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    [Console]::Error.WriteLine('OUTPUT_MUST_BE_OUTSIDE_SOURCE')
    exit 3
}

$videoExt = @('.mp4','.mov','.mkv','.avi','.m4v','.wmv','.mpg','.mpeg','.ts','.mts','.m2ts','.webm','.flv','.vob','.3gp')
$imageExt = @('.jpg','.jpeg','.png','.gif','.webp','.bmp','.tif','.tiff','.heic','.psd')
$partialExt = @('.yandex_disk_download','.part','.partial','.crdownload','.tmpdownload')
$all = New-Object 'System.Collections.Generic.List[object]'
$errs = New-Object 'System.Collections.Generic.List[object]'
$dirs = New-Object 'System.Collections.Generic.Stack[string]'
$dirs.Push($rootPath)
$dirCount = 0
$sizeTotal = [long]0
$counts = @{ VIDEO=0; IMAGE=0; PARTIAL=0; OTHER=0 }

while ($dirs.Count -gt 0) {
    $dir = $dirs.Pop()
    if (-not $dir.Equals($rootPath,[System.StringComparison]::OrdinalIgnoreCase)) { $dirCount++ }
    try { $entries = [System.IO.Directory]::GetFileSystemEntries($dir) }
    catch {
        $errs.Add([pscustomobject]@{path=$dir; stage='LIST_DIRECTORY'; error=$_.Exception.Message})
        continue
    }
    foreach ($path in $entries) {
        try {
            $attrs = [System.IO.File]::GetAttributes($path)
            if (($attrs -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                $errs.Add([pscustomobject]@{path=$path; stage='SKIP_REPARSE_POINT'; error='Not traversed to avoid loops or unexpected external sources'})
                continue
            }
            if (($attrs -band [System.IO.FileAttributes]::Directory) -ne 0) {
                $dirs.Push($path)
                continue
            }
            $fi = New-Object System.IO.FileInfo($path)
            $ext = $fi.Extension.ToLowerInvariant()
            $category = 'OTHER'
            if ($videoExt -contains $ext) { $category = 'VIDEO' }
            elseif ($imageExt -contains $ext) { $category = 'IMAGE' }
            elseif ($partialExt -contains $ext) { $category = 'PARTIAL' }
            $rel = $path.Substring($rootPath.Length).TrimStart('\', '/')
            $all.Add([pscustomobject]@{
                relative_path=$rel
                file_name=$fi.Name
                extension=$ext
                category=$category
                size_bytes=[long]$fi.Length
                last_write_utc=$fi.LastWriteTimeUtc.ToString('o')
            })
            $sizeTotal += [long]$fi.Length
            $counts[$category]++
        }
        catch { $errs.Add([pscustomobject]@{path=$path; stage='READ_FILE_METADATA'; error=$_.Exception.Message}) }
    }
}

[System.IO.Directory]::CreateDirectory($outPath) | Out-Null
$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$runId = [guid]::NewGuid().ToString('N').Substring(0,8)
$basename = 'L2F_INVENTORY_' + $stamp + '_' + $runId
$work = Join-Path $outPath ($basename + '_files')
[System.IO.Directory]::CreateDirectory($work) | Out-Null
$csv = Join-Path $work 'FILES.csv'
if ($all.Count -gt 0) { $all | Export-Csv -LiteralPath $csv -Encoding UTF8 -NoTypeInformation }
else { '"relative_path","file_name","extension","category","size_bytes","last_write_utc"' | Set-Content -LiteralPath $csv -Encoding UTF8 }
$errCsv = Join-Path $work 'ERRORS.csv'
if ($errs.Count -gt 0) { $errs | Export-Csv -LiteralPath $errCsv -Encoding UTF8 -NoTypeInformation }
else { '"path","stage","error"' | Set-Content -LiteralPath $errCsv -Encoding UTF8 }
$status = if ($errs.Count -eq 0) { 'COMPLETE' } else { 'COMPLETE_WITH_ERRORS' }
$report = [ordered]@{
    schema = 'L2F_QUICK_FILE_INVENTORY_1'
    status = $status
    scan_root = $rootPath
    timestamp_utc = [DateTime]::UtcNow.ToString('o')
    counts = [ordered]@{
        files_total=$all.Count
        video_files=$counts.VIDEO
        image_files=$counts.IMAGE
        partial_downloads=$counts.PARTIAL
        other_files=$counts.OTHER
        subdirectories=$dirCount
        metadata_errors=$errs.Count
    }
    total_file_bytes=$sizeTotal
    sha256_computed=$false
    notes='Metadata inventory only. No content was read or modified. This is not a fingerprint scan or snapshot reconciliation.'
}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $work 'SUMMARY.json') -Encoding UTF8
$lines = @(
    'L2F Quick Inventory'
    ('STATUS=' + $status)
    ('SOURCE=' + $rootPath)
    ('FILES_TOTAL=' + $all.Count)
    ('VIDEOS=' + $counts.VIDEO)
    ('IMAGES=' + $counts.IMAGE)
    ('PARTIAL=' + $counts.PARTIAL)
    ('OTHER=' + $counts.OTHER)
    ('SUBDIRECTORIES=' + $dirCount)
    ('ERRORS=' + $errs.Count)
    ('BYTES=' + $sizeTotal)
    'NO_SHA256_COMPUTED'
    'SOURCE_READ_ONLY'
)
$lines | Set-Content -LiteralPath (Join-Path $work 'SUMMARY.txt') -Encoding UTF8
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $outPath ($basename + '.zip')
[System.IO.Compression.ZipFile]::CreateFromDirectory($work, $zip)
if (-not [System.IO.File]::Exists($zip) -or (Get-Item -LiteralPath $zip).Length -le 0) { throw 'REPORT_ZIP_NOT_CREATED' }
Write-Output ($lines -join [Environment]::NewLine)
Write-Output ('REPORT_ZIP=' + $zip)
Write-Output ('EXIT_CODE=' + $(if ($errs.Count -eq 0) {0} else {4}))
if ($errs.Count -gt 0) { exit 4 }
exit 0
