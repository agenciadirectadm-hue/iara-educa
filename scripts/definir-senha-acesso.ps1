<#
  Define (ou troca) a senha de acesso ao portal do IARA Educa, sem a senha aparecer na tela, no histórico do terminal ou em arquivo.

  O servidor guarda só o hash da senha (PBKDF2-SHA256) no segredo IARA_ACESSO da função `api`. Ao gravar:
  - quem não digitar a senha não entra mais: nem pelo endereço antigo, nem pelo app instalado;
  - todas as sessões abertas caem (inclusive a de quem você quer bloquear) e os passes antigos deixam de valer.
  Na mesma hora, até o site novo ser publicado, ninguém entra (o site antigo não sabe pedir a senha).

  Uso:
    powershell -ExecutionPolicy Bypass -File scripts\definir-senha-acesso.ps1            (define ou troca a senha)
    powershell -ExecutionPolicy Bypass -File scripts\definir-senha-acesso.ps1 -Desligar  (portal aberto de novo, sem senha)
#>
param([switch]$Desligar)

$ref = 'fqpjbyhewzngutbyydig'
$api = "https://api.supabase.com/v1/projects/$ref"

function Pedir([string]$rotulo) {
  Write-Host ""
  Write-Host $rotulo -ForegroundColor Cyan
  Write-Host "Digite e tecle Enter. Nada vai aparecer na tela - e normal."
  $s = Read-Host -AsSecureString
  $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

# a variável do Windows vem antes: um terminal aberto antes da troca do token ainda guarda o antigo
$token = [Environment]::GetEnvironmentVariable('SUPABASE_ACCESS_TOKEN', 'User')
if (-not $token) { $token = $env:SUPABASE_ACCESS_TOKEN }
if (-not $token) { Write-Host "Falta a variavel SUPABASE_ACCESS_TOKEN do Windows. Nada foi alterado." -ForegroundColor Red; exit 1 }
$cab = @{ Authorization = "Bearer $token" }

function DerrubarSessoes {
  $sql = ConvertTo-Json @{ query = "update iara.app_sessions set revoked_at = now() where revoked_at is null and expires_at > now()" } -Compress
  try {
    Invoke-RestMethod -Method Post -Uri "$api/database/query" -Headers $cab -ContentType 'application/json' -Body $sql | Out-Null
    Write-Host "Todas as sessoes abertas foram encerradas." -ForegroundColor Green
  } catch {
    Write-Host "A senha foi gravada, mas nao consegui encerrar as sessoes abertas: $($_.Exception.Message). Elas expiram em ate 12 horas." -ForegroundColor Yellow
  }
}

if ($Desligar) {
  try {
    Invoke-RestMethod -Method Delete -Uri "$api/secrets" -Headers $cab -ContentType 'application/json' -Body '["IARA_ACESSO"]' | Out-Null
    Write-Host "Senha desligada: o portal volta a abrir sem senha em instantes." -ForegroundColor Green
  } catch { Write-Host "Nao consegui desligar: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
  exit 0
}

$senha = Pedir "Nova senha de acesso (minimo de 10 caracteres)"
$conf = Pedir "Repita a senha"
if ($senha -cne $conf) { Write-Host "As duas senhas nao conferem. Nada foi alterado." -ForegroundColor Yellow; exit 1 }
if ($senha.Length -lt 10) { Write-Host "Use pelo menos 10 caracteres. Nada foi alterado." -ForegroundColor Yellow; exit 1 }

# PBKDF2-SHA256, 310.000 iteracoes, sal aleatorio de 16 bytes: o mesmo calculo que o servidor faz para conferir
$iter = 310000
$sal = New-Object byte[] 16
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($sal)
$bytes = [Text.Encoding]::UTF8.GetBytes($senha.Normalize([Text.NormalizationForm]::FormC))
$kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($bytes, $sal, $iter, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
$hash = $kdf.GetBytes(32)
$kdf.Dispose()
$senha = $null; $conf = $null; [Array]::Clear($bytes, 0, $bytes.Length)
$valor = "pbkdf2`$$iter`$$([Convert]::ToBase64String($sal))`$$([Convert]::ToBase64String($hash))"

$corpo = ConvertTo-Json -InputObject @(@{ name = 'IARA_ACESSO'; value = $valor }) -Compress
try {
  Invoke-RestMethod -Method Post -Uri "$api/secrets" -Headers $cab -ContentType 'application/json' -Body $corpo | Out-Null
} catch {
  if ("$($_.Exception.Message)" -match '401') {
    Write-Host "O Supabase recusou o token (SUPABASE_ACCESS_TOKEN). Confira a variavel do Windows ou gere um token novo. Nada foi alterado." -ForegroundColor Red
  } else {
    Write-Host "Nao consegui gravar a senha: $($_.Exception.Message). Nada foi alterado." -ForegroundColor Red
  }
  exit 1
} finally { $valor = $null; $corpo = $null }

DerrubarSessoes
Start-Sleep -Seconds 4
try {
  $s = Invoke-RestMethod "https://$ref.supabase.co/functions/v1/api/acesso"
  if ($s.ativo) { Write-Host "OK - o portal ja pede a senha." -ForegroundColor Green }
  else { Write-Host "Senha gravada. O servidor passa a pedi-la em instantes (nova instancia da funcao)." -ForegroundColor Green }
} catch { Write-Host "Senha gravada. Nao consegui conferir agora; tente abrir o portal em instantes." -ForegroundColor Green }
