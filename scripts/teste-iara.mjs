// Teste de conversa com a IARA pelo gateway (simula o WhatsApp), sem chaves: usa sessões de demonstração.
// Uso: node scripts/teste-iara.mjs [nova|maria|escola]
const API = process.env.API_URL || 'https://fqpjbyhewzngutbyydig.supabase.co/functions/v1/api';
const roteiro = process.argv[2] || 'nova';

async function req(path, body, token) {
  const res = await fetch(API + path, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(token ? { 'x-iara-session': token } : {}) },
    body: JSON.stringify(body ?? {}),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${path} → ${res.status}: ${data.error ?? JSON.stringify(data)}`);
  return data;
}

function show(conv, since) {
  const msgs = (conv.messages ?? []).slice(since);
  for (const m of msgs) {
    if (m.sender_type === 'CIDADAO') continue;
    const who = m.sender_type === 'IARA' ? 'IARA' : m.sender_type;
    console.log(`  ${who}: ${m.body.replace(/\n/g, ' ⏎ ').slice(0, 260)}`);
    for (const c of m.payload?.cards ?? []) console.log(`     ▸ ${c.title}${c.subtitle ? ' — ' + c.subtitle : ''} | ${(c.lines ?? []).join(' · ').slice(0, 200)}`);
    const q = (m.payload?.quick_replies ?? []).map((x) => (typeof x === 'string' ? x : x.label));
    if (q.length) console.log(`     [${q.join('] [')}]`);
  }
  return conv.messages?.length ?? 0;
}

function lastQuick(conv) {
  const m = [...(conv.messages ?? [])].reverse().find((x) => x.sender_type === 'IARA' && (x.payload?.quick_replies ?? []).length);
  return (m?.payload?.quick_replies ?? []).map((x) => (typeof x === 'string' ? { label: x } : x));
}

const persona = roteiro === 'nova' ? 'CIDADAO_NOVO' : 'CIDADAO';
const { token } = await req('/session', { persona });
let conv = await req('/rpc/iara_conversation', { new: true }, token);
const id = conv.conversation.id;
console.log(`Conversa ${id} (${persona})`);
let seen = show(conv, 0);

async function send(text, action = null) {
  console.log(`\n» ${text}${action ? `  (${action})` : ''}`);
  conv = await req('/iara/message', { conversation_id: id, text, action }, token);
  seen = show(conv, seen);
}
async function tap(match) {
  const q = lastQuick(conv).find((x) => (typeof match === 'string' ? x.label.startsWith(match) : match.test(x.label)));
  if (!q) throw new Error(`Botão não encontrado: ${match}`);
  return send(q.label, q.action ?? null);
}

if (roteiro === 'nova') {
  await tap('Acabamos de chegar');
  await send('Londrina');
  await send('Joana Ribeiro Duarte');
  await send('Zona 7');
  await tap('Pular');
  await tap('Sim');             // CadÚnico
  await tap('Sim');             // mãe solo
  await tap('Confirmar cadastro');
  await send('Pedro Ribeiro Duarte');
  await send('10/03/2023');
  await tap('Sou a mãe');
  await tap('Não');             // sem laudo
  await send('CMEI Pingo de Gente');
  await tap('Inscrever:');
  await send('mudei de endereço');
  await send('Jardim Alvorada');
  await send('Rua das Palmeiras, 85');
  await send('preciso de transporte escolar');
  await send('Moramos longe e não temos carro');
  await send('quero desistir da fila');
  await tap('Tirar da fila');
  await tap('Sim, desistir');
} else if (roteiro === 'escola') {
  // vida escolar (Sprint 1): frequência, justificativa, cardápio, restrição, avisos e calendário.
  // Lança dados ao vivo; depois: select iara.demo_purge_sprint1(<início do teste>);
  await send('oi');
  await send('quantas faltas a Ana tem?');
  await tap('Confirmar código');
  await tap('Justificar uma falta');
  if (lastQuick(conv).some((q) => /^\w{3}\. \d{2}\/\d{2}$/.test(q.label))) await tap(/^\w{3}\. \d{2}\/\d{2}$/);
  await send('Ela estava com febre e ficou em casa');
  await tap('Não');
  await send('qual o cardápio de hoje?');
  await send('ela tem intolerância à lactose');
  await tap('Sim');
  await send('tem algum aviso da escola?');
  const enquete = lastQuick(conv).find((q) => (q.action ?? '').startsWith('enq:'));
  if (enquete) await send(enquete.label, enquete.action);
  await send('quando é o próximo feriado?');
} else {
  await send('oi');
  await send('a minha filha precisa trocar de turno');
  await tap('Confirmar código');
  await send('Gostaria do turno da manhã por causa do trabalho');
  await send('nasceu mais um filho');
  await tap('Uma criança');
  await send('Lucas Santos Oliveira');
  await send('02/08/2026');
  await tap('Sou a mãe');
  await tap('Não');
}
console.log('\nFim do roteiro.');
