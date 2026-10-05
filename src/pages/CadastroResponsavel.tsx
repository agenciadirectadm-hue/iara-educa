import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router';
import clsx from 'clsx';
import { Accessibility, Baby, Briefcase, FileText, Home, IdCard, Link2, Pencil, Phone, Plus, ShieldCheck, Trash2, UserMinus, Users } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate } from '@/lib/format';
import {
  BENEFICIOS, CANAL, ESCOLARIDADE, ESTADO_CIVIL, IDIOMAS, NACIONALIDADE, PARENTESCO, PARENTESCO_DOMICILIO, SEXO, TRABALHO, cpfValido, enderecoDoServidor,
  enderecoVazio, fmtMoeda, mascaraCpf, mascaraNis, mascaraTelefone, nisValido, soDigitos, type Endereco,
} from '@/lib/cadastro';
import { Avatar, Button, ButtonLink, Card, ErrorState, PageHeader, SkeletonList, inputCls } from '@/components/ui';
import { Crumbs } from '@/components/Crumbs';
import { Sheet, useConfirm, useToast } from '@/components/overlays';
import { Alternar, AvisoRestrito, BarraSalvar, Campo, Escolha, Secao, Selecao, Texto } from '@/components/cadastro';
import EnderecoEditor from '@/components/EnderecoEditor';
import { BuscarPessoaSheet, EncerrarVinculoSheet, LinhaVinculo, TabelaVinculos, VinculoSheet, useRecarregarCadastros, type Vinculo } from '@/components/Vinculos';
import { TCabecalho, TCelula, TLinha, Tabela } from '@/components/tabela';

type Form = {
  nome: string; nome_social: string; nascimento: string; sexo: string; nacionalidade: string; estado_civil: string; escolaridade: string; idioma: string;
  cpf: string; rg: string; nis: string; telefone: string; whatsapp: string; telefone_2: string; email: string; canal_preferido: string;
  ocupacao: string; situacao_trabalho: string; renda_individual: string; renda_familiar: string; pessoas_domicilio: string;
  cadunico: boolean; beneficios: string[]; mae_solo: boolean; acessibilidade: string; lgpd: boolean; aceita_whatsapp: boolean;
};
const formVazio = (): Form => ({
  nome: '', nome_social: '', nascimento: '', sexo: '', nacionalidade: 'BRASILEIRA', estado_civil: '', escolaridade: '', idioma: 'Português',
  cpf: '', rg: '', nis: '', telefone: '', whatsapp: '', telefone_2: '', email: '', canal_preferido: 'WHATSAPP', ocupacao: '', situacao_trabalho: '',
  renda_individual: '', renda_familiar: '', pessoas_domicilio: '', cadunico: false, beneficios: [], mae_solo: false, acessibilidade: '', lgpd: true, aceita_whatsapp: true,
});
function doServidor(r: any): Form {
  const num = (v: unknown) => (v == null ? '' : String(v));
  return {
    nome: r.nome ?? '', nome_social: r.nome_social ?? '', nascimento: r.nascimento ?? '', sexo: r.sexo ?? '', nacionalidade: r.nacionalidade ?? 'BRASILEIRA',
    estado_civil: r.estado_civil ?? '', escolaridade: r.escolaridade ?? '', idioma: r.idioma ?? 'Português', cpf: r.cpf ?? '', rg: r.rg ?? '', nis: r.nis ?? '',
    telefone: r.telefone ?? '', whatsapp: r.whatsapp ?? '', telefone_2: r.telefone_2 ?? '', email: r.email ?? '', canal_preferido: r.canal_preferido ?? 'WHATSAPP',
    ocupacao: r.ocupacao ?? '', situacao_trabalho: r.situacao_trabalho ?? '', renda_individual: num(r.renda_individual), renda_familiar: num(r.renda_familiar),
    pessoas_domicilio: num(r.pessoas_domicilio), cadunico: !!r.cadunico, beneficios: Array.isArray(r.beneficios) ? r.beneficios : [], mae_solo: !!r.mae_solo,
    acessibilidade: r.acessibilidade ?? '', lgpd: r.consentimento?.lgpd_ciencia !== false, aceita_whatsapp: r.consentimento?.whatsapp !== false,
  };
}

export default function CadastroResponsavel() {
  const { id } = useParams();
  const [sp] = useSearchParams();
  const criancaParam = sp.get('crianca');
  const cad = useRpc<any>('responsavel_cadastro', { id }, { enabled: !!id, refetchOnWindowFocus: false });
  const crianca = useRpc<any>('aluno_cadastro', { id: criancaParam }, { enabled: !id && !!criancaParam, refetchOnWindowFocus: false });
  if (id && cad.isLoading) return <SkeletonList rows={6} />;
  if (id && cad.error) return <ErrorState error={cad.error} onRetry={() => cad.refetch()} />;
  if (!id && criancaParam && crianca.isLoading) return <SkeletonList rows={6} />;
  return <FormularioResponsavel key={id ?? 'novo'} cad={id ? cad.data : null} crianca={!id ? crianca.data ?? null : null} />;
}

function FormularioResponsavel({ cad, crianca }: { cad: any | null; crianca: any | null }) {
  const novo = !cad;
  const nav = useNavigate();
  const toast = useToast();
  const confirm = useConfirm();
  const { can } = useSession();
  const recarregar = useRecarregarCadastros();
  const [f, setF] = useState<Form>(() => (cad ? doServidor(cad.responsavel) : formVazio()));
  const set = (patch: Partial<Form>) => setF((x) => ({ ...x, ...patch }));
  const [end, setEnd] = useState<Endereco>(() => enderecoDoServidor(cad?.endereco) ?? enderecoDoServidor(crianca?.endereco) ?? enderecoVazio());
  // responsável novo a partir de uma criança: começa no endereço dela (mesmo registro, se não for alterado)
  const [endAlterado, setEndAlterado] = useState(false);
  const [aplicarCriancas, setAplicarCriancas] = useState(true);
  const [parentesco, setParentesco] = useState('MAE');
  const [erros, setErros] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [dups, setDups] = useState<any[] | null>(null);
  const [buscarCrianca, setBuscarCrianca] = useState(false);
  const [vinc, setVinc] = useState<null | { id: string; nome: string; inicial?: Partial<Vinculo> }>(null);
  const [encerrar, setEncerrar] = useState<null | { id: string; nome: string }>(null);
  const [membro, setMembro] = useState<any | null>(null);
  const contatosMasc = !!cad?.contatos_mascarados;
  const podeEditar = novo ? can('guardians.write') : !!cad.permissoes?.editar;
  const criancas = (cad?.criancas ?? []) as any[];
  const ativas = criancas.filter((c) => !c.ate);
  const juntas = ativas.filter((c) => c.mesmo_endereco);
  const pendencias = useMemo(() => {
    const p: string[] = [];
    if (!soDigitos(f.cpf) && !/[•*]/.test(f.cpf)) p.push('CPF');
    if (!f.nascimento) p.push('Data de nascimento');
    if (!soDigitos(f.telefone) && !soDigitos(f.whatsapp) && !/[•*]/.test(f.telefone + f.whatsapp)) p.push('Telefone');
    if (!(end.lat != null && end.logradouro.trim())) p.push('Endereço');
    if (f.cadunico && !soDigitos(f.nis) && !/[•*]/.test(f.nis)) p.push('NIS (CadÚnico)');
    return p;
  }, [f, end]);
  const pct = (100 * (5 - pendencias.length)) / 5;
  const pessoas = Number(f.pessoas_domicilio) || cad?.pessoas_domicilio || 0;
  const perCapita = f.renda_familiar && pessoas ? Number(f.renda_familiar) / pessoas : null;

  const validar = () => {
    const e: Record<string, string> = {};
    const nome = f.nome.trim().replace(/\s+/g, ' ');
    if (nome.length < 5 || !nome.includes(' ')) e.nome = 'Informe o nome completo (nome e sobrenome).';
    if (f.nascimento) {
      const anos = (Date.now() - new Date(`${f.nascimento}T12:00:00`).getTime()) / (365.25 * 86_400_000);
      if (anos < 12 || anos > 110) e.nascimento = 'Confira a data de nascimento.';
    }
    if (!contatosMasc) {
      if (soDigitos(f.cpf) && soDigitos(f.cpf) !== soDigitos(cad?.responsavel?.cpf) && !cpfValido(f.cpf)) e.cpf = 'CPF inválido: os dígitos verificadores não conferem.';
      if (soDigitos(f.nis) && soDigitos(f.nis) !== soDigitos(cad?.responsavel?.nis) && !nisValido(f.nis)) e.nis = 'NIS inválido: confira os 11 dígitos.';
      if (f.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(f.email.trim())) e.email = 'E-mail inválido.';
      for (const k of ['telefone', 'whatsapp', 'telefone_2'] as const) {
        const d = soDigitos(f[k]);
        if (d && (d.length < 10 || d.length > 11)) e[k] = 'Telefone com DDD (10 ou 11 dígitos).';
      }
    }
    if ((novo || endAlterado) && (end.logradouro.trim() || end.lat != null)) {
      if (!end.logradouro.trim()) e.endereco = 'Informe o logradouro.';
      else if (end.lat == null) e.endereco = 'Marque a casa no mapa (ou localize pelo CEP).';
    }
    setErros(e);
    return e;
  };

  const salvar = async (forcar = false) => {
    const e = validar();
    if (Object.keys(e).length) {
      toast({ title: 'Confira os campos destacados', description: Object.values(e)[0], tone: 'error' });
      document.querySelector(`[data-campo="${Object.keys(e)[0]}"]`)?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      return;
    }
    setBusy(true);
    try {
      const p: Record<string, unknown> = {
        id: cad?.responsavel?.id, nome: f.nome.trim().replace(/\s+/g, ' '), nome_social: f.nome_social, nascimento: f.nascimento || null, sexo: f.sexo || null,
        nacionalidade: f.nacionalidade, estado_civil: f.estado_civil || null, escolaridade: f.escolaridade || null, idioma: f.idioma, canal_preferido: f.canal_preferido,
        ocupacao: f.ocupacao, situacao_trabalho: f.situacao_trabalho || null, renda_individual: f.renda_individual === '' ? null : Number(f.renda_individual),
        renda_familiar: f.renda_familiar === '' ? null : Number(f.renda_familiar), pessoas_domicilio: f.pessoas_domicilio === '' ? null : Number(f.pessoas_domicilio),
        cadunico: f.cadunico, beneficios: f.beneficios, mae_solo: f.mae_solo, acessibilidade: f.acessibilidade,
        consentimento: { lgpd_ciencia: f.lgpd, whatsapp: f.aceita_whatsapp }, forcar,
      };
      if (!contatosMasc) {
        Object.assign(p, {
          cpf: soDigitos(f.cpf), rg: f.rg.trim(), nis: soDigitos(f.nis), telefone: f.telefone.trim(), whatsapp: (f.whatsapp || f.telefone).trim(),
          telefone_2: f.telefone_2.trim(), email: f.email.trim(),
        });
      }
      if (novo && crianca?.endereco && !endAlterado) {
        p.endereco_id = crianca.endereco.id;
      } else if ((novo || endAlterado) && end.lat != null && end.logradouro.trim()) {
        p.endereco = { ...end, cep: soDigitos(end.cep), aplicar_criancas: aplicarCriancas };
      }
      if (novo && crianca) p.crianca = { id: crianca.aluno.id, parentesco };
      const r = await rpc<any>('responsavel_salvar', p);
      if (r.ok === false) {
        setDups(r.duplicados ?? []);
        return;
      }
      recarregar();
      toast({
        title: novo ? 'Responsável cadastrado' : 'Cadastro atualizado', tone: 'success',
        description: r.criancas_mudaram ? `${r.criancas_mudaram} criança(s) mudaram de endereço junto; a fila foi recalculada.` : r.cadastro?.pendencias?.length ? `Ainda falta: ${r.cadastro.pendencias.join(', ')}.` : 'Cadastro completo.',
      });
      nav(novo && crianca ? `/alunos/${crianca.aluno.id}` : `/responsaveis/${r.id}`);
    } catch (err) {
      toast({ title: 'Cadastro não salvo', description: (err as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };

  const removerMembro = async (m: any) => {
    if (!(await confirm({ title: `Remover ${m.nome}?`, body: 'A pessoa deixa de constar na composição familiar.', confirm: 'Remover', tone: 'danger' }))) return;
    try {
      await rpc('domicilio_remover', { id: m.id });
      recarregar();
      toast({ title: 'Removido da composição familiar', tone: 'success' });
    } catch (err) {
      toast({ title: 'Não foi possível remover', description: (err as Error).message, tone: 'error' });
    }
  };

  return (
    <div className="pb-6">
      <Crumbs items={[{ label: 'Responsáveis', to: '/responsaveis' }, ...(novo ? [] : [{ label: cad.responsavel.nome, to: `/responsaveis/${cad.responsavel.id}` }]), { label: novo ? 'Novo cadastro' : 'Cadastro' }]} />
      <PageHeader eyebrow="Cadastro 360º do responsável" title={novo ? 'Novo responsável' : f.nome || 'Responsável'}
        subtitle={novo ? (crianca ? `Será vinculado(a) a ${crianca.aluno.nome}.` : 'Documentos, contatos, trabalho e renda, endereço no mapa e composição familiar. Campos com * são obrigatórios.')
          : `Atualizado em ${fmtDate(cad.responsavel.atualizado_em)}`} />
      {!podeEditar && <AvisoRestrito>Seu perfil pode consultar, mas não alterar o cadastro de responsáveis.</AvisoRestrito>}

      <nav aria-label="Seções do cadastro" className="no-scrollbar -mx-4 mb-3 flex gap-1.5 overflow-x-auto px-4 sm:mx-0 sm:flex-wrap sm:px-0">
        {[['identificacao', 'Identificação'], ['documentos', 'Documentos'], ['contatos', 'Contatos'], ['renda', 'Trabalho e renda'], ['endereco', 'Endereço'],
          ...(novo ? [] : [['criancas', 'Crianças'], ['domicilio', 'Composição familiar']]), ['lgpd', 'Consentimento']].map(([k, l]) => (
          <a key={k} href={`#${k}`} onClick={(e) => { e.preventDefault(); document.getElementById(k)?.scrollIntoView({ behavior: 'smooth' }); }}
            className="inline-flex h-9 shrink-0 items-center rounded-full bg-white px-3.5 text-[13px] font-semibold text-ink-2 ring-1 ring-line hover:bg-purple-50">{l}</a>
        ))}
      </nav>

      <fieldset disabled={!podeEditar} className="space-y-4">
        <Secao id="identificacao" icon={IdCard} titulo="Identificação">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Campo label="Nome completo" obrigatorio erro={erros.nome} className="sm:col-span-2">
              <Texto data-campo="nome" value={f.nome} onChange={(v) => set({ nome: v })} erro={!!erros.nome} autoComplete="off" />
            </Campo>
            <Campo label="Nome social"><Texto value={f.nome_social} onChange={(v) => set({ nome_social: v })} /></Campo>
            <Campo label="Data de nascimento" obrigatorio erro={erros.nascimento}>
              <input data-campo="nascimento" type="date" value={f.nascimento} onChange={(e) => set({ nascimento: e.target.value })} className={clsx(inputCls, erros.nascimento && 'ring-2 ring-red-400')} />
            </Campo>
            <Campo label="Sexo"><Escolha nome="Sexo" value={f.sexo} onChange={(v) => set({ sexo: v })} opcoes={Object.entries(SEXO)} /></Campo>
            <Campo label="Nacionalidade"><Selecao value={f.nacionalidade} onChange={(v) => set({ nacionalidade: v })} opcoes={Object.entries(NACIONALIDADE)} vazio={false} /></Campo>
            <Campo label="Estado civil"><Selecao value={f.estado_civil} onChange={(v) => set({ estado_civil: v })} opcoes={Object.entries(ESTADO_CIVIL)} /></Campo>
            <Campo label="Escolaridade"><Selecao value={f.escolaridade} onChange={(v) => set({ escolaridade: v })} opcoes={ESCOLARIDADE} /></Campo>
            <Campo label="Idioma de preferência" dica="Para avisos e atendimento (ex.: famílias migrantes).">
              <Selecao value={f.idioma} onChange={(v) => set({ idioma: v })} opcoes={IDIOMAS} vazio={false} />
            </Campo>
          </div>
        </Secao>

        <Secao id="documentos" icon={FileText} titulo="Documentos">
          {contatosMasc && <AvisoRestrito>CPF, RG e NIS mascarados para o seu perfil (mínimo privilégio).</AvisoRestrito>}
          <div className={clsx('grid grid-cols-1 gap-3 sm:grid-cols-3', contatosMasc && 'mt-3')}>
            <Campo label="CPF" obrigatorio erro={erros.cpf} dica={soDigitos(f.cpf).length === 11 && !erros.cpf ? (cpfValido(f.cpf) ? 'CPF válido.' : soDigitos(f.cpf) === soDigitos(cad?.responsavel?.cpf) ? 'CPF de demonstração (dígito propositalmente inválido).' : 'Dígitos verificadores não conferem.') : undefined}>
              <Texto data-campo="cpf" value={f.cpf} onChange={(v) => set({ cpf: mascaraCpf(v) })} readOnly={contatosMasc} inputMode="numeric" erro={!!erros.cpf} placeholder="000.000.000-00" />
            </Campo>
            <Campo label="RG"><Texto value={f.rg} onChange={(v) => set({ rg: v })} readOnly={contatosMasc} /></Campo>
            <Campo label="NIS" erro={erros.nis} dica="Obrigatório para famílias no CadÚnico.">
              <Texto data-campo="nis" value={f.nis} onChange={(v) => set({ nis: mascaraNis(v) })} readOnly={contatosMasc} inputMode="numeric" erro={!!erros.nis} />
            </Campo>
          </div>
        </Secao>

        <Secao id="contatos" icon={Phone} titulo="Contatos" descricao="Por onde a família recebe avisos de vaga, oferta e matrícula.">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <Campo label="Telefone principal" obrigatorio erro={erros.telefone}>
              <Texto data-campo="telefone" value={f.telefone} onChange={(v) => set({ telefone: mascaraTelefone(v) })} readOnly={contatosMasc} inputMode="tel" erro={!!erros.telefone} placeholder="(44) 90000-0000" />
            </Campo>
            <Campo label="WhatsApp" erro={erros.whatsapp} dica={!f.whatsapp ? 'Em branco: usa o telefone principal.' : undefined}>
              <Texto data-campo="whatsapp" value={f.whatsapp} onChange={(v) => set({ whatsapp: mascaraTelefone(v) })} readOnly={contatosMasc} inputMode="tel" erro={!!erros.whatsapp} />
            </Campo>
            <Campo label="Outro telefone" erro={erros.telefone_2}>
              <Texto data-campo="telefone_2" value={f.telefone_2} onChange={(v) => set({ telefone_2: mascaraTelefone(v) })} readOnly={contatosMasc} inputMode="tel" erro={!!erros.telefone_2} />
            </Campo>
            <Campo label="E-mail" erro={erros.email} className="sm:col-span-2">
              <Texto data-campo="email" type="email" value={f.email} onChange={(v) => set({ email: v })} readOnly={contatosMasc} erro={!!erros.email} />
            </Campo>
            <Campo label="Prefere receber avisos por">
              <Selecao value={f.canal_preferido} onChange={(v) => set({ canal_preferido: v })} opcoes={Object.entries(CANAL)} vazio={false} />
            </Campo>
          </div>
        </Secao>

        <Secao id="renda" icon={Briefcase} titulo="Trabalho, renda e programas sociais" descricao="Usados nos critérios da fila (CadÚnico, mãe solo) e nos indicadores de vulnerabilidade.">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <Campo label="Ocupação"><Texto value={f.ocupacao} onChange={(v) => set({ ocupacao: v })} /></Campo>
            <Campo label="Situação de trabalho"><Selecao value={f.situacao_trabalho} onChange={(v) => set({ situacao_trabalho: v })} opcoes={TRABALHO} /></Campo>
            <Campo label="Renda individual (R$/mês)"><Texto type="number" min={0} step="0.01" value={f.renda_individual} onChange={(v) => set({ renda_individual: v })} /></Campo>
            <Campo label="Renda familiar (R$/mês)" dica={perCapita != null ? `Renda por pessoa: ${fmtMoeda(perCapita)}` : undefined}>
              <Texto type="number" min={0} step="0.01" value={f.renda_familiar} onChange={(v) => set({ renda_familiar: v })} />
            </Campo>
            <Campo label="Pessoas no domicílio"><Texto type="number" min={1} max={30} value={f.pessoas_domicilio} onChange={(v) => set({ pessoas_domicilio: v })} /></Campo>
            <div className="hidden sm:block" />
            <Alternar checked={f.cadunico} onChange={(v) => set({ cadunico: v })} label="Família no CadÚnico" dica="Critério da fila: +25 pontos (IN 025/2025)." />
            <Alternar checked={f.mae_solo} onChange={(v) => set({ mae_solo: v })} label="Mãe solo (declarado)" dica="Critério da fila: +5 pontos." />
            <div className="sm:col-span-3">
              <span className="mb-1 block text-[13px] font-semibold text-ink-2">Benefícios recebidos</span>
              <div className="flex flex-wrap gap-2">
                {BENEFICIOS.map((b) => {
                  const on = f.beneficios.includes(b);
                  return (
                    <button key={b} type="button" aria-pressed={on} onClick={() => set({ beneficios: on ? f.beneficios.filter((x) => x !== b) : [...f.beneficios, b] })}
                      className={clsx('min-h-10 rounded-2xl px-3 text-[13.5px] font-semibold ring-1 transition', on ? 'bg-purple-700 text-white ring-purple-700' : 'bg-white text-ink-2 ring-line hover:bg-purple-50')}>
                      {b}
                    </button>
                  );
                })}
              </div>
            </div>
          </div>
        </Secao>

        <Secao id="endereco" icon={Home} titulo="Endereço e localização" descricao="O ponto no mapa define território e distâncias. Mudou de casa? As crianças que moram junto mudam com o responsável e a fila é recalculada.">
          <div data-campo="endereco">
            {erros.endereco && <p className="mb-2 text-xs font-semibold text-red-700">{erros.endereco}</p>}
            <EnderecoEditor value={end} onChange={(e) => { setEnd(e); setEndAlterado(true); }} />
            {!novo && endAlterado && juntas.length > 0 && (
              <div className="mt-3">
                <Alternar checked={aplicarCriancas} onChange={setAplicarCriancas} label={`Aplicar às crianças que moram junto (${juntas.map((c) => c.nome.split(' ')[0]).join(', ')})`}
                  dica="O endereço novo vale para elas e para os outros responsáveis que moram no mesmo endereço; a fila de cada criança é recalculada." />
              </div>
            )}
          </div>
        </Secao>

        {novo && crianca && (
          <Secao icon={Baby} titulo={`Vínculo com ${crianca.aluno.nome}`}>
            <Campo label="Parentesco com a criança" obrigatorio>
              <Selecao value={parentesco} onChange={setParentesco} opcoes={Object.entries(PARENTESCO)} vazio={false} />
            </Campo>
          </Secao>
        )}

        {!novo && (
          <Secao id="criancas" icon={Baby} titulo="Crianças vinculadas" descricao="Encerrar um vínculo não apaga: fica no histórico da criança.">
            <TabelaVinculos quem="Criança" vazio={!criancas.length && 'Nenhuma criança vinculada.'}>
              {criancas.map((c) => (
                <LinhaVinculo key={c.id} to={`/alunos/${c.id}`} nome={c.nome} seed={c.avatar_seed} ate={c.ate} desde={c.desde}
                  detalhe={`${c.idade} · ${c.unidade ?? 'sem matrícula'}${c.mesmo_endereco ? ' · mesmo endereço' : ''}`}
                  v={{ parentesco: c.parentesco, principal: c.principal, pode_buscar: c.pode_buscar, recebe_avisos: c.recebe_avisos, situacao_legal: c.situacao_legal }}
                  acoes={podeEditar && c.acesso && can('students.write') && (
                    <>
                      <Button type="button" size="sm" variant="secondary" icon={Pencil} aria-label={`Editar vínculo com ${c.nome}`}
                        onClick={() => setVinc({ id: c.id, nome: c.nome, inicial: { parentesco: c.parentesco, principal: c.principal, pode_buscar: c.pode_buscar, recebe_avisos: c.recebe_avisos, situacao_legal: c.situacao_legal } })} />
                      <Button type="button" size="sm" variant="ghost" icon={UserMinus} aria-label={`Encerrar vínculo com ${c.nome}`} onClick={() => setEncerrar({ id: c.id, nome: c.nome })} />
                    </>
                  )} />
              ))}
            </TabelaVinculos>
            {podeEditar && can('students.write') && (
              <div className="mt-3 flex flex-wrap gap-2">
                <Button type="button" variant="secondary" icon={Link2} onClick={() => setBuscarCrianca(true)}>Vincular criança já cadastrada</Button>
                <ButtonLink to={`/alunos/novo?responsavel=${cad.responsavel.id}`} variant="ghost" icon={Plus}>Cadastrar criança</ButtonLink>
              </div>
            )}
          </Secao>
        )}

        {!novo && (
          <Secao id="domicilio" icon={Users} titulo="Composição familiar"
            descricao={`Quem mora na casa e não tem cadastro próprio (avós, irmãos mais velhos, companheiro…). ${cad.renda_per_capita != null ? `Renda por pessoa: ${fmtMoeda(cad.renda_per_capita)}.` : ''}`}
            acao={podeEditar ? <Button type="button" size="sm" variant="secondary" icon={Plus} onClick={() => setMembro({})}>Adicionar</Button> : undefined}>
            {(cad.outros_responsaveis as any[]).length > 0 && (
              <div className="mb-3 flex flex-wrap gap-2 text-[13px]">
                <span className="text-muted">Outros responsáveis das crianças:</span>
                {(cad.outros_responsaveis as any[]).map((o) => (
                  <ButtonLink key={o.id} to={`/responsaveis/${o.id}`} size="sm" variant="ghost">{o.nome}{o.mesmo_endereco ? ' · mora junto' : ''}</ButtonLink>
                ))}
              </div>
            )}
            <Card className="overflow-hidden">
              <Tabela rotulo="Composição familiar" largura={720} colunas="minmax(190px,1.6fr) 130px 84px minmax(130px,1fr) 112px 84px">
                <TCabecalho><span>Pessoa</span><span>Parentesco</span><span>Idade</span><span>Ocupação</span><span className="text-right">Renda</span><span /></TCabecalho>
                {(cad.domicilio as any[]).map((m) => (
                  <TLinha key={m.id}>
                    <TCelula fixa titulo={m.nome}><Avatar name={m.nome} seed={m.nome} size={24} className="mr-2 inline-flex align-middle" /><span className="font-semibold">{m.nome}</span></TCelula>
                    <TCelula>{PARENTESCO_DOMICILIO[m.parentesco] ?? m.parentesco}</TCelula>
                    <TCelula className="text-muted">{m.idade ?? '—'}</TCelula>
                    <TCelula titulo={m.ocupacao ?? undefined} className="text-muted">{m.ocupacao ?? '—'}</TCelula>
                    <TCelula className="text-right tabular text-muted">{m.renda != null ? fmtMoeda(m.renda) : '—'}</TCelula>
                    <TCelula livre className="flex justify-end gap-1">
                      {podeEditar && (
                        <>
                          <Button type="button" size="sm" variant="secondary" icon={Pencil} aria-label={`Editar ${m.nome}`} onClick={() => setMembro(m)} />
                          <Button type="button" size="sm" variant="ghost" icon={Trash2} aria-label={`Remover ${m.nome}`} onClick={() => removerMembro(m)} />
                        </>
                      )}
                    </TCelula>
                  </TLinha>
                ))}
                {!cad.domicilio.length && <p className="px-3 py-3 text-[13px] text-muted">Nenhuma outra pessoa registrada no domicílio.</p>}
              </Tabela>
            </Card>
          </Secao>
        )}

        <Secao id="lgpd" icon={ShieldCheck} titulo="Acessibilidade e consentimento">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Campo label="Necessidades de acessibilidade do responsável" className="sm:col-span-2" dica="Ex.: pessoa surda (prefere mensagens), baixa visão, mobilidade reduzida.">
              <span className="flex items-start gap-2">
                <Accessibility className="mt-3 size-5 shrink-0 text-subtle" />
                <textarea value={f.acessibilidade} onChange={(e) => set({ acessibilidade: e.target.value })} rows={2} className={clsx(inputCls, 'h-auto py-2.5')} />
              </span>
            </Campo>
            <Alternar checked={f.lgpd} onChange={(v) => set({ lgpd: v })} label="Ciente do uso dos dados (LGPD)" dica="Dados usados para matrícula, fila e comunicação da rede municipal." />
            <Alternar checked={f.aceita_whatsapp} onChange={(v) => set({ aceita_whatsapp: v })} label="Aceita receber avisos pelo WhatsApp" />
          </div>
        </Secao>
      </fieldset>

      {podeEditar && <BarraSalvar pct={pct} pendencias={pendencias} rotulo={novo ? 'Cadastrar responsável' : 'Salvar cadastro'} busy={busy} onSalvar={() => salvar(false)} />}

      <Sheet open={!!dups} onClose={() => setDups(null)} title="Possível cadastro duplicado" subtitle="Já existe responsável com o mesmo CPF, ou mesmo nome e data de nascimento.">
        <div className="space-y-2">
          {(dups ?? []).map((d) => (
            <ButtonLink key={d.id} to={`/responsaveis/${d.id}`} variant="secondary" block className="!justify-start">{d.nome}{d.telefone ? ` · ${d.telefone}` : ''}</ButtonLink>
          ))}
          <Button block variant="purple" loading={busy} onClick={() => { setDups(null); salvar(true); }}>É outra pessoa — cadastrar mesmo assim</Button>
        </div>
      </Sheet>
      {!novo && (
        <>
          <BuscarPessoaSheet open={buscarCrianca} onClose={() => setBuscarCrianca(false)} tipo="aluno" ignorar={ativas.map((c) => c.id)}
            onEscolher={(p) => { setBuscarCrianca(false); setVinc({ id: p.id, nome: p.nome, inicial: { parentesco: '' } }); }} />
          {vinc && <VinculoSheet open onClose={() => setVinc(null)} alunoId={vinc.id} responsavelId={cad.responsavel.id} titulo={`Vínculo com ${vinc.nome}`} inicial={vinc.inicial} />}
          {encerrar && <EncerrarVinculoSheet open onClose={() => setEncerrar(null)} alunoId={encerrar.id} responsavelId={cad.responsavel.id} nome={cad.responsavel.nome} />}
          <MembroSheet membro={membro} responsavelId={cad.responsavel.id} onClose={() => setMembro(null)} />
        </>
      )}
    </div>
  );
}

function MembroSheet({ membro, responsavelId, onClose }: { membro: any | null; responsavelId: string; onClose: () => void }) {
  const toast = useToast();
  const recarregar = useRecarregarCadastros();
  const [m, setM] = useState({ nome: '', parentesco: '', nascimento: '', ocupacao: '', renda: '', observacoes: '' });
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    if (membro) setM({ nome: membro.nome ?? '', parentesco: membro.parentesco ?? '', nascimento: membro.nascimento ?? '', ocupacao: membro.ocupacao ?? '', renda: membro.renda == null ? '' : String(membro.renda), observacoes: membro.observacoes ?? '' });
  }, [membro]);
  const salvar = async () => {
    setBusy(true);
    try {
      await rpc('domicilio_salvar', { responsavel_id: responsavelId, id: membro?.id ?? null, ...m, renda: m.renda === '' ? null : Number(m.renda) });
      recarregar();
      toast({ title: 'Composição familiar atualizada', tone: 'success' });
      onClose();
    } catch (e) {
      toast({ title: 'Não salvo', description: (e as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={!!membro} onClose={onClose} title={membro?.id ? 'Editar pessoa do domicílio' : 'Pessoa que mora na casa'}
      footer={<Button block size="lg" variant="purple" loading={busy} disabled={m.nome.trim().length < 3 || !m.parentesco} onClick={salvar}>Salvar</Button>}>
      <div className="space-y-3">
        <Campo label="Nome" obrigatorio><Texto value={m.nome} onChange={(v) => setM({ ...m, nome: v })} /></Campo>
        <Campo label="Parentesco com o responsável" obrigatorio><Selecao value={m.parentesco} onChange={(v) => setM({ ...m, parentesco: v })} opcoes={Object.entries(PARENTESCO_DOMICILIO)} /></Campo>
        <div className="grid grid-cols-2 gap-3">
          <Campo label="Nascimento"><input type="date" value={m.nascimento} onChange={(e) => setM({ ...m, nascimento: e.target.value })} className={inputCls} /></Campo>
          <Campo label="Renda (R$/mês)"><Texto type="number" min={0} step="0.01" value={m.renda} onChange={(v) => setM({ ...m, renda: v })} /></Campo>
        </div>
        <Campo label="Ocupação"><Texto value={m.ocupacao} onChange={(v) => setM({ ...m, ocupacao: v })} /></Campo>
        <Campo label="Observações"><Texto value={m.observacoes} onChange={(v) => setM({ ...m, observacoes: v })} /></Campo>
      </div>
    </Sheet>
  );
}
