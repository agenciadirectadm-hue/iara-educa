import { useState } from 'react';
import { Link } from 'react-router';
import clsx from 'clsx';
import { Accessibility, BookOpen, ChevronDown, Database, FileText, Search, ShieldCheck, Sigma, X } from 'lucide-react';
import { useDebounced, useRpc } from '@/lib/hooks';
import { useBootstrap } from '@/lib/data';
import { fmtDate, fmtInt } from '@/lib/format';
import { DOC, LEVEL_LABEL } from '@/lib/labels';
import { Badge, Card, EmptyState, PageHeader, Section, SkeletonList, SourceChip, inputCls, type SourceKind } from '@/components/ui';
import { IaraMascot } from '@/components/iara';
import { WhatsAppCard } from '@/components/whatsapp';

const SOURCES: { name: string; detail: string; kind: SourceKind }[] = [
  { name: 'IN nº 025/2025-SEDUC — Anexo I', detail: 'Critérios da fila de espera: pontuação (irmão, CadÚnico, até 2 km, mãe solo) e prioridade sob análise por laudo.', kind: 'oficial' },
  { name: 'Censo Escolar 2025 — INEP (microdados)', detail: 'Unidades, turmas, matrículas e funções docentes da rede municipal de Maringá.', kind: 'oficial' },
  { name: 'Consulta Escolas — SEED-PR (2026)', detail: 'Cadastro, endereço, etapas e situação das unidades.', kind: 'oficial' },
  { name: 'Prefeitura de Maringá / SEDUC (páginas públicas)', detail: 'Lista de CMEIs e escolas, contatos e serviços divulgados.', kind: 'publico' },
  { name: 'IBGE — malha municipal', detail: 'Limite do município usado no mapa.', kind: 'oficial' },
  { name: 'OpenStreetMap / OpenFreeMap', detail: 'Base cartográfica do mapa (ruas e bairros).', kind: 'publico' },
  { name: 'Camada operacional de demonstração', detail: 'Capacidades, vagas, fila, protocolos, conversas e pessoas — fictícios até a integração com a SEDUC.', kind: 'demo' },
];

export default function Help() {
  const boot = useBootstrap();
  const [q, setQ] = useState('');
  const dq = useDebounced(q, 300);
  const kb = useRpc<any>('knowledge_search', { q: dq }, { staleTime: 5 * 60_000 });
  const cat = useRpc<any>('service_catalog', {}, { staleTime: 10 * 60_000 });
  const [open, setOpen] = useState<number | null>(null);
  const k = boot.data?.kpis;
  return (
    <div>
      <div className="mb-4 flex items-end gap-4">
        <div className="min-w-0 flex-1">
          <PageHeader
            eyebrow="Ajuda e transparência"
            title="Ajuda, fontes e privacidade"
            subtitle="Como ler cada número, de onde vêm os dados, como a IARA decide e como seus dados são protegidos."
          />
        </div>
        <div className="hidden shrink-0 sm:block"><IaraMascot height={150} mood="idle" /></div>
      </div>

      <WhatsAppCard
        className="mb-6"
        subtitle="Para divulgar às famílias: QR code, número e link de conversa. Imprima o cartaz para a entrada da escola ou do CMEI."
      />

      <Section title="Como ler os números" subtitle="Toda informação tem um selo. Toque no selo para entender." className="mt-0">
        <Card className="grid grid-cols-1 gap-3 p-4 sm:grid-cols-2 lg:grid-cols-3">
          {([
            ['oficial', 'Veio de fonte oficial com data de referência.'],
            ['publico', 'Fonte pública que pode precisar de confirmação.'],
            ['calculado', 'Resultado de regra explícita e versionada.'],
            ['demo', 'Camada fictícia para demonstrar o funcionamento.'],
            ['projetado', 'Cenário de modelo simples — não é fato.'],
            ['pendente', 'Ainda não disponível. Nada foi inventado.'],
          ] as [SourceKind, string][]).map(([kind, text]) => (
            <div key={kind} className="flex items-start gap-2">
              <SourceChip kind={kind} />
              <span className="text-[13px] text-ink-2">{text}</span>
            </div>
          ))}
        </Card>
      </Section>

      <Section title={<span className="inline-flex items-center gap-2"><Sigma className="size-5 text-purple-700" />Como as vagas são calculadas</span>}>
        <Card className="space-y-3 p-4 text-[14px]">
          <div className="rounded-2xl bg-slate-50 p-3 font-mono text-[13px]">vagas físicas = capacidade autorizada − matrículas ativas</div>
          <div className="rounded-2xl bg-purple-50 p-3 font-mono text-[13px] text-purple-900">vagas ofertáveis = vagas físicas − vagas bloqueadas − vagas reservadas</div>
          <p className="text-ink-2">
            <b>Bloqueadas</b>: indisponíveis por inclusão, decisão judicial, adaptação de sala, obra ou ausência de profissional — sempre com justificativa auditada.
            <b> Reservadas</b>: seguram a vaga enquanto a família efetiva a matrícula — 72 h desde a oferta (IN nº 025/2025, Anexo II). Só vagas ofertáveis podem ser oferecidas, sempre seguindo a ordem da fila.
          </p>
          <div className="rounded-2xl bg-green-50 p-3 text-ink-2 ring-1 ring-green-100">
            <b>Ordem da fila (IN nº 025/2025-SEDUC, Anexo I):</b> irmão(ã) matriculado(a) na mesma unidade <b>55</b> · família de baixa renda no CadÚnico <b>25</b> ·
            reside até 2 km da unidade <b>15</b> · filho(a) de mãe solo <b>5</b> — no máximo 100 pontos; empate pela data da solicitação.
            Estudantes com deficiência (PCD), TEA, TGD e/ou altas habilidades/superdotação têm <b>prioridade sob análise</b>, mediante laudo médico com CID, fora da soma de pontos.
          </div>
          <p className="text-ink-2">Aceite não é matrícula: a unidade confere os documentos e confirma. Silêncio não é aceite nem recusa — no fim do prazo a vaga é liberada.</p>
          <Link to="/regras" className="inline-block font-semibold text-blue-700 underline">Ver todas as regras e simular a pontuação</Link>
        </Card>
      </Section>

      <Section title={<span className="inline-flex items-center gap-2"><BookOpen className="size-5 text-purple-700" />Perguntas frequentes</span>} subtitle="Base oficial de conhecimento — é dela que a IARA tira as respostas.">
        <div className="relative mb-3">
          <Search className="pointer-events-none absolute left-4 top-1/2 size-5 -translate-y-1/2 text-subtle" />
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Ex.: idade para creche, documentos, transferência" className={clsx(inputCls, 'pl-11')} aria-label="Buscar nas perguntas frequentes" />
          {q && <button className="absolute right-3 top-1/2 -translate-y-1/2" onClick={() => setQ('')} aria-label="Limpar"><X className="size-5 text-subtle" /></button>}
        </div>
        {kb.isLoading ? <SkeletonList rows={3} /> : (kb.data?.items ?? []).length ? (
          <Card className="divide-y divide-line overflow-hidden">
            {(kb.data.items as any[]).map((a) => (
              <div key={a.id}>
                <button onClick={() => setOpen(open === a.id ? null : a.id)} className="flex min-h-[56px] w-full items-center gap-3 px-4 py-3 text-left hover:bg-slate-50" aria-expanded={open === a.id}>
                  <span className="flex-1 font-semibold">{a.title}</span>
                  <ChevronDown className={clsx('size-4 shrink-0 text-subtle transition', open === a.id && 'rotate-180')} />
                </button>
                {open === a.id && (
                  <div className="px-4 pb-4">
                    <p className="whitespace-pre-line text-[14px] leading-relaxed text-ink-2">{a.body}</p>
                    <div className="mt-2 flex flex-wrap items-center gap-2 text-[11.5px] text-muted">
                      <Badge tone="gray">v{a.version}</Badge>
                      {a.source && <span>Fonte: {a.source}</span>}
                      {a.approved_at && <span>· aprovado em {fmtDate(a.approved_at)}</span>}
                      {a.sector && <span>· {a.sector}</span>}
                    </div>
                  </div>
                )}
              </div>
            ))}
          </Card>
        ) : <Card><EmptyState compact title="Nada encontrado" body="Tente outras palavras ou pergunte à IARA." /></Card>}
      </Section>

      <Section title={<span className="inline-flex items-center gap-2"><FileText className="size-5 text-purple-700" />Serviços e documentos</span>} subtitle="Cada solicitação vira um protocolo com prazo de resposta.">
        {cat.isLoading ? <SkeletonList rows={3} /> : (
          <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
            {((cat.data?.items ?? []) as any[]).map((sv) => (
              <Card key={sv.code} className="p-4">
                <div className="flex items-start justify-between gap-2">
                  <div className="font-display text-[16px] font-extrabold leading-tight">{sv.name}</div>
                  {sv.sla_days != null && <Badge tone="blue">{sv.sla_days} dia(s)</Badge>}
                </div>
                {sv.description && <p className="mt-1 text-[13.5px] text-ink-2">{sv.description}</p>}
                {sv.level && (
                  <div className="mt-2 space-y-1 rounded-2xl bg-slate-50 p-2.5 text-[12.5px] text-ink-2">
                    <Badge tone={LEVEL_LABEL[sv.level]?.tone ?? 'gray'}>{LEVEL_LABEL[sv.level]?.label ?? sv.level}</Badge>
                    {sv.iara_action && <div><b>A IARA faz na hora:</b> {sv.iara_action}</div>}
                    {sv.escalation && <div><b>Quem decide:</b> {sv.escalation}</div>}
                  </div>
                )}
                {(sv.documents ?? []).length > 0 && (
                  <div className="mt-2 flex flex-wrap gap-1">
                    {(sv.documents as string[]).map((d) => <Badge key={d} tone="gray">{DOC[d] ?? d}</Badge>)}
                  </div>
                )}
                {sv.source && <div className="mt-2 text-[11.5px] text-muted">Fonte: {sv.source}</div>}
              </Card>
            ))}
          </div>
        )}
      </Section>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Section title={<span className="inline-flex items-center gap-2"><ShieldCheck className="size-5 text-purple-700" />Privacidade (LGPD)</span>}>
          <Card className="p-4">
            <ul className="space-y-2 text-[14px] text-ink-2">
              <li>• Cada perfil vê só o necessário: o prefeito vê agregados; a unidade, os seus alunos; a família, apenas as próprias crianças.</li>
              <li>• Dados sensíveis (saúde, deficiência, rede de proteção) ficam separados, com acesso restrito e consulta registrada.</li>
              <li>• A IARA só mostra dados pessoais depois de verificar a identidade e o vínculo com a criança.</li>
              <li>• Toda ação relevante fica na trilha de auditoria, que não pode ser alterada.</li>
              <li>• Nesta demonstração, todas as pessoas, telefones e documentos são fictícios e nenhuma mensagem real é enviada.</li>
            </ul>
          </Card>
        </Section>
        <Section title={<span className="inline-flex items-center gap-2"><Accessibility className="size-5 text-purple-700" />Acessibilidade</span>}>
          <Card className="p-4">
            <ul className="space-y-2 text-[14px] text-ink-2">
              <li>• Feito primeiro para celular: botões de pelo menos 44 px e navegação por polegar.</li>
              <li>• Respeita “reduzir movimento” do aparelho — as animações são desligadas.</li>
              <li>• Mapas e gráficos têm alternativa em lista e tabela, com textos e números legíveis.</li>
              <li>• Navegação por teclado com foco visível e atalho “pular para o conteúdo”.</li>
            </ul>
          </Card>
        </Section>
      </div>

      <Section title={<span className="inline-flex items-center gap-2"><Database className="size-5 text-purple-700" />Fontes de dados</span>} subtitle={boot.data ? `Referência oficial: ${boot.data.tenant.official_reference_date} · regras ${boot.data.rule_version}` : undefined}>
        <Card className="divide-y divide-line">
          {SOURCES.map((s) => (
            <div key={s.name} className="flex items-start gap-3 px-4 py-3">
              <SourceChip kind={s.kind} className="mt-0.5 shrink-0" />
              <div className="min-w-0"><div className="font-semibold">{s.name}</div><div className="text-[13px] text-muted">{s.detail}</div></div>
            </div>
          ))}
        </Card>
        {k && (
          <p className="mt-3 text-[12.5px] text-muted">
            Base oficial: {fmtInt(k.official.units)} unidades · {fmtInt(k.official.classes)} turmas · {fmtInt(k.official.enrollments)} matrículas ({k.official.reference}).
            Métricas de demonstração identificadas como DEMO em todas as telas.
          </p>
        )}
      </Section>
    </div>
  );
}
