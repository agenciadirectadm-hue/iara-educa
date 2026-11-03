"""Atualiza o simulador de preços com a calculadora (valores já calculados pelo Excel): gera o SQL privado dos dados.
Uso: python scripts/simulador/extrai_sim.py docs/apresentacao/IARA_Educa_Calculadora_Municipios.xlsx
       supabase/privado/simulador_dados.sql scripts/simulador/modelo_dados.sql
Depois: node scripts/aplicar.mjs supabase/privado/simulador_dados.sql
Os preços nunca vão para o repositório público: supabase/privado/ e docs/apresentacao/ estão no .gitignore."""
import sys
from openpyxl import load_workbook

arq, saida = sys.argv[1], sys.argv[2]
wb = load_workbook(arq, data_only=True)
ag, bp, pm, mu = wb["Agentes"], wb["Banco de preços"], wb["Parâmetros"], wb["Municípios"]

precos = {}
for r in range(6, 60):
    n = bp[f"B{r}"].value
    if n:
        precos[n] = (bp[f"H{r}"].value or 0, bp[f"I{r}"].value or 0)
CHAVE_COB = {"Por agente": "agente", "Por vaga ocupada ou demandada": "vaga", "Por profissional": "profissional", "Por fila": "fila",
             "Por disparador": "disparador"}
agentes = []
for r in range(8, 60):
    num = ag[f"B{r}"].value
    if isinstance(num, (int, float)) and ag[f"C{r}"].value:
        nome = ag[f"C{r}"].value
        agentes.append(dict(num=int(num), nome=nome, assuntos=ag[f"D{r}"].value, tipo=int(str(ag[f"E{r}"].value).split()[-1]),
                            criticidade=ag[f"F{r}"].value, dimensao=ag[f"G{r}"].value, situacao=ag[f"H{r}"].value,
                            cobranca=CHAVE_COB[ag[f"I{r}"].value], disparador=ag[f"J{r}"].value == "Sim",
                            impl=precos[nome][0], mensal=precos[nome][1]))
municipios = []
for r in range(5, 35):
    if mu[f"A{r}"].value:
        municipios.append(dict(nome=mu[f"A{r}"].value, uf=mu[f"B{r}"].value, unidades=mu[f"C{r}"].value, ocupadas=mu[f"D{r}"].value,
                               creche=mu[f"E{r}"].value, fila=mu[f"F{r}"].value, docentes=mu[f"H{r}"].value, outros=mu[f"I{r}"].value,
                               centrais=mu[f"K{r}"].value, setor=mu[f"L{r}"].value, conveniadas=mu[f"O{r}"].value,
                               redutor=mu[f"P{r}"].value or 0, obs=mu[f"Q{r}"].value))
rot = {pm[f"A{r}"].value: pm[f"B{r}"].value for r in range(1, 120) if pm[f"A{r}"].value}
P = {
    "meses": rot["Meses no 1º ano"],
    "taxa_fila": rot["Fila estimada quando a prefeitura não informa (% das matrículas em creche)"],
    "resp_al": rot["Mensagens de resposta por aluno"], "util_al": rot["Mensagens de utilidade por aluno"],
    "doc_al": rot["Leituras de documento por aluno"], "aud_al": rot["Áudios por aluno"],
    "u_resp": rot["Custo por resposta — tokens (R$)"], "u_doc": rot["Custo por documento — tokens (R$)"],
    "u_aud": rot["Custo por áudio — transcrição (R$)"], "w_resp": rot["Resposta (mensagem de serviço), R$ por mensagem"],
    "w_fran": rot["Respostas grátis por mês (franquia por número)"],
    "w_isen": 1 if rot["Isenção de governo nas respostas (até 31/12/2027)"] == "Sim" else 0,
    "w_util": rot["Mensagem de utilidade, R$ por mensagem"], "o_perg": rot["Perguntas do prefeito por mês"],
    "u_orac": rot["Custo por pergunta do Oráculo — tokens do Opus 5.5 (R$)"], "pub_resp": rot["Responsáveis por aluno"],
    "pub_por": rot["Disparos de marketing por pessoa listada, por mês"], "pub_tar": rot["Tarifa do disparo de marketing (R$)"],
}


def q(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, int):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


linhas_ag = ",\n".join(
    f"  ({a['num']}, {q(a['nome'])}, {q(a['assuntos'])}, {a['tipo']}, {q(a['criticidade'])}, {q(a['dimensao'])}, {q(a['situacao'])}, "
    f"{q(a['cobranca'])}, {q(a['disparador'])}, {q(a['impl'])}, {q(a['mensal'])})" for a in agentes)
linhas_mu = ",\n".join(
    f"  ({i + 1}, {q(m['nome'])}, {q(m['uf'])}, {q(m['unidades'])}, {q(m['ocupadas'])}, {q(m['creche'])}, {q(m['fila'])}, {q(m['docentes'])}, "
    f"{q(m['outros'])}, {q(m['centrais'])}, {q(m['setor'])}, {q(m['conveniadas'])}, {q(m['redutor'])}, {q(m['obs'])})"
    for i, m in enumerate(municipios))
linhas_pa = ",\n".join(f"  ({q(k)}, {q(v)})" for k, v in P.items())

modelo = open(sys.argv[3], encoding="utf-8").read()
sql = modelo.replace("--AGENTES--", linhas_ag).replace("--MUNICIPIOS--", linhas_mu).replace("--PARAMETROS--", linhas_pa)
open(saida, "w", encoding="utf-8").write(sql)
print(len(agentes), "agentes |", len(municipios), "municípios |", P)
