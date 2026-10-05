// Cadastro 360º de alunos e responsáveis: rótulos, máscaras e validações (as mesmas regras do servidor).
import type { Tone } from './labels';

export const UFS = ['AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO'];
export const CIDADES_FREQUENTES = ['Maringá', 'Sarandi', 'Paiçandu', 'Marialva', 'Mandaguari', 'Mandaguaçu', 'Londrina', 'Cianorte', 'Campo Mourão', 'Apucarana', 'Curitiba'];

export const SEXO: Record<string, string> = { F: 'Feminino', M: 'Masculino' };
export const RACA: Record<string, string> = {
  BRANCA: 'Branca', PRETA: 'Preta', PARDA: 'Parda', AMARELA: 'Amarela', INDIGENA: 'Indígena', NAO_DECLARADA: 'Não declarada',
};
export const NACIONALIDADE: Record<string, string> = { BRASILEIRA: 'Brasileira', NATURALIZADA: 'Brasileira naturalizada', ESTRANGEIRA: 'Estrangeira' };
export const ESTADO_CIVIL: Record<string, string> = {
  SOLTEIRO: 'Solteiro(a)', CASADO: 'Casado(a)', UNIAO_ESTAVEL: 'União estável', DIVORCIADO: 'Divorciado(a)', SEPARADO: 'Separado(a)', VIUVO: 'Viúvo(a)',
};
export const ESCOLARIDADE = [
  'Sem escolaridade', 'Fundamental incompleto', 'Fundamental completo', 'Médio incompleto', 'Médio completo', 'Superior incompleto',
  'Superior completo', 'Pós-graduação',
];
export const TRABALHO = ['CLT', 'Servidor público', 'Autônomo', 'Informal', 'Desempregado', 'Do lar', 'Aposentado(a)', 'Estudante'];
export const IDIOMAS = ['Português', 'Espanhol', 'Crioulo haitiano / francês', 'Inglês', 'Japonês', 'Libras', 'Outro'];
export const BENEFICIOS = ['Bolsa Família', 'BPC', 'Auxílio Gás', 'Tarifa Social de Energia', 'Pé-de-Meia'];
export const CANAL: Record<string, string> = { WHATSAPP: 'WhatsApp', SMS: 'SMS', EMAIL: 'E-mail', TELEFONE: 'Ligação' };

export const PARENTESCO: Record<string, string> = {
  MAE: 'Mãe', PAI: 'Pai', AVO: 'Avó / avô', TIA: 'Tia / tio', IRMAO: 'Irmã / irmão (maior de idade)', PADRASTO: 'Padrasto / madrasta',
  RESPONSAVEL_LEGAL: 'Responsável legal (guarda)', OUTRO: 'Outro',
};
export const PARENTESCO_DOMICILIO: Record<string, string> = {
  AVO: 'Avó / avô', IRMAO: 'Irmã / irmão', TIO: 'Tia / tio', COMPANHEIRO: 'Companheiro(a)', PRIMO: 'Prima / primo', OUTRO: 'Outra pessoa',
};
export const SITUACAO_LEGAL: Record<string, { label: string; tone: Tone; hint: string }> = {
  CONFIRMADO: { label: 'Confirmada', tone: 'green', hint: 'Documento conferido (certidão, termo de guarda ou tutela).' },
  DECLARADO: { label: 'Declarada', tone: 'blue', hint: 'Informada pela família; conferir na matrícula.' },
  A_VERIFICAR: { label: 'A verificar', tone: 'amber', hint: 'Exige análise humana antes de decisões (guarda, retirada da criança).' },
};
export const SITUACAO_ALUNO: Record<string, { label: string; tone: Tone }> = {
  MATRICULADO: { label: 'Matriculado(a)', tone: 'green' },
  AGUARDANDO_VAGA: { label: 'Aguardando vaga', tone: 'purple' },
  SEM_VINCULO: { label: 'Sem vínculo', tone: 'gray' },
  TRANSFERENCIA: { label: 'Em transferência', tone: 'amber' },
  INATIVO: { label: 'Inativo(a)', tone: 'gray' },
};
export const TRANSPORTE_SITUACAO: Record<string, string> = { SOLICITADO: 'Solicitado', ATENDIDO: 'Atendido', NAO_ATENDIDO: 'Não atendido' };
export const PRECISAO: Record<string, { label: string; exata: boolean }> = {
  ENDERECO: { label: 'Endereço exato (com número)', exata: true },
  PONTO_NO_MAPA: { label: 'Ponto conferido no mapa', exata: true },
  LOGRADOURO: { label: 'Rua (sem o número)', exata: false },
  CEP: { label: 'Centro do CEP', exata: false },
  BAIRRO: { label: 'Centro do bairro', exata: false },
  DEMO_APROXIMADO: { label: 'Aproximada (demonstração)', exata: false },
};
export const precisaoRotulo = (p?: string | null) => (p ? PRECISAO[p]?.label ?? p.toLowerCase().replace(/_/g, ' ') : '—');

// ---------------------------------------------------------------- máscaras
export const soDigitos = (v: string | null | undefined) => (v ?? '').replace(/\D/g, '');
const agrupar = (d: string, tamanhos: number[], seps: string[]) => {
  let out = '';
  let i = 0;
  tamanhos.forEach((t, k) => {
    const parte = d.slice(i, i + t);
    if (!parte) return;
    out += (k > 0 ? seps[k - 1] : '') + parte;
    i += t;
  });
  return out;
};
export const mascaraCpf = (v: string) => agrupar(soDigitos(v).slice(0, 11), [3, 3, 3, 2], ['.', '.', '-']);
export const mascaraCep = (v: string) => agrupar(soDigitos(v).slice(0, 8), [5, 3], ['-']);
export const mascaraNis = (v: string) => agrupar(soDigitos(v).slice(0, 11), [3, 5, 2, 1], ['.', '.', '-']);
export const mascaraSus = (v: string) => agrupar(soDigitos(v).slice(0, 15), [3, 4, 4, 4], [' ', ' ', ' ']);
export const mascaraInep = (v: string) => soDigitos(v).slice(0, 12);
/** Matrícula da certidão de nascimento (32 dígitos): 000000 00 00 0000 0 00000 000 0000000 00 */
export const mascaraCertidao = (v: string) => agrupar(soDigitos(v).slice(0, 32), [6, 2, 2, 4, 1, 5, 3, 7, 2], [' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ']);
export function mascaraTelefone(v: string) {
  const d = soDigitos(v).slice(0, 11);
  if (d.length <= 2) return d ? `(${d}` : '';
  if (d.length <= 6) return `(${d.slice(0, 2)}) ${d.slice(2)}`;
  if (d.length <= 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
  return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`;
}
export const mascarado = (v?: string | null) => !!v && /[•*]/.test(v);

// ---------------------------------------------------------------- validações
export function cpfValido(v: string) {
  const d = soDigitos(v);
  if (d.length !== 11 || /^(\d)\1{10}$/.test(d)) return false;
  const dv = (n: number) => {
    let s = 0;
    for (let i = 0; i < n; i++) s += Number(d[i]) * (n + 1 - i);
    const r = (s * 10) % 11;
    return r === 10 ? 0 : r;
  };
  return dv(9) === Number(d[9]) && dv(10) === Number(d[10]);
}
export function nisValido(v: string) {
  const d = soDigitos(v);
  if (d.length !== 11) return false;
  const w = [3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
  const s = w.reduce((acc, p, i) => acc + p * Number(d[i]), 0);
  let r = 11 - (s % 11);
  if (r >= 10) r = 0;
  return r === Number(d[10]);
}

export const fmtMoeda = (n: number | string | null | undefined) =>
  n == null || n === '' ? '—' : Number(n).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
export const fmtDistancia = (m: number | null | undefined) => (m == null ? '—' : m < 1000 ? `${m} m` : `${(m / 1000).toFixed(1).replace('.', ',')} km`);

export type Endereco = {
  logradouro: string; numero: string; complemento: string; bairro: string; cep: string; cidade: string; uf: string;
  referencia: string; zona: 'URBANA' | 'RURAL'; lat: number | null; lng: number | null; precisao: string; fonte: string;
};
export const enderecoVazio = (): Endereco => ({
  logradouro: '', numero: '', complemento: '', bairro: '', cep: '', cidade: 'Maringá', uf: 'PR', referencia: '', zona: 'URBANA',
  lat: null, lng: null, precisao: '', fonte: '',
});
/** Endereço vindo do servidor (iara.endereco_json) para o formulário. */
export function enderecoDoServidor(a: any | null | undefined): Endereco | null {
  if (!a) return null;
  return {
    logradouro: a.logradouro ?? '', numero: a.numero ?? '', complemento: a.complemento ?? '', bairro: a.bairro ?? '', cep: a.cep ?? '',
    cidade: a.cidade ?? 'Maringá', uf: a.uf ?? 'PR', referencia: a.referencia ?? '', zona: a.zona === 'RURAL' ? 'RURAL' : 'URBANA',
    lat: a.lat ?? null, lng: a.lng ?? null, precisao: a.precisao ?? '', fonte: a.fonte ?? '',
  };
}
