#!/usr/bin/env python3
"""
Gera supabase/seed/10_dados_publicos.sql a partir da planilha de pesquisa
IARA_Educa_Microdados_2025_Nivel3_REAL.xlsx (base real das 118 unidades).

Regras:
  - Nada é inventado: campos ausentes ficam NULL / "Pendente SEDUC".
  - Macrorregiões são CALCULADAS (distância/rumo a partir do centro), rotuladas como
    território de demonstração até a SEDUC definir os territórios oficiais.
Uso: python scripts/seed/gerar_seed_publico.py [caminho.xlsx]
"""
from __future__ import annotations

import json
import math
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[2]
XLSX = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "IARA_Educa_Microdados_2025_Nivel3_REAL.xlsx"
OUT = ROOT / "supabase" / "seed" / "10_dados_publicos.sql"
BOUNDARY = ROOT / "public" / "geo" / "maringa-limite.geojson"
BATCH = "xlsx-nivel3-2026-10-03"

CENTER = (-23.4253, -51.9386)  # Catedral de Maringá (referência para macrorregiões calculadas)
CENTRO_RAIO_KM = 2.3

MACROS = [
    # id, code, name, color, sort
    (1, "CENTRO", "Centro", "#7A24C5", 1),
    (2, "NORTE", "Zona Norte", "#1594D2", 2),
    (3, "SUL", "Zona Sul", "#00A983", 3),
    (4, "LESTE", "Zona Leste", "#F28C38", 4),
    (5, "OESTE", "Zona Oeste", "#D94C7A", 5),
    (6, "IGUATEMI", "Distrito de Iguatemi", "#8C6A3F", 6),
    (7, "FLORIANO", "Distrito de Floriano", "#4F7D2B", 7),
]
GRADE_MAP = {
    ("Educação Infantil", "Creche"): 1,
    ("Educação Infantil", "Pré-escola"): 2,
    ("Ensino Fundamental", "1º ano"): 3,
    ("Ensino Fundamental", "2º ano"): 4,
    ("Ensino Fundamental", "3º ano"): 5,
    ("Ensino Fundamental", "4º ano"): 6,
    ("Ensino Fundamental", "5º ano"): 7,
    ("EJA", "Fundamental - anos iniciais"): 8,
}
SHIFT_STAGE_MAP = {
    "Educação Infantil - Creche": (1, 1),
    "Educação Infantil - Pré-escola": (1, 2),
    "Ensino Fundamental - anos iniciais": (2, None),
    "EJA - Fundamental": (3, 8),
}


def q(v) -> str:
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    s = str(v).strip()
    if s == "":
        return "null"
    return "'" + s.replace("'", "''") + "'"


def qi(v) -> str:
    """Inteiro ou null (strings como 'Pendente SEDUC' viram null)."""
    if v is None:
        return "null"
    if isinstance(v, (int, float)):
        return str(int(v))
    s = str(v).strip()
    return s if re.fullmatch(r"\d+", s) else "null"


def haversine_km(a, b) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    d = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 6371.0088 * 2 * math.asin(math.sqrt(d))


def bearing_deg(a, b) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    y = math.sin(lon2 - lon1) * math.cos(lat2)
    x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(lon2 - lon1)
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def macro_for(lat, lng, text: str) -> int:
    t = text.lower()
    if "iguatemi" in t:
        return 6
    if "floriano" in t:
        return 7
    d = haversine_km(CENTER, (lat, lng))
    if d <= CENTRO_RAIO_KM:
        return 1
    b = bearing_deg(CENTER, (lat, lng))
    if b >= 315 or b < 45:
        return 2
    if b < 135:
        return 4
    if b < 225:
        return 3
    return 5


def geo_precision(status: str | None) -> str:
    s = (status or "").lower()
    if "provisório" in s or "provisorio" in s:
        return "PROVISORIO"
    if "aproxima" in s or "geocodificado" in s or "revisão territorial" in s or "revisao territorial" in s:
        return "APROXIMADO"
    return "VALIDADO"


def rows(ws):
    data = list(ws.iter_rows(values_only=True))
    header = [h for h in data[0]]
    out = []
    for r in data[1:]:
        if r is None or all(c is None for c in r):
            continue
        out.append({header[i]: r[i] if i < len(r) else None for i in range(len(header)) if header[i] is not None})
    return out


def main() -> None:
    wb = openpyxl.load_workbook(XLSX, read_only=True, data_only=True)
    units = [u for u in rows(wb["Unidades"]) if u.get("ID") is not None]
    pub = {r["Unidade"]: r for r in rows(wb["Dados_Publicos_118"])}
    offers = [r for r in rows(wb["Nivel_2_Oferta"]) if r.get("Unidade")]
    grades = [r for r in rows(wb["Nivel_3_Serie_REAL"]) if r.get("Unidade")]
    shifts = [r for r in rows(wb["Turnos_por_Etapa_2025"]) if r.get("Unidade")]
    pend_micro = [r for r in rows(wb["Microdados_Pendencias"]) if r.get("Unidade IARA")]
    recon = [r for r in rows(wb["Reconciliacao_Rede"]) if r.get("Item")]
    pend_seduc = [r for r in rows(wb["Pendencias_SEDUC"]) if r.get("Dado necessário")]

    by_name = {u["Unidade"]: u for u in units}
    sql: list[str] = []
    w = sql.append
    w("-- GERADO AUTOMATICAMENTE por scripts/seed/gerar_seed_publico.py — não editar à mão.")
    w(f"-- Fonte: {XLSX.name} (base real de pesquisa IARA Educa · Censo Escolar 2025/INEP · SEED-PR 2026)")
    w("begin;")
    w("set local iara.skip_audit = 'on';")
    w("delete from iara.data_quality_issues; delete from iara.unit_shift_stats; delete from iara.unit_grade_stats;")
    w("delete from iara.unit_offers; update iara.education_units set macro_territory_id = null, neighborhood_territory_id = null;")
    w("delete from iara.education_units; delete from iara.territories; delete from iara.import_batches;")

    counts = {"unidades": len(units), "ofertas": len(offers), "series": len(grades), "turnos": len(shifts)}
    w(f"insert into iara.import_batches (id, source_file, description, row_counts) values ({q(BATCH)}, {q(XLSX.name)}, "
      f"{q('Seed inicial a partir da base consolidada de pesquisa (118 unidades)')}, {q(json.dumps(counts, ensure_ascii=False))}::jsonb);")

    # Limite municipal (IBGE) como território MUNICIPIO
    if BOUNDARY.exists():
        gj = json.loads(BOUNDARY.read_text(encoding="utf-8"))
        geom = gj["features"][0]["geometry"]
        w("insert into iara.territories (id, tenant_id, code, name, kind, geom, sort, source, confidence_status) values "
          f"(100, 1, 'MUNICIPIO', 'Município de Maringá', 'MUNICIPIO', "
          f"extensions.st_multi(extensions.st_setsrid(extensions.st_geomfromgeojson({q(json.dumps(geom))}), 4326))::extensions.geography, "
          f"0, 'Malha municipal IBGE (API de malhas v3)', 'PUBLIC_OFFICIAL');")

    # Macrorregiões calculadas
    macro_of: dict[int, int] = {}
    for u in units:
        macro_of[u["ID"]] = macro_for(float(u["Latitude"]), float(u["Longitude"]), f"{u.get('Endereço') or ''} {u.get('Bairro/Região') or ''}")
    for mid, code, name, color, sort in MACROS:
        members = [u for u in units if macro_of[u["ID"]] == mid]
        if not members:
            continue
        lat = sum(float(u["Latitude"]) for u in members) / len(members)
        lng = sum(float(u["Longitude"]) for u in members) / len(members)
        kind = "DISTRITO" if code in ("IGUATEMI", "FLORIANO") else "MACRORREGIAO"
        w("insert into iara.territories (id, tenant_id, code, name, kind, parent_id, center, color, sort, source, confidence_status) values "
          f"({mid}, 1, {q(code)}, {q(name)}, {q(kind)}, {'100' if BOUNDARY.exists() else 'null'}, iara.point({lat:.7f}, {lng:.7f}), {q(color)}, {sort}, "
          f"{q('Macrorregião calculada por distância/rumo ao centro (DEMO) — território oficial pendente SEDUC')}, 'DEMO');")

    # Bairros (texto real da base) com centroide das unidades
    bairro_units: dict[str, list] = defaultdict(list)
    for u in units:
        b = (u.get("Bairro/Região") or "").strip()
        if b:
            bairro_units[b].append(u)
    bairro_id: dict[str, int] = {}
    for i, (b, members) in enumerate(sorted(bairro_units.items(), key=lambda kv: kv[0]), start=1000):
        bairro_id[b] = i
        lat = sum(float(u["Latitude"]) for u in members) / len(members)
        lng = sum(float(u["Longitude"]) for u in members) / len(members)
        parent = Counter(macro_of[u["ID"]] for u in members).most_common(1)[0][0]
        code = "B" + str(i)
        w("insert into iara.territories (id, tenant_id, code, name, kind, parent_id, center, sort, source, confidence_status) values "
          f"({i}, 1, {q(code)}, {q(b)}, 'BAIRRO', {parent}, iara.point({lat:.7f}, {lng:.7f}), 0, "
          f"{q('Bairro/região conforme base de unidades (endereços públicos)')}, 'PUBLIC_SECONDARY');")

    # Educação especial (agregado oficial por unidade)
    special = {r["Unidade"]: r["Matrículas"] for r in grades if r.get("Etapa") == "Educação Especial"}

    totals = Counter()
    for u in units:
        uid = u["ID"]
        name = u["Unidade"].strip()
        p = pub.get(name, {})
        is_cmei = u["Tipo"] == "CMEI"
        status_base = u.get("Status base 2026") or ""
        if status_base.startswith("Base direção"):
            status, status_label = "ATIVA", "Ativa — direção 2026–2027 nomeada"
        elif "0 turmas" in status_base:
            status, status_label = "SEM_TURMAS", status_base
        else:
            status, status_label = "A_VALIDAR", status_base
        lat, lng = float(u["Latitude"]), float(u["Longitude"])
        stages_text = (u.get("Etapas atendidas") or "").replace("Cadastro SEED/PR: ", "")
        offers_text = p.get("Oferta pública mais recente") or stages_text
        has_aee = "AEE" in (offers_text or "") or "AEE" in stages_text
        phone = u.get("Telefone")
        if phone and "não localizado" in phone.lower():
            phone = None
        capacity = qi(u.get("Capacidade"))
        totals["turmas"] += int(u["Turmas (agregado)"] or 0) if isinstance(u.get("Turmas (agregado)"), (int, float)) else 0
        totals["matriculas"] += int(u["Ocupadas"] or 0) if isinstance(u.get("Ocupadas"), (int, float)) else 0
        display = ("CMEI " if is_cmei else "E.M. ") + name
        w("insert into iara.education_units (id, tenant_id, name, short_name, inep_name, unit_type, unit_type_label, status, status_label, "
          "address_line, neighborhood, postal_code, location, lat, lng, macro_territory_id, neighborhood_territory_id, inep_code, "
          "director_name, director_status, director_source, phone, stages_text, offers_text, public_classes, public_enrollments, "
          "census_classes, census_enrollments, census_teachers, census_status, census_special_ed_enrollments, public_capacity, public_detail, "
          "data_reference, data_status, main_source, address_confidence, address_source, geo_status, geo_source, geo_note, geo_precision, "
          "cep_source, seduc_confirmation_status, confidence_status, source_date, import_batch_id, has_aee) values ("
          f"{uid}, 1, {q(display)}, {q(name)}, null, {q('CMEI' if is_cmei else 'ESCOLA')}, {q('CMEI' if is_cmei else 'Escola Municipal')}, "
          f"{q(status)}, {q(status_label)}, {q(u.get('Endereço'))}, {q(u.get('Bairro/Região'))}, {q(u.get('CEP'))}, "
          f"iara.point({lat:.8f}, {lng:.8f}), {lat:.8f}, {lng:.8f}, {macro_of[uid]}, {bairro_id.get((u.get('Bairro/Região') or '').strip(), 'null')}, "
          f"{q(u.get('Código INEP'))}, {q(u.get('Diretor(a)'))}, {q(u.get('Situação da direção'))}, {q(u.get('Fonte da direção'))}, {q(phone)}, "
          f"{q(stages_text)}, {q(offers_text)}, {qi(u.get('Turmas (agregado)'))}, {qi(u.get('Ocupadas'))}, "
          f"{qi(p.get('Turmas Censo 2025'))}, {qi(p.get('Matrículas Censo 2025'))}, {qi(p.get('Docentes Censo 2025'))}, {q(p.get('Status Censo 2025'))}, "
          f"{qi(special.get(name))}, {capacity}, {q(p.get('Detalhe público 2026'))}, "
          f"{q(str(u.get('Data referência educacional')) if u.get('Data referência educacional') is not None else None)}, {q(u.get('Status do dado educacional'))}, "
          f"{q(u.get('Fonte principal'))}, {q(u.get('Confiabilidade do endereço'))}, {q(u.get('Fonte do endereço'))}, {q(u.get('Status GEO'))}, "
          f"{q(u.get('Fonte GEO'))}, {q(u.get('Observação GEO'))}, {q(geo_precision(u.get('Status GEO')))}, {q(u.get('Fonte CEP'))}, "
          f"{q(p.get('Status confirmação SEDUC'))}, 'PUBLIC_OFFICIAL', "
          f"{q(str(u.get('Data referência educacional')) if u.get('Data referência educacional') is not None else None)}, {q(BATCH)}, {q(has_aee)});")

    # Nível 2 — oferta
    stage_code = {"Educação Infantil": "EI", "Ensino Fundamental": "EF", "Fundamental": "EF", "EJA": "EJA",
                  "Atividades Complementares": "AC", "AEE": "AEE"}
    for r in offers:
        u = by_name.get(r["Unidade"])
        if not u:
            continue
        name = (r.get("Oferta/Etapa") or "").replace("Cadastro SEED/PR: ", "")
        code = next((v for k, v in stage_code.items() if name.startswith(k)), None)
        w("insert into iara.unit_offers (unit_id, offer_name, stage_code, classes_count, enrollments_count, reference_date, confidence_text, source, note) values ("
          f"{u['ID']}, {q(name)}, {q(code)}, {qi(r.get('Turmas da oferta'))}, {qi(r.get('Matrículas da oferta'))}, {q(r.get('Data referência'))}, "
          f"{q(r.get('Status/confiança'))}, {q(r.get('Fonte'))}, {q(r.get('Observação'))});")

    # Nível 3 — série/faixa (Censo 2025)
    for r in grades:
        u = by_name.get(r["Unidade"])
        if not u:
            continue
        gid = GRADE_MAP.get((r["Etapa"], r["Ano/Série/Faixa"]))
        avg = r.get("Média alunos/turma")
        w("insert into iara.unit_grade_stats (unit_id, stage_name, grade_name, grade_level_id, classes_count, enrollments_count, avg_per_class, reference_year, source, status) values ("
          f"{u['ID']}, {q(r['Etapa'])}, {q(r['Ano/Série/Faixa'])}, {gid if gid else 'null'}, {qi(r.get('Nº de turmas'))}, {qi(r.get('Matrículas'))}, "
          f"{round(float(avg), 2) if isinstance(avg, (int, float)) else 'null'}, {int(r.get('Ano referência') or 2025)}, {q(r.get('Fonte'))}, {q(r.get('Status'))});")

    # Turnos por etapa (Censo 2025)
    for r in shifts:
        u = by_name.get(r["Unidade"])
        if not u:
            continue
        st, gl = SHIFT_STAGE_MAP.get(r["Etapa"], (None, None))
        w("insert into iara.unit_shift_stats (unit_id, stage_name, stage_id, grade_level_id, shift, classes_count, enrollments_count, reference_year, source, limitation) values ("
          f"{u['ID']}, {q(r['Etapa'])}, {st if st else 'null'}, {gl if gl else 'null'}, {q(r['Turno'])}, {qi(r.get('Nº de turmas'))}, {qi(r.get('Matrículas'))}, "
          f"{int(r.get('Ano') or 2025)}, {q(r.get('Fonte'))}, {q(r.get('Limitação'))});")

    # Qualidade do dado / pendências
    def issue(kind, sev, unit_id, title, desc, source, action):
        w("insert into iara.data_quality_issues (tenant_id, issue_type, severity, unit_id, title, description, source, action) values ("
          f"1, {q(kind)}, {q(sev)}, {unit_id if unit_id else 'null'}, {q(title)}, {q(desc)}, {q(source)}, {q(action)});")

    recon_by_name = {r["Item"]: r for r in recon}
    for r in pend_micro:
        u = by_name.get(r["Unidade IARA"])
        rc = recon_by_name.get(r["Unidade IARA"], {})
        issue("SEM_CRUZAMENTO_CENSO_2025", "ALTA", u["ID"] if u else None,
              f"{r['Unidade IARA']}: sem cruzamento no Censo 2025",
              f"{r.get('Situação no Censo 2025')}. {rc.get('Situação') or ''}. {rc.get('Observação') or ''}".strip(),
              rc.get("Fonte") or "Microdados Censo Escolar 2025 / INEP", rc.get("Ação") or "Confirmar quantitativos com a SEDUC")
    for r in recon:
        if r["Item"] == "Miriam L Palandri E M Profa EF":
            issue("RECONCILIACAO_REDE", "ALTA", None, "Unidade ativa no Censo 2025 ausente da base (Miriam L. Palandri)",
                  f"{r.get('Quantidade/Unidade')}. {r.get('Observação')}", r.get("Fonte"), r.get("Ação"))
    issue("RECONCILIACAO_REDE", "MEDIA", None, "113 unidades ativas no Censo 2025 × 118 registros investigados",
          "112 unidades da base cruzam com o Censo 2025; 6 registros não têm microdado (novas, reclassificadas ou sem turmas).",
          "Aba Reconciliacao_Rede", "Conciliar cadastro oficial da rede 2026 com a SEDUC")
    for r in pend_seduc:
        sev = "ALTA" if (r.get("Prioridade") or "").lower().startswith("alta") else "MEDIA"
        issue("PENDENCIA_SEDUC", sev, None, r["Dado necessário"],
              f"Granularidade: {r.get('Granularidade')}. {r.get('Por que precisamos')}. {r.get('Observação') or ''}".strip(),
              r.get("Fonte/Área provável"), "Solicitar extração oficial à SEDUC")
    for u in units:
        prec = geo_precision(u.get("Status GEO"))
        if prec != "VALIDADO":
            issue("GEO_APROXIMADA", "MEDIA", u["ID"], f"{u['Unidade']}: coordenada {prec.lower()}",
                  f"{u.get('Status GEO')}. {u.get('Observação GEO') or ''}".strip(), u.get("Fonte GEO"),
                  "Refinar o ponto antes de decisões automáticas por raio de 2 km")
        if u.get("Status base 2026") and not str(u["Status base 2026"]).startswith("Base direção"):
            issue("SITUACAO_OPERACIONAL", "ALTA", u["ID"], f"{u['Unidade']}: situação operacional a confirmar",
                  f"{u.get('Status base 2026')}. {u.get('Situação da direção') or ''}".strip(), u.get("Fonte principal"),
                  "Confirmar funcionamento, turmas e direção com a SEDUC")
    sem_tel = sum(1 for u in units if not u.get("Telefone") or "não localizado" in str(u["Telefone"]).lower())
    issue("CONTATO_AUSENTE", "BAIXA", None, f"{sem_tel} unidades sem telefone em fonte pública",
          "Telefones institucionais não localizados em fontes públicas consultadas.", "Base de unidades",
          "Importar contatos oficiais da SEDUC")
    issue("TURMA_SEM_CAPACIDADE", "ALTA", None, "Capacidade autorizada por turma: pendente SEDUC (118 unidades)",
          "Sem capacidade por turma pública e confiável. No ambiente demo, a capacidade por turma é parametrização fictícia rotulada.",
          "Aba Pendencias_SEDUC / Dicionário", "Importar turmas operacionais (código, capacidade, matrículas ativas)")

    # Polígonos: áreas de influência (Voronoi das unidades) e macrorregiões, recortados pelo limite IBGE
    if BOUNDARY.exists():
        w("""
with b as (select extensions.st_buffer(geom::extensions.geometry, 0) g from iara.territories where id = 100),
pts as (select extensions.st_collect(location::extensions.geometry) g from iara.education_units),
vor as (select (extensions.st_dump(extensions.st_voronoipolygons(pts.g, 0, b.g))).geom as cell from pts, b),
cells as (
  select u.id, extensions.st_intersection(v.cell, b.g) as g
  from vor v cross join b
  join iara.education_units u on extensions.st_intersects(v.cell, u.location::extensions.geometry)
)
update iara.education_units u set influence_area = extensions.st_multi(extensions.st_collectionextract(c.g, 3))::extensions.geography
from cells c where c.id = u.id;

update iara.territories t set geom = sub.g
from (
  select u.macro_territory_id as id,
         extensions.st_multi(extensions.st_collectionextract(extensions.st_union(u.influence_area::extensions.geometry), 3))::extensions.geography as g
  from iara.education_units u where u.influence_area is not null group by u.macro_territory_id
) sub where t.id = sub.id;
""")

    w(f"-- Conferência: agregado público mais recente = {totals['turmas']} turmas / {totals['matriculas']} matrículas")
    w("commit;")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(sql) + "\n", encoding="utf-8")

    dist = Counter(macro_of.values())
    print(f"OK: {OUT.relative_to(ROOT)} — {len(units)} unidades, {len(offers)} ofertas, {len(grades)} séries, {len(shifts)} turnos")
    print("Agregado público mais recente:", dict(totals))
    print("Macrorregiões:", {next(m[2] for m in MACROS if m[0] == k): v for k, v in sorted(dist.items())})


if __name__ == "__main__":
    main()
