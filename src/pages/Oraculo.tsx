import { useEffect, useRef, useState } from 'react';
import clsx from 'clsx';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Copy, KeyRound, Mic, PlugZap, Send, Sparkles, Square, Trash2, Volume2 } from 'lucide-react';
import { API_URL, oraculoPerguntar, oraculoStatus, type OraculoNumero, type OraculoResposta } from '@/lib/api';
import { fmt1, fmtDateTime, fmtInt } from '@/lib/format';
import { useRpc, useRpcMutation } from '@/lib/hooks';
import { Badge, Button, Card, ErrorState, Field, PageHeader, Section, SkeletonList, inputCls } from '@/components/ui';

const SUGESTOES = [
  'Como está a rede municipal hoje?',
  'O que está acontecendo na rede?',
  'Quais os motivos dos encaminhamentos ao Conselho Tutelar?',
  'Qual o cardápio de hoje?',
  'Quantas crianças faltaram ontem?',
  'Por que as crianças estão faltando?',
  'Quais as três escolas com mais ocorrências?',
  'Me fale mais sobre a fila da creche',
  'Quais os problemas mais comuns de manutenção?',
  'Quantos alunos do Bolsa Família ficaram abaixo da frequência mínima?',
];
const MAX_AUDIO_S = 60;

type Troca = { id: number; pergunta: string; audio?: boolean; carregando?: boolean; r?: OraculoResposta; erro?: string };

const valor = (n: OraculoNumero) => (n.sigilo ? 'menos de 3' : n.valor == null ? '—' : (n.casas ? fmt1(n.valor) : fmtInt(n.valor)) + (n.sufixo ?? ''));

function falar(texto: string) {
  try {
    window.speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(texto);
    u.lang = 'pt-BR';
    window.speechSynthesis.speak(u);
  } catch { /* navegador sem voz */ }
}

const paraBase64 = (b: Blob) => new Promise<string>((ok, falha) => {
  const r = new FileReader();
  r.onload = () => ok(String(r.result).split(',')[1] ?? '');
  r.onerror = () => falha(r.error);
  r.readAsDataURL(b);
});

/** Oráculo do Prefeito: pergunta por texto ou por áudio sobre qualquer número consolidado do município. As respostas vêm só
 * de números agregados (nenhum dado de pessoa); com a chave da Anthropic, o Claude Opus 5.5 combina as consultas. */
export default function Oraculo() {
  const qc = useQueryClient();
  const st = useQuery({ queryKey: ['oraculo_status'], queryFn: oraculoStatus, staleTime: 60_000 });
  const [trocas, setTrocas] = useState<Troca[]>([]);
  const [texto, setTexto] = useState('');
  const [gravando, setGravando] = useState(false);
  const [segundos, setSegundos] = useState(0);
  const [erroMic, setErroMic] = useState<string | null>(null);
  const gravador = useRef<MediaRecorder | null>(null);
  const fim = useRef<HTMLDivElement>(null);
  const seq = useRef(0);

  useEffect(() => { fim.current?.scrollIntoView({ behavior: 'smooth', block: 'end' }); }, [trocas]);
  useEffect(() => {
    if (!gravando) return;
    const t = setInterval(() => setSegundos((s) => {
      if (s + 1 >= MAX_AUDIO_S) gravador.current?.stop();
      return s + 1;
    }), 1000);
    return () => clearInterval(t);
  }, [gravando]);

  const ocupado = trocas.some((t) => t.carregando);

  async function perguntar(corpo: { pergunta?: string; audio_base64?: string; audio_tipo?: string }, rotulo: string, audio = false) {
    const id = ++seq.current;
    setTrocas((l) => [...l, { id, pergunta: rotulo, audio, carregando: true }]);
    try {
      const r = await oraculoPerguntar(corpo);
      setTrocas((l) => l.map((t) => (t.id === id ? { ...t, pergunta: r.pergunta, carregando: false, r } : t)));
      qc.invalidateQueries({ queryKey: ['oraculo_status'] });
    } catch (e) {
      setTrocas((l) => l.map((t) => (t.id === id ? { ...t, carregando: false, erro: (e as Error).message } : t)));
    }
  }

  function enviar(p = texto) {
    const q = p.trim();
    if (q.length < 3 || ocupado) return;
    setTexto('');
    perguntar({ pergunta: q }, q);
  }

  async function gravar() {
    setErroMic(null);
    if (gravando) { gravador.current?.stop(); return; }
    try {
      const fluxo = await navigator.mediaDevices.getUserMedia({ audio: true });
      const tipo = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg'].find((t) => MediaRecorder.isTypeSupported?.(t)) ?? '';
      const rec = new MediaRecorder(fluxo, tipo ? { mimeType: tipo } : undefined);
      const partes: Blob[] = [];
      rec.ondataavailable = (e) => { if (e.data.size) partes.push(e.data); };
      rec.onstop = async () => {
        fluxo.getTracks().forEach((t) => t.stop());
        setGravando(false);
        const blob = new Blob(partes, { type: rec.mimeType || tipo || 'audio/webm' });
        if (blob.size < 1500) { setErroMic('O áudio ficou curto demais. Segure um pouco mais.'); return; }
        perguntar({ audio_base64: await paraBase64(blob), audio_tipo: blob.type }, 'Pergunta por áudio…', true);
      };
      gravador.current = rec;
      setSegundos(0);
      rec.start();
      setGravando(true);
    } catch {
      setErroMic('Não consegui usar o microfone. Confira a permissão do navegador ou escreva a pergunta.');
    }
  }

  if (st.isLoading) return <SkeletonList rows={5} />;
  if (st.error) return <ErrorState error={st.error as Error} onRetry={() => st.refetch()} />;
  const s = st.data!;

  return (
    <div>
      <PageHeader eyebrow="Gabinete do Prefeito"
        title={<span className="inline-flex items-center gap-2"><Sparkles className="size-6 text-purple-700" />Oráculo do Prefeito</span>}
        subtitle="Pergunte, por texto ou por áudio, sobre toda a rede municipal: vagas, frequência, ocorrências, merenda, transporte, manutenção, professores e o que está acontecendo agora. Na cidade, numa unidade ou numa região, sem expor pessoas." />

      <div className="mb-3 flex flex-wrap gap-2">
        {s.claude
          ? <Badge tone="purple" icon={Sparkles}>Respostas do Claude Opus 5.5</Badge>
          : <Badge tone="gray">Respostas pelas regras do IARA</Badge>}
        <Badge tone={s.audio ? 'green' : 'gray'} icon={Mic}>{s.audio ? 'Pergunta por áudio' : 'Áudio ainda não ligado'}</Badge>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1.6fr_1fr]">
        <Card className="flex min-h-[420px] flex-col p-3 sm:p-4">
          <div className="flex-1 space-y-3 overflow-y-auto" aria-live="polite">
            {trocas.length === 0 && (
              <div className="py-6 text-center">
                <p className="text-[14px] text-ink-2">Experimente uma destas perguntas:</p>
                <div className="mt-3 flex flex-wrap justify-center gap-2">
                  {SUGESTOES.map((q) => (
                    <button key={q} type="button" onClick={() => enviar(q)}
                      className="rounded-full bg-purple-50 px-3 py-1.5 text-[13px] font-semibold text-purple-800 ring-1 ring-purple-200 hover:bg-purple-100">
                      {q}
                    </button>
                  ))}
                </div>
              </div>
            )}
            {trocas.map((t) => <Conversa key={t.id} t={t} />)}
            <div ref={fim} />
          </div>

          <form className="mt-3 flex items-end gap-2" onSubmit={(e) => { e.preventDefault(); enviar(); }}>
            <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={2} maxLength={1000} disabled={gravando}
              onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); enviar(); } }}
              placeholder={gravando ? `Gravando… ${segundos}s (toque no quadrado para enviar)` : 'Pergunte ao Oráculo'}
              aria-label="Pergunta ao Oráculo" className={clsx(inputCls, 'min-h-[48px] flex-1 resize-none')} />
            {s.audio && (
              <Button type="button" variant={gravando ? 'danger' : 'secondary'} icon={gravando ? Square : Mic} onClick={gravar} disabled={ocupado && !gravando}
                aria-label={gravando ? 'Parar e enviar o áudio' : 'Perguntar por áudio'}>
                <span className="sr-only">{gravando ? 'Parar' : 'Áudio'}</span>
              </Button>
            )}
            <Button type="submit" icon={Send} disabled={texto.trim().length < 3 || ocupado || gravando} aria-label="Enviar pergunta">
              <span className="sr-only">Enviar</span>
            </Button>
          </form>
          {erroMic && <p role="alert" className="mt-2 text-[13px] font-semibold text-red-700">{erroMic}</p>}
        </Card>

        <div className="space-y-4">
          <Section title="Perguntas anteriores">
            {s.historico.length === 0 ? (
              <p className="text-[13px] text-muted">As perguntas feitas ao Oráculo ficam aqui (só você vê).</p>
            ) : (
              <Card className="divide-y divide-line">
                {s.historico.slice(0, 8).map((h) => (
                  <button key={h.id} type="button" onClick={() => enviar(h.pergunta)} disabled={ocupado}
                    className="block w-full px-3 py-2.5 text-left hover:bg-slate-50 disabled:opacity-60">
                    <div className="flex items-center gap-1.5 text-[13px] font-semibold text-ink">
                      {h.canal === 'AUDIO' && <Mic className="size-3.5 shrink-0 text-purple-700" aria-label="por áudio" />}
                      <span className="line-clamp-1">{h.pergunta}</span>
                    </div>
                    <div className="text-[12px] text-muted">{fmtDateTime(h.criado_em)} · {h.modo === 'CLAUDE' ? 'Claude' : 'regras'}</div>
                  </button>
                ))}
              </Card>
            )}
          </Section>
          <Mcp />
        </div>
      </div>
    </div>
  );
}

function Conversa({ t }: { t: Troca }) {
  return (
    <div className="space-y-2">
      <div className="flex justify-end">
        <div className="max-w-[85%] rounded-2xl rounded-br-md bg-purple-700 px-3 py-2 text-[14px] text-white">
          {t.audio && <Mic className="mr-1 inline size-3.5 align-[-2px]" aria-label="por áudio" />}{t.pergunta}
        </div>
      </div>
      <div className="flex justify-start">
        <div className="max-w-[92%] rounded-2xl rounded-bl-md bg-slate-50 px-3 py-2.5 ring-1 ring-line">
          {t.carregando && <p className="animate-pulse text-[14px] text-muted">Consultando os números…</p>}
          {t.erro && <p role="alert" className="text-[14px] font-semibold text-red-700">{t.erro}</p>}
          {t.r && (
            <>
              <p className="whitespace-pre-line text-[15px] leading-snug text-ink">{t.r.resposta}</p>
              {t.r.consultas.filter((c) => c?.numeros?.length).map((c, i) => (
                <div key={i} className="mt-2">
                  {c.recorte && <div className="text-[11px] font-bold uppercase tracking-wide text-muted">{c.recorte}</div>}
                  <div className="mt-1 flex flex-wrap gap-1.5">
                    {c.numeros!.map((n) => (
                      <span key={n.rotulo} className="rounded-lg bg-white px-2 py-1 text-[12px] ring-1 ring-line">
                        <b className="tabular text-purple-900">{valor(n)}</b> <span className="text-ink-2">{n.rotulo}</span>
                      </span>
                    ))}
                  </div>
                </div>
              ))}
              <div className="mt-2 flex flex-wrap items-center gap-2">
                <Badge tone={t.r.modo === 'CLAUDE' ? 'purple' : 'gray'}>{t.r.modo === 'CLAUDE' ? 'Claude Opus 5.5' : 'Regras do IARA'}</Badge>
                <button type="button" onClick={() => falar(t.r!.resposta)} className="inline-flex items-center gap-1 text-[12px] font-semibold text-purple-700">
                  <Volume2 className="size-3.5" />Ouvir
                </button>
              </div>
              {t.r.aviso && <p className="mt-1 text-[12px] text-amber-800">{t.r.aviso}</p>}
            </>
          )}
        </div>
      </div>
    </div>
  );
}

type Conexao = { id: string; rotulo: string; prefixo: string; criada_em: string; criada_por: string | null; ultimo_uso_em: string | null; usos: number; revogada_em: string | null };

/** Conexão permanente: o Prefeito liga o assistente dele (Claude no celular, no computador ou no navegador) às mesmas consultas
 * do Oráculo, por MCP, com uma chave que vale até ser revogada. A chave aparece uma vez só. */
function Mcp() {
  const lista = useRpc<Conexao[]>('oraculo_conexoes', {}, { refetchInterval: 20_000, refetchOnWindowFocus: true });
  const criar = useRpcMutation<{ rotulo: string }, { id: string; rotulo: string; chave: string }>('oraculo_conexao_criar', ['oraculo_conexoes']);
  const revogar = useRpcMutation('oraculo_conexao_revogar', ['oraculo_conexoes']);
  const [rotulo, setRotulo] = useState('Claude do Prefeito');
  const [nova, setNova] = useState<{ rotulo: string; chave: string } | null>(null);
  const [copiado, setCopiado] = useState<string | null>(null);
  const copiar = async (o: string, v: string) => {
    try { await navigator.clipboard.writeText(v); setCopiado(o); setTimeout(() => setCopiado(null), 2000); } catch { /* sem permissão */ }
  };
  const ativas = (lista.data ?? []).filter((c) => !c.revogada_em);
  return (
    <Section title="Conexão permanente (MCP)">
      <Card className="space-y-3 p-3 text-[13px] text-ink-2">
        <p className="flex items-start gap-1.5"><PlugZap className="mt-0.5 size-4 shrink-0 text-purple-700" />
          Ligue o seu assistente (Claude no celular, no computador ou no navegador) às consultas do Oráculo. A conexão não cai com a sessão: vale até você revogar.</p>

        {nova ? (
          <div className="space-y-2 rounded-xl bg-purple-50 p-3 ring-1 ring-purple-200">
            <p className="font-semibold text-purple-900">Conexão “{nova.rotulo}” criada. Copie agora: o endereço não aparece de novo.</p>
            <code className="block break-all rounded-lg bg-white px-2 py-1.5 text-[12px] ring-1 ring-line">{`${API_URL}/mcp/${nova.chave}`}</code>
            <Button size="sm" icon={Copy} onClick={() => copiar('url', `${API_URL}/mcp/${nova.chave}`)}>{copiado === 'url' ? 'Copiado' : 'Copiar endereço'}</Button>
            <ol className="list-decimal space-y-1 pl-5">
              <li>No Claude (claude.ai), abra <b>Personalizar › Conectores</b> e toque em <b>Adicionar conector personalizado</b>.</li>
              <li>Cole o endereço, escolha <b>Sem login</b> e confirme. O conector passa a aparecer também no aplicativo do celular e no desktop.</li>
              <li>Na conversa, peça: “Quantas crianças esperam vaga na creche na região do Jardim Alvorada?”</li>
            </ol>
            <p className="text-[12px]">O endereço leva a chave: guarde como uma senha. Se o seu Claude tiver <b>Cabeçalhos da requisição</b>, use o endereço sem a chave
              (<code>{`${API_URL}/mcp`}</code>) e o cabeçalho <code>Authorization: Bearer {nova.chave.slice(0, 13)}…</code>
              <button type="button" className="ml-1 font-semibold text-purple-700" onClick={() => copiar('chave', `Bearer ${nova.chave}`)}>{copiado === 'chave' ? 'copiado' : 'copiar valor'}</button>.</p>
            <Button size="sm" variant="secondary" onClick={() => setNova(null)}>Pronto, já copiei</Button>
          </div>
        ) : (
          <form className="flex items-end gap-2" onSubmit={(e) => { e.preventDefault(); criar.mutate({ rotulo }, { onSuccess: (r) => setNova({ rotulo: r.rotulo, chave: r.chave }) }); }}>
            <div className="flex-1"><Field label="Nome da conexão"><input value={rotulo} onChange={(e) => setRotulo(e.target.value)} maxLength={60} className={inputCls} /></Field></div>
            <Button type="submit" size="sm" icon={KeyRound} loading={criar.isPending} disabled={rotulo.trim().length < 3}>Criar conexão</Button>
          </form>
        )}
        {criar.error && <p role="alert" className="font-semibold text-red-700">{criar.error.message}</p>}

        {ativas.length > 0 && (
          <ul className="divide-y divide-line rounded-xl ring-1 ring-line">
            {ativas.map((c) => (
              <li key={c.id} className="flex items-center gap-2 px-3 py-2">
                <KeyRound className="size-4 shrink-0 text-purple-700" />
                <div className="min-w-0 flex-1">
                  <div className="font-semibold text-ink">{c.rotulo} <span className="font-normal text-muted">· {c.prefixo}…</span></div>
                  <div className="text-[12px] text-muted">
                    Criada em {fmtDateTime(c.criada_em)} · {c.ultimo_uso_em ? `último uso ${fmtDateTime(c.ultimo_uso_em)} (${fmtInt(c.usos)} consultas)` : 'ainda não usada'}
                  </div>
                </div>
                <Button size="sm" variant="ghost" icon={Trash2} loading={revogar.isPending} aria-label={`Revogar ${c.rotulo}`}
                  onClick={() => { if (confirm(`Revogar a conexão “${c.rotulo}”? O assistente deixa de acessar o Oráculo na hora.`)) revogar.mutate({ id: c.id }); }}>
                  <span className="sr-only">Revogar</span>
                </Button>
              </li>
            ))}
          </ul>
        )}
        <p className="text-[12px] text-muted">A conexão só lê números agregados (nenhum dado de pessoa) e cada consulta fica registrada.</p>
      </Card>
    </Section>
  );
}
