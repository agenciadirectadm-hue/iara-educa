// Gera arquivos FICTÍCIOS no layout da carga, para ensaiar o caminho completo antes dos dados reais.
// Uso: node scripts/carga/gerar-ensaio.mjs --saida <pasta fora do repositório> [--ano 2026]
// Depois: SUPABASE_ACCESS_TOKEN=... node scripts/carga/carga.mjs ensaio --pasta <mesma pasta>
// Tudo é inventado: nomes de listas, CPFs com dígito válido gerados ao acaso, endereços em pontos de Maringá.
// A "posição oficial" da fila é calculada aqui com as regras da IN nº 025/2025 (CadÚnico 25, até 2 km 15, mãe solo 5;
// desempate pela data) para a conciliação conferir a ordem que o sistema calcula.
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, a) => (v.startsWith('--') ? [...acc, [v.slice(2), a[i + 1]]] : acc), []));
const saida = args.saida;
if (!saida) {
  console.error('Informe --saida <pasta fora do repositório>.');
  process.exit(1);
}
const ano = Number(args.ano || new Date().getFullYear());

let semente = 20261006;
const rnd = () => ((semente = (semente * 1103515245 + 12345) % 2147483648) / 2147483648);
const pick = (a) => a[Math.floor(rnd() * a.length)];
const pad = (n, k = 3) => String(n).padStart(k, '0');

function cpf() {
  const d = Array.from({ length: 9 }, () => Math.floor(rnd() * 10));
  for (const pesoIni of [10, 11]) {
    const s = d.reduce((acc, v, i) => acc + v * (pesoIni - i), 0);
    const r = (s * 10) % 11;
    d.push(r === 10 ? 0 : r);
  }
  const t = d.join('');
  return `${t.slice(0, 3)}.${t.slice(3, 6)}.${t.slice(6, 9)}-${t.slice(9)}`;
}

// metros → graus (aprox. na latitude de Maringá)
const desloca = (lat, lng, m, ang) => [lat + (m * Math.cos(ang)) / 111_320, lng + (m * Math.sin(ang)) / (111_320 * Math.cos((lat * Math.PI) / 180))];
const distancia = (a, b) => {
  const R = 6_371_008.8, r = Math.PI / 180;
  const dLat = (b[0] - a[0]) * r, dLng = (b[1] - a[1]) * r;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a[0] * r) * Math.cos(b[0] * r) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
};

const NOMES_F = ['Ana', 'Beatriz', 'Camila', 'Daniela', 'Eduarda', 'Fernanda', 'Gabriela', 'Helena', 'Isabela', 'Juliana', 'Larissa', 'Mariana'];
const NOMES_M = ['Arthur', 'Bernardo', 'Caio', 'Davi', 'Enzo', 'Felipe', 'Gael', 'Heitor', 'Igor', 'Joaquim', 'Lucas', 'Miguel'];
const SOBRENOMES = ['Ensaio', 'Teste', 'Fictício', 'Exemplo', 'Modelo', 'Amostra'];

const UNIDADES = [
  { codigo_unidade: 'ENS-U1', nome: 'CMEI Ensaio Primavera', nome_curto: 'Ensaio Primavera', tipo: 'CMEI', lat: -23.4205, lng: -51.9333, bairro: 'Zona 7' },
  { codigo_unidade: 'ENS-U2', nome: 'Escola Municipal Ensaio Horizonte', nome_curto: 'Ensaio Horizonte', tipo: 'ESCOLA', lat: -23.4050, lng: -51.9400, bairro: 'Zona 5' },
];
const TURMAS = [
  { codigo_turma: `ENS-${ano}-U1-CRE-A`, codigo_unidade: 'ENS-U1', serie: 'CRECHE', nome: 'Creche A', turno: 'INTEGRAL', capacidade_autorizada: 12 },
  { codigo_turma: `ENS-${ano}-U1-CRE-B`, codigo_unidade: 'ENS-U1', serie: 'CRECHE', nome: 'Creche B', turno: 'INTEGRAL', capacidade_autorizada: 12 },
  { codigo_turma: `ENS-${ano}-U1-PRE-A`, codigo_unidade: 'ENS-U1', serie: 'PRE', nome: 'Pré-escola A', turno: 'TARDE', capacidade_autorizada: 20 },
  { codigo_turma: `ENS-${ano}-U2-EF1-A`, codigo_unidade: 'ENS-U2', serie: 'EF1', nome: '1º ano A', turno: 'MANHA', capacidade_autorizada: 25 },
  { codigo_turma: `ENS-${ano}-U2-EF2-A`, codigo_unidade: 'ENS-U2', serie: 'EF2', nome: '2º ano A', turno: 'MANHA', capacidade_autorizada: 25 },
];
// idade na data de corte (31/03) por série — o mesmo critério da rede
const NASC = { CRECHE: () => new Date(ano - 1 - Math.floor(rnd() * 3), Math.floor(rnd() * 9), 1 + Math.floor(rnd() * 27)),
  PRE: () => new Date(ano - 5, Math.floor(rnd() * 12), 1 + Math.floor(rnd() * 27)),
  EF1: () => new Date(ano - 7, 4 + Math.floor(rnd() * 6), 1 + Math.floor(rnd() * 27)),
  EF2: () => new Date(ano - 8, 4 + Math.floor(rnd() * 6), 1 + Math.floor(rnd() * 27)) };
const iso = (d) => d.toISOString().slice(0, 10);

const responsaveis = [], alunos = [], vinculos = [], matriculas = [], fila = [];
let nResp = 0, nAluno = 0, nMat = 0;

function familia(unidade, perto) {
  const r = { codigo_responsavel: `ENS-R${pad(++nResp)}`, nome: `${pick(NOMES_F)} ${pick(SOBRENOMES)} ${pick(SOBRENOMES)}`, cpf: cpf(),
    sexo: 'F', cadunico: rnd() < 0.4 ? 'S' : 'N', mae_solo: rnd() < 0.3 ? 'S' : 'N', telefone: `(44) 9${Math.floor(1000 + rnd() * 8999)}-${Math.floor(1000 + rnd() * 8999)}`,
    logradouro: `Rua do Ensaio ${nResp}`, numero: String(10 + nResp), bairro: unidade.bairro };
  const [lat, lng] = desloca(unidade.lat, unidade.lng, perto ? 300 + rnd() * 1100 : 2600 + rnd() * 1500, rnd() * 2 * Math.PI);
  r.lat = lat.toFixed(6); r.lng = lng.toFixed(6);
  responsaveis.push(r);
  return r;
}
function crianca(resp, serie) {
  const a = { codigo_aluno: `ENS-A${pad(++nAluno)}`, nome: `${rnd() < 0.5 ? pick(NOMES_F) : pick(NOMES_M)} ${resp.nome.split(' ').slice(1).join(' ')}`,
    data_nascimento: iso(NASC[serie]()), sexo: rnd() < 0.5 ? 'F' : 'M', cor_raca: pick(['BRANCA', 'PARDA', 'PRETA', 'NAO_DECLARADA']),
    nome_mae: resp.nome, logradouro: resp.logradouro, numero: resp.numero, bairro: resp.bairro, lat: resp.lat, lng: resp.lng };
  alunos.push(a);
  vinculos.push({ codigo_aluno: a.codigo_aluno, codigo_responsavel: resp.codigo_responsavel, parentesco: 'MAE', principal: 'S', situacao_legal: 'CONFIRMADO' });
  return a;
}

// matriculados: preenchem parte das turmas
for (const t of TURMAS) {
  const u = UNIDADES.find((x) => x.codigo_unidade === t.codigo_unidade);
  for (let i = 0; i < Math.floor(t.capacidade_autorizada * 0.75); i++) {
    const a = crianca(familia(u, rnd() < 0.7), t.serie);
    matriculas.push({ codigo_matricula: `ENS-M${pad(++nMat, 4)}`, codigo_aluno: a.codigo_aluno, codigo_turma: t.codigo_turma, ano_letivo: ano,
      situacao: 'ATIVA', data_matricula: `${ano}-01-${pad(10 + (nMat % 15), 2)}`, tipo_entrada: 'RENOVACAO' });
  }
}
// fila de creche no CMEI: famílias sem filho matriculado ali (sem pontos de irmão)
const cmei = UNIDADES[0];
const esperam = [];
for (let i = 0; i < 15; i++) {
  const resp = familia(cmei, i % 2 === 0);
  const a = crianca(resp, 'CRECHE');
  const dist = distancia([cmei.lat, cmei.lng], [Number(resp.lat), Number(resp.lng)]);
  const pontos = (resp.cadunico === 'S' ? 25 : 0) + (dist <= 2000 ? 15 : 0) + (resp.mae_solo === 'S' ? 5 : 0);
  const data = new Date(Date.UTC(ano, 1, 1 + i * 3, 11 + (i % 5), 15));
  esperam.push({ a, pontos, data });
}
esperam.sort((x, y) => y.pontos - x.pontos || x.data - y.data);
esperam.forEach((e, i) => fila.push({ codigo_inscricao: `ENS-F${pad(i + 1)}`, codigo_aluno: e.a.codigo_aluno, codigo_unidade: cmei.codigo_unidade,
  serie: 'CRECHE', turno_preferido: 'INTEGRAL', integral: 'S', data_solicitacao: e.data.toISOString().slice(0, 16).replace('T', ' '),
  posicao_oficial: i + 1, pontuacao_oficial: e.pontos, categoria: 'SEM_ATENDIMENTO' }));

// dois problemas de propósito: um CPF inválido (aviso) e uma criança sem data de nascimento (erro)
responsaveis[1].cpf = '111.111.111-11';
alunos.push({ codigo_aluno: `ENS-A${pad(++nAluno)}`, nome: 'Criança sem nascimento (erro proposital)' });

const SERVIDORES = [
  { matricula_funcional: 'ENS-S01', nome: 'Professora Ensaio Um', codigo_unidade: 'ENS-U1', funcao: 'PROFESSOR', vinculo: 'Efetivo',
    cargo: 'Professor(a) de Educação Básica', carga_horaria_semanal: 40, data_admissao: '2015-03-02', escolaridade: 'Pós-graduação', formacao: 'Pedagogia', area_atuacao: 'Anos iniciais', situacao: 'ATIVO' },
  { matricula_funcional: 'ENS-S02', nome: 'Educadora Ensaio Dois', codigo_unidade: 'ENS-U1', funcao: 'EDUCADOR', vinculo: 'Efetivo',
    cargo: 'Educador(a) Infantil', carga_horaria_semanal: 40, data_admissao: '2019-02-04', escolaridade: 'Superior', formacao: 'Pedagogia', area_atuacao: 'Educação infantil', situacao: 'ATIVO' },
  { matricula_funcional: 'ENS-S03', nome: 'Auxiliar Ensaio Três', codigo_unidade: 'ENS-U1', funcao: 'AUXILIAR', vinculo: 'PSS',
    cargo: 'Auxiliar de Apoio Escolar', carga_horaria_semanal: 40, data_admissao: '2025-08-01', escolaridade: 'Médio', situacao: 'ATIVO' },
  { matricula_funcional: 'ENS-S04', nome: 'Professor Ensaio Quatro', codigo_unidade: 'ENS-U2', funcao: 'PROFESSOR', vinculo: 'Efetivo',
    cargo: 'Professor(a) de Educação Básica', carga_horaria_semanal: 20, data_admissao: '2011-03-14', escolaridade: 'Pós-graduação', formacao: 'Educação Física', area_atuacao: 'Educação Física', situacao: 'LICENCA' },
];

function csv(nome, linhas) {
  const cols = [...new Set(linhas.flatMap((l) => Object.keys(l)))];
  const esc = (v) => { const s = v == null ? '' : String(v); return /[;"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
  writeFileSync(join(saida, nome), '﻿' + [cols.join(';'), ...linhas.map((l) => cols.map((c) => esc(l[c])).join(';'))].join('\r\n') + '\r\n');
  console.log(`  ${nome.padEnd(18)} ${linhas.length} linha(s)`);
}

mkdirSync(saida, { recursive: true });
console.log(`Arquivos fictícios de ensaio (${ano}) em ${resolve(saida)}:`);
csv('unidades.csv', UNIDADES);
csv('turmas.csv', TURMAS.map((t) => ({ ...t, ano_letivo: ano })));
csv('servidores.csv', SERVIDORES);
csv('responsaveis.csv', responsaveis);
csv('alunos.csv', alunos);
csv('vinculos.csv', vinculos);
csv('matriculas.csv', matriculas);
csv('fila.csv', fila);
