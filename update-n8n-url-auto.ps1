# --- Config ---
$composeFile        = "C:\Users\ers51\self-hosted-ai-starter-kit\docker-compose.yml"
$cloudflaredService = "cloudflared-quick"
$n8nService         = "n8n"
$anchorEnvLine      = "- N8N_SECURE_COOKIE=false"
$waitSeconds        = 90
$checkIntervalMs    = 1500
$sinceWindowSec     = 1800   # پنجره جستجو در لاگ (۳۰ دقیقه اخیر)
$tailLines          = 800    # تعداد خطوط آخر لاگ برای اسکن
# ---------------

function Fail($msg) { Write-Error $msg; exit 1 }

if (-not (Test-Path $composeFile)) { Fail "File not found: $composeFile" }

$composeDir = Split-Path -Path $composeFile -Parent
& docker compose -f $composeFile up -d $cloudflaredService | Out-Null

# آخرین URL از لاگ‌ها را برگردان
function Get-LastUrlFromText {
    param([string]$text)
    if (-not $text) { return $null }
    $clean = ($text -replace '\|', ' ')         # پاک کردن خطوط جدولی
    $rx = [regex]'https://[A-Za-z0-9\-\.]+trycloudflare\.com/?'
    $matches = $rx.Matches($clean)
    if ($matches.Count -gt 0) {
        $u = $matches[$matches.Count-1].Value.TrimEnd('/') + '/'
        return $u
    }
    return $null
}

function TryExtractUrl {
    param([int]$sinceSec, [int]$tail)
    # ترجیح: docker compose logs (هم‌فرمت اسکرین‌شاتت)
    $logs = (& docker compose -f $composeFile logs --no-color --since ${sinceSec}s --tail $tail $cloudflaredService 2>$null)
    $u = Get-LastUrlFromText $logs
    if ($u) { return $u }

    # fallback: docker logs روی خود کانتینر
    $cid = (& docker compose -f $composeFile ps -q $cloudflaredService 2>$null).Trim()
    if ($cid) {
        $raw = (& docker logs --since ${sinceSec}s --tail $tail $cid 2>$null)
        $u = Get-LastUrlFromText $raw
        if ($u) { return $u }
    }
    return $null
}

# ابتدا تلاش: آخرین URL در پنجره اخیر
$newUrl = TryExtractUrl -sinceSec $sinceWindowSec -tail $tailLines

# اگر نبود یا مطمئن می‌خوای جدیدترین باشه، ری‌استارت و پایش تا چاپ URL جدید
if (-not $newUrl) {
    & docker compose -f $composeFile restart $cloudflaredService | Out-Null
    Write-Host "Waiting for cloudflared to emit a fresh URL..."
    $elapsed = 0
    while ($elapsed -lt ($waitSeconds*1000)) {
        Start-Sleep -Milliseconds $checkIntervalMs
        $elapsed += $checkIntervalMs
        $newUrl = TryExtractUrl -sinceSec 300 -tail 400
        if ($newUrl) { break }
    }
}

if (-not $newUrl) { Fail "Could not find a fresh trycloudflare URL in logs." }
Write-Host "URL found (latest): $newUrl"

# Update compose file
$content = Get-Content $composeFile -Raw
if ($content -match "WEBHOOK_URL=") {
    $content = [regex]::Replace($content, "WEBHOOK_URL=.*", "WEBHOOK_URL=$newUrl")
} else {
    if ($content -match [regex]::Escape($anchorEnvLine)) {
        $content = $content -replace [regex]::Escape($anchorEnvLine), ($anchorEnvLine + "`r`n    - WEBHOOK_URL=$newUrl")
    } else {
        $serviceHeader = "  ${n8nService}`r?`n"
        $envHeader = "    environment:`r?`n"
        if ($content -match $serviceHeader) {
            if ($content -match ($serviceHeader + "(?s).*?" + $envHeader)) {
                $content = $content -replace ($envHeader), ($envHeader + "      - WEBHOOK_URL=$newUrl`r`n")
            } else {
                $content = $content -replace ($serviceHeader), ($serviceHeader + "    environment:`r`n      - WEBHOOK_URL=$newUrl`r`n")
            }
        } else {
            Fail "Could not locate a place to insert WEBHOOK_URL."
        }
    }
}
Set-Content -Path $composeFile -Value $content -Encoding UTF8
Write-Host "Compose file saved."

# Restart n8n
Push-Location $composeDir
try {
    & docker compose -f $composeFile up -d $n8nService | Out-Null
    Write-Host "$n8nService restarted."
} finally {
    Pop-Location
}

Write-Host "Done."
