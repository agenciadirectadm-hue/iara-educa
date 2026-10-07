// Teste de ponta a ponta dos arquivos pelo gateway (documento em PDF, foto sem EXIF/GPS, arquivo disfarçado, escopo de acesso,
// validação e recusa com orientação, anexo pela IARA, materiais e cadastro de servidores). Usa sessões de demonstração.
// Uso: node scripts/teste-arquivos.mjs — lança dados ao vivo; depois: select iara.demo_purge_sprint1('<início>'), iara.demo_limpar_arquivos_vivos('<início>');
const API = 'https://fqpjbyhewzngutbyydig.supabase.co/functions/v1/api';
const out = [];
const ok = (passo, cond, extra = '') => { out.push(`${cond ? 'OK   ' : 'FALHA'} ${passo}${extra ? '  ' + extra : ''}`); };
async function req(path, body, token, method = 'POST') {
  const r = await fetch(API + path, { method, headers: { 'content-type': 'application/json', ...(token ? { 'x-iara-session': token } : {}) }, body: method === 'GET' ? undefined : JSON.stringify(body ?? {}) });
  return { status: r.status, data: await r.json().catch(() => ({})) };
}
async function rpc(fn, args, token) { return req('/rpc/' + fn, args, token); }
async function enviar(token, params, bytes, tipo) {
  const q = new URLSearchParams(params);
  const r = await fetch(`${API}/arquivo?${q}`, { method: 'POST', headers: { 'content-type': tipo, 'x-iara-session': token }, body: bytes });
  return { status: r.status, data: await r.json().catch(() => ({})) };
}
async function baixar(token, id) {
  const r = await fetch(`${API}/arquivo/${id}`, { headers: { 'x-iara-session': token } });
  return { status: r.status, bytes: r.ok ? new Uint8Array(await r.arrayBuffer()) : null, tipo: r.headers.get('content-type') };
}
const sessao = async (persona, unit_id = null) => (await req('/session', { persona, unit_id })).data.token;

const pdf = new TextEncoder().encode('%PDF-1.4\n1 0 obj << /Type /Catalog >> endobj\ntrailer << /Root 1 0 R >>\n%%EOF\n');
const jpegBase = Buffer.from('/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=', 'base64');
const exif = Buffer.concat([Buffer.from('Exif\0\0', 'binary'), Buffer.from('GPSLatitude -23.4205 GPSLongitude -51.9333 ', 'binary')]);
const app1 = Buffer.concat([Buffer.from([0xff, 0xe1, ((exif.length + 2) >> 8) & 0xff, (exif.length + 2) & 0xff]), exif]);
const jpegGps = Buffer.concat([jpegBase.subarray(0, 2), app1, jpegBase.subarray(2)]);

const fam = await sessao('CIDADAO');
const docs = (await rpc('familia_documentos', {}, fam)).data;
const ana = docs.criancas.find((c) => c.primeiro_nome === 'Ana');
ok('F0. Família vê as crianças, documentos e pedidos', !!ana, `${docs.criancas.length} criança(s)`);

let r = await enviar(fam, { finalidade: 'DOCUMENTO', student_id: ana.student_id, doc_type: 'VACINACAO', nome: 'vacina.pdf' }, pdf, 'application/pdf');
ok('A1. Família envia PDF (fica aguardando conferência)', r.status === 200 && r.data.status === 'RECEBIDO', JSON.stringify(r.data).slice(0, 160));
const docId = r.data.documento_id; const pdfId = r.data.arquivo_id;
r = await enviar(fam, { finalidade: 'DOCUMENTO', student_id: ana.student_id, doc_type: 'CPF', nome: 'cpf.jpg' }, jpegGps, 'image/jpeg');
ok('A2. Foto como documento é recusada (documento só em PDF)', r.status >= 400, `${r.status} ${r.data.error}`);
r = await enviar(fam, { finalidade: 'DOCUMENTO', student_id: ana.student_id, doc_type: 'CPF', nome: 'malicioso.pdf' }, new TextEncoder().encode('<script>alert(1)</script>'), 'application/pdf');
ok('A3. Arquivo disfarçado de PDF é recusado (tipo pelo conteúdo)', r.status >= 400, `${r.status} ${r.data.error}`);
r = await enviar(fam, { finalidade: 'FOTO_ALUNO', student_id: ana.student_id, nome: 'ana.jpg' }, jpegGps, 'image/jpeg');
ok('A4. Família envia foto da criança (pendente de validação)', r.status === 200 && r.data.aplicada === false, JSON.stringify(r.data).slice(0, 160));
const fotoId = r.data.arquivo_id;
let b = await baixar(fam, fotoId);
const txt = b.bytes ? Buffer.from(b.bytes).toString('binary') : '';
ok('A5. Foto guardada sem EXIF/GPS', b.status === 200 && !txt.includes('Exif') && !txt.includes('GPSLatitude'), `${b.status} ${b.tipo} ${b.bytes?.length} bytes`);

const outra = await sessao('CIDADAO_NOVO');
b = await baixar(outra, pdfId);
ok('A6. Outra família não abre o documento', b.status === 403 || b.status === 404, `${b.status}`);
const dir = await sessao('DIRETOR_UNIDADE', 76);
const dirOutra = await sessao('DIRETOR_UNIDADE', 1);
b = await baixar(dir, pdfId);
ok('A7. Direção da unidade abre o PDF', b.status === 200 && b.tipo === 'application/pdf', `${b.status}`);
b = await baixar(dirOutra, pdfId);
ok('A8. Direção de outra unidade não abre', b.status === 403, `${b.status}`);
b = await baixar(null ?? '', pdfId);
ok('A9. Sem sessão não abre', b.status === 401, `${b.status}`);

const filaR = await rpc('validacoes_pendentes', {}, dir); const fila = filaR.data; 
ok('V1. Fila da unidade traz o documento e a foto', fila.documentos?.some((d) => d.id === docId) && fila.alteracoes?.some((a) => a.arquivo_id === fotoId), `docs ${fila.contagem?.documentos} · pedidos ${fila.contagem?.alteracoes}`);
r = await rpc('documento_decidir', { id: docId, aprovar: false, motivo: 'ok' }, dir);
ok('V2. Recusar sem motivo e orientação é negado', r.status >= 400, r.data.error);
r = await rpc('documento_decidir', { id: docId, aprovar: false, motivo: 'Página da vacina contra sarampo ilegível', orientacao: 'Envie um PDF legível, com todas as páginas da carteira.' }, dir);
ok('V3. Direção recusa com motivo e orientação', r.status === 200, r.data.error ?? '');
const altFoto = (fila.alteracoes ?? []).find((a) => a.arquivo_id === fotoId);
r = await rpc('alteracao_decidir', { id: altFoto.id, aprovar: true }, dir);
ok('V4. Direção aprova a foto', r.status === 200, r.data.error ?? '');
const docs2 = (await rpc('familia_documentos', {}, fam)).data;
const ana2 = docs2.criancas.find((c) => c.primeiro_nome === 'Ana');
const vac = ana2.documentos.find((d) => d.tipo === 'VACINACAO');
ok('V5. Família vê a recusa com motivo e como proceder, e o aviso', vac?.status === 'REJEITADO' && vac.orientacao?.includes('legível') && docs2.avisos.length > 0, vac?.motivo_recusa);
ok('V6. Foto aprovada entra na ficha', ana2.foto_arquivo_id === fotoId);

r = await rpc('familia_alterar_aluno', { student_id: ana.student_id, campos: { social_name: 'Aninha' } }, fam);
ok('D1. Família pede correção de dados (pendente)', r.status === 200, r.data.mensagem ?? r.data.error);
const outroAluno = (await rpc('alunos_lista', { limite: 1, unidade_id: 1 }, await sessao('SECRETARIO'))).data.itens?.[0]?.id;
r = await rpc('familia_alterar_aluno', { student_id: outroAluno, campos: { social_name: 'X' } }, fam);
ok('D2. Família não pede correção de criança de outra família', r.status === 403, `${r.status}`);

// anexo pela conversa da IARA (portal): PDF sem destino → IARA pergunta o tipo
r = await enviar(fam, { finalidade: 'CONVERSA', origem: 'IARA', nome: 'comprovante.pdf' }, pdf, 'application/pdf');
ok('I1. Anexo na conversa guardado', r.status === 200 && r.data.arquivo_id, JSON.stringify(r.data).slice(0, 100));
const conv = (await rpc('iara_conversation', { new: true }, fam)).data;
const convId = conv.conversation.id;
let m = (await req('/iara/message', { conversation_id: convId, text: '📎 comprovante.pdf', action: `arquivo:${r.data.arquivo_id}|pdf` }, fam)).data;
const ult = (x) => (x.messages ?? []).filter((y) => y.sender_type === 'IARA').slice(-1)[0];
if ((ult(m)?.payload?.quick_replies ?? []).some((q) => (q.action ?? '').startsWith('verify'))) {
  m = (await req('/iara/message', { conversation_id: convId, text: 'Confirmar código', action: 'verify:482913' }, fam)).data;
}
const pergunta = ult(m);
ok('I2. IARA pergunta que documento é', /documento|Qual/.test(pergunta?.body ?? ''), pergunta?.body?.slice(0, 80));
if (/qual criança/.test(ult(m)?.body ?? '')) m = (await req('/iara/message', { conversation_id: convId, text: 'Ana', action: `ans:${ana.student_id}` }, fam)).data;
m = (await req('/iara/message', { conversation_id: convId, text: 'Comprovante de endereço', action: 'ans:COMPROVANTE_ENDERECO' }, fam)).data;
ok('I3. Documento entra na ficha pela conversa', /recebido/i.test(ult(m)?.body ?? ''), ult(m)?.body?.slice(0, 120));

// materiais e profissionais
const mat = (await rpc('material_salvar', { nome: 'Teste de material', categoria: 'PEDAGOGICO', quantidade: 10, minimo: 5 }, dir)).data;
r = await rpc('material_movimentar', { id: mat.id, tipo: 'SAIDA', quantidade: 20 }, dir);
ok('M1. Saída maior que o estoque é negada', r.status >= 400, r.data.error);
r = await rpc('material_movimentar', { id: mat.id, tipo: 'SAIDA', quantidade: 7, motivo: 'Sala 3' }, dir);
ok('M2. Saída registrada e abaixo do mínimo', r.status === 200 && r.data.abaixo_minimo === true, `saldo ${r.data.quantidade}`);
r = await rpc('material_excluir', { id: mat.id, motivo: 'Cadastro de teste' }, dir);
ok('M3. Com movimentação, vira baixa (não apaga)', r.status === 200 && r.data.excluido === false, r.data.mensagem);
const novo = (await rpc('pessoal_salvar', { nome: 'Servidora Teste Silva', funcao: 'PROFESSOR', ch: 40, vinculo: 'Efetivo' }, dir)).data;
ok('P1. Direção inclui servidor na própria unidade', !!novo.id, JSON.stringify(novo).slice(0, 100));
r = await rpc('pessoal_salvar', { id: novo.id, nome: 'Servidora Teste Silva', funcao: 'PROFESSOR', ch: 40, unit_id: 1 }, dirOutra);
ok('P2. Direção de outra unidade não altera', r.status === 403, `${r.status}`);
r = await rpc('pessoal_excluir', { id: novo.id, motivo: 'Inclusão de teste' }, dir);
ok('P3. Sem histórico, exclusão apaga o cadastro', r.status === 200 && r.data.excluido === true, r.data.mensagem);
const prof = await sessao('PROFESSOR', 76);
r = await rpc('pessoal_salvar', { nome: 'Tentativa do Professor', funcao: 'PROFESSOR' }, prof);
ok('P4. Professor não inclui servidor', r.status === 403, `${r.status}`);

console.log(out.join('\n'));
console.log(`\n${out.filter((x) => x.startsWith('FALHA')).length} falha(s)`);
