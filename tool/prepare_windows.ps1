$ErrorActionPreference = "Stop"

$iconPath = "windows/runner/resources/app_icon.ico"
if (!(Test-Path $iconPath)) {
  throw "Windows launcher icon was not generated at $iconPath."
}

$resourceFiles = @(
  "windows/runner/Runner.rc",
  "windows/runner/Runner.rc.in"
)
$resourcePatched = $false
foreach ($resourceFile in $resourceFiles) {
  if (!(Test-Path $resourceFile)) { continue }

  $content = Get-Content $resourceFile -Raw
  $replacement = 'IDI_APP_ICON ICON "resources\app_icon.ico"'
  $pattern = '(?m)^\s*IDI_APP_ICON\s+ICON\s+"[^"]+"\s*$'
  if ([regex]::IsMatch($content, $pattern)) {
    $content = [regex]::Replace($content, $pattern, $replacement)
  } else {
    $content += "`r`n$replacement`r`n"
  }
  Set-Content -Path $resourceFile -Value $content -Encoding ascii
  $resourcePatched = $true
}
if (!$resourcePatched) {
  throw "Flutter Windows runner resource file was not found."
}

# The default Flutter runner uses the package name as the title bar caption.
foreach ($mainFile in @("windows/runner/main.cpp", "windows/runner/main.cpp.in")) {
  if (!(Test-Path $mainFile)) { continue }
  $content = Get-Content $mainFile -Raw
  $content = [regex]::Replace(
    $content,
    'window\.Create\(L"[^"]+"',
    'window.Create(L"Layer Studio"'
  )
  Set-Content -Path $mainFile -Value $content -Encoding ascii
}

Write-Host "Windows icon installed and native runner resources patched."
