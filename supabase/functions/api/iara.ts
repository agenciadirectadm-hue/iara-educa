// IARA — agente resolutiva de atendimento (capítulo 74), modo determinístico.
// Regras de ouro: só afirma sucesso após confirmação do backend; nunca inventa vaga, posição, prazo ou protocolo;
// dados pessoais só após verificação de identidade e vínculo; ferramentas rodam com as permissões do próprio cidadão.

export type QuickReply = { label: string; action?: string };
export type Card = { title: string; subtitle?: string; lines?: string[]; unit_id?: number; badge?: string; tone?: string };
export type Reply = { body: string; payload?: { quick_replies?: QuickReply[]; cards?: Card[]; notice?: string } };
export type ToolLog = { tool: string; input: unknown; output: unknown; status: "OK" | "ERRO" | "NEGADO"; error?: string; ms: number; correlation_id: string; idempotency_key?: string };

type Ctx = { flow?: string | null; step?: string | null; data?: Record<string, unknown>; pending?: string | null };
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
];

const STATUS_LABEL: Record<string, string> = {
  NOVO: "recebido", EM_ANALISE: "em análise", AGUARDANDO_DOCUMENTOS: "aguardando documentos", AGUARDANDO_FAMILIA: "aguardando sua resposta",
  VAGA_ENCONTRADA: "vaga encontrada (em validação)", VAGA_OFERTADA: "vaga ofertada", EM_FILA: "na fila", MATRICULA_CONCLUIDA: "matrícula concluída",
  NAO_ATENDIDO: "não atendido", RECURSO: "recurso em análise", ENCERRADO: "encerrado",
};
const DOC_LABEL: Record<string, string> = {
  CERTIDAO: "certidão de nascimento", CPF: "CPF", RG: "RG", COMPROVANTE_ENDERECO: "comprovante de endereço", CARTAO_SUS: "cartão SUS",
  VACINACAO: "carteira de vacinação", CADUNICO: "comprovante CadÚnico", DECLARACAO_TRABALHO: "declaração de trabalho", LAUDO: "laudo",
};
const SHIFT_LABEL: Record<string, string> = { MANHA: "manhã", TARDE: "tarde", NOITE: "noite", INTEGRAL: "integral" };
/** "no CMEI X" / "na Escola Municipal Y" (CMEI é masculino) */
const naUnidade = (name?: string | null) => (!name ? "na unidade" : /^CMEI\s/i.test(name) ? `no ${name}` : `na ${name}`);
const daUnidade = (name?: string | null) => (!name ? "da unidade" : /^CMEI\s/i.test(name) ? `do ${name}` : `da ${name}`);

function detectIntent(t: string): string {
  if (/(cancelar|menu|recomecar|inicio|ajuda)\b/.test(t)) return "menu";
  if (/(atendente|humano|uma pessoa|falar com alguem|servidor|ouvidoria|reclama)/.test(t)) return "atendente";
  if (/(oferta|aceitar|aceito|recusar|recuso)/.test(t)) return "oferta";
  if (/(posicao|fila|colocacao|lugar na)/.test(t)) return "fila";
  if (/(protocolo|acompanhar|andamento|solicitacao|status do pedido|meu pedido)/.test(t)) return "acompanhar";
  if (/(document|certidao|comprovante|vacina|cpf|cartao sus|\brg\b)/.test(t)) return "documentos";
  if (/(transfer|mudar de escola|trocar de escola|mudei|mudanca de endereco)/.test(t)) return "transferencia";
  if (/(vaga|creche|matricul|pre.?escola|1.?\s?ano|primeiro ano|cmei para|estudar)/.test(t)) return "procurar_vaga";
  if (/(unidade|onde fica|perto de mim|mais proxim|encontrar escola|encontrar cmei|endereco da)/.test(t)) return "unidade";
  if (/(transporte|onibus|van escolar)/.test(t)) return "conhecimento";
  if (/(aee|inclus|deficien|autis|\btea\b|laudo)/.test(t)) return "conhecimento";
  if (/(calendario|prazo|quando|rematricula|eja|integral|etapa)/.test(t)) return "conhecimento";
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

const km = (m: number | null | undefined) => (m == null ? "—" : `${(m / 1000).toFixed(1).replace(".", ",")} km`);
const dt = (iso: string) =>
  new Date(iso).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });

export class Agent {
  messages: Reply[] = [];
  tools: ToolLog[] = [];
  patch: Patch = {};
  ctx: Ctx;
  private home: any = null;

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

  private done(summary?: string) {
    this.ctx = { flow: null, step: null, data: {}, pending: null };
    if (summary) this.patch.summary = summary;
  }

  private needGuardian(): boolean {
    if (this.conv.guardian_id) return true;
    this.say("Esta conversa não está vinculada a um responsável cadastrado, então não consigo consultar dados de crianças. Posso ajudar com informações gerais da rede.",
      { quick_replies: [MENU[0], MENU[5], MENU[4]] });
    return false;
  }

  /** Dados pessoais exigem identidade + vínculo verificados (cap. 74.5). */
  private ensureVerified(pending: string): boolean {
    if (this.conv.identity_verified || this.patch.identity_verified) return true;
    this.ctx.pending = pending;
    this.say(
      "Para consultar dados pessoais, preciso confirmar sua identidade e seu vínculo com a criança. Enviei um código de 6 dígitos para o telefone cadastrado.",
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
        this.say("Tudo bem, recomeçamos. Como posso ajudar?", { quick_replies: MENU });
        return;
      }
      if (this.ctx.flow && this.ctx.step && ["desconhecido", "saudacao"].includes(intent)) return await this.continueFlow(text);
      if (this.ctx.flow && this.ctx.step && intent === "procurar_vaga" && this.ctx.flow === "procurar_vaga") return await this.continueFlow(text);
      return await this.route(intent, text);
    } catch (e) {
      const msg = (e as Error).message ?? "erro";
      this.say(`Não consegui concluir esta etapa agora: ${msg} Nada foi registrado nesta tentativa. Quer tentar de novo ou falar com um atendente?`,
        { quick_replies: [{ label: "Tentar de novo", action: "intent:" + (this.ctx.flow ?? "menu") }, MENU[6]] });
    }
  }

  private async route(intent: string, text: string) {
    this.patch.intent = intent;
    switch (intent) {
      case "saudacao": {
        const first = this.conv.guardian_id ? (await this.citizen())?.guardian?.first_name : null;
        this.say(`Oi${first ? ", " + first : ""}! Como posso ajudar hoje?`, { quick_replies: MENU });
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
        return this.handoff(/reclam|ouvidoria/.test(norm(text)) ? "Reclamação / ouvidoria" : "Pedido de atendimento humano");
      case "transferencia":
        return await this.knowledge("transferencia unidade", "Quer que eu registre um pedido de transferência?", "intent:transferencia_reg");
      case "conhecimento":
        return await this.knowledge(text);
      default:
        this.say("Desculpe, não entendi. Posso ajudar com estes assuntos:", { quick_replies: MENU });
    }
  }

  private async onAction(action: string, text: string) {
    const [kind, ...rest] = action.split(":");
    const value = rest.join(":");
    switch (kind) {
      case "intent":
        if (value === "transferencia_reg") return await this.registerTransfer();
        return await this.route(value, text);
      case "verify": {
        if (!this.needGuardian()) return;
        await this.tool("verify_identity", null, { metodo: "codigo_sms_simulado" });
        this.patch.identity_verified = true;
        this.say("Identidade e vínculo confirmados ✅", { notice: "Verificação simulada no ambiente de demonstração." });
        const pending = this.ctx.pending;
        this.ctx.pending = null;
        if (pending) return await this.onAction(pending, text);
        this.say("O que você gostaria de consultar?", { quick_replies: MENU.slice(1, 5) });
        return;
      }
      case "child":
        return await this.vagaChild(value);
      case "addr":
        return await this.vagaAddress(value);
      case "register":
        return await this.registerRequest();
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

  // ------------------------------------------------------------------ procurar vaga
  private async startVaga() {
    this.ctx = { flow: "procurar_vaga", step: "child", data: {} };
    if (this.conv.guardian_id) {
      const home = await this.citizen();
      const kids = (home?.children ?? []) as any[];
      if (kids.length) {
        this.say("Vamos lá! Para qual criança é a vaga?", {
          quick_replies: [...kids.map((k) => ({ label: k.first_name, action: `child:${k.id}` })), { label: "Outra criança", action: "child:new" }],
        });
        return;
      }
    }
    this.ctx.step = "birth";
    this.say("Vamos lá! Qual é a data de nascimento da criança? (ex.: 20/07/2024)");
  }

  private async vagaChild(id: string) {
    this.ctx.flow = "procurar_vaga";
    if (id === "new") {
      this.ctx.step = "birth";
      this.ctx.data = {};
      this.say("Certo. Qual é a data de nascimento da criança? (ex.: 20/07/2024)");
      return;
    }
    const home = await this.citizen();
    const kid = (home?.children ?? []).find((k: any) => k.id === id);
    if (!kid) {
      this.say("Não encontrei essa criança no seu cadastro.", { quick_replies: MENU });
      return;
    }
    this.patch.active_student_id = kid.id;
    this.ctx.data = { child_id: kid.id, child_name: kid.first_name, birth_date: kid.birth_date };
    if (kid.school) {
      this.say(`${kid.first_name} já está matriculado(a) ${naUnidade(kid.school.unit)} (${kid.school.class}). Para mudar de unidade, o caminho é a transferência.`, {
        quick_replies: [{ label: "Pedir transferência", action: "intent:transferencia" }, { label: "Outra criança", action: "child:new" }],
      });
      this.done();
      return;
    }
    await this.applyGrade(kid.birth_date);
  }

  private async applyGrade(birth: string) {
    const rule = await this.tool("determine_grade", "grade_for_birthdate", { birth_date: birth });
    if (!rule?.ok) {
      this.say(rule?.explanation ?? "Não consegui determinar a faixa pela data informada.", { quick_replies: MENU });
      this.done();
      return;
    }
    this.ctx.data = { ...this.ctx.data, birth_date: birth, grade_level_id: rule.grade_level_id, grade: rule.grade_name };
    this.say(`Pela regra da data de corte, a faixa é **${rule.grade_name}**. ${rule.explanation}`);
    const addr = this.conv.guardian_id ? (await this.citizen())?.guardian?.address : null;
    this.ctx.step = "address";
    if (addr?.lat) {
      this.ctx.data.home = { lat: addr.lat, lng: addr.lng, label: `${addr.street}, ${addr.number} · ${addr.neighborhood ?? ""}` };
      this.say(`Posso considerar o endereço cadastrado (${addr.street}, ${addr.number} — ${addr.neighborhood ?? "Maringá"})?`, {
        quick_replies: [{ label: "Sim, usar este endereço", action: "addr:home" }, { label: "Informar outro bairro", action: "addr:other" }],
      });
    } else {
      this.ctx.step = "bairro";
      this.say("Qual é o seu bairro? (ex.: Jardim Alvorada)");
    }
  }

  private async vagaAddress(kind: string) {
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

  private async searchVacancies(lat: number, lng: number, label: string) {
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
    this.ctx.data = { ...d, unit_id: items[0].unit_id, unit_name: items[0].name, search_label: label };
    this.say(`Estas unidades atendem **${d.grade}** perto de ${label}:`, {
      cards: items.map((u) => ({
        title: u.name,
        subtitle: `${km(u.distance_m)} · ${u.territory ?? ""}`,
        lines: [
          u.offerable_effective > 0 ? `${u.offerable_effective} vaga(s) ofertável(is) agora` : "Sem vaga ofertável no momento",
          u.my_position ? `${d.child_name ?? "A criança"} já é ${u.my_position}º(ª) na fila desta unidade` : u.queue > 0 ? `${u.queue} criança(s) na fila desta faixa` : "Sem fila nesta faixa",
          u.within_territory ? "Dentro do território prioritário (até 2 km)" : "Fora do raio prioritário",
        ],
        unit_id: u.unit_id,
        badge: u.offerable_effective > 0 ? "com vaga" : "fila",
        tone: u.offerable_effective > 0 ? "green" : "amber",
      })),
      notice: "Consulta de disponibilidade — não é oferta de vaga. Ofertas seguem a ordem da fila e a validação da Central de Vagas.",
    });
    const kidQueue = d.child_id ? await this.childQueue(d.child_id as string) : null;
    if (kidQueue) {
      if (this.conv.identity_verified || this.patch.identity_verified) {
        this.say(`${d.child_name} já está na fila de ${kidQueue.grade} ${daUnidade(kidQueue.unit)}, na posição ${kidQueue.position ?? "—"}. Não é preciso abrir outro pedido.`,
          { quick_replies: [{ label: "Ver critérios da fila", action: "intent:fila" }, MENU[2]] });
      } else {
        this.say(`Vi que ${d.child_name} já tem um pedido em andamento. Posso mostrar a posição na fila depois de confirmar sua identidade.`,
          { quick_replies: [{ label: "Ver posição na fila", action: "intent:fila" }] });
      }
      this.done(`Consultou vagas de ${d.grade}; criança já está na fila.`);
      return;
    }
    this.ctx.step = "confirm_register";
    this.say("Quer que eu registre a solicitação de vaga? Ela gera um protocolo e segue os critérios públicos da fila.", {
      quick_replies: [{ label: "Registrar solicitação", action: "register" }, { label: "Agora não", action: "nothing" }],
    });
  }

  private async childQueue(childId: string) {
    const home = await this.citizen();
    const kid = (home?.children ?? []).find((k: any) => k.id === childId);
    return (kid?.queue ?? []).find((q: any) => ["WAITING", "OFFERED", "ACCEPTED"].includes(q.status)) ?? null;
  }

  private async registerRequest() {
    if (!this.needGuardian()) return;
    if (!this.ensureVerified("register")) return;
    const d = this.ctx.data ?? {};
    if (!d.grade_level_id) {
      this.say("Vamos começar pela criança.", { quick_replies: [MENU[0]] });
      return;
    }
    if (!d.child_id) {
      this.ctx.flow = "procurar_vaga";
      this.ctx.step = "child_name";
      this.say("Qual é o nome completo da criança?");
      return;
    }
    const idem = `iara-${this.conv.conversation_id}-${d.child_id}-${d.grade_level_id}`;
    const res = await this.tool("create_service_case", "case_create", {
      case_type: "SOLICITACAO_VAGA", channel: "WHATSAPP", student_id: d.child_id, unit_id: d.unit_id,
      subject: `Solicitação de vaga — ${d.grade} (${d.child_name})`,
      description: `Pedido registrado pela IARA. Unidade de referência: ${d.unit_name}. Endereço considerado: ${d.search_label}.`,
      idempotency_key: idem,
    }, idem);
    if (!res?.ok) throw new Error("o sistema não confirmou o registro.");
    this.patch.active_case_id = res.case_id;
    this.patch.active_student_id = d.child_id as string;
    const steps = ((res.next_steps ?? []) as (string | null)[]).filter(Boolean).map((s) => "• " + s).join("\n");
    this.say(`Pronto! Protocolo **${res.protocol}** registrado ✅\n${steps}\nVou avisar cada mudança por aqui.`, {
      quick_replies: [{ label: "Acompanhar solicitação", action: "intent:acompanhar" }, { label: "Documentos", action: "intent:documentos" }],
    });
    this.done(`Solicitação de vaga registrada (${res.protocol}) para ${d.child_name}.`);
  }

  private async continueFlow(text: string) {
    const step = this.ctx.step;
    const t = norm(text);
    if (this.ctx.flow === "procurar_vaga") {
      if (step === "child") {
        const home = await this.citizen();
        const kid = (home?.children ?? []).find((k: any) => t.includes(norm(k.first_name)));
        if (kid) return await this.vagaChild(kid.id);
        if (/outr/.test(t)) return await this.vagaChild("new");
        const date = parseDate(text);
        if (date) return await this.applyGrade(date);
        this.say("Me diga o nome da criança ou toque em uma das opções.");
        return;
      }
      if (step === "birth") {
        const date = parseDate(text);
        if (!date) {
          this.say("Não consegui entender a data. Pode enviar no formato dia/mês/ano? (ex.: 20/07/2024)");
          return;
        }
        return await this.applyGrade(date);
      }
      if (step === "address") {
        if (/^(sim|s|isso|ok|pode)/.test(t)) return await this.vagaAddress("home");
        this.ctx.step = "bairro";
        return await this.continueFlow(text);
      }
      if (step === "bairro") {
        const geo = await this.tool("list_units", "geo_search", { q: text });
        const hit = (geo?.items ?? [])[0];
        if (!hit) {
          this.say("Não encontrei esse bairro na base. Pode tentar outro nome? (ex.: Jardim Alvorada, Zona 7)");
          return;
        }
        return await this.searchVacancies(hit.lat, hit.lng, hit.label);
      }
      if (step === "confirm_register") {
        if (/^(sim|s|pode|registr|quero)/.test(t)) return await this.registerRequest();
        this.done();
        this.say("Tudo bem. Se mudar de ideia, é só pedir. 💜", { quick_replies: MENU });
        return;
      }
      if (step === "child_name") {
        if (text.trim().split(/\s+/).length < 2) {
          this.say("Preciso do nome completo (nome e sobrenome).");
          return;
        }
        const d = this.ctx.data ?? {};
        const st = await this.tool("register_student", "student_create", { full_name: text.trim(), birth_date: d.birth_date, relationship: "RESPONSAVEL_LEGAL" });
        if (st?.ok === false && st?.duplicates) {
          this.say("Já existe uma criança com esse nome e data de nascimento. Para evitar cadastro duplicado, vou encaminhar para um atendente conferir.",
            { quick_replies: [{ label: "Encaminhar", action: "handoff:Possível cadastro duplicado" }] });
          return;
        }
        if (!st?.ok) throw new Error("o cadastro da criança não foi confirmado.");
        this.ctx.data = { ...d, child_id: st.student_id, child_name: text.trim().split(/\s+/)[0] };
        this.home = null;
        return await this.registerRequest();
      }
    }
    if (this.ctx.flow === "unidade" && step === "bairro") {
      const geo = await this.tool("list_units", "geo_search", { q: text });
      const hit = (geo?.items ?? [])[0];
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
    if (this.ctx.flow === "oferta" && step === "decline_reason") {
      return await this.declineOffer(String(this.ctx.data?.offer_id ?? ""), text);
    }
    this.done();
    return await this.route(detectIntent(t), text);
  }

  // ------------------------------------------------------------------ fila / protocolos / ofertas
  private async queueStatus() {
    if (!this.needGuardian()) return;
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

  private async caseStatus() {
    if (!this.needGuardian()) return;
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

  private async offers() {
    if (!this.needGuardian()) return;
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
      this.say(`Há uma vaga para **${o.child}** ${naUnidade(o.unit)} (${o.class}, turno ${SHIFT_LABEL[o.shift] ?? o.shift}). Prazo para responder: até ${dt(o.expires_at)} (${Math.max(0, o.hours_left)} h).`, {
        quick_replies: [{ label: "Aceitar vaga", action: `accept:${o.id}` }, { label: "Recusar vaga", action: `decline:${o.id}` }],
        cards: [{ title: o.unit, subtitle: `${o.class} · ${SHIFT_LABEL[o.shift] ?? o.shift}`, lines: [o.address ?? ""], unit_id: o.unit_id, badge: "oferta", tone: "green" }],
        notice: "Aceitar não é a matrícula: depois do aceite, a unidade confere os documentos e confirma.",
      });
      this.ctx = { flow: "oferta", step: null, data: { offer_id: o.id, child: o.child, unit: o.unit } };
    }
    for (const o of accepted) {
      const missing = ((o.documents ?? []) as any[]).filter((d) => d.status !== "VALIDADO").map((d) => DOC_LABEL[d.type] ?? d.type);
      this.say(`O aceite da vaga de ${o.child} ${naUnidade(o.unit)} já foi registrado. A unidade vai confirmar a matrícula${missing.length ? ` — pendentes: ${missing.join(", ")}` : ""}.`,
        { quick_replies: missing.length ? [{ label: "Enviar documento", action: "intent:documentos" }] : [] });
    }
  }

  private confirmAccept(offerId: string) {
    this.ctx = { flow: "oferta", step: "confirm_accept", data: { ...(this.ctx.data ?? {}), offer_id: offerId } };
    this.say("Confirma o aceite desta vaga? Lembrando: aceitar não é a matrícula — depois a unidade confere os documentos e confirma.", {
      quick_replies: [{ label: "Sim, aceito a vaga", action: `accept_confirm:${offerId}` }, { label: "Cancelar", action: "nothing" }],
    });
  }

  private async acceptOffer(offerId: string) {
    if (!this.ensureVerified(`accept_confirm:${offerId}`)) return;
    const res = await this.tool("accept_offer", "offer_respond", { offer_id: offerId, accept: true, channel: "WHATSAPP" }, `accept-${offerId}`);
    if (!res?.ok) throw new Error("o sistema não confirmou o aceite.");
    const missing = ((res.missing_documents ?? []) as string[]).map((d) => DOC_LABEL[d] ?? d);
    this.say(`✅ ${res.message}${missing.length ? `\nPara concluir, faltam: ${missing.join(", ")}.` : ""}`, {
      quick_replies: missing.length ? [{ label: "Enviar documento", action: "intent:documentos" }, MENU[3]] : [MENU[3]],
    });
    this.done("Aceite de oferta registrado (aguardando matrícula).");
  }

  private async declineOffer(offerId: string, reason: string) {
    if (!this.ensureVerified(`decline:${offerId}`)) return;
    const res = await this.tool("decline_offer", "offer_respond", { offer_id: offerId, accept: false, reason, channel: "WHATSAPP" }, `decline-${offerId}`);
    if (!res?.ok) throw new Error("o sistema não confirmou a recusa.");
    this.say(`${res.message}`, { quick_replies: [MENU[1], MENU[0]] });
    this.done("Recusa de oferta registrada.");
  }

  // ------------------------------------------------------------------ documentos
  private async documents() {
    const kb = await this.tool("search_official_knowledge", "knowledge_search", { q: "documentos matricula" });
    const art = (kb?.items ?? [])[0];
    if (art) this.say(`${art.body}`, { notice: `Fonte: ${art.source} · versão ${art.version}` });
    if (!this.conv.guardian_id) return;
    if (!(this.conv.identity_verified || this.patch.identity_verified)) {
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

  private async sendDocument(value: string) {
    if (!this.ensureVerified(`doc_send:${value}`)) return;
    const [studentId, docType] = value.split("|");
    const res = await this.tool("submit_document", "document_set", { student_id: studentId, doc_type: docType, status: "RECEBIDO" });
    if (!res?.ok) throw new Error("o envio não foi confirmado.");
    this.say(`Recebemos ${DOC_LABEL[docType] ?? docType} ✅ (envio simulado). A unidade fará a validação e eu aviso o resultado.`, { quick_replies: [MENU[4], MENU[2]] });
    this.done(`Documento ${docType} enviado.`);
  }

  // ------------------------------------------------------------------ conhecimento / transferência / humano
  private async knowledge(q: string, followUp?: string, followAction?: string) {
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
      quick_replies: followUp && followAction ? [{ label: "Sim", action: followAction }, { label: "Não, obrigado", action: "nothing" }] : MENU.slice(0, 3),
    });
    if (followUp) this.say(followUp);
    this.done(`Informação: ${art.title}.`);
  }

  private async registerTransfer() {
    if (!this.needGuardian()) return;
    if (!this.ensureVerified("intent:transferencia_reg")) return;
    const home = await this.citizen();
    const kid = ((home?.children ?? []) as any[]).find((k) => k.school);
    if (!kid) {
      this.say("Transferência é para quem já estuda na rede. Nenhuma criança sua tem matrícula ativa — nesse caso, o caminho é a solicitação de vaga.", { quick_replies: [MENU[0]] });
      return;
    }
    const idem = `iara-transf-${this.conv.conversation_id}-${kid.id}`;
    const res = await this.tool("create_service_case", "case_create", {
      case_type: "TRANSFERENCIA", channel: "WHATSAPP", student_id: kid.id, subject: `Transferência — ${kid.first_name}`,
      description: "Pedido de transferência registrado pela IARA; a matrícula atual permanece até a confirmação da nova vaga.", idempotency_key: idem,
    }, idem);
    if (!res?.ok) throw new Error("o registro não foi confirmado.");
    this.patch.active_case_id = res.case_id;
    this.say(`Pedido de transferência registrado: protocolo **${res.protocol}** ✅ A matrícula atual de ${kid.first_name} continua valendo até a confirmação da nova vaga.`,
      { quick_replies: [MENU[3]] });
    this.done(`Transferência registrada (${res.protocol}).`);
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
    else if (k === "full_name" && typeof v === "string") out[k] = v.split(" ")[0] + " …";
    else out[k] = v;
  }
  return out;
}

function summarize(out: any) {
  if (!out || typeof out !== "object") return { value: out };
  if (Array.isArray(out.results)) return { results: out.results.length, rule_version: out.rule_version };
  if (Array.isArray(out.items)) return { items: out.items.length };
  if (out.children) return { children: out.children.length, cases: out.cases?.length ?? 0 };
  const keep: Record<string, unknown> = {};
  for (const k of ["ok", "status", "protocol", "case_id", "offer_id", "grade_name", "message", "student_id"]) if (k in out) keep[k] = out[k];
  return keep;
}
