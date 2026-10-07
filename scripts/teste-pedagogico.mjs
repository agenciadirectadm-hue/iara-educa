// Teste de ponta a ponta do Sprint 2 pelo gateway publicado: IARA (boletim, declaração, AEE) e verificação pública sem login.
// Uso: node scripts/teste-pedagogico.mjs — lança dados ao vivo; depois: select iara.demo_purge_sprint2('<início>');
const API = process.env.IARA_API ?? 'https://fqpjbyhewzngutbyydig.supabase.co/functions/v1/api';
const out = [];
const ok = (passo, cond, extra = '') => { out.push(`${cond ? 'OK   ' : 'FALHA'} ${passo}${extra ? '  ' + extra : ''}`); };
async function req(path, body, token) {
  const r = await fetch(API + path, { method: 'POST', headers: { 'content-type': 'application/json', ...(token ? { 'x-iara-session': token } : {}) }, body: JSON.stringify(body ?? {}) });
  return { status: r.status, data: await r.json().catch(() => ({})) };
}
const rpc = (fn, args, token) => req('/rpc/' + fn, args, token);
const sessao = async (persona, unit_id = null) => (await req('/session', { persona, unit_id })).data.token;
const ult = (x) => (x.messages ?? []).filter((y) => y.sender_type === 'IARA').slice(-1)[0];

const fam = await sessao('CIDADAO');
const conv = (await rpc('iara_conversation', { new: true }, fam)).data.conversation.id;
const falar = async (text, action) => {
  let m = (await req('/iara/message', { conversation_id: conv, text, action }, fam)).data;
  if ((ult(m)?.payload?.quick_replies ?? []).some((q) => (q.action ?? '').startsWith('verify'))) {
    m = (await req('/iara/message', { conversation_id: conv, text: 'Confirmar código', action: 'verify:482913' }, fam)).data;
  }
  return m;
};

let m = await falar('quero ver o boletim da Ana');
let u = ult(m);
ok('I1. IARA mostra o boletim (parecer da educação infantil)', /Boletim/.test(u?.body ?? '') && (u?.payload?.cards ?? []).some((c) => /Parecer/.test(c.badge ?? '')), u?.body);

m = await falar('preciso da declaração de frequência para o bolsa família');
u = ult(m);
if (/qual criança/i.test(u?.body ?? '')) {
  const ana = (u.payload.quick_replies ?? []).find((q) => /Ana/.test(q.label));
  m = await falar('Ana', ana?.action);
  u = ult(m);
}
const card = (u?.payload?.cards ?? [])[0];
const codigo = (card?.subtitle ?? '').match(/[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}/)?.[0];
ok('I2. IARA emite a declaração de frequência com código', /emitida/.test(u?.body ?? '') && !!codigo && /frequência/.test(card?.lines?.[0] ?? ''), codigo ?? u?.body);
ok('I3. A resposta traz o endereço de verificação', (card?.lines ?? []).some((l) => l.includes(`#/verificar/${codigo}`)));

let r = await rpc('declaracao_verificar', { codigo });
ok('V1. Verificação pública sem login: válida, nome abreviado', r.status === 200 && r.data.encontrada && r.data.situacao === 'VALIDA' && !/Souza|Oliveira/.test(r.data.aluno ?? '') && !r.data.conteudo,
  `${r.status} ${r.data.aluno}`);
r = await rpc('declaracao_verificar', { codigo: 'AAAA-BBBB-CCCC' });
ok('V2. Código inexistente não autentica', r.status === 200 && r.data.encontrada === false);
r = await rpc('declaracao_emitir', { student_id: '00000000-0000-0000-0000-000000000000', tipo: 'MATRICULA' });
ok('V3. Sem login não emite', r.status >= 400, `${r.status}`);

m = await falar('plano do aee');
u = ult(m);
ok('I4. IARA responde sobre o AEE (sem plano para a Maria)', /AEE|atendimento educacional/i.test(u?.body ?? ''), u?.body?.slice(0, 90));

const aee = await sessao('PROFESSOR_AEE', 76);
const me = (await rpc('me', {}, aee)).data;
const lista = (await rpc('aee_lista', { situacao: 'MEUS' }, aee)).data;
ok('A1. Professor(a) do AEE entra e vê os alunos que atende', me.role === 'PROFESSOR_AEE' && lista.contagem?.meus > 0, `${me.display_name} · ${lista.contagem?.meus} aluno(s)`);
const prof = await sessao('PROFESSOR', 76);
r = await rpc('aee_plano', { student_id: lista.itens?.[0]?.student_id }, prof);
ok('A2. Regente não abre o plano completo', r.status === 403, `${r.status}`);

console.log(out.join('\n'));
console.log(`\n${out.filter((x) => x.startsWith('FALHA')).length} falha(s)`);
