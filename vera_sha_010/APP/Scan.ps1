[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$OutputDir,
    [Parameter(Mandatory=$true)][string]$StateDir
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$rootPath = [System.IO.Path]::GetFullPath($Root)
if ($rootPath.Length -gt [System.IO.Path]::GetPathRoot($rootPath).Length) { $rootPath=$rootPath.TrimEnd('\', '/') }
$outPath = [System.IO.Path]::GetFullPath($OutputDir).TrimEnd('\', '/')
$statePath = [System.IO.Path]::GetFullPath($StateDir).TrimEnd('\', '/')
if (-not [System.IO.Directory]::Exists($rootPath)) {
    [Console]::Error.WriteLine('SOURCE_NOT_FOUND: ' + $rootPath)
    exit 2
}
if ($outPath.Equals($rootPath, [System.StringComparison]::OrdinalIgnoreCase) -or
    $outPath.StartsWith($rootPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
    $statePath.Equals($rootPath, [System.StringComparison]::OrdinalIgnoreCase) -or
    $statePath.StartsWith($rootPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    [Console]::Error.WriteLine('OUTPUT_MUST_BE_OUTSIDE_SOURCE')
    exit 3
}

[IO.Directory]::CreateDirectory($statePath) | Out-Null
$lockPath = Join-Path $statePath 'HASH_SCAN.lock'
try { $runLock = New-Object IO.FileStream($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
catch { [Console]::Error.WriteLine('SCAN_ALREADY_RUNNING'); exit 13 }
$journalWriter = $null
$recentDeferred=0
$videoShaAvailable=0
try {
$cache = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
$cacheFile = Join-Path $statePath 'SHA_CACHE.jsonl'
if ([IO.File]::Exists($cacheFile)) {
    foreach ($cacheLine in [IO.File]::ReadLines($cacheFile)) {
        try {
            $item = $cacheLine | ConvertFrom-Json -ErrorAction Stop
            if ($item.path -and $item.sha256 -match '^[a-f0-9]{64}$' -and ($null -ne $item.size_bytes) -and ($null -ne $item.mtime_ticks)) {
                $cache[[string]$item.path] = $item
            }
        } catch { }
    }
}
$writerStream = New-Object IO.FileStream($cacheFile,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::Read)
$journalWriter = New-Object IO.StreamWriter($writerStream,(New-Object System.Text.UTF8Encoding($false)))
$journalWriter.AutoFlush = $true
$hashFresh=0
$hashReused=0
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
    $folderName=[IO.Path]::GetFileName($dir.TrimEnd('\'))
    if ($folderName -ieq 'System Volume Information' -or $folderName -ieq '$RECYCLE.BIN') { continue }
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
            $fileSize=[long]$fi.Length
            $mtimeTicks=[long]$fi.LastWriteTimeUtc.Ticks
            $digest=''
            $hashStatus='SKIPPED_NONVIDEO'
            if ($category -eq 'PARTIAL') { $hashStatus='SKIPPED_PARTIAL' }
            $hashError=''
            if ($category -eq 'VIDEO') {
                if ($fi.LastWriteTimeUtc -gt [DateTime]::UtcNow.AddMinutes(-10)) {
                    $hashStatus='PENDING_RECENT'
                    $recentDeferred++
                } else {
                    $cached=$null
                    if ($cache.ContainsKey($path)) { $cached=$cache[$path] }
                    if ($null -ne $cached -and [long]$cached.size_bytes -eq $fileSize -and [long]$cached.mtime_ticks -eq $mtimeTicks) {
                        $digest=[string]$cached.sha256
                        $hashStatus='REUSED'
                        $hashReused++
                    } else {
                        try {
                            $f = New-Object IO.FileStream($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read,1048576,[IO.FileOptions]::SequentialScan)
                            try {
                                $sha=[Security.Cryptography.SHA256]::Create()
                                try { $digest=[BitConverter]::ToString($sha.ComputeHash($f)).Replace('-','').ToLowerInvariant() }
                                finally { $sha.Dispose() }
                            } finally { $f.Dispose() }
                            $fi.Refresh()
                            if (-not $fi.Exists -or [long]$fi.Length -ne $fileSize -or [long]$fi.LastWriteTimeUtc.Ticks -ne $mtimeTicks) {
                                $hashStatus='CHANGED_DURING_HASH'
                                $digest=''
                                $hashError='File changed while being read. Retry on next run.'
                            } else {
                                $rec=[ordered]@{path=$path;size_bytes=$fileSize;mtime_ticks=$mtimeTicks;sha256=$digest}
                                $journalWriter.WriteLine(($rec | ConvertTo-Json -Compress))
                                $cache[$path]=[pscustomobject]$rec
                                $hashStatus='HASHED'
                                $hashFresh++
                            }
                        } catch {
                            $hashStatus='HASH_ERROR'
                            $digest=''
                            $hashError=$_.Exception.Message
                        }
                    }
                }
                if ($digest -match '^[0-9a-f]{64}
            if ($hashError) {
                $errs.Add([pscustomobject]@{path=$path;stage=$hashStatus;error=$hashError})
            }

            $all.Add([pscustomobject]@{
                relative_path=$rel
                file_name=$fi.Name
                extension=$ext
                category=$category
                size_bytes=[long]$fi.Length
                last_write_utc=$fi.LastWriteTimeUtc.ToString('o')
                sha256=$digest
                sha_status=$hashStatus
                sha_error=$hashError
            })
            $sizeTotal += [long]$fi.Length
            $counts[$category]++
            if (($all.Count % 20) -eq 0) { Write-Output ("PROGRESS_FILES=" + $all.Count + "; VIDEO_SHA=" + $videoShaAvailable + "; NEW=" + $hashFresh + "; REUSED=" + $hashReused + "; PENDING=" + $recentDeferred) }
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
else { '"relative_path","file_name","extension","category","size_bytes","last_write_utc","sha256","sha_status","sha_error"' | Set-Content -LiteralPath $csv -Encoding UTF8 }
$errCsv = Join-Path $work 'ERRORS.csv'
if ($errs.Count -gt 0) { $errs | Export-Csv -LiteralPath $errCsv -Encoding UTF8 -NoTypeInformation }
else { '"path","stage","error"' | Set-Content -LiteralPath $errCsv -Encoding UTF8 }
$status = if ($errs.Count -eq 0 -and $recentDeferred -eq 0) { 'COMPLETE' } else { 'PARTIAL_RETRY_AVAILABLE' }
$report = [ordered]@{
    schema = 'L2F_VERA_VIDEO_SHA_INVENTORY_1'
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
    sha256_computed=$true
    sha_fresh=$hashFresh
    sha_reused=$hashReused
    sha_available=($hashFresh+$hashReused)
    video_sha_available=$videoShaAvailable
    pending_recent=$recentDeferred
    notes='Full SHA-256 for video files only. Partial download files are skipped. Cached results reuse unchanged path+size+mtime. Ongoing or changing videos are deferred. SHA match with Snapshot proves byte equality, not independent playback or storefront availability.'
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
    ('SHA_AVAILABLE=' + ($hashFresh+$hashReused))
    ('SHA_FRESH=' + $hashFresh)
    ('SHA_REUSED=' + $hashReused)
    ('PENDING_RECENT=' + $recentDeferred)
    ('VIDEO_SHA_AVAILABLE=' + $videoShaAvailable)
    'SOURCE_READ_ONLY'
)
$lines | Set-Content -LiteralPath (Join-Path $work 'SUMMARY.txt') -Encoding UTF8
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $outPath ($basename + '.zip')
[System.IO.Compression.ZipFile]::CreateFromDirectory($work, $zip)
if (-not [System.IO.File]::Exists($zip) -or (Get-Item -LiteralPath $zip).Length -le 0) { throw 'REPORT_ZIP_NOT_CREATED' }
Write-Output ($lines -join [Environment]::NewLine)
Write-Output ('REPORT_ZIP=' + $zip)
Write-Output ('EXIT_CODE=' + $(if ($errs.Count -eq 0 -and $recentDeferred -eq 0) {0} else {4}))
if ($errs.Count -gt 0 -or $recentDeferred -gt 0) { exit 4 }
exit 0
}
finally {
    if ($null -ne $journalWriter) { $journalWriter.Dispose() }
    $runLock.Dispose()
}
) { $videoShaAvailable++ }
            }
            if ($hashError) {
                $errs.Add([pscustomobject]@{path=$path;stage=$hashStatus;error=$hashError})
            }

            $all.Add([pscustomobject]@{
                relative_path=$rel
                file_name=$fi.Name
                extension=$ext
                category=$category
                size_bytes=[long]$fi.Length
                last_write_utc=$fi.LastWriteTimeUtc.ToString('o')
                sha256=$digest
                sha_status=$hashStatus
                sha_error=$hashError
            })
            $sizeTotal += [long]$fi.Length
            $counts[$category]++
            if (($all.Count % 20) -eq 0) { Write-Output ("PROGRESS_FILES=" + $all.Count + "; HASHED=" + $hashFresh + "; REUSED=" + $hashReused) }
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
else { '"relative_path","file_name","extension","category","size_bytes","last_write_utc","sha256","sha_status","sha_error"' | Set-Content -LiteralPath $csv -Encoding UTF8 }
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
    sha256_computed=$true
    sha_fresh=$hashFresh
    sha_reused=$hashReused
    sha_available=($hashFresh+$hashReused)
    notes='Full SHA-256 each file. Cached results reuse unchanged path+size+mtime; intentionally no content re-read on reuse. Changed files during scanning are not accepted. Do not treat incomplete download SHA as final asset hash.'
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
    ('SHA_AVAILABLE=' + ($hashFresh+$hashReused))
    ('SHA_FRESH=' + $hashFresh)
    ('SHA_REUSED=' + $hashReused)
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
}
finally {
    if ($null -ne $journalWriter) { $journalWriter.Dispose() }
    $runLock.Dispose()
}
