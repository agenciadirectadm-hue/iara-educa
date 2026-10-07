# Carga dos dados reais — procedimento

Os dados reais entram **sempre** por este caminho, nunca por SQL avulso. A estrutura está no schema `carga`
(migração `supabase/migrations/20261003003600_estrutura_carga.sql`), sem acesso pela API do portal.

```
receber (arquivo → área de preparação, com hash) → validar → conciliar → promover → [reverter]
```

- **Receber:** cada arquivo vira um **lote** com hash SHA-256, origem, data de referência e responsável.
- **Validar:** campo a campo pelo dicionário (`LAYOUTS.md`) e por regras de cada domínio: referências, idade × série,
  ponto dentro de Maringá, chaves repetidas, possíveis duplicidades de pessoa. Linha com **erro** não entra; **aviso** entra
  (ex.: CPF inválido é descartado e a linha segue). As pendências de lotes reais aparecem em **Qualidade de dados**.
- **Conciliar:** contagens por unidade/série/turno; na fila, a ordem calculada pela IN nº 025/2025 comparada com a lista oficial.
- **Promover:** grava no sistema. É **repetível** (o mesmo código atualiza o mesmo registro, não duplica) e guarda o valor anterior.
- **Reverter:** desfaz um lote promovido, na ordem inversa das dependências. A reversão é recusada se outro lote ou o uso do
  sistema já depende dos registros.

## Antes da carga real (pré-requisitos — seção 9.4 do documento de estrutura)

Autenticação real, ambiente de produção (projeto novo, região Brasil), backup com restauração testada, auditoria reforçada,
criptografia de campo, encarregado LGPD e RIPD aprovados. **Dados reais nunca entram no projeto de demonstração**: a ferramenta
recusa (o projeto de produção é informado em `SUPABASE_PROJECT_REF`).

## Passo a passo (um domínio por vez, nesta ordem)

`UNIDADES → TURMAS → SERVIDORES → RESPONSAVEIS → ALUNOS → VINCULOS → MATRICULAS → FILA`

Os arquivos ficam numa pasta protegida **fora do repositório** (a ferramenta recusa arquivos dentro dele).

```powershell
$env:SUPABASE_ACCESS_TOKEN = "<token de validade curta>"; $env:SUPABASE_PROJECT_REF = "<projeto de produção>"
node scripts/carga/carga.mjs receber   --dominio UNIDADES --arquivo D:\cargas\unidades.csv --origem "Sistema SEDUC" --referencia 2026-11-30 --responsavel "Nome"
node scripts/carga/carga.mjs validar   --lote <código mostrado>
node scripts/carga/carga.mjs conciliar --lote <código>          # SEDUC confere e assina
node scripts/carga/carga.mjs promover  --lote <código>          # com erros: corrigir na fonte e reenviar (ou --parcial)
node scripts/carga/carga.mjs situacao                           # lotes e situação
```

Depois de cada domínio, siga para o próximo (as referências — unidade da turma, aluno da matrícula — precisam estar promovidas).
Ao final, revogue o token no painel do Supabase.

## Ensaio (antes da primeira carga real)

```powershell
node scripts/carga/gerar-ensaio.mjs --saida D:\ensaio-carga         # arquivos FICTÍCIOS no mesmo layout
node scripts/carga/carga.mjs ensaio --pasta D:\ensaio-carga          # valida e promove tudo e DESFAZ ao final
```

O teste automatizado `supabase/tests/carga_ensaio.sql` cobre o mesmo caminho (19 passos, revertido).

## Arquivos desta pasta

- `LAYOUTS.md`: dicionário de dados de cada arquivo (campo, tipo, obrigatório, descrição, exemplo).
- `<domínio>.csv`: modelo com o cabeçalho e uma linha de exemplo (fictícia) para enviar à SEDUC.
- Gerados a partir do banco: `node scripts/carga/carga.mjs layouts --saida docs/carga`.

## Ainda não coberto (próximas etapas)

Laudos, AEE e restrições alimentares (dados sensíveis, com criptografia de campo), ofertas em aberto e protocolos em
andamento, conveniadas (compra de vagas) e a Secretaria como unidade, e a **geocodificação em lote** dos endereços sem
coordenada (precisa de um provedor de geocodificação definido).
