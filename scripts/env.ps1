# scripts/env.ps1
$url  = "https://djbtzyezhfnxberzliwc.supabase.co"
$anon = "sb_publishable_Z2OADxGNhEqXfNCwhiIxpg_C1p4KtCR"

function Invoke-Fn {
    param([string]$Name, [hashtable]$Payload)
    try {
        return Invoke-RestMethod -Uri "$url/functions/v1/$Name" -Method Post `
          -Headers @{ "Authorization"="Bearer $anon"; "Content-Type"="application/json" } `
          -Body ($Payload | ConvertTo-Json -Depth 5)
    } catch {
        Write-Host "=== $Name failed ===" -ForegroundColor Red
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $reader.ReadToEnd() | Write-Host
            $reader.Close()
        } catch { Write-Host $_.Exception.Message }
        return $null
    }
}

function Invoke-Rpc {
    param([string]$Name, [hashtable]$Payload, [string]$Token)
    if (-not $Token) { $Token = $script:porterToken }
    try {
        return Invoke-RestMethod -Uri "$url/rest/v1/rpc/$Name" -Method Post `
          -Headers @{ "apikey"=$anon; "Authorization"="Bearer $Token"; "Content-Type"="application/json" } `
          -Body ($Payload | ConvertTo-Json -Depth 10)
    } catch {
        Write-Host "=== $Name failed ===" -ForegroundColor Red
        $_.ErrorDetails.Message
        return $null
    }
}

function Show-Vars {
    Write-Host "url:              $url"
    Write-Host "anon:             $($anon.Length) символов"
    Write-Host "clientId:         $clientId"
    Write-Host "porterId:         $porterId"
    Write-Host "dispatcherId:     $dispatcherId"
    Write-Host "orderId:          $orderId"
    Write-Host "clientToken:      $($clientToken.Length) символов"
    Write-Host "porterToken:      $($porterToken.Length) символов"
    Write-Host "dispatcherToken:  $($dispatcherToken.Length) символов"
}

function Load-Tokens {
    if (Test-Path "$PSScriptRoot\.tokens.json") {
        $t = Get-Content "$PSScriptRoot\.tokens.json" | ConvertFrom-Json
        $script:clientToken     = $t.clientToken
        $script:porterToken     = $t.porterToken
        $script:dispatcherToken = $t.dispatcherToken
        $script:clientId        = $t.clientId
        $script:porterId        = $t.porterId
        $script:dispatcherId    = $t.dispatcherId
        Write-Host "Токены загружены" -ForegroundColor Green
    } else {
        Write-Host ".tokens.json не найден" -ForegroundColor Yellow
    }
}

function Save-Tokens {
    @{
        clientToken     = $clientToken
        porterToken     = $porterToken
        dispatcherToken = $dispatcherToken
        clientId        = $clientId
        porterId        = $porterId
        dispatcherId    = $dispatcherId
    } | ConvertTo-Json | Set-Content "$PSScriptRoot\.tokens.json"
    Write-Host "Токены сохранены" -ForegroundColor Green
}

Write-Host "env.ps1 загружен. Команды: Invoke-Fn, Invoke-Rpc, Show-Vars, Load-Tokens, Save-Tokens" -ForegroundColor Green

function Get-Token {
    param([string]$Phone, [string]$Role)

    Invoke-Fn "send-sms" @{ phone=$Phone } | Out-Null
    Start-Sleep -Seconds 2

    Write-Host "Введи 6-значный код из sms_codes для $Phone (SQL Editor):" -ForegroundColor Yellow
    $code = Read-Host

    $resp = Invoke-Fn "verify-sms" @{ phone=$Phone; code=$code; role=$Role; full_name=$Role }

    if (-not $resp -or -not $resp.ok) {
        Write-Host "verify-sms failed: $($resp.error)" -ForegroundColor Red
        return $null
    }

    $sess = Invoke-RestMethod -Uri "$url/auth/v1/verify" -Method Post `
      -Headers @{ "apikey"=$anon; "Content-Type"="application/json" } `
      -Body (@{ type="magiclink"; token_hash="$($resp.token_hash)" } | ConvertTo-Json)

    Write-Host "OK role=$Role id=$($resp.userId) token=$($sess.access_token.Length)" -ForegroundColor Green

    return @{ Token = $sess.access_token; Id = $resp.userId }
}
