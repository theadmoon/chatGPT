L2F VERA QUICK FILE INVENTORY 0.1.0
===================================
Purpose: first-stage inventory of My Passport (D:) during active Yandex downloads.
The program is READ ONLY. No SHA-256, no media playback and no content inspection.

1. Unzip entire package in C: drive (Desktop or Downloads) OUTSIDE D:.
2. Check SOURCE_ROOT.txt: default is D:\
3. Double-click SCAN_VERA_D.cmd. Do not launch from inside ZIP.
4. Wait for SUCCESS and send the newest .zip from REPORTS.

Reports include FILES.csv (relative paths, size, timestamps, category), ERRORS.csv,
SUMMARY.json and SUMMARY.txt.
VIDEO means video-extension candidate, NOT verified-complete or verified-good media.
PARTIAL indicates .yandex_disk_download and other incomplete-file extensions.
For videos being downloaded to a final .mp4 filename, repeat the inventory later:
stable size and timestamp in two reports is a screening condition, NOT proof of completeness.
A separate later SHA phase can identify the file against the published snapshot, irrespective
of filename. No private filenames or files are sent to GitHub.
Do not extract program to D: because reports must be stored outside the source disk.
