L2F Vera video SHA256 inventory 0.1.0
====================================
Unzip entire ZIP onto E: or C: outside the scanned D: drive.
Confirm SOURCE_ROOT.txt contains D:\, then double-click SCAN_VERA_SHA.cmd.
Only finished video-extension candidates are hashed; .yandex_disk_download,
.part and other partial downloads get no SHA. The program also skips
System Volume Information and $RECYCLE.BIN.
A video modified within the last 10 minutes is deferred. Existing SHA values
are durably saved in STATE/SHA_CACHE.jsonl; keep that entire STATE folder.
On next run unchanged files reuse their SHA based on path+size+UTC timestamp.
An exit code 4 means partial or inaccessible files; send newest REPORTS ZIP
even then, and rerun later if necessary. No video files are altered.
The first scan can read hundreds of GB from D: and take hours.
The private report contains filenames, so never post it to a PUBLIC GitHub repo.
Send the report only through your private recovery workflow.
A SHA match to Snapshot identifies identical file bytes, not playable status
or storefront download accessibility; physical duplicates must be deduplicated.
