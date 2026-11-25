$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path "assets/fonts" | Out-Null

$downloads = @(
    @{
        Url = "https://raw.githubusercontent.com/google/fonts/main/ofl/cairo/Cairo%5Bslnt%2Cwght%5D.ttf"
        Path = "assets/fonts/Cairo.ttf"
    },
    @{
        Url = "https://raw.githubusercontent.com/google/fonts/main/ofl/cairo/OFL.txt"
        Path = "assets/fonts/Cairo-OFL.txt"
    },
    @{
        Url = "https://raw.githubusercontent.com/google/fonts/main/ofl/opensans/OpenSans%5Bwdth%2Cwght%5D.ttf"
        Path = "assets/fonts/OpenSans.ttf"
    },
    @{
        Url = "https://raw.githubusercontent.com/google/fonts/main/ofl/opensans/OFL.txt"
        Path = "assets/fonts/OpenSans-OFL.txt"
    }
)

foreach ($item in $downloads) {
    Invoke-WebRequest -Uri $item.Url -OutFile $item.Path
}
if ((Get-Item "assets/fonts/Cairo.ttf").Length -eq 0) { throw "Cairo font download is empty." }
if ((Get-Item "assets/fonts/OpenSans.ttf").Length -eq 0) { throw "Open Sans font download is empty." }
