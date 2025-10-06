param (
    [Parameter(Mandatory=$true)]
    [string]$NewUrl
)

# مسیر فایل docker-compose.yml (جایگزین کن اگر در پوشه دیگری است)
$composeFile = "C:\Users\ers51\self-hosted-ai-starter-kit\docker-compose.yml"

# از کاربر URL جدید رو بگیره
$NewUrl = Read-Host

# فایل رو بخونه
$content = Get-Content $composeFile -Raw

# اگر خط WEBHOOK_URL موجود باشه، جایگزین کن
if ($content -match "WEBHOOK_URL=") {
    $content = $content -replace "WEBHOOK_URL=.*", "WEBHOOK_URL=$NewUrl"
} else {
    # اگر وجود نداشت، بعد از N8N_SECURE_COOKIE اضافه کن
    $content = $content -replace "(- N8N_SECURE_COOKIE=false)", "`$1`r`n      - WEBHOOK_URL=$NewUrl"
}

# بازنویسی فایل
Set-Content -Path $composeFile -Value $content -Encoding UTF8

Write-Host "✅ WEBHOOK_URL updated to $NewUrl"

# ری‌استارت سرویس n8n
docker compose -f $composeFile up -d n8n
