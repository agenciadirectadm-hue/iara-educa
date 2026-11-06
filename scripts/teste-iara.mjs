// Teste de conversa com a IARA pelo gateway (simula o WhatsApp), sem chaves: usa sessões de demonstração.
// Uso: node scripts/teste-iara.mjs [nova|maria|escola|conversa|recado|avisos|sem-dado|recusa|reuniao]
// "conversa" não grava nada além das próprias mensagens e confere as respostas: sai com erro se a IARA voltar a não entender.
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

const falhas = [];
/** Envia e confere a última resposta da IARA. */
async function espera(text, padrao) {
  await send(text);
  const ultimas = (conv.messages ?? []).slice(-6).filter((m) => m.sender_type === 'IARA').map((m) => m.body).join(' ');
  if (!padrao.test(ultimas) || /não entendi|Não consegui entender/i.test(ultimas)) falhas.push(`${text} → ${ultimas.slice(0, 160)}`);
}

if (roteiro === 'conversa') {
  await espera('minha filha nao esta muito bem hoje. Dá pra falar com a professora?', /Sinto muito.*agenda da turma/s);
  await espera('na verdade, tive mais uma criança e quero creche para ela', /nome completo/);
  await espera('Joaquim', /sobrenome de Joaquim/);
  await espera('Documentos', /confirmar sua identidade/);
  await espera('sim', /Documentos das crianças/);
  await espera('e o davi, faltadocumento/', /Documentos de Davi/);
  await espera('quero ver o que falta para o davi', /Documentos de Davi/);
  await espera('qual o cardápio de hoje?', /Cardápio/);
  await espera('qual a turma da ana?', /Ana estuda/);
  await espera('quero creche', /Para qual criança/);
  await espera('a vaga é para joaquim', /Joaquim é uma criança nova/);
  await espera('não entendi', /vou repetir/);
  await espera('deixa pra lá', /recomeçamos/);
  if (falhas.length) {
    console.error('\nFALHAS:\n' + falhas.join('\n'));
    process.exit(1);
  }
} else if (roteiro === 'recusa') {
  // recusa de vaga: o histórico da família, a lista de motivos e "Outro motivo" pedindo o texto. Usa uma oferta inexistente,
  // então nada é gravado além das mensagens; a gravação do motivo está em supabase/tests/recusas_vaga.sql.
  const ultimaIara = () => [...(conv.messages ?? [])].reverse().find((m) => m.sender_type === 'IARA');
  await send('quero ver as vagas que recusei');
  if (lastQuick(conv).some((q) => q.label.startsWith('Confirmar código'))) await tap('Confirmar código');
  const cards = (conv.messages ?? []).slice(-8).flatMap((m) => m.payload?.cards ?? []);
  const recusa = cards.find((c) => c.badge === 'recusada');
  if (!recusa) falhas.push('a recusa da família não apareceu no histórico');
  else if (!(recusa.lines ?? []).some((l) => /Motivo: Turno ou horário não atende/.test(l))) falhas.push(`motivo errado no histórico: ${JSON.stringify(recusa.lines)}`);
  const falsa = '00000000-0000-4000-8000-000000000000';
  await send('Recusar vaga', `decline:${falsa}`);
  const botoes = lastQuick(conv);
  for (const b of ['Longe de casa/trabalho', 'Turno não atende', 'Aguardar outra unidade', 'Sem transporte', 'Irmãos em outra unidade', 'Vaga em outra escola', 'Mudança de endereço', 'Saúde ou adaptação', 'Outro motivo'])
    if (!botoes.some((q) => q.label === b)) falhas.push(`falta o botão ${b}`);
  if (botoes.some((q) => q.label.length > 24)) falhas.push('botão com mais de 24 letras');
  if (!botoes.find((q) => q.label === 'Longe de casa/trabalho')?.action.endsWith(':Unidade longe de casa ou do trabalho')) falhas.push('o botão não envia o motivo completo');
  await tap('Outro motivo');
  if (!/poucas palavras/.test(ultimaIara()?.body ?? '')) falhas.push(`Outro motivo não pediu o texto: ${ultimaIara()?.body}`);
  await send('a família vai se mudar para outra cidade');
  // a oferta não existe: a IARA tenta gravar a recusa com o texto digitado e o banco recusa, sem gravar nada
  if (!/Oferta não encontrada/.test(ultimaIara()?.body ?? '')) falhas.push(`o texto não foi para a recusa: ${ultimaIara()?.body?.slice(0, 160)}`);
  // uma pergunta no meio da recusa não pode virar motivo: recusar libera a vaga
  await send('Recusar vaga', `decline:${falsa}`);
  await send('qual o prazo para responder a oferta?');
  if (/Oferta não encontrada/.test(ultimaIara()?.body ?? '')) falhas.push('a pergunta virou motivo de recusa');
  // resposta curta demais não recusa: pede o motivo de novo
  await send('Recusar vaga', `decline:${falsa}`);
  await send('sim');
  if (!/poucas palavras/.test(ultimaIara()?.body ?? '')) falhas.push(`resposta curta não pediu o motivo: ${ultimaIara()?.body?.slice(0, 160)}`);
  // e um motivo escrito de próprio punho, sem tocar em botão, vale
  await send('a creche fica muito longe da minha casa');
  if (!/Oferta não encontrada/.test(ultimaIara()?.body ?? '')) falhas.push(`o motivo escrito não foi para a recusa: ${ultimaIara()?.body?.slice(0, 160)}`);
  if (falhas.length) {
    console.error('\nFALHAS:\n' + falhas.join('\n'));
    process.exit(1);
  }
  console.log('\n✓ Recusa: histórico, motivos e Outro motivo.');
} else if (roteiro === 'sem-dado') {
  // o que a IARA não tem: diz que não tem neste momento, em vez de pedir para reformular; e o que dá para responder, responde
  for (const p of ['quero saber se na escola tem energia eletrica', 'a escola tem piscina?', 'o uniforme é de que cor?', 'qual o nome da cozinheira?', 'a quadra da escola é coberta?']) {
    await send(p);
    const resposta = [...(conv.messages ?? [])].reverse().find((m) => m.sender_type === 'IARA')?.body ?? '';
    if (!/Não tenho esta informação neste momento/.test(resposta)) falhas.push(`${p} → ${resposta.slice(0, 160)}`);
  }
  await espera('quero saber se a escola esta aberta hoje', /dia de aula|não tem aula|fim de semana|ano letivo terminou/);
  await espera('tem aula amanhã?', /dia de aula|não tem aula|fim de semana|ano letivo terminou/);
  await espera('qual o cardápio de hoje?', /Cardápio/);
  await espera('quantas faltas a Ana tem?', /confirmar sua identidade/);
  if (falhas.length) {
    console.error('\nFALHAS:\n' + falhas.join('\n'));
    process.exit(1);
  }
  console.log('\n✓ O que não tem, diz que não tem.');
} else if (roteiro === 'reuniao') {
  // registro de reunião da Ana Luísa: o aviso vem antes de qualquer assunto, e a leitura traz os dois botões.
  // Não responde, para não mudar o registro de demonstração.
  await espera('oi', /registro da escola|Antes de continuar|URGENTE/);
  await tap('Ler e responder');
  if (lastQuick(conv).some((q) => q.label.startsWith('Confirmar código'))) await tap('Confirmar código');
  const botoes = lastQuick(conv).map((q) => q.label);
  if (!botoes.includes('Confirmo o registro') || !botoes.includes('Quero me manifestar')) falhas.push(`sem os botões de resposta: ${botoes.join(', ')}`);
} else if (roteiro === 'avisos') {
  // avisos: todo aviso com data e hora e ciência; a ciência leva ao histórico. Grava ciências ao vivo; saem com "Limpar depois da apresentação".
  await send('tem algum aviso da escola?');
  if (lastQuick(conv).some((q) => q.label.startsWith('Confirmar código'))) await tap('Confirmar código');
  const ultimaIara = () => [...(conv.messages ?? [])].reverse().find((m) => m.sender_type === 'IARA');
  const cartoes = ultimaIara()?.payload?.cards ?? [];
  if (!cartoes.length || !cartoes.every((c) => /enviado em \d{2}\/\d{2}\/\d{4} às \d{2}:\d{2}/.test(c.subtitle ?? ''))) falhas.push(`avisos sem data e hora: ${JSON.stringify(cartoes.map((c) => c.subtitle)).slice(0, 200)}`);
  const ciente = lastQuick(conv).find((q) => q.label.startsWith('Estou ciente'));
  if (!ciente) falhas.push('sem o botão de ciência');
  else {
    const titulo = ciente.label.replace('Estou ciente: ', '');
    await send(ciente.label, ciente.action);
    if (!/foi para o histórico/.test(ultimaIara()?.body ?? '')) falhas.push(`ciência → ${(ultimaIara()?.body ?? '').slice(0, 120)}`);
    await send('qual o historico de avisos?');
    const hist = ultimaIara()?.payload?.cards ?? [];
    if (!hist.some((c) => c.title.startsWith(titulo) && (c.lines ?? []).some((l) => /^Ciência em/.test(l)))) falhas.push(`não está no histórico: ${titulo}`);
    await send('tem algum aviso da escola?');
    if ((ultimaIara()?.payload?.cards ?? []).some((c) => c.title.startsWith(titulo))) falhas.push(`continua no quadro: ${titulo}`);
  }
  // agenda: o mesmo padrão
  await send('tem recado na agenda?');
  const cartoesAgenda = ultimaIara()?.payload?.cards ?? [];
  if (!cartoesAgenda.length || !cartoesAgenda.every((c) => /enviado em \d{2}\/\d{2}\/\d{4} às \d{2}:\d{2}/.test(c.subtitle ?? ''))) falhas.push(`agenda sem data e hora: ${JSON.stringify(cartoesAgenda.map((c) => c.subtitle)).slice(0, 200)}`);
  const cienteAgenda = lastQuick(conv).find((q) => q.label.startsWith('Ciente:'));
  if (!cienteAgenda) falhas.push('agenda sem o botão de ciência');
  else {
    const recado = cienteAgenda.label.replace('Ciente: ', '');
    await send(cienteAgenda.label, cienteAgenda.action);
    if (!/foi para o histórico/.test(ultimaIara()?.body ?? '')) falhas.push(`ciência da agenda → ${(ultimaIara()?.body ?? '').slice(0, 120)}`);
    await send('qual o historico de avisos?');
    const histAgenda = ultimaIara()?.payload?.cards ?? [];
    if (!histAgenda.some((c) => c.title.includes(recado.slice(0, 15)))) falhas.push(`recado não está no histórico: ${recado}`);
    await send('tem recado na agenda?');
    if (lastQuick(conv).some((q) => q.action === cienteAgenda.action)) falhas.push(`recado continua na agenda: ${recado}`);
  }
  if (falhas.length) {
    console.error(`\n✗ ${falhas.length} resposta(s) erradas:\n- ${falhas.join('\n- ')}`);
    process.exit(1);
  }
  console.log('\n✓ Avisos: tudo certo.');
} else if (roteiro === 'recado') {
  // recado à professora: criança sem turma, o que vem junto do "sim", correção do texto, e o que a professora da turma vê.
  // Grava bilhetes com a marca "teste-recado"; depois: delete from iara.agenda_escolar where texto like '%teste-recado%';
  await send('o davi nao passou bem hoje, pode avisar a professora');
  if (lastQuick(conv).some((q) => q.label.startsWith('Confirmar código'))) await tap('Confirmar código');
  const semTurma = (conv.messages ?? []).slice(-4).filter((m) => m.sender_type === 'IARA').map((m) => m.body).join(' ');
  if (!/Davi ainda não tem turma/.test(semTurma)) falhas.push(`Davi sem turma → ${semTurma.slice(0, 160)}`);
  await tap('É sobre Ana');
  const ultima = () => (conv.messages ?? []).slice(-6).filter((m) => m.sender_type === 'IARA').map((m) => m.body).join(' ');
  if (!/Ana não está se sentindo bem/.test(ultima())) falhas.push(`aviso pronto → ${ultima().slice(0, 160)}`);
  await espera('sim, peça para a professora cuidar da febre teste-recado', /entregue[\s\S]*cuidar da febre/);
  await espera('quero mandar um bilhete para a professora', /O que você quer dizer/);
  await espera('a ana vai sair mais cedo teste-recado', /Confirma/);
  await espera('acrescenta que o pai vem buscar', /sair mais cedo teste-recado\. O pai vem buscar[\s\S]*Confirma/);
  await espera('nao, diga que a avó vem buscar teste-recado', /“a avó vem buscar teste-recado”/);
  await espera('sim', /entregue/);
  await espera('quero mandar um bilhete para a professora', /O que você quer dizer/);
  await espera('vai sair cedo teste-recado-cancelado', /Confirma/);
  await espera('nao', /não enviei/);
  const { token: prof } = await req('/session', { persona: 'PROFESSOR', unit_id: Number(process.env.UNIDADE_MARIA || 76) });
  const recados = await req('/rpc/agenda_recados_familia', {}, prof);
  const textos = recados.map((r) => r.texto).join(' | ');
  console.log(`\nA professora da turma vê ${recados.length} recado(s): ${textos.slice(0, 400)}`);
  if (!/cuidar da febre teste-recado/.test(textos)) falhas.push('a professora não vê o recado da febre');
  if (!/a avó vem buscar teste-recado/.test(textos)) falhas.push('a professora não vê o recado corrigido');
  if (/teste-recado-cancelado/.test(textos)) falhas.push('o recado cancelado foi entregue');
  if (falhas.length) {
    console.error(`\n✗ ${falhas.length} resposta(s) erradas:\n- ${falhas.join('\n- ')}`);
    process.exit(1);
  }
  console.log('\n✓ Recado à professora: tudo certo.');
} else if (roteiro === 'nova') {
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
  await send('tem recado na agenda?');
  const ciente = lastQuick(conv).find((q) => (q.action ?? '').startsWith('ag_ok:'));
  if (ciente) await send(ciente.label, ciente.action);
  await send('quero mandar um bilhete para a professora');
  await send('A Ana vai sair mais cedo amanhã, às 16h, com o pai.');
  await tap('Sim');
  await send('tem alguma ocorrência?');
  const oc = lastQuick(conv).find((q) => (q.action ?? '').startsWith('oc_ok:'));
  if (oc) await send(oc.label, oc.action);
  await send('a Ana chegou em casa machucada, foi mordida por um colega');
  await send('Ontem à tarde ela chegou com uma marca de mordida no braço e ninguém avisou.');
  await tap('Sim');
} else {
  await send('oi');
  await send('a minha filha precisa trocar de turno');
  await tap('Confirmar código');
  await send('Gostaria do turno da manhã por causa do trabalho');
  await send('nasceu mais um filho');
  await send('Lucas Santos Oliveira');
  await send('02/08/2026');
  await tap('Sou a mãe');
  await tap('Não');
}
console.log('\nFim do roteiro.');
