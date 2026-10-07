import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Archive, ArchiveRestore, Megaphone, Plus, Send, Trash2 } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtInt } from '@/lib/format';
import { FAIXA_CARDAPIO, PUBLICO_MURAL, TIPO_MURAL, hojeISO } from '@/lib/escola';
import { Button, Card, Chip, EmptyState, ErrorState, Field, PageHeader, Segmented, Simulado, SkeletonList, inputCls } from '@/components/ui';
import { Sheet, useConfirm, useToast } from '@/components/overlays';
import { PublicacaoCard } from '@/components/escola';

/** Mural: avisos, comunicados, eventos e enquetes da rede e da unidade, com o alcance de cada publicação. */
export default function Mural() {
  const { me } = useSession();
  const [arq, setArq] = useState(false);
  const [tipo, setTipo] = useState<string>('');
  const [novo, setNovo] = useState(false);
  const res = useRpc<any>('mural_feed', { arquivados: arq });
  const qc = useQueryClient();
  const toast = useToast();
  const confirm = useConfirm();
  const itens = ((res.data?.publicacoes ?? []) as any[]).filter((p) => !tipo || p.tipo === tipo);

  const arquivar = async (p: any) => {
    const ok = await confirm({ title: p.situacao === 'ARQUIVADO' ? 'Voltar a publicar?' : 'Arquivar a publicação?', body: p.situacao === 'ARQUIVADO' ? 'Ela volta a aparecer para as famílias.' : 'Ela sai do portal e da IARA; as leituras ficam registradas.', confirm: p.situacao === 'ARQUIVADO' ? 'Publicar' : 'Arquivar' });
    if (!ok) return;
    try {
      await rpc('mural_arquivar', { id: p.id });
      qc.invalidateQueries({ queryKey: ['mural_feed'] });
    } catch (e) {
      toast({ title: 'Não foi possível', description: (e as Error).message, tone: 'error' });
    }
  };

  return (
    <div>
      <PageHeader eyebrow={res.data?.escopo === 'UNIDADE' ? me?.unit?.name : 'SEDUC · comunicação'}
        title={<span className="inline-flex items-center gap-2">Mural<Simulado detail="Publicações e leituras de demonstração." /></span>}
        subtitle="O que a rede e a escola publicam chega ao portal da família e à IARA no WhatsApp. A família confirma a ciência quando o aviso pede."
        actions={res.data?.pode_publicar ? <Button icon={Plus} onClick={() => setNovo(true)}>Publicar</Button> : undefined} />
      <div className="mb-3 flex flex-wrap items-center gap-2">
        <Chip active={!tipo} onClick={() => setTipo('')}>Tudo</Chip>
        {Object.entries(TIPO_MURAL).map(([k, v]) => <Chip key={k} active={tipo === k} onClick={() => setTipo(k)}>{v.label}</Chip>)}
        <label className="ml-auto flex items-center gap-2 text-[13px] font-semibold text-muted">
          <input type="checkbox" checked={arq} onChange={(e) => setArq(e.target.checked)} className="size-4 accent-purple-700" />Mostrar arquivados
        </label>
      </div>
      {res.isLoading ? <SkeletonList rows={4} /> : res.error ? <ErrorState error={res.error} onRetry={() => res.refetch()} /> : (
        <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
          {itens.map((p) => (
            <PublicacaoCard key={p.id} p={p} acoes={p.pode_editar ? (
              <Button size="sm" variant="secondary" icon={p.situacao === 'ARQUIVADO' ? ArchiveRestore : Archive} onClick={() => arquivar(p)}>
                {p.situacao === 'ARQUIVADO' ? 'Publicar de novo' : 'Arquivar'}
              </Button>
            ) : undefined} />
          ))}
          {!itens.length && <Card className="lg:col-span-2"><EmptyState compact title="Nada publicado" /></Card>}
        </div>
      )}
      <NovaPublicacao open={novo} onClose={() => setNovo(false)} unidade={res.data?.escopo === 'UNIDADE'} />
    </div>
  );
}

function NovaPublicacao({ open, onClose, unidade }: { open: boolean; onClose: () => void; unidade: boolean }) {
  const qc = useQueryClient();
  const toast = useToast();
  const [tipo, setTipo] = useState('AVISO');
  const [titulo, setTitulo] = useState('');
  const [texto, setTexto] = useState('');
  const [publico, setPublico] = useState('FAMILIAS');
  const [faixas, setFaixas] = useState<string[]>([]);
  const [conf, setConf] = useState(false);
  const [dataEv, setDataEv] = useState('');
  const [reuniao, setReuniao] = useState(false);
  const [opcoes, setOpcoes] = useState<string[]>(['', '']);
  const [busy, setBusy] = useState(false);
  const limpar = () => { setTitulo(''); setTexto(''); setFaixas([]); setConf(false); setDataEv(''); setReuniao(false); setOpcoes(['', '']); };
  const enviar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('mural_publicar', {
        tipo, titulo, texto, publico, faixas, exige_confirmacao: conf, data_evento: dataEv || null, reuniao_pais: reuniao,
        opcoes: tipo === 'ENQUETE' ? opcoes.filter((o) => o.trim()) : [],
      });
      toast({ title: 'Publicado', description: r.destinatarios ? `Chega a ${fmtInt(r.destinatarios)} famílias pelo portal e pela IARA.` : 'Visível no mural dos profissionais.', tone: 'success' });
      ['mural_feed', 'calendario'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
      limpar();
      onClose();
    } catch (e) {
      toast({ title: 'Não publicado', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} title="Nova publicação" subtitle={unidade ? 'Para as famílias e a equipe da sua unidade.' : 'Para toda a rede.'} size="lg"
      footer={<Button block size="lg" icon={Send} loading={busy} disabled={titulo.trim().length < 5 || texto.trim().length < 10} onClick={enviar}>Publicar</Button>}>
      <div className="space-y-4 pt-1">
        <Segmented value={tipo} onChange={setTipo} items={Object.entries(TIPO_MURAL).map(([value, v]) => ({ value, label: v.label }))} />
        <Field label="Título"><input value={titulo} onChange={(e) => setTitulo(e.target.value)} maxLength={120} className={inputCls} /></Field>
        <Field label="Texto" hint="Linguagem simples: a família lê no celular e a IARA lê em voz alta para quem precisa.">
          <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={4} maxLength={4000} className={`${inputCls} h-auto py-3`} />
        </Field>
        {tipo === 'ENQUETE' ? (
          <Field label="Opções (2 a 6)">
            <div className="space-y-2">
              {opcoes.map((o, i) => (
                <div key={i} className="flex gap-2">
                  <input value={o} onChange={(e) => setOpcoes(opcoes.map((x, j) => (j === i ? e.target.value : x)))} placeholder={`Opção ${i + 1}`} className={inputCls} />
                  {opcoes.length > 2 && <Button variant="secondary" icon={Trash2} aria-label="Remover opção" onClick={() => setOpcoes(opcoes.filter((_, j) => j !== i))} />}
                </div>
              ))}
              {opcoes.length < 6 && <Button size="sm" variant="ghost" icon={Plus} onClick={() => setOpcoes([...opcoes, ''])}>Opção</Button>}
            </div>
          </Field>
        ) : (
          <Field label="Público">
            <select value={publico} onChange={(e) => setPublico(e.target.value)} className={inputCls}>
              {Object.entries(PUBLICO_MURAL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </Field>
        )}
        <Field label="Só para algumas etapas (opcional)">
          <div className="flex flex-wrap gap-2">
            {Object.entries(FAIXA_CARDAPIO).map(([k, v]) => (
              <Chip key={k} active={faixas.includes(k)} onClick={() => setFaixas(faixas.includes(k) ? faixas.filter((x) => x !== k) : [...faixas, k])}>{v}</Chip>
            ))}
          </div>
        </Field>
        <Field label="Data do evento (vai para o calendário)">
          <input type="date" min={hojeISO()} value={dataEv} onChange={(e) => setDataEv(e.target.value)} className={inputCls} />
        </Field>
        {dataEv && (
          <label className="flex items-center gap-2 text-[14px]"><input type="checkbox" checked={reuniao} onChange={(e) => setReuniao(e.target.checked)} className="size-5 accent-purple-700" />É reunião de pais e responsáveis</label>
        )}
        {tipo !== 'ENQUETE' && (
          <label className="flex items-start gap-3 rounded-2xl bg-purple-50 p-3 ring-1 ring-purple-200">
            <input type="checkbox" checked={conf} onChange={(e) => setConf(e.target.checked)} className="mt-1 size-5 accent-purple-700" />
            <span className="text-[13.5px]"><b>Pedir confirmação de ciência</b><br /><span className="text-muted">A família toca em “Estou ciente” no portal ou responde à IARA. Você vê quantas confirmaram.</span></span>
          </label>
        )}
        <p className="flex items-center gap-2 text-[12.5px] text-muted"><Megaphone className="size-4" />Não publique dados de alunos: o mural é coletivo.</p>
      </div>
    </Sheet>
  );
}
