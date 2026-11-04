"""SW2_09: classify every mobility and trade flag with explicit rules (documented in SWEEP2.md section 5),
apply the evidence-based overrides from the official checks, and count affected baseline rows for the
new findings. Outputs: 05_output/11_data_screens/MOBILITY_FLAGS_CLASSIFIED.csv, TRADE_FLAGS_CLASSIFIED.csv,
NEW_FINDINGS_COUNTS.csv."""
from pathlib import Path
import numpy as np
import pandas as pd

# package paths: ROOT = package root; screens write to 05_output/11_data_screens (not run by run_all.py)
ROOT = Path(__file__).resolve().parents[2]
W = ROOT
OUT = ROOT / "05_output/11_data_screens"
p = pd.read_csv(OUT / "work/prepared_corrected_slim.csv.gz", low_memory=False)
p["year"] = p.year.astype(str).str[:4].astype(int)
TOT = {"tour": p.loc[p.s_base_tour == 1, "v_ttl_k"].sum(), "vis": p.loc[p.s_base_vis == 1, "v_ttl_k"].sum()}
BAS = {"RES": "residence", "NAT": "nationality"}


def cnt(iso, fam, years, basis=None, partner=None):
    s = p[(p[f"s_base_{fam}"] == 1) & p.year.isin(years)]
    rev = s.iso3_o.eq(iso)
    same = s.iso3_d.eq(iso)
    if partner:
        rev &= s.iso3_d.eq(partner)
        same &= s.iso3_o.eq(partner)
    if basis:
        rev &= s[f"basis_rev_{fam}"].eq(BAS[basis])
        same &= s[f"basis_same_{fam}"].eq(BAS[basis])
    m = rev | same
    return int(m.sum()), float(s.loc[m, "v_ttl_k"].sum() / TOT[fam])


# ------------------------------------------------------------------ mobility
F = pd.read_csv(OUT / "MOBILITY_FLAGS.csv")
KNOWN_PRY = (F.reporter_area_code == 600) & F.year.between(2015, 2024)
KNOWN_PAK = (F.reporter_area_code == 586) & F.year.between(2020, 2024)


def classify(r):
    pr, rt, ra = r.pub_ratio, r.ratio, r.ratio_aux
    if r.reporter_area_code == 600 and r.year >= 2020:
        return "unit error (KNOWN, C12)", "confirmed; corrected vintage quarantines 2020-2022 (0 residence rows remain); 2023-2024 outside window"
    if r.reporter_area_code == 586 and r.year >= 2020:
        return "unit error (KNOWN, DC_tourism.md section 6)", "confirmed; quarantine 2020-2021 as decided for vintage corrected2"
    if r.screen == "M1":
        if r.flag_type == "UNIT1000":
            return "coverage", "1 partner cell vs total; regional total / published = 0.99997 (Hungary 2005)"
        if r.flag_type == "LOW":
            if ra == ra and 0.95 <= ra <= 1.05:
                return "coverage", "partner detail incomplete; workbook regional total within 5% of published total"
            if r.reporter_area_code == 112:
                return "coverage or definitional break", "Belarus tourists = organized-tourism clients (Belstat 2022: 143.0 thsd = workbook [UN Tourism value; workbook 0112011119992022202512.xlsx, sheet Data, rows 1509 and 1523]); border total is 10x larger"
            return "coverage or definitional break", "partner detail and workbook total both below published total; narrower population in the bilateral table"
        if r.flag_type == "HIGH":
            if r.reporter_area_code == 398:
                return "definitional break", "Kazakhstan 2020: tourist workbook [UN Tourism values; workbook 0398011220202024202512.xlsx, sheet Data, sum of the partner rows of 2020] = published TOTL_TOUR [UN Tourism value; bulk file UN_Tourism_inbound_arrivals_12_2025.xlsx, sheet Data, row 4188] but AREA_TOTL_TOUR [UN Tourism value; bulk file UN_Tourism_inbound_arrivals_by_region_12_2025.xlsx, sheet Data, row 2971] (UN publishes two tourist totals); visitor workbook [UN Tourism values; workbook 0398012219962024202512.xlsx, sheet Data, sum of the partner rows of 2020] > published visitors [UN Tourism value; bulk file UN_Tourism_inbound_arrivals_12_2025.xlsx, sheet Data, row 11841]"
            return "definitional break", "partner-sum above published total by 5-93%; different coverage between bilateral table and headline total"
    if r.screen == "M2":
        if r.reporter_area_code == 112:
            return "code or mapping error", "Belarus visitors by residence 2020-2022: 'Liechtenstein' [UN Tourism values; workbook 0112012220202024202512.xlsx, sheet Data, rows 182-184], Lithuania absent; nationality Lithuania 2020 = [UN Tourism value; workbook 0112012120122022202512.xlsx, sheet Data, row 883]"
        if r.reporter_area_code == 512:
            return "definitional break", "Oman: nationality counts GCC-resident Asian nationals by nationality (India 2019: nationality [UN Tourism value; workbook 0512012120052022202512.xlsx, sheet Data, row 126] vs residence [UN Tourism value; workbook 0512012220182024202512.xlsx, sheet Data, row 98]); both series match the NCSI total 3.5 m"
        return "definitional break", "residence vs nationality differ for expatriate-resident nationals (cell level)"
    if r.screen.startswith("M3") or r.screen == "M4":
        if pr == pr and pr > 0 and abs(np.log(rt / pr)) <= np.log(1.25):
            tag = "real change" + (" (COVID-19)" if 2020 <= r.year <= 2022 else "")
            return tag, f"published total moves alike ({pr:.3g} vs {rt:.3g})"
        if r.reporter_area_code == 356:
            return "real change (COVID-19)", "India FTAs (MoT, ITS at a Glance 2022): 2016 8.80 m, 2019 10.93 m, 2020 2.74 m; bilateral series excludes NRIs on both bases"
        if r.reporter_area_code == 348 and r.year == 2006:
            return "coverage", "1 partner (2005) -> 17 partners; common-partner ratio 1.22"
        if r.reporter_area_code == 64:
            return "real change (COVID-19)", "Bhutan 2021: 1 partner [UN Tourism value; workbook 0064011119952022202512.xlsx, sheet Data, row 2195]; published total moves alike [UN Tourism values; bulk file UN_Tourism_inbound_arrivals_12_2025.xlsx, sheet Data, rows 2316-2319]"
        if r.reporter_area_code == 180:
            return "coverage or definitional break", "DRC: nationality 2013 (26 partners) -> residence 2015 (169 partners); common-partner ratio 2.23, published 1.85"
        if r.reporter_area_code in (414,):
            return "real change (COVID-19)", "Kuwait 2022 reopening; partner set unchanged (243)"
        if r.reporter_area_code in (454, 858, 296, 798, 882, 540, 431):
            return "real change (COVID-19)", "small partner set; direction matches published total"
        return "real change (COVID-19)" if 2020 <= r.year <= 2022 else "unknown", "published ratio differs; see metric"
    if r.screen == "M5":
        if r.flag_type == "V<T_TOTAL":
            return "definitional break", "Bolivia nationality: visitors < tourists in total, 89% of cells equal, no C11b note"
        return "definitional break", "visitor values equal tourist values without (full) C11b note: tourists-only substitute not documented"
    if r.screen == "M8":
        if r.reporter_area_code == 600:
            return "unit error (KNOWN, C12)", "confirmed"
        return "definitional break", "land-border same-day flows above the origin's departures series (ratios < 4)"
    return "unknown", ""


v = F.apply(classify, axis=1, result_type="expand")
F["verdict"], F["evidence"] = v[0], v[1]


def treat(verdict):
    if verdict.startswith("unit error"):
        return "quarantine (C12 rule: set missing, no rescaling)"
    if verdict.startswith("code or mapping error"):
        return "quarantine the mis-coded cells (proven error) + flag"
    if verdict.startswith("real change"):
        return "none"
    if verdict.startswith("coverage") and "definitional" not in verdict:
        return "none (detail coverage); flag"
    return "flag only + sensitivity exclusion"


F["treatment"] = F.verdict.map(treat)
F.to_csv(OUT / "MOBILITY_FLAGS_CLASSIFIED.csv", index=False)
print(F.groupby(["verdict"]).agg(n=("year", "size"), rows=("base_rows", "sum")).to_string())

# ------------------------------------------------------------------ new-finding counts (window 2007-2021)
rows = []
def add(name, iso, fam, years, basis=None, partner=None, note=""):
    n, sh = cnt(iso, fam, years, basis, partner)
    rows.append({"finding": name, "iso3": iso, "family": fam, "years": f"{min(years)}-{max(years)}", "basis": basis or "any",
                 "partner": partner or "", "baseline_rows": n, "value_share": round(sh, 6), "note": note})
add("PAK residence unit error (known)", "PAK", "tour", [2020, 2021]); add("PAK residence unit error (known)", "PAK", "vis", [2020, 2021])
add("PRY residence 2020-2022 after C12 (known; residence rows left)", "PRY", "tour", [2020, 2021], "RES")
add("PRY residence 2020-2022 after C12 (known; residence rows left)", "PRY", "vis", [2020, 2021], "RES")
add("BLR visitors residence: Lithuania coded as Liechtenstein", "BLR", "vis", [2020, 2021], "RES", "LIE")
add("BLR tourists = organized tourism only (nationality series)", "BLR", "tour", list(range(2007, 2021)), "NAT")
add("KAZ residence 2020-2021 tourists/visitors definitional", "KAZ", "tour", [2020, 2021], "RES")
add("KAZ residence 2020-2021 tourists/visitors definitional", "KAZ", "vis", [2020, 2021], "RES")
add("BOL nationality visitors 2020-2021 (undocumented equality, V<T)", "BOL", "vis", [2020, 2021], "NAT")
add("SAU residence visitors 2020-2021 (98% equal, no note)", "SAU", "vis", [2020, 2021], "RES")
add("ZAF residence visitors 2020-2021 (partly undocumented equality)", "ZAF", "vis", [2020, 2021], "RES")
add("OMN visitors 2018-2019 residence vs nationality", "OMN", "vis", [2018, 2019])
add("SVK tourists accommodation basis (known)", "SVK", "tour", list(range(2007, 2022)))
add("SVN tourists accommodation basis (known)", "SVN", "tour", list(range(2007, 2022)))
N = pd.DataFrame(rows)

# ------------------------------------------------------------------ trade
T = pd.read_csv(OUT / "TRADE_FLAGS.csv")
E = pd.read_csv(OUT / "TRADE_FLOW_EVIDENCE.csv")
uv = E.groupby(["year", "iso3_o", "iso3_d"]).apply(lambda g: g.loc[g.imp_usd.idxmax(), ["cmd", "imp_usd_per_kg", "mirror_usd"]]).reset_index()
T = T.merge(uv, on=["year", "iso3_o", "iso3_d"], how="left")
C09 = {("AFG", y) for y in range(2009, 2018)} | {("ARE", y) for y in (2009, 2010, 2011)} | {("BMU", y) for y in (2007, 2008, 2009)} | \
      {("TCA", y) for y in (2007, 2008, 2009)} | {("IRQ", y) for y in (2010, 2011, 2012, 2013, 2015, 2016)} | {("KWT", 2009), ("QAT", 2009), ("QAT", 2011),
       ("COK", 2008), ("MSR", 2010), ("SLB", 2007), ("SLB", 2008), ("SLB", 2010), ("ABW", 2007), ("ABW", 2008), ("CYM", 2013), ("CYM", 2015)}
UNK = {("PAN", "RUS", 2013): "852329 [UN Comtrade value and net weight; file HS_2013_H4_Rb659f465_C08c07520.csv, line 8220] (unit value from the same line); Panama reports no export (Comtrade preview 2026-11-03); value unchanged since snapshot",
       ("NZL", "SGP", 2017): "SGP imports 9701/9703 [UN Comtrade values; file HS_2017_H4_R29e499d4_C08c07520.csv, lines 4066, 4139, 4251]; NZ reports exports [UN Comtrade values; file X_HS_2017_H5_Re21e78c3_Ce2c5be11.csv, lines 4441, 4804]",
       ("RUS", "HKG", 2019): "HKG imports 970110 [UN Comtrade value; file HS_2019_H5_R1ab54736_C08c07520.csv, line 13077], no weight; Russia reports no export",
       ("KOR", "VEN", 2012): "VEN imports 970110 [UN Comtrade value and net weight; file HS_2012_H2_R73877e9a_Ce90ec010.csv, line 833]; Korea reports no export",
       ("CAN", "GTM", 2021): "GTM imports 970600 [UN Comtrade value and net weight; file HS_2021_H5_R4e9ed300_C805c7ea4.csv, line 583]; Canada reports no export",
       ("RUS", "EGY", 2018): "EGY 4911 [UN Comtrade values; file HS_2018_H4_R9172896a_C08c07520.csv, lines 5500, 5699] unmatched (RUS reports [UN Comtrade values; file X_HS_2018_H5_Ra6218a3e_Ce2c5be11.csv, lines 739, 795, 892]); 8523 [UN Comtrade values; file HS_2018_H4_R9172896a_C08c07520.csv, lines 5776, 5889, 5947] matched by RUS exports [UN Comtrade value; file X_HS_2018_H5_Ra6218a3e_Ce2c5be11.csv, line 1032]",
       ("NOR", "SAU", 2019): "970600 [UN Comtrade value; file HS_2019_H4_Rd87708e3_C805c7ea4.csv, line 98] in the archive; current Comtrade preview returns no SAU import record from Norway for 970600 in 2019 (withdrawn after the snapshot); not in a baseline"}


def code6(x):
    try:
        return str(int(float(x)))
    except (TypeError, ValueError):
        return ""


def tclass(r):
    key3 = (r.iso3_o, r.iso3_d, r.year)
    r = r.copy()
    r["cmd"], r["top_hs6"] = code6(r.cmd), code6(r.top_hs6)
    if r.screen in ("T1a", "T1b") and (r.iso3_d, r.year) in C09:
        return "coverage (KNOWN, C09)", "available importer-year without basket rows"
    if key3 in UNK:
        return "unknown (possible misrecording)", UNK[key3]
    if str(r.cmd) == "490700" or str(r.top_hs6) == "490700":
        u = r.imp_usd_per_kg
        if u == u and u > 1000:
            return "definitional break (banknotes at face value)", f"490700 at USD {u:,.0f}/kg; IMTS 2010 para 1.46 excludes issued banknotes in circulation, para 4.15(a) values unissued notes at printed-paper value"
        return "definitional break (non-cultural 490700)", "490700 = stamps, banknotes, cheques, securities (not in UNESCO FCS core list)"
    if str(r.top_hs6) in ("852340", "852380", "852329", "852349"):
        return "definitional break (8523 media incl. software/data)", "8523 lines carry software/data (UNESCO_benchmark.md: 8523 ambiguous)"
    if str(r.top_hs6) == "490600":
        return "real change (non-cultural plans)", "490600 engineering/architectural plans (e.g. RUS->BGD 2015-2018)"
    if r.screen in ("T1a", "T1b"):
        sh = S49.get((r.iso3_d, r.year), 0.0)
        if sh >= 0.85:
            return "definitional break (banknotes at face value)", f"HS 490700 = {sh:.0%} of the importer-year basket (see the pair-year flags: USA->COD, USA/DEU->YEM, CHN->MNG, GBR->CYM, GBR/ZAF->MWI)"
        im = IMIR.get((r.iso3_d, r.year), np.nan)
        if im == im and im < 0.1:
            return "coverage (importer below partner-reported exports)", f"importer/mirror = {im:.3g}; possible partial importer reporting (C09-like, not in C09)"
        return "coverage (mirror)", "importer above exporter-reported mirror without 490700 dominance (e.g. SACU partners of ZAF in 2009, ISR->PSE); exporters' reporting incomplete"
    return "real change or unknown", "single large lot; not verified"


_c = pd.read_csv(OUT / "work/hs6_comp_lb.csv.gz")
_g = _c.groupby(["iso3_d", "year"]).primaryValue.sum()
_g49 = _c[_c.h3 == 490700].groupby(["iso3_d", "year"]).primaryValue.sum()
S49 = (_g49 / _g).dropna().to_dict()
_ry = pd.read_csv(OUT / "T1_reporter_year_totals.csv")
IMIR = {(a, b): c for a, b, c in zip(_ry.iso3, _ry.year, _ry.imp_mir)}
v = T.apply(tclass, axis=1, result_type="expand")
T["verdict"], T["evidence"] = v[0], v[1]
T["treatment"] = np.where(T.verdict.str.startswith("coverage (KNOWN"), "flag only + sensitivity (C09: set missing)",
                 np.where(T.verdict.str.startswith("definitional break (banknotes"), "flag only + sensitivity: Narrow-A/B basket (excl. 490700) or drop 490700 lines > USD 1,000/kg",
                 np.where(T.verdict.str.startswith("unknown"), "flag only + sensitivity exclusion of the pair-year", "flag only (basket-definition sensitivity)")))
T.to_csv(OUT / "TRADE_FLAGS_CLASSIFIED.csv", index=False)
print(T.groupby("verdict").agg(n=("year", "size"), vis=("rows_vis", "sum"), tour=("rows_tour", "sum"), sv=("share_vis", "sum"), st=("share_tour", "sum")).round(4).to_string())

# 490700 currency-like lines in the baselines
comp = pd.read_csv(OUT / "work/hs6_comp_lb.csv.gz")
c49 = comp[comp.h3 == 490700].merge(p[["year", "iso3_o", "iso3_d", "s_base_vis", "s_base_tour"]], on=["year", "iso3_o", "iso3_d"])
for fam in ["vis", "tour"]:
    s = c49[c49[f"s_base_{fam}"] == 1]
    rows.append({"finding": "HS 490700 inside the LB basket (all lines)", "iso3": "*", "family": fam, "years": "2007-2021", "basis": "",
                 "partner": "", "baseline_rows": int((s.primaryValue > 0).sum()), "value_share": round(s.primaryValue.sum() / TOT[fam], 6),
                 "note": "rows with any 490700 value; share of baseline v_ttl_k"})
for key, txt in UNK.items():
    o, d_, y = key
    s = p[(p.iso3_o == o) & (p.iso3_d == d_) & (p.year == y)]
    for fam in ["vis", "tour"]:
        if int(s[f"s_base_{fam}"].sum()):
            rows.append({"finding": f"unknown large lot {o}->{d_} {y}", "iso3": f"{o}->{d_}", "family": fam, "years": str(y), "basis": "", "partner": "",
                         "baseline_rows": 1, "value_share": round(float(s.v_ttl_k.sum()) / TOT[fam], 6), "note": txt})
N = pd.DataFrame(rows)
N.to_csv(OUT / "NEW_FINDINGS_COUNTS.csv", index=False)
pd.set_option("display.width", 250)
print(N.to_string())
