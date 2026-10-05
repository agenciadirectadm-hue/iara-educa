import { useMemo, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router';
import clsx from 'clsx';
import { Accessibility, Camera, FileText, Globe2, HeartPulse, Home, IdCard, Link2, Pencil, UserMinus, UserPlus, Users } from 'lucide-react';
import { rpc } from '@/lib/api';
import { useRpc } from '@/lib/hooks';
import { useSession } from '@/lib/session';
import { fmtDate } from '@/lib/format';
import {
  CIDADES_FREQUENTES, NACIONALIDADE, PARENTESCO, RACA, SEXO, TRANSPORTE_SITUACAO, UFS, cpfValido, enderecoDoServidor, enderecoVazio, mascaraCertidao,
  mascaraCpf, mascaraInep, mascaraNis, mascaraSus, nisValido, soDigitos, type Endereco,
} from '@/lib/cadastro';
import { Avatar, Button, ButtonLink, Card, ErrorState, PageHeader, SkeletonList, inputCls } from '@/components/ui';
import { Crumbs } from '@/components/Crumbs';
import { Sheet, useToast } from '@/components/overlays';
import { Alternar, AvisoRestrito, BarraSalvar, Campo, Escolha, Secao, Selecao, Texto } from '@/components/cadastro';
import EnderecoEditor from '@/components/EnderecoEditor';
import { BuscarPessoaSheet, EncerrarVinculoSheet, LinhaVinculo, VinculoSheet, useRecarregarCadastros, type Vinculo } from '@/components/Vinculos';

const PAISES = ['Haiti', 'Venezuela', 'Paraguai', 'Argentina', 'Colômbia', 'Bolívia', 'Peru', 'Japão', 'Portugal', 'Estados Unidos'];

type Form = {
  nome: string; nome_social: string; nascimento: string; sexo: string; cor_raca: string; nacionalidade: string; pais_nascimento: string;
  naturalidade_municipio: string; naturalidade_uf: string; cpf: string; nis: string; certidao: string; cartao_sus: string; codigo_inep: string;
  filiacao_1: string; filiacao_2: string; uso_imagem: string; transporte: boolean; transporte_situacao: string; acessibilidade: string; aee: boolean;
};
const formVazio = (): Form => ({
  nome: '', nome_social: '', nascimento: '', sexo: '', cor_raca: '', nacionalidade: 'BRASILEIRA', pais_nascimento: '', naturalidade_municipio: '',
  naturalidade_uf: 'PR', cpf: '', nis: '', certidao: '', cartao_sus: '', codigo_inep: '', filiacao_1: '', filiacao_2: '', uso_imagem: '',
  transporte: false, transporte_situacao: '', acessibilidade: '', aee: false,
});
function doServidor(a: any): Form {
  const masc = (v: string | null, f: (x: string) => string) => (v == null ? '' : /[•*]/.test(v) ? v : f(v));
  return {
    nome: a.nome ?? '', nome_social: a.nome_social ?? '', nascimento: a.nascimento ?? '', sexo: a.sexo ?? '', cor_raca: a.cor_raca ?? '',
    nacionalidade: a.nacionalidade ?? 'BRASILEIRA', pais_nascimento: a.pais_nascimento ?? '', naturalidade_municipio: a.naturalidade_municipio ?? '',
    naturalidade_uf: a.naturalidade_uf ?? '', cpf: masc(a.cpf, mascaraCpf), nis: masc(a.nis, mascaraNis), certidao: masc(a.certidao, mascaraCertidao),
    cartao_sus: masc(a.cartao_sus, mascaraSus), codigo_inep: a.codigo_inep ?? '', filiacao_1: a.filiacao_1 ?? '', filiacao_2: a.filiacao_2 ?? '',
    uso_imagem: a.uso_imagem == null ? '' : a.uso_imagem ? 'SIM' : 'NAO', transporte: !!a.transporte, transporte_situacao: a.transporte_situacao ?? '',
    acessibilidade: a.acessibilidade ?? '', aee: !!a.aee,
  };
}

export default function CadastroAluno() {
  const { id } = useParams();
  const [sp] = useSearchParams();
  const respParam = sp.get('responsavel');
  const cad = useRpc<any>('aluno_cadastro', { id }, { enabled: !!id, refetchOnWindowFocus: false });
  const resp = useRpc<any>('responsavel_cadastro', { id: respParam }, { enabled: !id && !!respParam, refetchOnWindowFocus: false });
  if (id && cad.isLoading) return <SkeletonList rows={6} />;
  if (id && cad.error) return <ErrorState error={cad.error} onRetry={() => cad.refetch()} />;
  if (!id && respParam && resp.isLoading) return <SkeletonList rows={6} />;
  return <FormularioAluno key={id ?? 'novo'} cad={id ? cad.data : null} respInicial={!id ? resp.data ?? null : null} parentescoInicial={sp.get('parentesco') ?? ''} />;
}

function FormularioAluno({ cad, respInicial, parentescoInicial }: { cad: any | null; respInicial: any | null; parentescoInicial: string }) {
  const novo = !cad;
  const nav = useNavigate();
  const toast = useToast();
  const { can } = useSession();
  const recarregar = useRecarregarCadastros();
  const [f, setF] = useState<Form>(() => (cad ? doServidor(cad.aluno) : formVazio()));
  const set = (patch: Partial<Form>) => setF((x) => ({ ...x, ...patch }));
  const [sens, setSens] = useState(() => ({
    necessidade_especial: cad?.sensiveis?.necessidade_especial ?? '', alertas_saude: cad?.sensiveis?.alertas_saude ?? '',
    alergias_alimentares: cad?.sensiveis?.alergias_alimentares ?? '', observacoes_legais: cad?.sensiveis?.observacoes_legais ?? '',
  }));
  const [sensAlterado, setSensAlterado] = useState(false);
  const enderecoResp = novo ? respInicial?.endereco ?? null : cad.responsavel_principal?.endereco ?? null;
  const modoInicial: 'RESPONSAVEL' | 'PROPRIO' = novo ? (respInicial?.endereco ? 'RESPONSAVEL' : 'PROPRIO')
    : cad.endereco_do_responsavel || (!cad.endereco && cad.responsavel_principal?.tem_endereco) ? 'RESPONSAVEL' : 'PROPRIO';
  const [modo, setModo] = useState<'RESPONSAVEL' | 'PROPRIO'>(modoInicial);
  const [end, setEnd] = useState<Endereco>(() => (cad && !cad.endereco_do_responsavel ? enderecoDoServidor(cad.endereco) : null) ?? enderecoVazio());
  const [endAlterado, setEndAlterado] = useState(false);
  const [resp, setResp] = useState<{ id: string; nome: string } | null>(respInicial ? { id: respInicial.responsavel.id, nome: respInicial.responsavel.nome } : null);
  const [parentesco, setParentesco] = useState(parentescoInicial || 'MAE');
  const [erros, setErros] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [dups, setDups] = useState<any[] | null>(null);
  const [buscarResp, setBuscarResp] = useState(false);
  const [vinc, setVinc] = useState<null | { id: string; nome: string; inicial?: Partial<Vinculo> }>(null);
  const [encerrar, setEncerrar] = useState<null | { id: string; nome: string }>(null);
  const docsMasc = !!cad?.documentos_mascarados;
  const podeSens = novo ? can('students.read_sensitive') : !!cad.permissoes?.sensiveis;
  const podeEditar = novo ? can('students.write') : !!cad.permissoes?.editar;
  const faixa = useRpc<any>('grade_for_birthdate', { birth_date: f.nascimento }, { enabled: /^\d{4}-\d{2}-\d{2}$/.test(f.nascimento) });
  const ativos = ((cad?.responsaveis ?? []) as any[]).filter((r) => !r.ate);
  const temResp = novo ? !!resp : ativos.length > 0;

  const pendencias = useMemo(() => {
    const p: string[] = [];
    if (!f.sexo) p.push('Sexo');
    if (!f.cor_raca) p.push('Cor/raça');
    if (f.nacionalidade === 'BRASILEIRA') {
      if (!f.naturalidade_municipio.trim() || !f.naturalidade_uf) p.push('Naturalidade');
    } else if (!f.pais_nascimento.trim()) p.push('País de nascimento');
    if (!f.filiacao_1.trim()) p.push('Filiação');
    if (!soDigitos(f.certidao) && !soDigitos(f.cpf) && !/[•*]/.test(f.certidao + f.cpf)) p.push('Certidão de nascimento ou CPF');
    const temEndereco = modo === 'RESPONSAVEL' ? !!enderecoResp : end.lat != null && !!end.logradouro.trim();
    if (!temEndereco) p.push('Endereço');
    if (!temResp) p.push('Responsável');
    return p;
  }, [f, modo, end, enderecoResp, temResp]);
  const pct = (100 * (7 - pendencias.length)) / 7;

  const validar = () => {
    const e: Record<string, string> = {};
    const nome = f.nome.trim().replace(/\s+/g, ' ');
    if (nome.length < 5 || !nome.includes(' ')) e.nome = 'Informe o nome completo (nome e sobrenome).';
    if (!f.nascimento) e.nascimento = 'Informe a data de nascimento.';
    else if (new Date(`${f.nascimento}T12:00:00`) > new Date()) e.nascimento = 'A data está no futuro.';
    if (!docsMasc) {
      if (soDigitos(f.cpf) && soDigitos(f.cpf) !== soDigitos(cad?.aluno?.cpf) && !cpfValido(f.cpf)) e.cpf = 'CPF inválido: os dígitos verificadores não conferem.';
      if (soDigitos(f.nis) && soDigitos(f.nis) !== soDigitos(cad?.aluno?.nis) && !nisValido(f.nis)) e.nis = 'NIS inválido: confira os 11 dígitos.';
      if (soDigitos(f.certidao) && soDigitos(f.certidao).length !== 32) e.certidao = 'A matrícula da certidão tem 32 dígitos.';
      if (soDigitos(f.cartao_sus) && soDigitos(f.cartao_sus).length !== 15) e.cartao_sus = 'O Cartão SUS (CNS) tem 15 dígitos.';
    }
    if (soDigitos(f.codigo_inep) && soDigitos(f.codigo_inep).length !== 12) e.codigo_inep = 'O código INEP do aluno tem 12 dígitos.';
    if (modo === 'PROPRIO' && (novo || endAlterado || modo !== modoInicial)) {
      if (!end.logradouro.trim()) e.endereco = 'Informe o logradouro do endereço.';
      else if (end.lat == null) e.endereco = 'Marque a casa no mapa (ou localize pelo CEP).';
    }
    if (modo === 'RESPONSAVEL' && !enderecoResp) e.endereco = novo && !resp ? 'Escolha o responsável (para usar o endereço dele) ou informe um endereço próprio.' : 'O responsável principal não tem endereço: informe um endereço próprio.';
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
        id: cad?.aluno?.id, nome: f.nome.trim().replace(/\s+/g, ' '), nome_social: f.nome_social, nascimento: f.nascimento, sexo: f.sexo || null,
        cor_raca: f.cor_raca || null, nacionalidade: f.nacionalidade, pais_nascimento: f.pais_nascimento, naturalidade_municipio: f.naturalidade_municipio,
        naturalidade_uf: f.naturalidade_uf, codigo_inep: soDigitos(f.codigo_inep), filiacao_1: f.filiacao_1, filiacao_2: f.filiacao_2,
        uso_imagem: f.uso_imagem === '' ? null : f.uso_imagem === 'SIM', transporte: f.transporte, transporte_situacao: f.transporte ? f.transporte_situacao : '',
        acessibilidade: f.acessibilidade, aee: f.aee, forcar,
      };
      if (!docsMasc) Object.assign(p, { cpf: soDigitos(f.cpf), nis: soDigitos(f.nis), certidao: soDigitos(f.certidao), cartao_sus: soDigitos(f.cartao_sus) });
      if (modo === 'RESPONSAVEL' && (novo || modo !== modoInicial)) p.endereco = { modo: 'RESPONSAVEL' };
      if (modo === 'PROPRIO' && (novo || endAlterado || modo !== modoInicial)) p.endereco = { modo: 'PROPRIO', ...end, cep: soDigitos(end.cep) };
      if (podeSens && sensAlterado) p.sensiveis = sens;
      if (novo && resp) p.responsavel = { id: resp.id, parentesco };
      const r = await rpc<any>('aluno_salvar', p);
      if (r.ok === false) {
        setDups(r.duplicados ?? []);
        return;
      }
      recarregar();
      toast({
        title: novo ? 'Aluno cadastrado' : 'Cadastro atualizado', tone: 'success',
        description: r.impactos_fila?.length ? 'O endereço mudou: a fila da criança foi recalculada.' : r.cadastro?.pendencias?.length ? `Ainda falta: ${r.cadastro.pendencias.join(', ')}.` : 'Cadastro completo.',
      });
      nav(`/alunos/${r.id}`);
    } catch (err) {
      toast({ title: 'Cadastro não salvo', description: (err as Error).message, tone: 'error' });
    } finally {
      setBusy(false);
    }
  };

  const nomeTitulo = f.nome.trim() || 'Novo aluno';
  const maeOuPai = (rel: string) => ativos.find((r) => r.parentesco === rel)?.nome as string | undefined;
  return (
    <div className="pb-6">
      <Crumbs items={[{ label: 'Alunos', to: '/alunos' }, ...(novo ? [] : [{ label: cad.aluno.nome, to: `/alunos/${cad.aluno.id}` }]), { label: novo ? 'Novo cadastro' : 'Cadastro' }]} />
      <PageHeader eyebrow="Cadastro 360º do aluno" title={novo ? 'Novo aluno' : nomeTitulo}
        subtitle={novo ? 'Dados pessoais, documentos, filiação, endereço no mapa e responsáveis. Campos com * são obrigatórios; o restante pode ser completado depois.'
          : `Código da rede ${cad.aluno.registro} · atualizado em ${fmtDate(cad.aluno.atualizado_em)}`} />
      {!podeEditar && <AvisoRestrito>Seu perfil pode consultar, mas não alterar o cadastro de alunos.</AvisoRestrito>}

      <nav aria-label="Seções do cadastro" className="no-scrollbar -mx-4 mb-3 flex gap-1.5 overflow-x-auto px-4 sm:mx-0 sm:flex-wrap sm:px-0">
        {[['identificacao', 'Identificação'], ['naturalidade', 'Naturalidade'], ['documentos', 'Documentos'], ['filiacao', 'Filiação'], ['endereco', 'Endereço'],
          ['responsaveis', 'Responsáveis'], ['inclusao', 'Inclusão e saúde'], ['autorizacoes', 'Autorizações']].map(([k, l]) => (
          <a key={k} href={`#${k}`} onClick={(e) => { e.preventDefault(); document.getElementById(k)?.scrollIntoView({ behavior: 'smooth' }); }}
            className="inline-flex h-9 shrink-0 items-center rounded-full bg-white px-3.5 text-[13px] font-semibold text-ink-2 ring-1 ring-line hover:bg-purple-50">{l}</a>
        ))}
      </nav>

      <fieldset disabled={!podeEditar} className="space-y-4">
        <Secao id="identificacao" icon={IdCard} titulo="Identificação">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Campo label="Nome completo" obrigatorio erro={erros.nome} className="sm:col-span-2">
              <Texto data-campo="nome" value={f.nome} onChange={(v) => set({ nome: v })} erro={!!erros.nome} autoComplete="off" placeholder="Como na certidão de nascimento" />
            </Campo>
            <Campo label="Nome social" dica="Nome pelo qual a criança é reconhecida, se diferente do registro.">
              <Texto value={f.nome_social} onChange={(v) => set({ nome_social: v })} />
            </Campo>
            <Campo label="Data de nascimento" obrigatorio erro={erros.nascimento}
              dica={faixa.data?.ok ? `Faixa em ${faixa.data.school_year}: ${faixa.data.grade_name} (data de corte ${fmtDate(faixa.data.cutoff)})` : faixa.data?.explanation}>
              <input data-campo="nascimento" type="date" value={f.nascimento} max={new Date().toISOString().slice(0, 10)} onChange={(e) => set({ nascimento: e.target.value })}
                className={clsx(inputCls, erros.nascimento && 'ring-2 ring-red-400')} />
            </Campo>
            <Campo label="Sexo" obrigatorio>
              <Escolha nome="Sexo" value={f.sexo} onChange={(v) => set({ sexo: v })} opcoes={Object.entries(SEXO)} />
            </Campo>
            <Campo label="Cor/raça" obrigatorio dica="Autodeclarada pela família (Censo Escolar).">
              <Escolha nome="Cor/raça" value={f.cor_raca} onChange={(v) => set({ cor_raca: v })} opcoes={Object.entries(RACA)} />
            </Campo>
          </div>
        </Secao>

        <Secao id="naturalidade" icon={Globe2} titulo="Nacionalidade e naturalidade">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <Campo label="Nacionalidade" className="sm:col-span-3">
              <Escolha nome="Nacionalidade" value={f.nacionalidade} onChange={(v) => set({ nacionalidade: v })} opcoes={Object.entries(NACIONALIDADE)} />
            </Campo>
            {f.nacionalidade === 'BRASILEIRA' ? (
              <>
                <Campo label="Município de nascimento" obrigatorio className="sm:col-span-2">
                  <Texto value={f.naturalidade_municipio} onChange={(v) => set({ naturalidade_municipio: v })} list="cidades-frequentes" placeholder="Ex.: Maringá" />
                  <datalist id="cidades-frequentes">{CIDADES_FREQUENTES.map((c) => <option key={c} value={c} />)}</datalist>
                </Campo>
                <Campo label="UF" obrigatorio>
                  <Selecao value={f.naturalidade_uf} onChange={(v) => set({ naturalidade_uf: v })} opcoes={UFS} />
                </Campo>
              </>
            ) : (
              <Campo label="País de nascimento" obrigatorio className="sm:col-span-2" dica="Famílias migrantes têm direito à matrícula mesmo sem documentos brasileiros (Resolução CNE/CEB nº 1/2020).">
                <Texto value={f.pais_nascimento} onChange={(v) => set({ pais_nascimento: v })} list="paises" />
                <datalist id="paises">{PAISES.map((c) => <option key={c} value={c} />)}</datalist>
              </Campo>
            )}
          </div>
        </Secao>

        <Secao id="documentos" icon={FileText} titulo="Documentos" descricao="A certidão de nascimento ou o CPF identificam a criança; os demais ajudam no Censo Escolar e na saúde.">
          {docsMasc && <AvisoRestrito>Documentos mascarados para o seu perfil (mínimo privilégio). Só perfis com acesso a contatos e documentos podem alterá-los.</AvisoRestrito>}
          <div className={clsx('grid grid-cols-1 gap-3 sm:grid-cols-2', docsMasc && 'mt-3')}>
            <Campo label="Matrícula da certidão de nascimento" erro={erros.certidao} className="sm:col-span-2" dica="32 dígitos, no canto da certidão.">
              <Texto data-campo="certidao" value={f.certidao} onChange={(v) => set({ certidao: mascaraCertidao(v) })} readOnly={docsMasc} inputMode="numeric" erro={!!erros.certidao} placeholder="000000 00 00 0000 0 00000 000 0000000 00" />
            </Campo>
            <Campo label="CPF" erro={erros.cpf} dica={soDigitos(f.cpf).length === 11 && !erros.cpf ? (cpfValido(f.cpf) ? 'CPF válido.' : soDigitos(f.cpf) === soDigitos(cad?.aluno?.cpf) ? 'CPF de demonstração (dígito propositalmente inválido).' : 'Dígitos verificadores não conferem.') : undefined}>
              <Texto data-campo="cpf" value={f.cpf} onChange={(v) => set({ cpf: mascaraCpf(v) })} readOnly={docsMasc} inputMode="numeric" erro={!!erros.cpf} placeholder="000.000.000-00" />
            </Campo>
            <Campo label="NIS" erro={erros.nis} dica="Famílias no CadÚnico.">
              <Texto data-campo="nis" value={f.nis} onChange={(v) => set({ nis: mascaraNis(v) })} readOnly={docsMasc} inputMode="numeric" erro={!!erros.nis} />
            </Campo>
            <Campo label="Cartão SUS (CNS)" erro={erros.cartao_sus}>
              <Texto data-campo="cartao_sus" value={f.cartao_sus} onChange={(v) => set({ cartao_sus: mascaraSus(v) })} readOnly={docsMasc} inputMode="numeric" erro={!!erros.cartao_sus} placeholder="000 0000 0000 0000" />
            </Campo>
            <Campo label="Código INEP do aluno" erro={erros.codigo_inep} dica="Gerado pelo Censo Escolar após a 1ª matrícula.">
              <Texto data-campo="codigo_inep" value={f.codigo_inep} onChange={(v) => set({ codigo_inep: mascaraInep(v) })} inputMode="numeric" erro={!!erros.codigo_inep} />
            </Campo>
            {!novo && (
              <Campo label="Código na rede municipal" dica="Gerado pelo sistema; não muda.">
                <Texto value={cad.aluno.registro} onChange={() => {}} readOnly />
              </Campo>
            )}
          </div>
        </Secao>

        <Secao id="filiacao" icon={Users} titulo="Filiação" descricao="Como consta na certidão. Pode ser diferente de quem é o responsável legal hoje.">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Campo label="Filiação 1" obrigatorio dica={!f.filiacao_1 && maeOuPai('MAE') ? undefined : 'Geralmente a mãe.'}>
              <Texto value={f.filiacao_1} onChange={(v) => set({ filiacao_1: v })} />
              {!f.filiacao_1 && maeOuPai('MAE') && (
                <button type="button" onClick={() => set({ filiacao_1: maeOuPai('MAE')! })} className="mt-1 text-[12.5px] font-semibold text-purple-700 underline">Usar {maeOuPai('MAE')} (mãe vinculada)</button>
              )}
            </Campo>
            <Campo label="Filiação 2" dica="Deixe em branco se não declarada.">
              <Texto value={f.filiacao_2} onChange={(v) => set({ filiacao_2: v })} />
              {!f.filiacao_2 && maeOuPai('PAI') && (
                <button type="button" onClick={() => set({ filiacao_2: maeOuPai('PAI')! })} className="mt-1 text-[12.5px] font-semibold text-purple-700 underline">Usar {maeOuPai('PAI')} (pai vinculado)</button>
              )}
            </Campo>
          </div>
        </Secao>

        <Secao id="endereco" icon={Home} titulo="Endereço e localização" descricao="O ponto no mapa define o território e a distância até as unidades (critério da fila: residência até 2 km).">
          <div data-campo="endereco">
            <Escolha nome="Onde a criança mora" value={modo} onChange={(v) => { setModo(v); setErros((x) => ({ ...x, endereco: '' })); }}
              opcoes={[['RESPONSAVEL', 'Com o responsável principal'], ['PROPRIO', 'Em outro endereço']]} />
            {erros.endereco && <p className="mt-2 text-xs font-semibold text-red-700">{erros.endereco}</p>}
          </div>
          <div className="mt-3">
            {modo === 'RESPONSAVEL' ? (
              enderecoResp ? (
                <div className="flex items-start gap-3 rounded-2xl bg-slate-50 p-3 ring-1 ring-line">
                  <Home className="mt-0.5 size-5 shrink-0 text-ink-2" />
                  <div className="min-w-0 text-[14px]">
                    <div className="font-semibold">{enderecoResp.linha}</div>
                    <div className="text-[12.5px] text-muted">{enderecoResp.territorio ?? '—'} · zona {enderecoResp.zona?.toLowerCase()} · endereço de {novo ? respInicial?.responsavel?.nome ?? resp?.nome : cad.responsavel_principal?.nome}</div>
                    <div className="mt-1 text-[12px] text-muted">Mudou o endereço da família? Altere no cadastro do responsável — as crianças que moram junto mudam com ele.</div>
                  </div>
                </div>
              ) : (
                <p className="rounded-2xl bg-amber-50 p-3 text-[13px] text-amber-950 ring-1 ring-amber-200">
                  {novo && !resp ? 'Escolha o responsável na seção abaixo para usar o endereço dele.' : 'O responsável principal ainda não tem endereço. Use "Em outro endereço" ou complete o cadastro do responsável.'}
                </p>
              )
            ) : (
              <EnderecoEditor value={end} onChange={(e) => { setEnd(e); setEndAlterado(true); }} faixaId={faixa.data?.grade_level_id ?? null} />
            )}
          </div>
        </Secao>

        <Secao id="responsaveis" icon={UserPlus} titulo="Responsáveis"
          descricao="Quem responde pela criança, quem pode buscá-la e quem recebe os avisos. Encerrar um vínculo não apaga: fica no histórico.">
          {novo ? (
            resp ? (
              <div className="grid grid-cols-1 items-end gap-3 sm:grid-cols-[1fr_260px_auto]">
                <div className="flex items-center gap-3 rounded-2xl bg-slate-50 p-3 ring-1 ring-line">
                  <Avatar name={resp.nome} seed={resp.nome} size={40} />
                  <div className="min-w-0"><div className="truncate font-semibold">{resp.nome}</div><div className="text-[12px] text-muted">Responsável principal</div></div>
                </div>
                <Campo label="Parentesco"><Selecao value={parentesco} onChange={setParentesco} opcoes={Object.entries(PARENTESCO)} vazio={false} /></Campo>
                <Button type="button" variant="ghost" onClick={() => setResp(null)}>Trocar</Button>
              </div>
            ) : (
              <div className="flex flex-wrap gap-2">
                <Button type="button" variant="secondary" icon={Link2} onClick={() => setBuscarResp(true)}>Vincular responsável já cadastrado</Button>
                <p className="w-full text-[12.5px] text-muted">Ou salve a criança e cadastre o responsável em seguida (botão no cadastro).</p>
              </div>
            )
          ) : (
            <>
              <Card className="divide-y divide-line overflow-hidden">
                {(cad.responsaveis as any[]).map((r) => (
                  <LinhaVinculo key={r.id} to={`/responsaveis/${r.id}`} nome={r.nome} seed={r.nome} ate={r.ate} desde={r.desde}
                    detalhe={`CPF ${r.cpf ?? '—'} · ${r.telefone ?? 'sem telefone'}${r.mesmo_endereco ? ' · mesmo endereço' : ''}`}
                    v={{ parentesco: r.parentesco, principal: r.principal, pode_buscar: r.pode_buscar, recebe_avisos: r.recebe_avisos, situacao_legal: r.situacao_legal }}
                    acoes={podeEditar && (
                      <>
                        <Button type="button" size="sm" variant="secondary" icon={Pencil} aria-label={`Editar vínculo com ${r.nome}`}
                          onClick={() => setVinc({ id: r.id, nome: r.nome, inicial: { parentesco: r.parentesco, principal: r.principal, pode_buscar: r.pode_buscar, recebe_avisos: r.recebe_avisos, situacao_legal: r.situacao_legal } })} />
                        <Button type="button" size="sm" variant="ghost" icon={UserMinus} aria-label={`Encerrar vínculo com ${r.nome}`} onClick={() => setEncerrar({ id: r.id, nome: r.nome })} />
                      </>
                    )} />
                ))}
                {!cad.responsaveis.length && <p className="p-4 text-[13px] text-muted">Nenhum responsável vinculado.</p>}
              </Card>
              {podeEditar && (
                <div className="mt-3 flex flex-wrap gap-2">
                  <Button type="button" variant="secondary" icon={Link2} onClick={() => setBuscarResp(true)}>Vincular responsável já cadastrado</Button>
                  {can('guardians.write') && <ButtonLink to={`/responsaveis/novo?crianca=${cad.aluno.id}`} variant="ghost" icon={UserPlus}>Cadastrar novo responsável</ButtonLink>}
                </div>
              )}
            </>
          )}
        </Secao>

        <Secao id="inclusao" icon={Accessibility} titulo="Inclusão, saúde e transporte">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Alternar checked={f.aee} onChange={(v) => set({ aee: v })} label="Público do AEE (educação especial)" dica="Deficiência, TEA ou altas habilidades. O detalhe é dado sensível." />
            <Alternar checked={f.transporte} onChange={(v) => set({ transporte: v })} label="Precisa de transporte escolar" />
            {f.transporte && (
              <Campo label="Situação do transporte">
                <Selecao value={f.transporte_situacao} onChange={(v) => set({ transporte_situacao: v })} opcoes={Object.entries(TRANSPORTE_SITUACAO)} />
              </Campo>
            )}
            <Campo label="Acessibilidade" className="sm:col-span-2" dica="Ex.: usa cadeira de rodas, precisa de mediador, baixa visão.">
              <textarea value={f.acessibilidade} onChange={(e) => set({ acessibilidade: e.target.value })} rows={2} className={clsx(inputCls, 'h-auto py-2.5')} />
            </Campo>
          </div>
          <div className="mt-4 border-t border-line pt-4">
            <div className="mb-2 flex items-center gap-2 text-[13px] font-bold text-ink-2"><HeartPulse className="size-4 text-red-600" />Dados sensíveis (LGPD)</div>
            {podeSens ? (
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                {([['necessidade_especial', 'Necessidade educacional especial / laudo'], ['alertas_saude', 'Alertas de saúde (alergias graves, medicação, convulsão…)'],
                  ['alergias_alimentares', 'Restrições alimentares'], ['observacoes_legais', 'Observações legais (guarda, medida protetiva…)']] as const).map(([k, l]) => (
                  <Campo key={k} label={l}>
                    <textarea value={sens[k]} onChange={(e) => { setSens({ ...sens, [k]: e.target.value }); setSensAlterado(true); }} rows={2} className={clsx(inputCls, 'h-auto py-2.5')} />
                  </Campo>
                ))}
                <p className="text-[12px] text-muted sm:col-span-2">Acesso restrito à unidade da criança; cada consulta e alteração fica na auditoria.</p>
              </div>
            ) : (
              <AvisoRestrito>Laudos, saúde, restrições e observações legais exigem permissão específica (perfis da unidade da criança).</AvisoRestrito>
            )}
          </div>
        </Secao>

        <Secao id="autorizacoes" icon={Camera} titulo="Autorizações">
          <Campo label="Uso de imagem da criança (fotos e vídeos de atividades)">
            <Escolha nome="Uso de imagem" value={f.uso_imagem} onChange={(v) => set({ uso_imagem: v })} opcoes={[['SIM', 'Autoriza'], ['NAO', 'Não autoriza'], ['', 'Não informado']]} />
          </Campo>
        </Secao>
      </fieldset>

      {podeEditar && <BarraSalvar pct={pct} pendencias={pendencias} rotulo={novo ? 'Cadastrar aluno' : 'Salvar cadastro'} busy={busy} onSalvar={() => salvar(false)} />}

      <Sheet open={!!dups} onClose={() => setDups(null)} title="Possível cadastro duplicado"
        subtitle="Já existe criança com o mesmo nome e data de nascimento (ou o mesmo CPF). Abra o cadastro existente ou confirme que é outra criança.">
        <div className="space-y-2">
          {(dups ?? []).map((d) => (
            <ButtonLink key={d.id} to={`/alunos/${d.id}`} variant="secondary" block className="!justify-start">
              {d.nome} · {fmtDate(d.nascimento)} · código {d.registro}
            </ButtonLink>
          ))}
          <Button block variant="purple" loading={busy} onClick={() => { setDups(null); salvar(true); }}>É outra criança — cadastrar mesmo assim</Button>
        </div>
      </Sheet>
      <BuscarPessoaSheet open={buscarResp} onClose={() => setBuscarResp(false)} tipo="responsavel" ignorar={ativos.map((r) => r.id)}
        onEscolher={(pessoa) => {
          setBuscarResp(false);
          if (novo) setResp(pessoa);
          else setVinc({ id: pessoa.id, nome: pessoa.nome, inicial: { parentesco: '', principal: ativos.length === 0 } });
        }} />
      {!novo && vinc && (
        <VinculoSheet open onClose={() => setVinc(null)} alunoId={cad.aluno.id} responsavelId={vinc.id} titulo={`Vínculo com ${vinc.nome}`} inicial={vinc.inicial} />
      )}
      {!novo && encerrar && (
        <EncerrarVinculoSheet open onClose={() => setEncerrar(null)} alunoId={cad.aluno.id} responsavelId={encerrar.id} nome={encerrar.nome} />
      )}
    </div>
  );
}
