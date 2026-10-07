// Inclusão e alteração de servidor (SEDUC na rede; direção na própria unidade).
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router';
import { rpc } from '@/lib/api';
import { useSession } from '@/lib/session';
import { FUNCAO_SERVIDOR } from '@/lib/escola';
import { Button, Field, inputCls } from '@/components/ui';
import { Sheet, useToast } from '@/components/overlays';
import { UnitSelect } from '@/components/escola';
import { useRecarregarArquivos } from '@/components/arquivos';

const VAZIO = { nome: '', funcao: 'PROFESSOR', vinculo: 'Efetivo', matricula: '', cargo: '', ch: '40', admissao: '', escolaridade: '', formacao: '', area: '', situacao: 'ATIVO' };

export function ServidorForm({ open, onClose, servidor }: { open: boolean; onClose: () => void; servidor?: any }) {
  const { me } = useSession();
  const toast = useToast();
  const navigate = useNavigate();
  const recarregar = useRecarregarArquivos();
  const [f, setF] = useState<Record<string, string>>(VAZIO);
  const [unit, setUnit] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    if (!open) return;
    setF(servidor ? {
      nome: servidor.nome ?? '', funcao: servidor.funcao ?? 'PROFESSOR', vinculo: servidor.vinculo ?? '', matricula: servidor.matricula ?? '', cargo: servidor.cargo ?? '',
      ch: servidor.ch ? String(servidor.ch) : '', admissao: servidor.admissao ?? '', escolaridade: servidor.escolaridade ?? '', formacao: servidor.formacao ?? '',
      area: servidor.area ?? '', situacao: servidor.situacao ?? 'ATIVO',
    } : VAZIO);
    setUnit(servidor?.unit_id ?? me?.unit?.id ?? null);
  }, [open, servidor, me?.unit?.id]);
  const set = (k: string) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });
  const salvar = async () => {
    setBusy(true);
    try {
      const r = await rpc<any>('pessoal_salvar', { ...f, id: servidor?.id ?? null, unit_id: unit });
      toast({ title: servidor ? 'Cadastro atualizado' : 'Servidor incluído', tone: 'success' });
      recarregar();
      onClose();
      if (!servidor) navigate(`/pessoal/${r.id}`);
    } catch (e) {
      toast({ title: 'Não salvo', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} title={servidor ? 'Alterar cadastro do servidor' : 'Novo servidor'} size="lg"
      footer={<Button block size="lg" loading={busy} disabled={f.nome.trim().length < 5 || !unit} onClick={salvar}>Salvar</Button>}>
      <div className="grid grid-cols-1 gap-3 pt-1 sm:grid-cols-2">
        <Field label="Nome completo"><input value={f.nome} onChange={set('nome')} className={inputCls} /></Field>
        <Field label="Matrícula funcional"><input value={f.matricula} onChange={set('matricula')} className={inputCls} /></Field>
        <Field label="Função">
          <select value={f.funcao} onChange={set('funcao')} className={inputCls}>
            {['PROFESSOR', 'EDUCADOR', 'AEE', 'AUXILIAR', 'APOIO', 'ESTAGIARIO', 'SUBSTITUTO'].map((k) => <option key={k} value={k}>{FUNCAO_SERVIDOR[k] ?? (k === 'ESTAGIARIO' ? 'Estagiário(a)' : 'Substituto(a)')}</option>)}
          </select>
        </Field>
        <Field label="Cargo"><input value={f.cargo} onChange={set('cargo')} placeholder="Ex.: Professor(a) de Educação Básica" className={inputCls} /></Field>
        <Field label="Vínculo">
          <select value={f.vinculo} onChange={set('vinculo')} className={inputCls}>
            {['Efetivo', 'PSS/temporário', 'Comissionado', 'Cedido'].map((v) => <option key={v} value={v}>{v}</option>)}
          </select>
        </Field>
        <Field label="Jornada semanal">
          <select value={f.ch} onChange={set('ch')} className={inputCls}>
            <option value="">—</option>{['20', '30', '40'].map((v) => <option key={v} value={v}>{v} horas</option>)}
          </select>
        </Field>
        <Field label="Unidade de lotação">{me?.scope === 'UNIT' ? <input value={me.unit?.name ?? ''} disabled className={inputCls} /> : <UnitSelect value={unit} onChange={setUnit} todas={null} className="h-12 w-full" />}</Field>
        <Field label="Admissão"><input type="date" value={f.admissao} onChange={set('admissao')} className={inputCls} /></Field>
        <Field label="Escolaridade">
          <select value={f.escolaridade} onChange={set('escolaridade')} className={inputCls}>
            <option value="">—</option>{['Médio', 'Superior', 'Pós-graduação', 'Mestrado', 'Doutorado'].map((v) => <option key={v} value={v}>{v}</option>)}
          </select>
        </Field>
        <Field label="Formação"><input value={f.formacao} onChange={set('formacao')} placeholder="Ex.: Pedagogia" className={inputCls} /></Field>
        <Field label="Área de atuação"><input value={f.area} onChange={set('area')} placeholder="Ex.: Anos iniciais, Educação Física" className={inputCls} /></Field>
        <Field label="Situação">
          <select value={f.situacao} onChange={set('situacao')} className={inputCls}>
            {[['ATIVO', 'Em exercício'], ['LICENCA', 'Licença'], ['AFASTADO', 'Afastado'], ['DESLIGADO', 'Desligado']].map(([v, l]) => <option key={v} value={v}>{l}</option>)}
          </select>
        </Field>
      </div>
    </Sheet>
  );
}
