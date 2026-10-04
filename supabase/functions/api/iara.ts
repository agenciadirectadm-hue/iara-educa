// IARA — agente resolutiva de atendimento (capítulo 74), modo determinístico.
// Regras de ouro: só afirma sucesso após confirmação do backend; nunca inventa vaga, posição, prazo ou protocolo;
// dados pessoais só após verificação de identidade e vínculo; ferramentas rodam com as permissões do próprio cidadão.
// Princípio: o munícipe resolve tudo pelo WhatsApp, sem abrir o portal. A IARA resolve na hora o que é da alçada dela
// (cadastro, novo membro, mudança de endereço, inscrição e desistência da fila, dados, ofertas, documentos) e só
// encaminha o que exige decisão humana — para a secretaria da unidade ou para a Secretaria (SEDUC), conforme a alçada.

export type QuickReply = { label: string; action?: string };
export type Card = { title: string; subtitle?: string; lines?: string[]; unit_id?: number; badge?: string; tone?: string };
export type Reply = { body: string; payload?: { quick_replies?: QuickReply[]; cards?: Card[]; notice?: string } };
export type ToolLog = { tool: string; input: unknown; output: unknown; status: "OK" | "ERRO" | "NEGADO"; error?: string; ms: number; correlation_id: string; idempotency_key?: string };

type Ctx = { flow?: string | null; step?: string | null; data?: Record<string, any>; pending?: string | null };
export type ConvSnapshot = {
  conversation_id: string;
  state: string;
  context: Ctx | null;
  identity_verified: boolean;
  guardian_id: string | null;
  active_student_id: string | null;
  active_case_id: string | null;
};
export type Patch = {
  context?: Ctx;
  intent?: string;
  state?: string;
  identity_verified?: boolean;
  active_student_id?: string | null;
  active_case_id?: string | null;
  summary?: string;
  handoff_reason?: string;
  handoff_sector?: string;
};

type CallFn = (fn: string, args: unknown) => Promise<any>;

const norm = (s: string) => (s ?? "").toLowerCase().normalize("NFD").replace(/\p{Diacritic}/gu, "").trim();

const MENU: QuickReply[] = [
  { label: "Procurar vaga", action: "intent:procurar_vaga" },
  { label: "Posição na fila", action: "intent:fila" },
  { label: "Ofertas de vaga", action: "intent:oferta" },
  { label: "Acompanhar solicitação", action: "intent:acompanhar" },
  { label: "Documentos", action: "intent:documentos" },
  { label: "Encontrar unidade", action: "intent:unidade" },
  { label: "Falar com atendente", action: "intent:atendente" },
  { label: "Minha família", action: "intent:familia" },
  { label: "Outros serviços", action: "intent:servicos" },
];
const FAMILY_MENU: QuickReply[] = [
  { label: "Novo membro da família", action: "fam:novo_membro" },
  { label: "Mudança de endereço", action: "fam:mudanca" },
  { label: "Atualizar dados", action: "fam:atualizar" },
  { label: "Chegamos de outra cidade", action: "fam:outra_cidade" },
  { label: "Pedir transferência", action: "intent:transferencia" },
  { label: "Desistir da fila", action: "fam:desistencia" },
];
const SERVICES: { code: string; label: string }[] = [
  { code: "TROCA_TURNO", label: "Troca de turno" },
  { code: "INTEGRAL", label: "Educação integral" },
  { code: "TRANSPORTE", label: "Transporte escolar" },
  { code: "ALIMENTACAO", label: "Alimentação especial" },
  { code: "AEE", label: "AEE / inclusão" },
  { code: "DOCUMENTO", label: "Declarações" },
  { code: "ALTERACAO_RESPONSAVEL", label: "Alteração de responsável" },
  { code: "RECURSO", label: "Recurso da classificação" },
  { code: "RECLAMACAO", label: "Reclamação ou sugestão" },
];
const SERVICE_KB: Record<string, string> = {
  TROCA_TURNO: "", INTEGRAL: "integral", TRANSPORTE: "transporte escolar", ALIMENTACAO: "alimentacao merenda",
  AEE: "inclusao aee laudo", DOCUMENTO: "", ALTERACAO_RESPONSAVEL: "responsavel guarda", RECURSO: "fila criterios", RECLAMACAO: "",
};
/** Serviços que só fazem sentido para criança com matrícula ativa. */
const ENROLLED_ONLY = new Set(["TROCA_TURNO", "DOCUMENTO", "INTEGRAL", "ALIMENTACAO"]);
const NEEDS_CHILD = new Set(["TROCA_TURNO", "INTEGRAL", "TRANSPORTE", "ALIMENTACAO", "AEE", "DOCUMENTO", "ALTERACAO_RESPONSAVEL", "RECURSO"]);
/** Passos que esperam texto livre: o que a pessoa digita não deve ser confundido com outro assunto. */
const FREE_TEXT_STEPS = new Set(["name", "bairro", "street", "child_name", "adult_name", "city", "school", "phone", "email", "description", "question"]);

const STATUS_LABEL: Record<string, string> = {
  NOVO: "recebido", EM_ANALISE: "em análise", AGUARDANDO_DOCUMENTOS: "aguardando documentos", AGUARDANDO_FAMILIA: "aguardando sua resposta",
  VAGA_ENCONTRADA: "vaga encontrada (em validação)", VAGA_OFERTADA: "vaga ofertada", EM_FILA: "na fila", MATRICULA_CONCLUIDA: "matrícula concluída",
  NAO_ATENDIDO: "não atendido", RECURSO: "recurso em análise", ENCERRADO: "encerrado",
};
const DOC_LABEL: Record<string, string> = {
  CERTIDAO: "certidão de nascimento", CPF: "CPF", RG: "RG", COMPROVANTE_ENDERECO: "comprovante de endereço", CARTAO_SUS: "cartão SUS",
  VACINACAO: "carteira de vacinação", CADUNICO: "comprovante CadÚnico", DECLARACAO_TRABALHO: "declaração de trabalho", LAUDO: "laudo",
  TRANSFERENCIA: "declaração de transferência (ou histórico) da escola anterior", GUARDA: "termo de guarda",
};
const SHIFT_LABEL: Record<string, string> = { MANHA: "manhã", TARDE: "tarde", NOITE: "noite", INTEGRAL: "integral" };
const REL_CHILD: QuickReply[] = [
  { label: "Sou a mãe", action: "ans:MAE" }, { label: "Sou o pai", action: "ans:PAI" },
  { label: "Avó / avô", action: "ans:AVO" }, { label: "Outro responsável", action: "ans:RESPONSAVEL_LEGAL" },
];
const REL_ADULT: QuickReply[] = [
  { label: "Pai", action: "ans:PAI" }, { label: "Mãe", action: "ans:MAE" }, { label: "Avó / avô", action: "ans:AVO" },
  { label: "Padrasto / madrasta", action: "ans:PADRASTO" }, { label: "Companheiro(a)", action: "ans:COMPANHEIRO" }, { label: "Outro", action: "ans:OUTRO" },
];
const YES_NO: QuickReply[] = [{ label: "Sim", action: "ans:sim" }, { label: "Não", action: "ans:nao" }];
const REL_NAME: Record<string, string> = {
  MAE: "mãe", PAI: "pai", AVO: "avó/avô", RESPONSAVEL_LEGAL: "responsável legal", PADRASTO: "padrasto/madrasta", COMPANHEIRO: "companheiro(a)", OUTRO: "outro",
};

/** "no CMEI X" / "na Escola Municipal Y" (CMEI é masculino) */
const naUnidade = (name?: string | null) => (!name ? "na unidade" : /^CMEI\s/i.test(name) ? `no ${name}` : `na ${name}`);
const daUnidade = (name?: string | null) => (!name ? "da unidade" : /^CMEI\s/i.test(name) ? `do ${name}` : `da ${name}`);

function detectIntent(t: string): string {
  if (/(cancelar|menu|recomecar|inicio|ajuda)\b/.test(t)) return "menu";
  if (/(atendente|humano|uma pessoa|falar com alguem|servidor)/.test(t)) return "atendente";
  if (/(reclama|ouvidoria|denunci|sugest)/.test(t)) return "servico:RECLAMACAO";
  if (/(vou me mudar para|mudar de cidade|morar em outra cidade|sair de maringa|vamos embora de maringa|mudando de cidade)/.test(t)) return "saida";
  if (/(outra cidade|outro municipio|outro estado|viemos de|vim de|chegamos|cheguei|acabamos de chegar|mudamos para maringa|mudei para maringa|de fora de maringa|transferencia de fora|transferencia de outr)/.test(t)) return "outra_cidade";
  if (/(fazer (o |meu )?cadastro|me cadastrar|cadastrar (a |minha )?familia|nao tenho cadastro|criar (o |meu )?cadastro)/.test(t)) return "cadastro";
  if (/(nasceu|recem.?nascid|novo membro|novo filho|nova filha|outro filho|outra filha|mais um filho|incluir (meu|minha|um|uma|o|a) |adotei|adocao|tenho a guarda|ganhei a guarda)/.test(t)) return "novo_membro";
  if (/(mudei|me mudei|mudamos|mudanca de endereco|mudar de endereco|mudar de casa|novo endereco|endereco novo|alterar (o )?endereco|trocar (o )?endereco)/.test(t)) return "mudanca";
  if (/(desist|tirar d[ao] fila|sair da fila|cancelar (a )?inscricao|nao quero mais a vaga)/.test(t)) return "desistencia";
  if (/((atualizar|trocar|mudar|alterar) (o |meu |minha |os |meus )?(telefone|numero|celular|whatsapp|e-?mail|dados|cadastro))|cadunico|bolsa familia|mae solo|crio sozinha/.test(t)) return "atualizar";
  if (/(minha familia|dados da familia|composicao familiar)/.test(t)) return "familia";
  if (/(troca de turno|trocar de turno|mudar de turno|mudar o turno|outro turno)/.test(t)) return "servico:TROCA_TURNO";
  if (/(periodo integral|educacao integral|contraturno|\bintegral\b)/.test(t)) return "servico:INTEGRAL";
  if (/(transporte|onibus|van escolar)/.test(t)) return "servico:TRANSPORTE";
  if (/(merenda|alimentacao|dieta|alergia|intoleran)/.test(t)) return "servico:ALIMENTACAO";
  if (/(declaracao|historico escolar|atestado de matricula|comprovante de matricula)/.test(t)) return "servico:DOCUMENTO";
  if (/((alterar|trocar|mudar) (o )?responsavel|termo de guarda)/.test(t)) return "servico:ALTERACAO_RESPONSAVEL";
  if (/(recurso|contestar|discordo da posicao|classificacao errada)/.test(t)) return "servico:RECURSO";
  if (/(\baee\b|inclus|deficien|autis|\btea\b|\btgd\b|laudo|superdota|altas habilidades)/.test(t)) return "servico:AEE";
  if (/(outros servicos|outro servico|outras solicitacoes|servicos|tirar uma duvida)/.test(t)) return "servicos";
  if (/(oferta|aceitar|aceito|recusar|recuso)/.test(t)) return "oferta";
  if (/(posicao|fila|colocacao|lugar na)/.test(t)) return "fila";
  if (/(protocolo|acompanhar|andamento|solicitacao|status do pedido|meu pedido)/.test(t)) return "acompanhar";
  if (/(document|certidao|comprovante|vacina|cpf|cartao sus|\brg\b)/.test(t)) return "documentos";
  if (/(transfer|mudar de escola|trocar de escola|mudar de cmei|trocar de cmei)/.test(t)) return "transferencia";
  if (/(vaga|creche|matricul|pre.?escola|1.?\s?ano|primeiro ano|cmei para|estudar|inscrever|inscricao)/.test(t)) return "procurar_vaga";
  if (/(unidade|onde fica|perto de mim|mais proxim|encontrar escola|encontrar cmei|endereco da)/.test(t)) return "unidade";
  if (/(calendario|prazo|quando|rematricula|eja|etapa)/.test(t)) return "conhecimento";
  if (/^(oi|ola|bom dia|boa tarde|boa noite|e ai|hello|opa)\b/.test(t)) return "saudacao";
  if (/(obrigad|valeu|tchau|ate mais)/.test(t)) return "obrigado";
  return "desconhecido";
}

function parseDate(text: string): string | null {
  const m = text.match(/(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})/);
  if (!m) return null;
  let [, d, mo, y] = m;
  if (y.length === 2) y = (Number(y) > 40 ? "19" : "20") + y;
  const iso = `${y.padStart(4, "0")}-${mo.padStart(2, "0")}-${d.padStart(2, "0")}`;
  const dt = new Date(iso + "T12:00:00Z");
  if (Number.isNaN(dt.getTime()) || dt.getUTCDate() !== Number(d)) return null;
  return iso;
}

function yesNo(t: string): boolean | null {
  if (/^(sim|s|isso|claro|pode|quero|tenho|sou|esta|estou|confirm|ok|mora|moram)\b/.test(t)) return true;
  if (/^(nao|n|nunca|negativo|nao mora)\b/.test(t)) return false;
  return null;
}

/** "Rua das Flores, 123" → rua + número */
function splitStreet(text: string): { street: string; number: string | null } {
  const m = text.trim().match(/^(.*?)[,\s]+(?:n[º°o.]?\s*)?(\d{1,5}[a-zA-Z]?)\s*$/);
  if (m && m[1].trim().length >= 3) return { street: m[1].trim(), number: m[2] };
  return { street: text.trim(), number: null };
}

const km = (m: number | null | undefined) => (m == null ? "—" : `${(m / 1000).toFixed(1).replace(".", ",")} km`);
const dt = (iso: string) =>
  new Date(iso).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
const first = (name?: string | null) => (name ?? "").trim().split(/\s+/)[0] ?? "";

export class Agent {
  messages: Reply[] = [];
  tools: ToolLog[] = [];
  patch: Patch = {};
  ctx: Ctx;
  private home: any = null;
  private fam: any = null;

  constructor(private call: CallFn, private conv: ConvSnapshot) {
    this.ctx = { flow: null, step: null, data: {}, pending: null, ...(conv.context ?? {}) };
    this.ctx.data = this.ctx.data ?? {};
  }

  private say(body: string, payload?: Reply["payload"]) {
    this.messages.push({ body, payload });
  }

  private async tool<T = any>(tool: string, fn: string | null, args: Record<string, unknown>, idem?: string): Promise<T> {
    const started = Date.now();
    const correlation_id = crypto.randomUUID();
    try {
      const out = fn ? await this.call(fn, args) : { ok: true, simulated: true };
      this.tools.push({ tool, input: minimize(args), output: summarize(out), status: "OK", ms: Date.now() - started, correlation_id, idempotency_key: idem });
      return out as T;
    } catch (e) {
      const msg = (e as Error).message ?? String(e);
      this.tools.push({ tool, input: minimize(args), output: {}, status: /permiss|perfil/.test(msg) ? "NEGADO" : "ERRO", error: msg, ms: Date.now() - started, correlation_id });
      throw e;
    }
  }

  private async citizen(): Promise<any> {
    if (!this.home) this.home = await this.tool("get_student_service_context", "citizen_home", {});
    return this.home;
  }

  private async family(): Promise<any> {
    if (!this.fam) this.fam = await this.tool("get_family", "family_overview", {});
    return this.fam;
  }

  private resetCache() {
    this.home = null;
    this.fam = null;
  }

  private done(summary?: string) {
    this.ctx = { flow: null, step: null, data: {}, pending: null };
    if (summary) this.patch.summary = summary;
  }

  private ask(step: string, body: string, payload?: Reply["payload"]) {
    this.ctx.step = step;
    this.say(body, payload);
  }

  private verified(): boolean {
    return !!(this.conv.identity_verified || this.patch.identity_verified);
  }

  /** Sem cadastro: a IARA oferece fazer o cadastro ali mesmo e depois retoma o pedido. */
  private needGuardian(next?: string): boolean {
    if (this.conv.guardian_id) return true;
    this.say("Para isso preciso do cadastro da família — faço por aqui mesmo, em cerca de 1 minuto. 😊", {
      quick_replies: [{ label: "Fazer meu cadastro", action: `fam:cadastro${next ? "|" + next : ""}` }, { label: "Agora não", action: "nothing" }],
    });
    return false;
  }

  /** Dados pessoais exigem identidade + vínculo verificados (cap. 74.5). */
  private ensureVerified(pending: string): boolean {
    if (this.verified()) return true;
    this.ctx.pending = pending;
    this.say(
      "Para consultar ou mudar dados pessoais, preciso confirmar sua identidade e seu vínculo com a criança. Enviei um código de 6 dígitos para o telefone cadastrado.",
      { quick_replies: [{ label: "Confirmar código 482913", action: "verify:482913" }], notice: "Demonstração: o envio do código é simulado." },
    );
    return false;
  }

  async handle(text: string, action?: string | null): Promise<void> {
    const t = norm(text);
    try {
      if (action) return await this.onAction(action, text);
      if (/^\d{6}$/.test(t.replace(/\s/g, "")) && this.ctx.pending) return await this.onAction("verify:" + t.replace(/\s/g, ""), text);
      const intent = detectIntent(t);
      if (intent === "menu") {
        this.done();
        this.say("Tudo bem, recomeçamos. Como posso ajudar?", { quick_replies: this.conv.guardian_id ? MENU : this.newcomerMenu() });
        return;
      }
      if (this.ctx.flow && this.ctx.step && FREE_TEXT_STEPS.has(this.ctx.step) && intent !== "atendente") return await this.continueFlow(text);
      if (this.ctx.flow && this.ctx.step && ["desconhecido", "saudacao"].includes(intent)) return await this.continueFlow(text);
      if (this.ctx.flow && this.ctx.step && intent === "procurar_vaga" && this.ctx.flow === "procurar_vaga") return await this.continueFlow(text);
      return await this.route(intent, text);
    } catch (e) {
      const msg = (e as Error).message ?? "erro";
      this.say(`Não consegui concluir esta etapa: ${msg} Nada foi registrado nesta tentativa. Quer tentar de novo ou falar com um atendente?`,
        { quick_replies: [{ label: "Tentar de novo", action: "intent:" + (this.ctx.flow ?? "menu") }, MENU[6]] });
    }
  }

  private newcomerMenu(): QuickReply[] {
    return [
      { label: "Acabamos de chegar a Maringá", action: "intent:outra_cidade" },
      { label: "Fazer meu cadastro", action: "intent:cadastro" },
      { label: "Consultar vagas", action: "intent:procurar_vaga" },
      { label: "Encontrar unidade", action: "intent:unidade" },
      { label: "Outros serviços", action: "intent:servicos" },
    ];
  }

  private async route(intent: string, text: string): Promise<void> {
    this.patch.intent = intent;
    if (intent.startsWith("servico:")) return await this.startService(intent.slice(8));
    switch (intent) {
      case "saudacao": {
        if (!this.conv.guardian_id) {
          this.say("Oi! 💜 Eu sou a IARA, da Secretaria Municipal de Educação de Maringá. Ainda não encontrei cadastro para este número — se vocês acabaram de chegar à cidade, faço o cadastro e a inscrição na fila por aqui mesmo.",
            { quick_replies: this.newcomerMenu() });
          return;
        }
        const g = (await this.citizen())?.guardian?.first_name;
        this.say(`Oi${g ? ", " + g : ""}! Como posso ajudar hoje?`, { quick_replies: MENU });
        return;
      }
      case "obrigado":
        this.done();
        this.say("Por nada! Fico por aqui se precisar. 💜");
        return;
      case "procurar_vaga":
        return await this.startVaga();
      case "fila":
        return await this.queueStatus();
      case "acompanhar":
        return await this.caseStatus();
      case "oferta":
        return await this.offers();
      case "documentos":
        return await this.documents();
      case "unidade":
        this.ctx = { flow: "unidade", step: "bairro", data: {} };
        this.say("Me diga o bairro (ou o nome da unidade) e eu mostro as unidades mais próximas.", { quick_replies: [{ label: "Jardim Alvorada" }, { label: "Zona 7" }, { label: "Vila Morangueira" }] });
        return;
      case "atendente":
        return this.handoff("Pedido de atendimento humano");
      case "transferencia":
        return await this.startTransfer();
      case "familia":
        return await this.familyMenu();
      case "cadastro":
        return await this.startRegister(null);
      case "outra_cidade":
        return await this.startOutraCidade();
      case "novo_membro":
        return await this.startNewMember();
      case "mudanca":
        return await this.startMove();
      case "saida":
        return await this.startService("DOCUMENTO", "Declaração de transferência: a família vai se mudar de Maringá.");
      case "desistencia":
        return await this.startWithdraw();
      case "atualizar":
        return await this.startUpdate(norm(text));
      case "servicos":
        return this.servicesMenu();
      case "conhecimento":
        if (!text.trim() || /^(tirar uma )?duvida( sobre a rede)?$/.test(norm(text))) return this.askQuestion();
        return await this.knowledge(text);
      default:
        this.say("Desculpe, não entendi. Posso ajudar com estes assuntos:", { quick_replies: this.conv.guardian_id ? MENU : this.newcomerMenu() });
    }
  }

  private async onAction(action: string, text: string): Promise<void> {
    const [kind, ...rest] = action.split(":");
    const value = rest.join(":");
    switch (kind) {
      case "intent":
        if (value === "transferencia_reg") return await this.startTransfer();
        return await this.route(value, text);
      case "verify": {
        if (!this.needGuardian(this.ctx.pending ?? undefined)) return;
        await this.tool("verify_identity", null, { metodo: "codigo_sms_simulado" });
        this.patch.identity_verified = true;
        this.say("Identidade e vínculo confirmados ✅", { notice: "Verificação simulada no ambiente de demonstração." });
        const pending = this.ctx.pending;
        this.ctx.pending = null;
        if (pending) return await this.onAction(pending, text);
        this.say("O que você gostaria de fazer?", { quick_replies: MENU.slice(1, 5) });
        return;
      }
      case "fam": {
        const [op, ...nx] = value.split("|");
        const next = nx.join("|") || null;
        switch (op) {
          case "cadastro": return await this.startRegister(next);
          case "novo_membro": return await this.startNewMember();
          case "add_child": return await this.startAddChild(next);
          case "mudanca": return await this.startMove();
          case "atualizar": return await this.startUpdate(next ?? "");
          case "outra_cidade": return await this.startOutraCidade();
          case "desistencia": return await this.startWithdraw();
          default: return await this.familyMenu();
        }
      }
      case "ans":
      case "skip":
        return await this.continueFlow(kind === "skip" ? "__skip__" : value);
      case "svc":
        return await this.startService(value);
      case "svc_child":
        return await this.serviceChild(value);
      case "child":
        return await this.vagaChild(value);
      case "addr":
        return await this.vagaAddress(value);
      case "enroll":
        return await this.enrollQueue(Number(value));
      case "vaga":
        return await this.resumeVaga();
      case "oc":
        if (value === "school") {
          this.ctx.flow = "outra_cidade";
          return this.ask("school", `${this.ctx.data?.child_name ?? "A criança"} estudava em qual escola ou CMEI em ${this.ctx.data?.origin?.city ?? "sua cidade"}? (ou toque em Pular)`,
            { quick_replies: [{ label: "Pular", action: "skip:" }] });
        }
        return await this.ocChild();
      case "register":
        return await this.enrollQueue(Number(this.ctx.data?.unit_id));
      case "transfer_child":
        return await this.startTransferChild(value);
      case "withdraw":
        return this.confirmWithdraw(value);
      case "withdraw_confirm":
        return await this.withdraw(value);
      case "accept":
        return this.confirmAccept(value);
      case "accept_confirm":
        return await this.acceptOffer(value);
      case "decline":
        this.ctx = { flow: "oferta", step: "decline_reason", data: { offer_id: value } };
        this.say("Entendi. Qual o motivo da recusa? Isso ajuda a Central a melhorar as ofertas.", {
          quick_replies: ["Unidade distante", "Turno incompatível", "Prefiro aguardar outra unidade", "Outro motivo"].map((r) => ({ label: r, action: `decline_reason:${value}:${r}` })),
        });
        return;
      case "decline_reason": {
        const [offerId, ...reason] = value.split(":");
        return await this.declineOffer(offerId, reason.join(":"));
      }
      case "doc_send":
        return await this.sendDocument(value);
      case "handoff":
        return this.handoff(value || "Pedido do cidadão");
      case "nothing":
        this.done();
        this.say("Combinado! Se precisar, é só chamar. 💜");
        return;
      default:
        this.say("Não reconheci essa opção. Como posso ajudar?", { quick_replies: MENU });
    }
  }

  // ================================================================== família: menu e cadastro
  private async familyMenu(): Promise<void> {
    this.done();
    if (!this.conv.guardian_id) {
      this.say("Ainda não há cadastro da família neste número. Faço agora, por aqui mesmo?", {
        quick_replies: [{ label: "Fazer meu cadastro", action: "fam:cadastro" }, { label: "Acabamos de chegar a Maringá", action: "fam:outra_cidade" }],
      });
      return;
    }
    this.say("O que mudou na família? Eu atualizo na hora e recalculo a fila quando precisar:", { quick_replies: FAMILY_MENU });
  }

  private async startRegister(next: string | null): Promise<void> {
    if (this.conv.guardian_id) {
      this.say("Você já tem cadastro na rede ✅");
      if (next) return await this.onAction(next, "");
      return await this.familyMenu();
    }
    const carry = { ...(this.ctx.data ?? {}) };
    this.ctx = { flow: "cadastro", step: "name", data: { carry, next } };
    this.say("Vamos fazer o cadastro da família por aqui mesmo, sem ir à Secretaria. 😊 Qual é o **seu nome completo** (responsável)?", {
      notice: "Seus dados são usados só para o atendimento da rede municipal e ficam protegidos (LGPD).",
    });
  }

  private async findPlace(text: string) {
    const geo = await this.tool("locate_address", "geo_search", { q: text });
    const items = (geo?.items ?? []) as any[];
    return items.find((i) => i.kind === "BAIRRO") ?? items[0] ?? null;
  }

  private async registerStep(text: string): Promise<void> {
    const t = norm(text);
    const d = this.ctx.data ?? (this.ctx.data = {});
    switch (this.ctx.step) {
      case "name":
        if (text.trim().split(/\s+/).length < 2) return this.say("Preciso do nome completo (nome e sobrenome).");
        d.full_name = text.trim();
        return this.ask("bairro", `Obrigada, ${first(d.full_name)}! Em qual **bairro de Maringá** vocês moram?`);
      case "bairro": {
        const hit = await this.findPlace(text);
        if (!hit) return this.say("Não encontrei esse bairro. Pode escrever de outro jeito? (ex.: Jardim Alvorada, Zona 7, Vila Operária)");
        d.address = { neighborhood: hit.label, lat: hit.lat, lng: hit.lng, precision: hit.kind === "BAIRRO" ? "BAIRRO" : "UNIDADE_PROXIMA" };
        return this.ask("street", `Bairro **${hit.label}** ✅ Qual a rua e o número? (se preferir, toque em Pular)`, { quick_replies: [{ label: "Pular", action: "skip:" }] });
      }
      case "street":
        if (text !== "__skip__") Object.assign(d.address, splitStreet(text));
        return this.ask("cadunico", "A família está inscrita no **CadÚnico** (Cadastro Único)? Isso conta 25 pontos na fila.", { quick_replies: YES_NO });
      case "cadunico": {
        const yn = yesNo(t);
        if (yn === null) return this.say("Responda sim ou não, por favor.", { quick_replies: YES_NO });
        d.cadunico = yn;
        return this.ask("mae_solo", "Você é **mãe solo** (cria as crianças sem companheiro ou companheira)? Conta 5 pontos na fila.", {
          quick_replies: [...YES_NO, { label: "Prefiro não informar", action: "ans:nao" }],
        });
      }
      case "mae_solo": {
        const yn = yesNo(t);
        if (yn === null) return this.say("Responda sim ou não, por favor.", { quick_replies: YES_NO });
        d.single_mother = yn;
        const a = d.address ?? {};
        return this.ask("confirm",
          `Confere os dados?\n• Responsável: **${d.full_name}**\n• Endereço: ${a.street ? `${a.street}${a.number ? ", " + a.number : ""} — ` : ""}${a.neighborhood}\n• CadÚnico: ${d.cadunico ? "sim" : "não"} · Mãe solo: ${d.single_mother ? "sim" : "não"}`,
          { quick_replies: [{ label: "Confirmar cadastro", action: "ans:sim" }, { label: "Recomeçar", action: "ans:recomecar" }],
            notice: "As declarações (CadÚnico, mãe solo, endereço) são conferidas com os comprovantes na matrícula." });
      }
      case "confirm": {
        if (yesNo(t) !== true) {
          this.ctx = { flow: "cadastro", step: "name", data: { carry: d.carry ?? {}, next: d.next ?? null } };
          return this.say("Sem problema, vamos de novo. Qual é o seu nome completo?");
        }
        const res = await this.tool("register_family", "family_register", {
          full_name: d.full_name, address: d.address, cadunico: !!d.cadunico, single_mother: !!d.single_mother,
          channel: "WHATSAPP", origin: d.carry?.origin ?? null,
        });
        if (!res?.ok) throw new Error("o cadastro não foi confirmado.");
        this.conv.guardian_id = res.guardian_id;
        this.patch.identity_verified = true;
        this.resetCache();
        const carry = d.carry ?? {};
        const next = d.next ?? null;
        this.say(`Cadastro feito ✅ Protocolo **${res.protocol}**. Bem-vinda(o) à rede municipal de Maringá, ${first(d.full_name)}! 💜`);
        this.ctx = { flow: null, step: null, data: carry, pending: null };
        this.patch.summary = `Cadastro de família feito pela IARA (${res.protocol}).`;
        if (next) return await this.onAction(next, "");
        this.say("Agora vamos incluir as crianças?", { quick_replies: [{ label: "Incluir criança", action: "fam:add_child" }, { label: "Agora não", action: "nothing" }] });
        return;
      }
      default:
        this.done();
        return await this.route(detectIntent(t), text);
    }
  }

  // ================================================================== chegada de outra cidade
  private async startOutraCidade(): Promise<void> {
    this.ctx = { flow: "outra_cidade", step: "city", data: {} };
    this.say("Bem-vindos a Maringá! 💜 Eu cuido da vaga por transferência por aqui mesmo: cadastro, inscrição na fila e lista de documentos. **De qual cidade vocês vieram?**");
  }

  private async outraCidadeStep(text: string): Promise<void> {
    const d = this.ctx.data ?? (this.ctx.data = {});
    if (this.ctx.step === "city") {
      d.origin = { city: text.trim() };
      if (!this.conv.guardian_id) {
        this.say(`Anotado: vieram de ${text.trim()}. Primeiro, o cadastro da família (1 minuto).`);
        return await this.startRegister("oc:child");
      }
      return await this.ocChild();
    }
    if (this.ctx.step === "school") {
      if (text !== "__skip__") d.origin = { ...(d.origin ?? {}), school: text.trim() };
      return await this.applyGrade(d.birth_date as string);
    }
    this.done();
    return await this.route(detectIntent(norm(text)), text);
  }

  private async ocChild(): Promise<void> {
    this.resetCache();
    const fam = await this.family();
    const kids = ((fam?.children ?? []) as any[]).filter((k) => !k.school && !(k.queue ?? []).length);
    this.ctx.flow = "outra_cidade";
    if (!kids.length) return await this.startAddChild("oc:school");
    this.ctx.step = "pick_child";
    this.say("Para qual criança é a vaga?", {
      quick_replies: [...kids.map((k: any) => ({ label: k.first_name, action: `ans:${k.id}` })), { label: "Outra criança", action: "fam:add_child|oc:school" }],
    });
  }

  // ================================================================== novo membro da família
  private async startNewMember(): Promise<void> {
    if (!this.needGuardian("fam:novo_membro")) return;
    this.ctx = { flow: "novo_membro", step: "type", data: {} };
    this.say("Que bom! 💜 Quem chegou na família?", {
      quick_replies: [{ label: "Uma criança", action: "ans:crianca" }, { label: "Um adulto / responsável", action: "ans:adulto" }],
    });
  }

  private async startAddChild(next: string | null): Promise<void> {
    if (!this.needGuardian(`fam:add_child${next ? "|" + next : ""}`)) return;
    const carry = { ...(this.ctx.data ?? {}) };
    this.ctx = { flow: "novo_membro", step: "child_name", data: { ...carry, next } };
    this.say("Qual é o **nome completo da criança**?");
  }

  private async newMemberStep(text: string): Promise<void> {
    const t = norm(text);
    const d = this.ctx.data ?? (this.ctx.data = {});
    switch (this.ctx.step) {
      case "type":
        if (/adult|respons|pai|mae|avo/.test(t)) return this.ask("adult_name", "Qual é o **nome completo** dessa pessoa?");
        return await this.startAddChild(null);
      case "child_name":
        if (text.trim().split(/\s+/).length < 2) return this.say("Preciso do nome completo (nome e sobrenome).");
        d.child_full_name = text.trim();
        if (d.birth_date) return this.ask("child_rel", `Qual o seu parentesco com ${first(d.child_full_name)}?`, { quick_replies: REL_CHILD });
        return this.ask("child_birth", `Qual a data de nascimento de ${first(d.child_full_name)}? (ex.: 14/03/2024)`);
      case "child_birth": {
        const date = parseDate(text);
        if (!date) return this.say("Não entendi a data. Pode enviar no formato dia/mês/ano? (ex.: 14/03/2024)");
        d.birth_date = date;
        return this.ask("child_rel", `Qual o seu parentesco com ${first(d.child_full_name)}?`, { quick_replies: REL_CHILD });
      }
      case "child_rel":
        d.relationship = /^[A-Z_]+$/.test(text) ? text : /pai/.test(t) ? "PAI" : /mae/.test(t) ? "MAE" : /avo/.test(t) ? "AVO" : "RESPONSAVEL_LEGAL";
        return this.ask("child_aee", `${first(d.child_full_name)} tem deficiência, TEA, TGD ou altas habilidades/superdotação (com laudo)?`, { quick_replies: YES_NO });
      case "child_aee": {
        const yn = yesNo(t);
        if (yn === null) return this.say("Responda sim ou não, por favor.", { quick_replies: YES_NO });
        const res = await this.tool("add_family_member", "family_add_child", {
          full_name: d.child_full_name, birth_date: d.birth_date, relationship: d.relationship, aee: yn, channel: "WHATSAPP", origin: d.origin ?? null,
        });
        if (res?.ok === false) {
          this.say(res.message ?? "Encontrei um cadastro parecido; a equipe vai conferir.", { quick_replies: [MENU[3]] });
          return this.done(`Inclusão de criança encaminhada para conferência (${res.protocol}).`);
        }
        this.resetCache();
        d.child_id = res.student_id;
        d.child_name = res.first_name;
        d.grade_announced = !!res.grade_rule?.ok;
        this.patch.active_student_id = res.student_id;
        const grade = res.grade_rule?.ok ? res.grade_rule.grade_name : null;
        this.say(`✅ ${res.existing ? "Encontrei" : "Incluí"} **${res.first_name}** na família.${grade ? ` Pela data de corte, a faixa é **${grade}**.` : ""}${res.protocol ? ` Protocolo ${res.protocol}.` : ""}`,
          yn ? { notice: "Envie o laudo médico com CID quando puder: a prioridade fica sob análise da Central de Vagas, fora da soma de pontos (IN nº 025/2025)." } : undefined);
        const next = d.next as string | null;
        if (next) return await this.onAction(next, "");
        this.ask("after_child", `Quer inscrever ${res.first_name} na fila de espera agora?`, {
          quick_replies: [{ label: "Inscrever na fila", action: `child:${res.student_id}` }, { label: "Agora não", action: "nothing" }],
        });
        return;
      }
      case "adult_name":
        if (text.trim().split(/\s+/).length < 2) return this.say("Preciso do nome completo (nome e sobrenome).");
        d.adult_name = text.trim();
        return this.ask("adult_rel", `Qual o parentesco de ${first(d.adult_name)} com as crianças?`, { quick_replies: REL_ADULT });
      case "adult_rel":
        d.adult_rel = /^[A-Z_]+$/.test(text) ? text : /pai/.test(t) ? "PAI" : /mae/.test(t) ? "MAE" : /avo/.test(t) ? "AVO" : /padrast|madrast/.test(t) ? "PADRASTO" : /companh|marido|esposa|namorad/.test(t) ? "COMPANHEIRO" : "OUTRO";
        return this.ask("adult_together", `${first(d.adult_name)} mora com vocês?`, { quick_replies: YES_NO });
      case "adult_together": {
        const yn = yesNo(t);
        if (yn === null) return this.say("Responda sim ou não, por favor.", { quick_replies: YES_NO });
        const res = await this.tool("add_family_member", "family_add_adult", {
          full_name: d.adult_name, relationship: d.adult_rel, lives_together: yn, channel: "WHATSAPP",
        });
        this.resetCache();
        this.say(`✅ ${res.message}`, res.escalated
          ? { notice: "Validação da guarda é decisão da unidade/Secretaria; você acompanha pelo protocolo.", quick_replies: [MENU[3]] }
          : undefined);
        if (res.review_single_mother) {
          this.done();
          this.say("Você tinha declarado **mãe solo**. Com essa mudança, quer atualizar essa informação? (o critério vale 5 pontos na fila)", {
            quick_replies: [{ label: "Atualizar", action: "fam:atualizar|ms" }, { label: "Manter como está", action: "nothing" }],
          });
          return;
        }
        return this.done(`Novo responsável incluído (${res.protocol}).`);
      }
      case "after_child":
        if (yesNo(t)) return await this.vagaChild(String(d.child_id));
        this.done();
        return this.say("Combinado! Quando quiser inscrever na fila, é só pedir. 💜", { quick_replies: MENU });
      default:
        this.done();
        return await this.route(detectIntent(t), text);
    }
  }

  // ================================================================== mudança de endereço
  private async startMove(): Promise<void> {
    if (!this.needGuardian("fam:mudanca")) return;
    if (!this.ensureVerified("fam:mudanca")) return;
    this.ctx = { flow: "mudanca", step: "bairro", data: {} };
    this.say("Para qual **bairro de Maringá** vocês se mudaram? 🏠", {
      notice: "Vai sair de Maringá? Escreva “vou me mudar para outra cidade” que eu oriento sobre a declaração de transferência.",
    });
  }

  private async moveStep(text: string): Promise<void> {
    const d = this.ctx.data ?? (this.ctx.data = {});
    if (this.ctx.step === "bairro") {
      const hit = await this.findPlace(text);
      if (!hit) return this.say("Não encontrei esse bairro em Maringá. Pode escrever de outro jeito? (ex.: Jardim Alvorada, Zona 7)");
      d.address = { neighborhood: hit.label, lat: hit.lat, lng: hit.lng, precision: hit.kind === "BAIRRO" ? "BAIRRO" : "UNIDADE_PROXIMA" };
      return this.ask("street", `Novo bairro: **${hit.label}**. Qual a rua e o número? (ou toque em Pular)`, { quick_replies: [{ label: "Pular", action: "skip:" }] });
    }
    if (this.ctx.step === "street") {
      if (text !== "__skip__") Object.assign(d.address, splitStreet(text));
      const res = await this.tool("update_address", "family_move", { address: d.address, channel: "WHATSAPP" });
      if (!res?.ok) throw new Error("o endereço não foi atualizado.");
      this.resetCache();
      const cards: Card[] = [];
      for (const i of (res.impacts ?? []) as any[]) {
        const lost = (i.distance_before ?? 0) <= 2000 && (i.distance_after ?? 0) > 2000;
        const gained = (i.distance_before ?? 99999) > 2000 && (i.distance_after ?? 99999) <= 2000;
        cards.push({
          title: `${i.child} · ${i.grade}`, subtitle: i.unit,
          lines: [
            `Posição: ${i.position_before ?? "—"}º → **${i.position_after ?? "—"}º**`,
            `Pontos: ${Number(i.score_before ?? 0)} → ${Number(i.score_after ?? 0)} de 100`,
            `Distância da unidade: ${km(i.distance_before)} → ${km(i.distance_after)}`,
            lost ? "O critério “reside até 2 km” deixou de valer" : gained ? "O critério “reside até 2 km” passou a valer" : "",
          ].filter(Boolean),
          tone: i.changed ? "amber" : "gray", badge: `${i.position_after ?? "—"}º`,
        });
      }
      const quick: QuickReply[] = [];
      for (const e of (res.enrolled ?? []) as any[]) {
        cards.push({
          title: `${e.child} estuda ${naUnidade(e.unit)}`, subtitle: `${km(e.distance_m)} da nova casa`, unit_id: e.unit_id,
          lines: ((e.nearby ?? []) as any[]).length
            ? ((e.nearby ?? []) as any[]).map((u: any) => `${u.unit} · ${km(u.distance_m)} · ${u.offerable} vaga(s) de ${e.grade}`)
            : ["Sem vaga ofertável de " + e.grade + " perto da nova casa agora"],
          tone: "blue",
        });
        if (e.distance_m > 2000) quick.push({ label: `Pedir transferência (${e.child})`, action: `transfer_child:${e.student_id}` });
      }
      this.say(`Endereço atualizado ✅ Protocolo **${res.protocol}**.${cards.length ? " Veja como ficou:" : " Não há crianças na fila para recalcular."}`, {
        cards: cards.length ? cards : undefined,
        notice: "A fila foi recalculada na hora. Leve o comprovante do novo endereço na matrícula.",
        quick_replies: [...quick, MENU[1], MENU[7]],
      });
      return this.done(`Mudança de endereço registrada (${res.protocol}).`);
    }
    this.done();
    return await this.route(detectIntent(norm(text)), text);
  }

  // ================================================================== atualização de dados e declarações
  private async startUpdate(hint: string): Promise<void> {
    if (!this.needGuardian("fam:atualizar")) return;
    if (!this.ensureVerified("fam:atualizar")) return;
    this.ctx = { flow: "atualizar", step: "what", data: {} };
    if (hint === "ms" || /mae solo|crio sozinha/.test(hint)) return this.updateStep("ms");
    if (hint === "cad" || /cadunico|bolsa familia/.test(hint)) return this.updateStep("cad");
    if (/telefone|numero|celular|whatsapp/.test(hint)) return this.updateStep("tel");
    if (/e-?mail/.test(hint)) return this.updateStep("email");
    this.say("O que você quer atualizar?", {
      quick_replies: [
        { label: "Telefone / WhatsApp", action: "ans:tel" }, { label: "E-mail", action: "ans:email" },
        { label: "CadÚnico", action: "ans:cad" }, { label: "Mãe solo", action: "ans:ms" },
      ],
    });
  }

  private async updateStep(text: string): Promise<void> {
    const t = norm(text);
    const step = this.ctx.step;
    if (step === "what") {
      if (/tel|fone|whats|cel/.test(t)) return this.ask("phone", "Qual o novo número com DDD? (ex.: 44 99999-1234)");
      if (/mail/.test(t)) return this.ask("email", "Qual o novo e-mail?");
      if (/cad/.test(t)) return this.ask("cad", "A família está inscrita no CadÚnico agora?", { quick_replies: YES_NO });
      if (/ms|mae|solo/.test(t)) return this.ask("ms", "Você é mãe solo (cria as crianças sem companheiro ou companheira)?", { quick_replies: YES_NO });
      return this.say("Escolha uma das opções, por favor.");
    }
    let args: Record<string, unknown> | null = null;
    if (step === "phone") {
      const digits = text.replace(/\D/g, "");
      if (digits.length < 10) return this.say("O número precisa ter DDD + telefone (ex.: 44 99999-1234).");
      args = { phone: text.trim() };
    } else if (step === "email") {
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(text.trim())) return this.say("Esse e-mail não parece válido. Pode conferir?");
      args = { email: text.trim() };
    } else if (step === "cad" || step === "ms") {
      const yn = yesNo(t);
      if (yn === null) return this.say("Responda sim ou não, por favor.", { quick_replies: YES_NO });
      args = step === "cad" ? { cadunico: yn } : { single_mother: yn };
    }
    if (!args) return;
    const res = await this.tool("update_family_data", "family_update", { ...args, channel: "WHATSAPP" });
    this.resetCache();
    const cards: Card[] = ((res.impacts ?? []) as any[]).filter((i) => i.changed).map((i) => ({
      title: `${i.child} · ${i.grade}`, subtitle: i.unit,
      lines: [`Pontos: ${Number(i.score_before ?? 0)} → ${Number(i.score_after ?? 0)} de 100`, `Posição: ${i.position_before ?? "—"}º → ${i.position_after ?? "—"}º`],
      tone: "purple", badge: `${i.position_after ?? "—"}º`,
    }));
    this.say(res.protocol ? `Atualizado ✅ Protocolo **${res.protocol}**.${cards.length ? " A fila foi recalculada:" : ""}` : res.message ?? "Nada mudou.", {
      cards: cards.length ? cards : undefined,
      notice: res.documents_note ?? undefined,
      quick_replies: [MENU[1], MENU[7]],
    });
    this.done("Dados da família atualizados.");
  }

  // ================================================================== procurar vaga e inscrição na fila
  private async startVaga(): Promise<void> {
    this.ctx = { flow: "procurar_vaga", step: "child", data: {} };
    if (this.conv.guardian_id) {
      const fam = await this.family();
      const kids = ((fam?.children ?? []) as any[]);
      if (kids.length) {
        this.say("Vamos lá! Para qual criança é a vaga?", {
          quick_replies: [...kids.map((k: any) => ({ label: k.first_name, action: `child:${k.id}` })), { label: "Outra criança", action: "child:new" }],
        });
        return;
      }
      return await this.startAddChild("vaga:resume");
    }
    this.ctx.step = "birth";
    this.say("Vamos lá! Qual é a data de nascimento da criança? (ex.: 20/07/2024)", {
      notice: "Para inscrever na fila, eu faço o cadastro da família por aqui mesmo.",
    });
  }

  private async vagaChild(id: string): Promise<void> {
    this.ctx.flow = "procurar_vaga";
    if (id === "new") return await this.startAddChild("vaga:resume");
    this.resetCache();
    const fam = await this.family();
    const kid = ((fam?.children ?? []) as any[]).find((k) => k.id === id);
    if (!kid) {
      this.say("Não encontrei essa criança no seu cadastro.", { quick_replies: MENU });
      return;
    }
    this.patch.active_student_id = kid.id;
    this.ctx.data = { ...(this.ctx.data ?? {}), child_id: kid.id, child_name: kid.first_name, birth_date: kid.birth_date };
    const active = (kid.queue ?? [])[0];
    if (active) {
      this.say(`${kid.first_name} já está na fila de ${active.grade} ${daUnidade(active.unit)}${active.position ? `, na posição ${active.position}º` : ""}. Não é preciso nova inscrição.`,
        { quick_replies: [MENU[1], { label: "Desistir dessa inscrição", action: "fam:desistencia" }] });
      return this.done();
    }
    if (kid.school) {
      this.say(`${kid.first_name} já estuda ${naUnidade(kid.school.unit)} (${kid.school.class}). Para mudar de unidade, eu faço a inscrição na fila de transferência — a matrícula atual continua valendo até a nova vaga.`, {
        quick_replies: [{ label: "Pedir transferência", action: `transfer_child:${kid.id}` }, { label: "Outra criança", action: "child:new" }],
      });
      return this.done();
    }
    await this.applyGrade(kid.birth_date);
  }

  private async applyGrade(birth: string, gradeOverride?: { id: number; name: string }): Promise<void> {
    if (gradeOverride) {
      this.ctx.data = { ...this.ctx.data, grade_level_id: gradeOverride.id, grade: gradeOverride.name };
    } else {
      const rule = await this.tool("determine_grade", "grade_for_birthdate", { birth_date: birth });
      if (!rule?.ok) {
        this.say(rule?.explanation ?? "Não consegui determinar a faixa pela data informada.", { quick_replies: MENU });
        this.done();
        return;
      }
      const announced = this.ctx.data?.grade_announced;
      this.ctx.data = { ...this.ctx.data, birth_date: birth, grade_level_id: rule.grade_level_id, grade: rule.grade_name };
      if (!announced) this.say(`Pela regra da data de corte, a faixa é **${rule.grade_name}**. ${rule.explanation}`);
    }
    const addr = this.conv.guardian_id ? (await this.family())?.guardian?.address : null;
    this.ctx.flow = this.ctx.flow ?? "procurar_vaga";
    if (addr?.lat) {
      const street = addr.street && addr.street !== "Endereço informado" ? `${addr.street}${addr.number ? ", " + addr.number : ""} · ` : "";
      this.ctx.data!.home = { lat: addr.lat, lng: addr.lng, label: `${street}${addr.neighborhood ?? "seu endereço"}` };
      if (this.ctx.flow !== "procurar_vaga") return await this.vagaAddress("home");
      this.ctx.step = "address";
      this.say(`Posso considerar o endereço cadastrado (${addr.neighborhood ?? "Maringá"})?`, {
        quick_replies: [{ label: "Sim, usar este endereço", action: "addr:home" }, { label: "Informar outro bairro", action: "addr:other" }],
      });
    } else {
      this.ctx.step = "bairro";
      this.say("Qual é o seu bairro? (ex.: Jardim Alvorada)");
    }
  }

  private async vagaAddress(kind: string): Promise<void> {
    if (kind === "other") {
      this.ctx.step = "bairro";
      this.say("Certo! Qual é o bairro? (ex.: Jardim Alvorada, Zona 7, Conjunto Requião)");
      return;
    }
    const home = this.ctx.data?.home as any;
    if (!home) {
      this.ctx.step = "bairro";
      this.say("Qual é o seu bairro?");
      return;
    }
    await this.searchVacancies(home.lat, home.lng, home.label);
  }

  private async searchVacancies(lat: number, lng: number, label: string): Promise<void> {
    const d = this.ctx.data ?? {};
    const res = await this.tool("search_vacancies", "search_vacancies", {
      grade_level_id: d.grade_level_id, lat, lng, limit: 3, student_id: d.child_id ?? null,
    });
    const items = (res?.results ?? []) as any[];
    if (!items.length) {
      this.say(`Não encontrei unidades que atendam ${d.grade} perto de ${label}. Posso encaminhar para a Central de Vagas analisar?`, {
        quick_replies: [{ label: "Encaminhar", action: "handoff:Sem unidade compatível próxima" }, { label: "Agora não", action: "nothing" }],
      });
      this.done();
      return;
    }
    this.ctx.data = { ...d, unit_id: items[0].unit_id, unit_name: items[0].name, search_label: label, units: items.map((u) => ({ id: u.unit_id, name: u.name })) };
    this.say(`Estas unidades atendem **${d.grade}** perto de ${label}:`, {
      cards: items.map((u) => ({
        title: u.name,
        subtitle: `${km(u.distance_m)} · ${u.territory ?? ""}`,
        lines: [
          u.offerable_effective > 0 ? `${u.offerable_effective} vaga(s) ofertável(is) agora` : "Sem vaga ofertável no momento",
          u.my_position ? `${d.child_name ?? "A criança"} já é ${u.my_position}º(ª) na fila desta unidade` : u.queue > 0 ? `${u.queue} criança(s) na fila desta faixa` : "Sem fila nesta faixa",
          u.within_territory ? "Até 2 km de casa (+15 pontos na fila)" : "Mais de 2 km de casa",
        ],
        unit_id: u.unit_id,
        badge: u.offerable_effective > 0 ? "com vaga" : "fila",
        tone: u.offerable_effective > 0 ? "green" : "amber",
      })),
      notice: "Consulta de disponibilidade — não é oferta. A inscrição entra na fila on-line; a oferta é feita pela Central de Vagas, na ordem da fila, com 72 h para efetivar a matrícula.",
    });
    if (!this.conv.guardian_id) {
      this.ctx.step = "await_register";
      this.say("Para inscrever na fila, faço o cadastro da família agora (1 minuto). Vamos?", {
        quick_replies: [{ label: "Fazer cadastro e inscrever", action: "fam:cadastro|vaga:resume" }, { label: "Só estava consultando", action: "nothing" }],
      });
      return;
    }
    if (!d.child_id) return await this.startAddChild("vaga:resume");
    this.ctx.step = "pick_unit";
    this.say(`Em qual unidade você quer inscrever ${d.child_name}? (pode desistir ou trocar depois)`, {
      quick_replies: [...items.map((u) => ({ label: `Inscrever: ${u.name}`, action: `enroll:${u.unit_id}` })), { label: "Agora não", action: "nothing" }],
    });
  }

  /** Retoma a inscrição depois do cadastro da família ou da inclusão da criança. */
  private async resumeVaga(): Promise<void> {
    const d = this.ctx.data ?? (this.ctx.data = {});
    this.ctx.flow = "procurar_vaga";
    if (!d.child_id) return await this.startAddChild("vaga:resume");
    const units = (d.units ?? []) as { id: number; name: string }[];
    if (units.length) {
      this.ctx.step = "pick_unit";
      this.say(`Em qual unidade você quer inscrever ${d.child_name}?`, {
        quick_replies: [...units.map((u) => ({ label: `Inscrever: ${u.name}`, action: `enroll:${u.id}` })), { label: "Agora não", action: "nothing" }],
      });
      return;
    }
    return await this.applyGrade(String(d.birth_date));
  }

  private askQuestion() {
    this.ctx = { flow: "duvida", step: "question", data: {} };
    this.say("Qual é a sua dúvida? Pode escrever do seu jeito — eu respondo com a base oficial da SEDUC e digo a fonte.");
  }

  private async enrollQueue(unitId: number): Promise<void> {
    const d = this.ctx.data ?? {};
    if (!this.needGuardian(`enroll:${unitId}`)) return;
    if (!this.ensureVerified(`enroll:${unitId}`)) return;
    if (!d.child_id) return await this.startAddChild(`enroll:${unitId}`);
    if (!unitId) return this.say("Escolha uma unidade, por favor.");
    const res = await this.tool("queue_register", "queue_self_register", {
      student_id: d.child_id, unit_id: unitId, channel: "WHATSAPP", origin: d.origin ?? null,
    }, `iara-fila-${d.child_id}-${unitId}`);
    if (!res?.ok) throw new Error("a inscrição não foi confirmada.");
    this.resetCache();
    this.patch.active_student_id = d.child_id;
    const applied = ((res.breakdown ?? []) as any[]).filter((b) => b.applied && b.weight > 0).map((b) => `✓ ${b.name} (+${b.weight})`);
    const analysis = ((res.breakdown ?? []) as any[]).filter((b) => b.applied && b.analysis).map((b) => `◆ ${b.name}: prioridade sob análise (laudo)`);
    const docs = ((res.documents ?? []) as string[]).map((x) => DOC_LABEL[x] ?? x);
    this.say(`✅ **${res.child}** está na fila de espera on-line de ${res.grade} ${daUnidade(res.unit)}. Protocolo **${res.protocol}**.`, {
      cards: [{
        title: `${res.child} · ${res.position}º de ${res.queue_size}`, subtitle: `${res.grade} · ${res.unit}`, unit_id: res.unit_id,
        lines: [`${Number(res.score)} de 100 pontos (IN nº 025/2025)`, ...applied, ...analysis, `Regras ${res.rule_version}`],
        badge: `${res.position}º`, tone: "purple",
      }],
      notice: res.message,
    });
    if (docs.length) this.say(`Quando a vaga for ofertada (aviso por aqui, com 72 h para efetivar), leve à unidade:\n${docs.map((x) => "• " + x).join("\n")}`,
      { quick_replies: [MENU[1], MENU[7]] });
    this.done(`Inscrição na fila (${res.case_type}) de ${res.child}: ${res.position}º (${res.protocol}).`);
  }

  // ================================================================== transferência (já estuda na rede)
  private async startTransfer(): Promise<void> {
    if (!this.needGuardian("intent:transferencia")) return;
    if (!this.ensureVerified("intent:transferencia")) return;
    const fam = await this.family();
    const kids = ((fam?.children ?? []) as any[]).filter((k) => k.school);
    if (!kids.length) {
      this.say("Transferência é para quem já estuda na rede municipal. Nenhuma criança da família tem matrícula ativa — o caminho é a inscrição na fila (e, se vieram de outra cidade, eu cuido disso por aqui).",
        { quick_replies: [MENU[0], { label: "Chegamos de outra cidade", action: "fam:outra_cidade" }] });
      return this.done();
    }
    if (kids.length === 1) return await this.startTransferChild(kids[0].id);
    this.ctx = { flow: "transferencia", step: "child", data: {} };
    this.say("Para qual criança é a transferência?", { quick_replies: kids.map((k: any) => ({ label: k.first_name, action: `transfer_child:${k.id}` })) });
  }

  private async startTransferChild(id: string): Promise<void> {
    if (!this.needGuardian(`transfer_child:${id}`)) return;
    if (!this.ensureVerified(`transfer_child:${id}`)) return;
    this.resetCache();
    const fam = await this.family();
    const kid = ((fam?.children ?? []) as any[]).find((k) => k.id === id);
    if (!kid?.school) {
      this.say("Essa criança não tem matrícula ativa; o caminho é a inscrição na fila.", { quick_replies: [MENU[0]] });
      return this.done();
    }
    if ((kid.queue ?? []).length) {
      const q = kid.queue[0];
      this.say(`${kid.first_name} já está na fila de ${q.grade} ${daUnidade(q.unit)}${q.position ? ` (posição ${q.position}º)` : ""}.`, { quick_replies: [MENU[1]] });
      return this.done();
    }
    this.ctx = { flow: "transferencia", step: "units", data: { child_id: kid.id, child_name: kid.first_name, birth_date: kid.birth_date } };
    this.say(`${kid.first_name} estuda ${naUnidade(kid.school.unit)} (${kid.school.class}). Vou mostrar unidades com ${kid.school.class.replace(/\s+[A-Z]$/, "")} perto de casa — a matrícula atual continua valendo até a nova vaga.`);
    await this.applyGrade(kid.birth_date, { id: kid.school.grade_level_id, name: String(kid.school.class).replace(/\s+[A-Z]$/, "") });
  }

  // ================================================================== desistência da fila
  private async startWithdraw(): Promise<void> {
    if (!this.needGuardian("fam:desistencia")) return;
    if (!this.ensureVerified("fam:desistencia")) return;
    this.resetCache();
    const fam = await this.family();
    const entries: { id: string; label: string }[] = [];
    for (const k of (fam?.children ?? []) as any[]) {
      for (const q of (k.queue ?? []) as any[]) if (q.status === "WAITING") entries.push({ id: q.id, label: `${k.first_name} · ${q.unit}` });
    }
    if (!entries.length) {
      this.say("Nenhuma criança da família está aguardando na fila agora.", { quick_replies: [MENU[0]] });
      return this.done();
    }
    this.say("Qual inscrição você quer cancelar?", {
      quick_replies: [...entries.map((e) => ({ label: `Tirar da fila: ${e.label}`, action: `withdraw:${e.id}` })), { label: "Cancelar", action: "nothing" }],
    });
  }

  private confirmWithdraw(entryId: string) {
    this.ctx = { flow: "desistencia", step: null, data: { entry_id: entryId } };
    this.say("Confirma a desistência? A posição na fila é perdida — se mudar de ideia, será uma nova inscrição.", {
      quick_replies: [{ label: "Sim, desistir", action: `withdraw_confirm:${entryId}` }, { label: "Cancelar", action: "nothing" }],
    });
  }

  private async withdraw(entryId: string): Promise<void> {
    if (!this.ensureVerified(`withdraw_confirm:${entryId}`)) return;
    const res = await this.tool("queue_withdraw", "queue_withdraw", { entry_id: entryId, reason: "Pedido pelo WhatsApp", channel: "WHATSAPP" }, `iara-desist-${entryId}`);
    if (!res?.ok) throw new Error("a desistência não foi confirmada.");
    this.resetCache();
    this.say(`✅ ${res.message} Protocolo **${res.protocol}**.`, { quick_replies: [MENU[0]] });
    this.done(`Desistência da fila registrada (${res.protocol}).`);
  }

  // ================================================================== outros serviços (alçada da unidade ou da Secretaria)
  private servicesMenu() {
    this.done();
    this.say("Além de vaga e fila, eu cuido destes pedidos. O que depende de decisão eu encaminho direto para quem decide — a unidade ou a Secretaria — com protocolo e prazo:", {
      quick_replies: [...SERVICES.map((s) => ({ label: s.label, action: `svc:${s.code}` })), { label: "Dúvida sobre a rede", action: "intent:conhecimento" }],
    });
  }

  private async startService(code: string, presetDescription?: string): Promise<void> {
    const flows: Record<string, () => Promise<void>> = {
      SOLICITACAO_VAGA: () => this.startVaga(), TRANSFERENCIA: () => this.startTransfer(), TRANSFERENCIA_EXTERNA: () => this.startOutraCidade(),
      MUDANCA_ENDERECO: () => this.startMove(), INCLUSAO_MEMBRO: () => this.startNewMember(), ATUALIZACAO_CADASTRAL: () => this.startUpdate(""),
      DESISTENCIA: () => this.startWithdraw(), DUVIDA: async () => this.askQuestion(),
    };
    if (flows[code]) return await flows[code]();
    // informação oficial primeiro (resolve dúvidas na hora); uma vez só, depois das verificações
    const showKb = async () => {
      const kbq = SERVICE_KB[code];
      if (!kbq) return;
      const kb = await this.tool("search_official_knowledge", "knowledge_search", { q: kbq });
      const art = (kb?.items ?? [])[0];
      if (art) this.say(`**${art.title}**\n${art.body}`, { notice: `Fonte: ${art.source} · versão ${art.version}` });
    };
    if (!this.conv.guardian_id) {
      await showKb();
      this.needGuardian(`svc:${code}`);
      return;
    }
    if (!this.ensureVerified(`svc:${code}`)) return;
    await showKb();
    this.ctx = { flow: "servico", step: null, data: { code, preset: presetDescription ?? null } };
    if (!NEEDS_CHILD.has(code)) return this.ask("description", "Conte em poucas palavras o que aconteceu (vou registrar para a equipe responsável).");
    const fam = await this.family();
    const kids = ((fam?.children ?? []) as any[]).filter((k) => !ENROLLED_ONLY.has(code) || k.school);
    if (!kids.length) {
      this.say(ENROLLED_ONLY.has(code) ? "Esse pedido é para criança com matrícula ativa na rede, e não encontrei nenhuma na família." : "Não encontrei crianças no cadastro da família.",
        { quick_replies: [MENU[0], MENU[7]] });
      return this.done();
    }
    if (kids.length === 1) return await this.serviceChild(kids[0].id);
    this.ctx.step = "child";
    this.say("Para qual criança?", { quick_replies: kids.map((k: any) => ({ label: k.first_name, action: `svc_child:${k.id}` })) });
  }

  /** Antes de encaminhar, a IARA resolve o que dá: consulta disponibilidade e situação na hora. */
  private async serviceChild(id: string): Promise<void> {
    const d = this.ctx.data ?? (this.ctx.data = {});
    const code = String(d.code ?? "");
    const fam = await this.family();
    const kid = ((fam?.children ?? []) as any[]).find((k) => k.id === id);
    if (!kid) return this.say("Não encontrei essa criança no cadastro.");
    d.child_id = kid.id;
    d.child_name = kid.first_name;
    this.patch.active_student_id = kid.id;
    if (code === "TROCA_TURNO") {
      const av = await this.tool("check_shift_availability", "shift_availability", { student_id: kid.id });
      if (av?.enrolled) {
        const opts = ((av.options ?? []) as any[]);
        const withSeat = opts.filter((o) => o.offerable > 0);
        d.check = withSeat.length
          ? `Há vaga no outro turno: ${withSeat.map((o) => `${SHIFT_LABEL[o.shift] ?? o.shift} (${o.offerable})`).join(", ")}`
          : opts.length ? "Sem vaga no outro turno no momento" : "A série só tem turmas neste turno";
        this.say(`${kid.first_name} estuda no turno da **${SHIFT_LABEL[av.current_shift] ?? av.current_shift}** (${av.class}) ${naUnidade(av.unit)}. ${withSeat.length
          ? `Na mesma série há ${withSeat.map((o) => `${o.offerable} vaga(s) à ${SHIFT_LABEL[o.shift] ?? o.shift}`).join(" e ")}.`
          : opts.length ? "No momento não há vaga no outro turno da mesma série." : "Essa série só tem turmas neste turno na unidade."} A troca é decidida pela secretaria da unidade.`);
      }
    }
    if (code === "DOCUMENTO" && kid.school) {
      this.say(`Situação de ${kid.first_name}: **matrícula ativa** ${naUnidade(kid.school.unit)}, turma ${kid.school.class}, turno da ${SHIFT_LABEL[kid.school.shift] ?? kid.school.shift}. Isso já serve como consulta; a declaração oficial assinada é emitida pela secretaria da unidade.`, {
        quick_replies: [{ label: "Pedir a declaração oficial", action: "ans:pedir" }, { label: "Era só isso", action: "nothing" }],
      });
      this.ctx.step = "doc_confirm";
      return;
    }
    if (d.preset) return await this.serviceCreate(String(d.preset));
    this.ask("description", "Conte em poucas palavras o que você precisa (ou toque em Enviar assim mesmo).", {
      quick_replies: [{ label: "Enviar assim mesmo", action: "skip:" }],
    });
  }

  private async serviceCreate(text: string): Promise<void> {
    const d = this.ctx.data ?? {};
    const code = String(d.code ?? "DUVIDA");
    const label = SERVICES.find((s) => s.code === code)?.label ?? code;
    const description = text === "__skip__" ? `Pedido de ${label.toLowerCase()} registrado pela IARA (WhatsApp).` : text.trim();
    const res = await this.tool("create_service_case", "case_create", {
      case_type: code, channel: "WHATSAPP", student_id: d.child_id ?? null,
      subject: `${label}${d.child_name ? ` — ${d.child_name}` : ""}`, description,
      details: { canal: "WHATSAPP", verificacao_iara: d.check ?? null },
    });
    if (!res?.ok) throw new Error("o registro não foi confirmado.");
    this.patch.active_case_id = res.case_id;
    const r = res.routed_to ?? {};
    const who = r.level === "UNIDADE" ? "da unidade" : "da Secretaria (SEDUC)";
    this.say(`Pronto! Encaminhei para a **${r.team_label ?? "equipe responsável"}** — essa decisão é ${who}. Protocolo **${res.protocol}**, prazo de até ${r.sla_days ?? "alguns"} dia(s). Eu aviso aqui cada atualização. 💜`, {
      notice: r.escalation ?? undefined,
      quick_replies: [MENU[3], MENU[8]],
    });
    this.done(`${label} encaminhado (${res.protocol}) → ${r.team_label ?? "equipe"}.`);
  }

  // ================================================================== continuação dos fluxos
  private async continueFlow(text: string): Promise<void> {
    const step = this.ctx.step;
    const t = norm(text);
    const flow = this.ctx.flow;
    if (flow === "duvida" && step === "question") return await this.knowledge(text);
    if (flow === "cadastro") return await this.registerStep(text);
    if (flow === "novo_membro") return await this.newMemberStep(text);
    if (flow === "mudanca") return await this.moveStep(text);
    if (flow === "atualizar") return await this.updateStep(text);
    if (flow === "outra_cidade") {
      if (step === "pick_child") {
        const fam = await this.family();
        const kid = ((fam?.children ?? []) as any[]).find((k) => k.id === text || norm(k.first_name) === t);
        if (!kid) return this.say("Toque no nome da criança, por favor.");
        this.ctx.data = { ...this.ctx.data, child_id: kid.id, child_name: kid.first_name, birth_date: kid.birth_date };
        return this.ask("school", `${kid.first_name} estudava em qual escola ou CMEI em ${this.ctx.data?.origin?.city ?? "sua cidade"}? (ou toque em Pular)`, { quick_replies: [{ label: "Pular", action: "skip:" }] });
      }
      return await this.outraCidadeStep(text);
    }
    if (flow === "servico") {
      if (step === "child") {
        const fam = await this.family();
        const kid = ((fam?.children ?? []) as any[]).find((k) => norm(k.first_name) === t);
        if (kid) return await this.serviceChild(kid.id);
        return this.say("Toque no nome da criança, por favor.");
      }
      if (step === "doc_confirm") {
        if (/pedir|sim|quero/.test(t)) return this.ask("description", "Para que você precisa da declaração? (ex.: trabalho, benefício, transferência)", { quick_replies: [{ label: "Enviar assim mesmo", action: "skip:" }] });
        this.done("Consulta de situação de matrícula resolvida pela IARA.");
        this.say("Combinado! Se precisar da declaração oficial depois, é só pedir. 💜");
        return;
      }
      if (step === "description") return await this.serviceCreate(text);
    }
    if (flow === "procurar_vaga" || flow === "transferencia") {
      if (step === "child") {
        const fam = this.conv.guardian_id ? await this.family() : null;
        const kid = ((fam?.children ?? []) as any[]).find((k) => t.includes(norm(k.first_name)));
        if (kid) return await this.vagaChild(kid.id);
        if (/outr/.test(t)) return await this.vagaChild("new");
        const date = parseDate(text);
        if (date) return await this.applyGrade(date);
        this.say("Me diga o nome da criança ou toque em uma das opções.");
        return;
      }
      if (step === "birth") {
        const date = parseDate(text);
        if (!date) return this.say("Não consegui entender a data. Pode enviar no formato dia/mês/ano? (ex.: 20/07/2024)");
        return await this.applyGrade(date);
      }
      if (step === "address") {
        if (/^(sim|s|isso|ok|pode)/.test(t)) return await this.vagaAddress("home");
        this.ctx.step = "bairro";
        return await this.continueFlow(text);
      }
      if (step === "bairro") {
        const hit = await this.findPlace(text);
        if (!hit) return this.say("Não encontrei esse bairro na base. Pode tentar outro nome? (ex.: Jardim Alvorada, Zona 7)");
        return await this.searchVacancies(hit.lat, hit.lng, hit.label);
      }
      if (step === "pick_unit") {
        const units = ((this.ctx.data?.units ?? []) as any[]);
        const u = units.find((x) => t.includes(norm(x.name).split(" ").slice(-1)[0]));
        if (u) return await this.enrollQueue(u.id);
        return this.say("Toque na unidade em que você quer inscrever.");
      }
    }
    if (flow === "unidade" && step === "bairro") {
      const hit = await this.findPlace(text);
      if (!hit) {
        this.say("Não encontrei esse local. Tente outro bairro ou o nome da unidade.");
        return;
      }
      const res = await this.tool("list_units", "units_list", { lat: hit.lat, lng: hit.lng, sort: "distance" });
      const items = ((res?.items ?? []) as any[]).slice(0, 3);
      this.say(`Unidades mais próximas de ${hit.label}:`, {
        cards: items.map((u) => ({
          title: u.name, subtitle: `${km(u.distance_m)} · ${u.type_label}`,
          lines: [u.address ?? "", u.stages ?? "", `${u.ops?.offerable ?? 0} vaga(s) ofertável(is) (demonstração)`], unit_id: u.id,
        })),
        notice: "Toque numa unidade para ver detalhes e localização no mapa.",
      });
      this.done(`Consultou unidades próximas de ${hit.label}.`);
      return;
    }
    if (flow === "oferta" && step === "decline_reason") {
      return await this.declineOffer(String(this.ctx.data?.offer_id ?? ""), text);
    }
    this.done();
    return await this.route(detectIntent(t), text);
  }

  // ================================================================== fila / protocolos / ofertas
  private async queueStatus(): Promise<void> {
    if (!this.needGuardian("intent:fila")) return;
    if (!this.ensureVerified("intent:fila")) return;
    const home = await this.citizen();
    const lines: string[] = [];
    const cards: Card[] = [];
    for (const kid of home?.children ?? []) {
      for (const q of kid.queue ?? []) {
        const bd = (q.breakdown ?? []) as any[];
        const applied = bd.filter((b) => b.applied && b.weight > 0 && !b.analysis).map((b) => `✓ ${b.name} (+${b.weight})`);
        const analysis = bd.filter((b) => b.applied && b.analysis).map((b) => `◆ ${b.name}: prioridade sob análise mediante laudo (fora da soma)`);
        if (q.status === "WAITING") {
          cards.push({
            title: `${kid.first_name} · ${q.position}º na fila`, subtitle: `${q.grade} · ${q.unit}`,
            lines: [`${q.queue_size} criança(s) nesta fila · ${Number(q.score ?? 0)} de 100 pontos`, ...applied, ...analysis,
              `Critérios da IN nº 025/2025-SEDUC · regras ${q.rule_version ?? ""} · entrada em ${new Date(q.entered_at).toLocaleDateString("pt-BR")}`],
            unit_id: q.unit_id, badge: `${q.position}º`, tone: "purple",
          });
        } else {
          lines.push(`${kid.first_name}: ${q.status === "OFFERED" ? "há uma oferta de vaga aguardando sua resposta" : "aceite registrado — aguardando a matrícula"} (${q.unit}).`);
        }
      }
    }
    if (!cards.length && !lines.length) {
      this.say("Nenhuma criança sob sua responsabilidade está na fila no momento.", { quick_replies: [MENU[0]] });
      this.done();
      return;
    }
    if (cards.length) {
      this.say("Situação na fila:", { cards, notice: "Pontuação oficial: irmão na mesma unidade 55, CadÚnico 25, até 2 km 15, mãe solo 5. A posição muda com novas entradas e com ofertas realizadas; não há previsão de data sem fonte oficial." });
    }
    for (const l of lines) this.say(l, { quick_replies: [MENU[2]] });
    this.done("Consultou posição na fila.");
  }

  private async caseStatus(): Promise<void> {
    if (!this.needGuardian("intent:acompanhar")) return;
    if (!this.ensureVerified("intent:acompanhar")) return;
    const home = await this.citizen();
    const open = ((home?.cases ?? []) as any[]).filter((c) => c.open).slice(0, 4);
    if (!open.length) {
      this.say("Você não tem protocolos em aberto agora. 🙂", { quick_replies: [MENU[0], MENU[1]] });
      this.done();
      return;
    }
    this.say("Seus protocolos em aberto:", {
      cards: open.map((c) => ({
        title: c.protocol, subtitle: `${c.type_name} · ${STATUS_LABEL[c.status] ?? c.status}`,
        lines: [c.last_event ?? "", `Aberto em ${new Date(c.opened_at).toLocaleDateString("pt-BR")}`],
        tone: c.status === "VAGA_OFERTADA" ? "green" : "blue",
      })),
    });
    this.done("Consultou protocolos em aberto.");
  }

  private async offers(): Promise<void> {
    if (!this.needGuardian("intent:oferta")) return;
    if (!this.ensureVerified("intent:oferta")) return;
    const home = await this.citizen();
    const all: any[] = [];
    for (const kid of home?.children ?? []) for (const o of kid.offers ?? []) all.push({ ...o, child: kid.first_name, documents: kid.documents });
    const pending = all.filter((o) => o.status === "OFFERED");
    const accepted = all.filter((o) => o.status === "ACCEPTED");
    if (!pending.length && !accepted.length) {
      this.say("Não há ofertas de vaga para suas crianças no momento. Quando houver, aviso por aqui com unidade, turno e prazo.", { quick_replies: [MENU[1]] });
      this.done();
      return;
    }
    for (const o of pending) {
      this.say(`Há uma vaga para **${o.child}** ${naUnidade(o.unit)} (${o.class}, turno ${SHIFT_LABEL[o.shift] ?? o.shift}). Prazo para efetivar a matrícula: até ${dt(o.expires_at)} (${Math.max(0, o.hours_left)} h).`, {
        quick_replies: [{ label: "Aceitar vaga", action: `accept:${o.id}` }, { label: "Recusar vaga", action: `decline:${o.id}` }],
        cards: [{ title: o.unit, subtitle: `${o.class} · ${SHIFT_LABEL[o.shift] ?? o.shift}`, lines: [o.address ?? ""], unit_id: o.unit_id, badge: "oferta", tone: "green" }],
        notice: "Pela IN nº 025/2025 (Anexo II), são 72 h desde a contemplação para efetivar a matrícula na unidade com os documentos.",
      });
      this.ctx = { flow: "oferta", step: null, data: { offer_id: o.id, child: o.child, unit: o.unit } };
    }
    for (const o of accepted) {
      const missing = ((o.documents ?? []) as any[]).filter((d) => d.status !== "VALIDADO").map((d) => DOC_LABEL[d.type] ?? d.type);
      this.say(`O aceite da vaga de ${o.child} ${naUnidade(o.unit)} já foi registrado. Efetive a matrícula na unidade até ${dt(o.expires_at)}${missing.length ? ` — pendentes: ${missing.join(", ")}` : ""}.`,
        { quick_replies: missing.length ? [{ label: "Enviar documento", action: "intent:documentos" }] : [] });
    }
  }

  private confirmAccept(offerId: string) {
    this.ctx = { flow: "oferta", step: "confirm_accept", data: { ...(this.ctx.data ?? {}), offer_id: offerId } };
    this.say("Confirma o aceite desta vaga? Lembrando: aceitar não é a matrícula — a unidade confere os documentos e confirma (prazo de 72 h desde a oferta).", {
      quick_replies: [{ label: "Sim, aceito a vaga", action: `accept_confirm:${offerId}` }, { label: "Cancelar", action: "nothing" }],
    });
  }

  private async acceptOffer(offerId: string): Promise<void> {
    if (!this.ensureVerified(`accept_confirm:${offerId}`)) return;
    const res = await this.tool("accept_offer", "offer_respond", { offer_id: offerId, accept: true, channel: "WHATSAPP" }, `accept-${offerId}`);
    if (!res?.ok) throw new Error("o sistema não confirmou o aceite.");
    const missing = ((res.missing_documents ?? []) as string[]).map((d) => DOC_LABEL[d] ?? d);
    this.say(`✅ ${res.message}${missing.length ? `\nPara concluir, faltam: ${missing.join(", ")}.` : ""}`, {
      quick_replies: missing.length ? [{ label: "Enviar documento", action: "intent:documentos" }, MENU[3]] : [MENU[3]],
    });
    this.done("Aceite de oferta registrado (aguardando matrícula).");
  }

  private async declineOffer(offerId: string, reason: string): Promise<void> {
    if (!this.ensureVerified(`decline:${offerId}`)) return;
    const res = await this.tool("decline_offer", "offer_respond", { offer_id: offerId, accept: false, reason, channel: "WHATSAPP" }, `decline-${offerId}`);
    if (!res?.ok) throw new Error("o sistema não confirmou a recusa.");
    this.say(`${res.message}`, { quick_replies: [MENU[1], MENU[0]] });
    this.done("Recusa de oferta registrada.");
  }

  // ================================================================== documentos
  private async documents(): Promise<void> {
    const kb = await this.tool("search_official_knowledge", "knowledge_search", { q: "documentos matricula" });
    const art = (kb?.items ?? [])[0];
    if (art) this.say(`${art.body}`, { notice: `Fonte: ${art.source} · versão ${art.version}` });
    if (!this.conv.guardian_id) return;
    if (!this.verified()) {
      this.ctx.pending = "intent:documentos";
      this.say("Quer ver o que falta para suas crianças? Para isso preciso confirmar sua identidade.", {
        quick_replies: [{ label: "Ver pendências", action: "verify:482913" }, { label: "Agora não", action: "nothing" }],
      });
      return;
    }
    const home = await this.citizen();
    const pend: QuickReply[] = [];
    const lines: string[] = [];
    for (const kid of home?.children ?? []) {
      const missing = ((kid.documents ?? []) as any[]).filter((d) => !["VALIDADO", "RECEBIDO"].includes(d.status));
      if (missing.length && (kid.offers?.length || kid.queue?.length)) {
        lines.push(`${kid.first_name}: ${missing.map((d: any) => DOC_LABEL[d.type] ?? d.type).join(", ")}`);
        for (const d of missing) pend.push({ label: `Enviar ${DOC_LABEL[d.type] ?? d.type} (${kid.first_name})`, action: `doc_send:${kid.id}|${d.type}` });
      }
    }
    if (!lines.length) {
      this.say("Não há documentos pendentes para as solicitações em andamento. 🎉");
      this.done();
      return;
    }
    this.say(`Documentos pendentes:\n${lines.map((l) => "• " + l).join("\n")}`, { quick_replies: pend.slice(0, 4), notice: "Envio de arquivo simulado na demonstração." });
  }

  private async sendDocument(value: string): Promise<void> {
    if (!this.ensureVerified(`doc_send:${value}`)) return;
    const [studentId, docType] = value.split("|");
    const res = await this.tool("submit_document", "document_set", { student_id: studentId, doc_type: docType, status: "RECEBIDO" });
    if (!res?.ok) throw new Error("o envio não foi confirmado.");
    this.say(`Recebemos ${DOC_LABEL[docType] ?? docType} ✅ (envio simulado). A unidade fará a validação e eu aviso o resultado.`, { quick_replies: [MENU[4], MENU[2]] });
    this.done(`Documento ${docType} enviado.`);
  }

  // ================================================================== conhecimento / humano
  private async knowledge(q: string, followUp?: string, followAction?: string): Promise<void> {
    const kb = await this.tool("search_official_knowledge", "knowledge_search", { q });
    const art = (kb?.items ?? [])[0];
    if (!art) {
      this.say("Não encontrei informação oficial vigente sobre isso. Para não arriscar uma resposta errada, posso encaminhar sua dúvida para a equipe?", {
        quick_replies: [{ label: "Sim, encaminhar", action: "handoff:Dúvida sem conhecimento oficial" }, { label: "Não, obrigado", action: "nothing" }],
      });
      return;
    }
    this.say(`**${art.title}**\n${art.body}`, {
      notice: `Fonte: ${art.source} · ${art.sector} · versão ${art.version}`,
      quick_replies: followUp && followAction ? [{ label: "Sim", action: followAction }, { label: "Não, obrigado", action: "nothing" }] : (this.conv.guardian_id ? MENU.slice(0, 3) : this.newcomerMenu()),
    });
    if (followUp) this.say(followUp);
    this.done(`Informação: ${art.title}.`);
  }

  private handoff(reason: string) {
    this.patch.state = "HUMAN_PENDING";
    this.patch.handoff_reason = reason;
    this.patch.summary = `Encaminhado para atendimento humano: ${reason}.`;
    this.tools.push({ tool: "handoff_to_team", input: { motivo: reason }, output: { ok: true }, status: "OK", ms: 1, correlation_id: crypto.randomUUID() });
    this.say("Encaminhei sua conversa para a equipe da Central de Vagas com todo o histórico — você não precisa repetir as informações. Enquanto aguarda, suas mensagens continuam registradas.",
      { notice: "Atendimento humano no horário de expediente da SEDUC." });
    this.done(`Encaminhado: ${reason}.`);
  }
}

function minimize(args: Record<string, unknown>) {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(args ?? {})) {
    if (["lat", "lng"].includes(k) && typeof v === "number") out[k] = Math.round(v * 100) / 100; // localização aproximada no log
    else if (["full_name", "child_full_name", "adult_name"].includes(k) && typeof v === "string") out[k] = v.split(" ")[0] + " …";
    else if (k === "address" && v && typeof v === "object") out[k] = { neighborhood: (v as any).neighborhood ?? null };
    else if (["phone", "email"].includes(k)) out[k] = "•••";
    else out[k] = v;
  }
  return out;
}

function summarize(out: any) {
  if (!out || typeof out !== "object") return { value: out };
  if (Array.isArray(out.results)) return { results: out.results.length, rule_version: out.rule_version };
  if (Array.isArray(out.items)) return { items: out.items.length };
  if (out.children && !out.ok) return { children: out.children.length, cases: out.cases?.length ?? 0 };
  const keep: Record<string, unknown> = {};
  for (const k of ["ok", "status", "protocol", "case_id", "offer_id", "grade_name", "message", "student_id", "position", "score", "case_type", "escalated", "registered"])
    if (k in out) keep[k] = out[k];
  if (out.routed_to) keep.routed_to = out.routed_to.team_label;
  return keep;
}
