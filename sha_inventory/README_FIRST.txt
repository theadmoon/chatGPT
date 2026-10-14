L2F ALL HDD SHA256 Inventory (candidate build)
Unzip outside scanned drives. Edit SOURCES.txt if required. Run SCAN_ALL_HDD.cmd.
All files, including partially downloaded files, are hashed as bytes; partial hash is not final video identity.
STATE holds an append-only SHA cache; do not delete it. REPORTS has one subfolder per source.
Missing source produces PARTIAL and doesn't erase other source reports.
Hash reuse is based on path+size+mtime. To cryptographically re-check an unchanged-metadata file, a full rehash is required.
Never upload filenames and reports from private drives to a public repository.
