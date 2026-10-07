// Teste de ponta a ponta do Sprint 3 pelo gateway publicado: IARA (transporte e aviso), rota não executada e ciclo do pedido de material.
// Uso: node scripts/teste-transporte.mjs — lança dados ao vivo; depois: select iara.demo_purge_sprint3('<início>');
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

let u = ult(await falar('o ônibus da Ana já passou?'));
const card = (u?.payload?.cards ?? [])[0];
ok('I1. IARA mostra a rota da Ana, o ponto e a situação de hoje', /Transporte escolar/.test(u?.body ?? '') && /rota R-/.test(card?.title ?? '') && (card?.lines ?? []).some((l) => /^Ponto:/.test(l)),
  card?.title);
u = ult(await falar('a Ana não vai de van amanhã'));
if (/Ida|volta/i.test(u?.body ?? '')) u = ult(await falar('Ida e volta', 'ans:AMBOS'));
ok('I2. Família avisa pela IARA que a Ana não usa o transporte amanhã', /Aviso registrado/.test(u?.body ?? ''), u?.body?.slice(0, 100));

const tr = await sessao('TRANSPORTE');
const dir = await sessao('DIRETOR_UNIDADE', 76);
const painel = (await rpc('transporte_painel', { unit_id: 76 }, tr)).data;
const rota = painel.lista?.[0];
let r = await rpc('transporte_viagem_registrar', { rota_id: rota.id, sentido: 'VOLTA', situacao: 'CONCLUIDA', atraso_min: 18, motivo: 'Chuva forte' }, tr);
ok('T1. Gerência registra a volta com 18 min de atraso: famílias avisadas', r.status === 200 && r.data.familias_avisadas >= 1, `${r.data.familias_avisadas} família(s)`);
const fam2 = (await rpc('familia_transporte', {}, fam)).data;
ok('T2. A família vê a volta como concluída com atraso', fam2.some((k) => k.rota?.hoje?.volta?.atraso_min === 18), JSON.stringify(fam2[0]?.rota?.hoje?.volta ?? {}).slice(0, 120));
r = await rpc('transporte_viagem_registrar', { rota_id: rota.id, sentido: 'VOLTA', situacao: 'CONCLUIDA' }, dir);
ok('T3. Direção não registra viagem', r.status === 403, `${r.status}`);

// pedido de material: escola → almoxarifado → remessa → recebimento
const al = await sessao('ALMOXARIFADO');
r = await rpc('pedido_criar', { itens: [{ codigo: 'PED-002', quantidade: 6 }, { codigo: 'ALI-002', quantidade: 10 }], justificativa: 'Reposição do bimestre' }, dir);
const ped = r.data;
ok('P1. Escola envia o pedido', r.status === 200 && ped.situacao === 'ENVIADO', ped.numero);
r = await rpc('pedido_decidir', { id: ped.id, aprovar: true }, al);
ok('P2. Almoxarifado aprova', r.data.situacao === 'APROVADO');
r = await rpc('pedido_despachar', { id: ped.id }, al);
ok('P3. Remessa despachada com lote do feijão', r.data.situacao === 'EM_TRANSPORTE' && r.data.itens.some((i) => i.codigo === 'ALI-002' && i.lotes.length > 0));
const itemFeijao = r.data.itens.find((i) => i.codigo === 'ALI-002');
r = await rpc('pedido_receber', { id: ped.id, itens: [{ id: itemFeijao.id, recebida: 9, divergencia: 'Um pacote rasgado' }] }, dir);
ok('P4. Escola recebe com divergência explicada', r.data.situacao === 'RECEBIDO_PARCIAL', r.data.situacao ?? r.data.error);

console.log(out.join('\n'));
console.log(`\n${out.filter((x) => x.startsWith('FALHA')).length} falha(s)`);
