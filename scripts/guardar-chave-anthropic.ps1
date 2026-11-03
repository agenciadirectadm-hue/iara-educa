<#
  Grava a chave da Anthropic (Claude Opus 5.5 do Oráculo do Prefeito) nos segredos da Edge Function `api`
  do projeto IARA Educa — sem a chave aparecer na tela, no histórico do terminal ou em arquivo.

  Sem esta chave o Oráculo responde pelas regras do próprio IARA (consultas fixas por assunto). Com ela, o Claude
  escolhe e combina as consultas e escreve a resposta. A chave sai de platform.claude.com → API Keys
  (o consumo é cobrado pela Anthropic, direto na conta dona da chave).

  Uso:  powershell -ExecutionPolicy Bypass -File scripts\guardar-chave-anthropic.ps1
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
if (-not $token) { $token = [Environment]::GetEnvironmentVariable('SUPABASE_ACCESS_TOKEN', 'User') }
if (-not $token) { $token = Pedir 'SUPABASE_ACCESS_TOKEN' 'supabase.com/dashboard/account/tokens' }
$chave = Pedir 'ANTHROPIC_API_KEY' 'platform.claude.com - API Keys'
if (-not $token -or -not $chave) { Write-Host "Nada gravado."; exit 1 }
if (-not $chave.StartsWith('sk-ant-')) { Write-Host "Isto nao parece uma chave da Anthropic (comeca com sk-ant-). Nada gravado." -ForegroundColor Yellow; exit 1 }

$corpo = ConvertTo-Json -InputObject @(@{ name = 'ANTHROPIC_API_KEY'; value = $chave }) -Compress
try {
  Invoke-RestMethod -Method Post -Uri "https://api.supabase.com/v1/projects/$ref/secrets" `
    -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' -Body $corpo | Out-Null
} catch {
  Write-Host "Nao consegui gravar: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
} finally {
  $chave = $null; $corpo = $null
}

Start-Sleep -Seconds 3
$saude = Invoke-RestMethod "https://$ref.supabase.co/functions/v1/api/health"
if ($saude.oraculo_claude) {
  Write-Host "OK - o Oraculo do Prefeito ja responde com o Claude Opus 5.5." -ForegroundColor Green
} else {
  Write-Host "Chave gravada. O gateway passa a usa-la em instantes (nova instancia da funcao)." -ForegroundColor Green
}
