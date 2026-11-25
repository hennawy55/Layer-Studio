$ErrorActionPreference = "Stop"

python tool/fetch_fonts.py
if ($LASTEXITCODE -ne 0) {
    throw "Offline font bundle download failed."
}
