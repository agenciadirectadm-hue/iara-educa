<#
  Grava a chave da Groq (transcrição de áudio da IARA no WhatsApp) nos segredos da Edge Function `api`
  do projeto IARA Educa — sem a chave aparecer na tela, no histórico do terminal ou em arquivo.

  É a mesma transcrição da IARA Saúde (Whisper large-v3 na Groq): dá para usar a mesma chave
  (console.groq.com → API Keys) ou criar uma só para a Educação.

  Uso:  powershell -ExecutionPolicy Bypass -File scripts\guardar-chave-groq.ps1
#>

$ref = 'fqpjbyhewzngutbyydig'

function Pedir([string]$nome, [string]$de) {
  Write-Host ""
  Write-Host "$nome  ($de)" -ForegroundColor Cyan
  Write-Host "Cole e tecle Enter. Nada vai aparecer na tela - e normal."
  $s = Read-Host -AsSecureString
  $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b).Trim() }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

$token = $env:SUPABASE_ACCESS_TOKEN
if (-not $token) { $token = Pedir 'SUPABASE_ACCESS_TOKEN' 'supabase.com/dashboard/account/tokens' }
$groq = Pedir 'GROQ_API_KEY' 'console.groq.com/keys - pode ser a mesma da IARA Saude'
if (-not $token -or -not $groq) { Write-Host "Nada gravado."; exit 1 }
if (-not $groq.StartsWith('gsk_')) { Write-Host "Isto nao parece uma chave da Groq (comeca com gsk_). Nada gravado." -ForegroundColor Yellow; exit 1 }

$corpo = ConvertTo-Json -InputObject @(@{ name = 'GROQ_API_KEY'; value = $groq }) -Compress
try {
  Invoke-RestMethod -Method Post -Uri "https://api.supabase.com/v1/projects/$ref/secrets" `
    -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' -Body $corpo | Out-Null
} catch {
  Write-Host "Nao consegui gravar: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
} finally {
  $groq = $null; $corpo = $null
}

Start-Sleep -Seconds 3
$saude = Invoke-RestMethod "https://$ref.supabase.co/functions/v1/api/health"
if ($saude.audio) {
  Write-Host "OK - a IARA Educa ja ouve audios no WhatsApp." -ForegroundColor Green
} else {
  Write-Host "Chave gravada. O gateway passa a usa-la em instantes (nova instancia da funcao)." -ForegroundColor Green
}
