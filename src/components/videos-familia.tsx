import { useEffect, useState } from 'react';
import { Link } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import clsx from 'clsx';
import { Film, Plus, Trash2, Upload } from 'lucide-react';
import { useRpc, useRpcMutation } from '@/lib/hooks';
import { fmtDate, fmtInt } from '@/lib/format';
import { CATEGORIAS_VIDEO, LIMITE_VIDEO, duracaoDoVideo, enviarVideoFamilia, fmtDuracao, youtubeId, type VideoFamilia } from '@/lib/iaraflix';
import { Badge, Button, Card, ErrorState, Field, Segmented, SkeletonList, inputCls } from '@/components/ui';
import { Tabela, TCabecalho, TCelula, TLinha } from '@/components/tabela';
import { Sheet, useConfirm, useToast } from '@/components/overlays';

type FormVideo = {
  id: string | null; titulo: string; descricao: string; categoria: string; fonte: 'YOUTUBE' | 'ARQUIVO'; youtube: string;
  situacao: 'RASCUNHO' | 'PUBLICADO'; destaque: boolean; ordem: string; tem_arquivo: boolean; duracao_s: number | null;
};
const VAZIO: FormVideo = {
  id: null, titulo: '', descricao: '', categoria: 'TUTORIAL', fonte: 'YOUTUBE', youtube: '', situacao: 'RASCUNHO', destaque: false, ordem: '', tem_arquivo: false, duracao_s: null,
};
const nomeCategoria = (c: string) => CATEGORIAS_VIDEO.find((x) => x.codigo === c)?.nome ?? c;
const durTxt = (s: number | null) => (s == null ? '' : s < 60 ? `${s} s` : fmtDuracao(s));

/** Gestão dos vídeos públicos para as famílias (aba do IARAFLIX › Gestão): link do YouTube ou arquivo enviado. */
export function VideosFamiliaGestao() {
  const q = useRpc<{ videos: VideoFamilia[] }>('videos_familia_lista', { gestao: true }, { staleTime: 0 });
  const [aberto, setAberto] = useState<FormVideo | null>(null);
  if (q.isLoading) return <SkeletonList rows={5} />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => q.refetch()} />;
  const vids = q.data!.videos;
  const abrir = (v: VideoFamilia) => setAberto({
    id: v.id, titulo: v.titulo, descricao: v.descricao ?? '', categoria: v.categoria, fonte: v.fonte, youtube: v.youtube_id ? `https://youtu.be/${v.youtube_id}` : '',
    situacao: v.situacao ?? 'RASCUNHO', destaque: v.destaque, ordem: String(v.ordem ?? ''), tem_arquivo: v.tem_arquivo, duracao_s: v.duracao_s,
  });
  return (
    <>
      <div className="mb-3 flex flex-wrap items-center gap-3">
        <p className="min-w-0 flex-1 text-[13.5px] text-muted">
          Vídeos públicos para as famílias: no portal (em <Link to="/videos" className="font-semibold text-purple-700">Vídeos</Link>, sem login) e pela IARA.
          Cole o link do YouTube (vídeo público ou não listado do canal oficial) ou envie o arquivo.
        </p>
        <Button icon={Plus} variant="purple" size="sm" onClick={() => setAberto({ ...VAZIO })}>Novo vídeo</Button>
      </div>
      <Card className="overflow-hidden">
        <Tabela colunas="minmax(0,1fr) minmax(0,13rem) 6.5rem 7rem 5.5rem 7rem" largura={820} rotulo="Vídeos para as famílias">
          <TCabecalho><span>Vídeo</span><span>Assunto</span><span>Fonte</span><span>Situação</span><span>Vistas</span><span>Atualizado</span></TCabecalho>
          {vids.map((v) => (
            <TLinha key={v.id} onClick={() => abrir(v)} rotulo={`Editar: ${v.titulo}`}>
              <TCelula titulo={v.titulo} className="font-semibold text-ink">{v.destaque ? '★ ' : ''}{v.titulo}</TCelula>
              <TCelula titulo={nomeCategoria(v.categoria)} className="text-muted">{nomeCategoria(v.categoria)}</TCelula>
              <TCelula className="text-[13px]">{v.fonte === 'YOUTUBE' ? 'YouTube' : v.tem_arquivo ? `Arquivo ${durTxt(v.duracao_s)}` : <span className="text-amber-700">sem arquivo</span>}</TCelula>
              <TCelula livre>{v.situacao === 'PUBLICADO' ? <Badge tone="green">Publicado</Badge> : <Badge tone="amber">Rascunho</Badge>}</TCelula>
              <TCelula className="tabular text-muted">{fmtInt(v.visualizacoes ?? 0)}</TCelula>
              <TCelula className="text-[13px] text-muted" titulo={v.atualizado_por ?? undefined}>{fmtDate(v.atualizado_em)}</TCelula>
            </TLinha>
          ))}
          {vids.length === 0 && <div className="p-4 text-sm text-muted">Nenhum vídeo ainda. Toque em "Novo vídeo".</div>}
        </Tabela>
      </Card>
      <VideoEditor form={aberto} setForm={setAberto} />
    </>
  );
}

function VideoEditor({ form, setForm }: { form: FormVideo | null; setForm: (f: FormVideo | null) => void }) {
  const toast = useToast();
  const confirm = useConfirm();
  const qc = useQueryClient();
  const salvar = useRpcMutation('videos_familia_salvar', ['videos_familia_lista', 'videos_familia_ver']);
  const [arquivo, setArquivo] = useState<File | null>(null);
  const [pct, setPct] = useState<number | null>(null);
  useEffect(() => { setArquivo(null); setPct(null); }, [form?.id]);
  if (!form) return null;
  const f = form;
  const set = (x: Partial<FormVideo>) => setForm({ ...f, ...x });
  const yt = f.fonte === 'YOUTUBE' ? youtubeId(f.youtube) : null;
  const grande = !!arquivo && arquivo.size > LIMITE_VIDEO;

  const gravar = async (excluir = false) => {
    if (excluir && !(await confirm({ title: 'Excluir este vídeo?', body: 'Ele sai do portal e da IARA. O arquivo enviado, se houver, é apagado.', confirm: 'Excluir', tone: 'danger' }))) return;
    try {
      const r = await salvar.mutateAsync({
        id: f.id, titulo: f.titulo, descricao: f.descricao, categoria: f.categoria, fonte: f.fonte, youtube: f.youtube,
        situacao: f.situacao, destaque: f.destaque, ordem: f.ordem || null, excluir,
      });
      toast({ title: excluir ? 'Vídeo excluído' : f.situacao === 'PUBLICADO' ? 'Vídeo publicado' : 'Rascunho salvo', tone: 'success' });
      if (excluir || f.fonte === 'YOUTUBE' || f.tem_arquivo) setForm(null);
      else setForm({ ...f, id: r.id }); // vídeo de arquivo: a folha fica aberta para enviar o arquivo
    } catch (e) {
      toast({ title: 'Não foi possível salvar', description: (e as Error).message, tone: 'error' });
    }
  };

  const enviar = async () => {
    if (!f.id || !arquivo) return;
    setPct(0);
    try {
      const duracao = await duracaoDoVideo(arquivo);
      await enviarVideoFamilia({ id: f.id, arquivo, duracao_s: duracao }, setPct);
      toast({ title: 'Arquivo enviado', description: 'Marque "Publicado" e salve para as famílias verem.', tone: 'success' });
      setArquivo(null);
      setForm({ ...f, tem_arquivo: true, duracao_s: duracao });
      qc.invalidateQueries({ queryKey: ['videos_familia_lista'] });
    } catch (e) {
      toast({ title: 'O envio não foi concluído', description: (e as Error).message, tone: 'error' });
    } finally {
      setPct(null);
    }
  };

  return (
    <Sheet open onClose={() => setForm(null)} size="lg" title={f.id ? 'Editar vídeo' : 'Novo vídeo para as famílias'}
      subtitle="Público: aparece no portal, sem login, e a IARA indica"
      footer={<div className="flex justify-between gap-2">
        {f.id ? <Button variant="ghost" className="text-red-700" icon={Trash2} onClick={() => gravar(true)}>Excluir</Button> : <span />}
        <div className="flex items-center gap-2">
          {f.id && <Link to={`/videos/${f.id}`} className="px-2 text-sm font-semibold text-purple-700">Ver como a família vê</Link>}
          <Button variant="purple" loading={salvar.isPending} onClick={() => gravar()}>Salvar</Button>
        </div>
      </div>}>
      <div className="space-y-4">
        <Field label="Título"><input className={inputCls} value={f.titulo} onChange={(e) => set({ titulo: e.target.value })} data-autofocus /></Field>
        <Field label="Descrição" hint="Uma ou duas frases: o que a família aprende com o vídeo.">
          <textarea className={clsx(inputCls, 'h-20 py-3')} value={f.descricao} onChange={(e) => set({ descricao: e.target.value })} />
        </Field>
        <Field label="Assunto">
          <select className={inputCls} value={f.categoria} onChange={(e) => set({ categoria: e.target.value })}>
            {CATEGORIAS_VIDEO.map((c) => <option key={c.codigo} value={c.codigo}>{c.nome}</option>)}
          </select>
        </Field>
        <div>
          <span className="mb-1 block text-[13px] font-semibold text-ink-2">De onde vem o vídeo</span>
          <Segmented value={f.fonte} onChange={(v) => set({ fonte: v })} items={[{ value: 'YOUTUBE', label: 'YouTube' }, { value: 'ARQUIVO', label: 'Arquivo enviado' }]} />
        </div>
        {f.fonte === 'YOUTUBE' ? (
          <Field label="Link do vídeo no YouTube" hint="Vídeo público ou não listado do canal oficial. Vídeo privado não abre para as famílias."
            error={f.youtube && !yt ? 'Não reconheci este link do YouTube.' : null}>
            <input className={inputCls} value={f.youtube} placeholder="https://youtu.be/..." onChange={(e) => set({ youtube: e.target.value })} />
          </Field>
        ) : (
          <div className="rounded-2xl bg-slate-50 p-4 ring-1 ring-line">
            <div className="flex items-center gap-2 font-bold text-ink"><Film className="size-4 text-purple-700" aria-hidden />Arquivo do vídeo</div>
            {!f.id ? <p className="mt-1 text-[13.5px] text-muted">Salve o vídeo primeiro (como rascunho); depois envie o arquivo aqui.</p> : (
              <>
                <p className="mt-1 text-[13.5px] text-ink-2">{f.tem_arquivo ? `Arquivo enviado${f.duracao_s ? ` (${durTxt(f.duracao_s)})` : ''}. Pode trocar.` : 'Ainda sem arquivo.'}</p>
                <input type="file" accept="video/mp4,video/webm"
                  className="mt-2 block w-full text-sm file:mr-3 file:rounded-xl file:border-0 file:bg-purple-100 file:px-3 file:py-2 file:font-semibold file:text-purple-800"
                  onChange={(e) => setArquivo(e.target.files?.[0] ?? null)} />
                {arquivo && (
                  <div className="mt-2 space-y-2">
                    <p className={clsx('text-[13px]', grande ? 'font-semibold text-red-700' : 'text-muted')}>
                      {arquivo.name} · {(arquivo.size / 1048576).toFixed(1).replace('.', ',')} MB{grande ? ' — passa de 50 MB: exporte em 720p, perto de 1 Mbps.' : ''}
                    </p>
                    <Button icon={Upload} size="sm" variant="purple" disabled={grande || pct != null} loading={pct != null} onClick={enviar}>
                      {pct != null ? `Enviando… ${pct}%` : 'Enviar o arquivo'}
                    </Button>
                    {pct != null && <div className="h-1.5 overflow-hidden rounded-full bg-slate-200"><div className="h-full bg-purple-500 transition-all" style={{ width: `${pct}%` }} /></div>}
                  </div>
                )}
              </>
            )}
          </div>
        )}
        <div className="flex flex-wrap items-end gap-4">
          <div>
            <span className="mb-1 block text-[13px] font-semibold text-ink-2">Situação</span>
            <Segmented value={f.situacao} onChange={(v) => set({ situacao: v })} items={[{ value: 'PUBLICADO', label: 'Publicado' }, { value: 'RASCUNHO', label: 'Rascunho' }]} />
          </div>
          <Field label="Ordem"><input className={clsx(inputCls, 'w-24')} inputMode="numeric" value={f.ordem} onChange={(e) => set({ ordem: e.target.value.replace(/\D/g, '') })} /></Field>
          <label className="flex h-12 items-center gap-2 text-[14px] text-ink">
            <input type="checkbox" className="size-4 accent-purple-700" checked={f.destaque} onChange={(e) => set({ destaque: e.target.checked })} />Em destaque
          </label>
        </div>
      </div>
    </Sheet>
  );
}
