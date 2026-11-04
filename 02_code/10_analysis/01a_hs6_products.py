"""01a_hs6_products.py -- dyad-year x canonical-H3 (HS2007) importer-reported values.

Called by 01_prep.do (shell) with explicit paths taken from 00_config.do:
  python3 01a_hs6_products.py <vintage> <raw_dir> <manifest_csv> <ct_int_dir> <crosswalk_csv> <out_dta> <status_json>

Reconstructs, from the archived raw UN Comtrade API files, the same aggregation the
original build performs, but keeps the 31 canonical HS2007 six-digit codes separate:
  source build = STUDENT 02_code/00_common/01_UN_Comtrade/05_build_cultural_trade.py
    raw stacking and provenance checks ........ lines 20-204
    concordance merge (SAFE / AMBIGUOUS) ....... lines 209-224
    reporter ISO from availability ............. lines 227-238
    partner ISO from partner reference ......... lines 241-253
    LB = v_3706 + v_49 + v_8523(id) + v_97 ..... lines 351-360 (AMBIGUOUS_POOL_v_8523 excluded from LB)
    v_8523_exact = (ambiguous pool == 0) ....... line 355
    any_unreported = any isReported false ...... lines 299-300, 366
  corrected vintage only: C02 crosswalk code 490 -> TWN for reporter and partner
    (COPY 05_build_cultural_trade.py:345-347, 02_code/99_rescue/ia_common.py:10-31).
  country-table filter (valid ISO3, 2007-2021, non-domestic) = base_core.py:103-108.
Every SAFE concordance row maps to exactly one canonical H3 code (checked below), so no
value is ever allocated fractionally. Values are primaryValue (current USD) / 1000.
No data value is altered; the script writes only <out_dta> and <status_json>.
"""
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd

vintage, raw_dir, manifest_csv, ct_int, crosswalk_csv, out_dta, status_json = sys.argv[1:8]
assert vintage in ("submitted", "corrected", "corrected2", "corrected2x"), vintage
# corrected2 / corrected2x (rerun C2): same rules as corrected (C02 crosswalk); in addition the
# number of unreported source rows of HS 490700 is kept (n_unreported4907_py) so that the 30-code
# outcome of corrected2x gets its own "fully reported" indicator. submitted/corrected output unchanged.
C2 = vintage in ("corrected2", "corrected2x")
RAW = Path(raw_dir)
CT = Path(ct_int)
status = {"vintage": vintage, "started_utc": datetime.now(timezone.utc).isoformat(), "status": "FAIL"}


def done(**kw):
    status.update(kw)
    status["finished_utc"] = datetime.now(timezone.utc).isoformat()
    Path(status_json).write_text(json.dumps(status, indent=2, sort_keys=True) + "\n", encoding="utf-8")


try:
    # ------------------------------------------------------------ inputs
    manifest = pd.read_csv(manifest_csv)
    mapping = pd.read_csv(CT / "concordance/reported_HS_to_H3_concordance.csv", dtype={"source_code": "string"})
    mapping["source_code"] = mapping["source_code"].str.zfill(6)
    avail = pd.read_csv(CT / "classification_availability/reported_classification_availability_2007_2021.csv")
    pref = pd.read_csv(CT / "reference/partner_reference.csv")

    assert len(mapping) == 219 and not mapping.duplicated(["source_version", "source_code"]).any()
    safe = mapping.mapping_status.eq("SAFE_CATEGORY_MAPPING")
    assert (mapping.loc[~safe, "pipeline_treatment"] == "AMBIGUOUS_POOL_v_8523").all()
    ntouch = mapping.canonical_H3_codes_touched.astype(str).str.count(";") + 1
    assert (ntouch[safe] == 1).all(), "a SAFE source code touches more than one canonical H3 code"
    mapping["h3"] = np.where(safe, mapping.canonical_H3_codes_touched.astype(str), "AMB")
    codes = sorted(mapping.loc[safe, "h3"].unique())
    assert len(codes) == 31, len(codes)
    # category of each canonical code must agree with the pipeline treatment
    cat = mapping.loc[safe].groupby("h3").pipeline_treatment.nunique()
    assert (cat == 1).all()
    code_cat = mapping.loc[safe].drop_duplicates("h3").set_index("h3").pipeline_treatment.to_dict()

    files = sorted(RAW.glob("*.csv"))
    assert len(files) == 330 and len(manifest) == 330
    assert set(manifest.filename) == {p.name for p in files}
    mby = manifest.set_index("filename")
    pat = re.compile(r"^HS_(\d{4})_(H\d)_R[0-9a-f]+_C[0-9a-f]+\.csv$")

    cols = ["refYear", "reporterCode", "partnerCode", "classificationCode", "cmdCode", "primaryValue", "isReported"]
    parts, empty = [], []
    for p in files:
        try:
            if p.stat().st_size == 0:
                raise pd.errors.EmptyDataError("zero-byte")
            d = pd.read_csv(p, usecols=cols, dtype={"classificationCode": str, "cmdCode": str}, low_memory=False)
        except pd.errors.EmptyDataError:
            assert int(mby.loc[p.name, "data_rows"]) == 0
            empty.append(p.name)
            continue
        assert len(d) == int(mby.loc[p.name, "data_rows"]), p.name
        m = pat.fullmatch(p.name)
        assert m and (d.refYear == int(m.group(1))).all() and (d.classificationCode == m.group(2)).all(), p.name
        parts.append(d)
    raw = pd.concat(parts, ignore_index=True)
    n_raw = len(raw)
    assert n_raw == 1611818, n_raw  # frozen_snapshot_expectations.json raw_trade_rows
    raw["cmdCode"] = raw.cmdCode.astype(str).str.replace(r"\.0$", "", regex=True).str.zfill(6)
    raw["primaryValue"] = pd.to_numeric(raw.primaryValue, errors="raise")
    assert raw.primaryValue.notna().all() and (raw.primaryValue >= 0).all()
    assert not raw.duplicated(["refYear", "reporterCode", "partnerCode", "classificationCode", "cmdCode"]).any()

    raw = raw.merge(mapping[["source_version", "source_code", "h3", "pipeline_treatment"]],
                    left_on=["classificationCode", "cmdCode"], right_on=["source_version", "source_code"],
                    how="left", validate="m:1")
    assert raw.pipeline_treatment.notna().all()
    rmap = avail[["_query_year", "reporterCode", "reporterISO", "classificationCode"]].rename(
        columns={"_query_year": "refYear", "classificationCode": "avail_cls"})
    raw = raw.merge(rmap, on=["refYear", "reporterCode"], how="left", validate="m:1")
    assert raw.reporterISO.notna().all() and (raw.classificationCode == raw.avail_cls).all()
    raw = raw.merge(pref[["partnerCode", "partnerISO"]], on="partnerCode", how="left", validate="m:1")
    assert raw.partnerCode.isin(pref.partnerCode).all()

    raw["unrep"] = (~raw.isReported.astype(str).str.lower().isin(["true", "1"])).astype("int8")

    # ------------------------------------------------------------ aggregate to dyad-year x code
    key = ["refYear", "reporterCode", "partnerCode", "reporterISO", "partnerISO", "classificationCode"]
    raw["reporterISO"] = raw.reporterISO.fillna("").astype(str)
    raw["partnerISO"] = raw.partnerISO.fillna("").astype(str)
    long = raw.groupby(key + ["h3"], dropna=False).primaryValue.sum().reset_index()
    wide = long.pivot_table(index=key, columns="h3", values="primaryValue", aggfunc="sum", fill_value=0.0).reset_index()
    wide.columns.name = None
    for c in codes + ["AMB"]:
        if c not in wide.columns:
            wide[c] = 0.0
    if C2:
        raw["unrep4907"] = (raw.unrep * raw.h3.eq("490700")).astype("int8")
        prov = raw.groupby(key, dropna=False).agg(n_rows=("primaryValue", "size"), n_unrep=("unrep", "sum"),
                                                  n_unrep4907=("unrep4907", "sum")).reset_index()
    else:
        prov = raw.groupby(key, dropna=False).agg(n_rows=("primaryValue", "size"), n_unrep=("unrep", "sum")).reset_index()
    wide = wide.merge(prov, on=key, how="left", validate="1:1")
    # category sums grouped exactly as the original build (by pipeline_treatment), for the positive control
    catsum = raw.groupby(key + ["pipeline_treatment"], dropna=False).primaryValue.sum().reset_index().pivot_table(
        index=key, columns="pipeline_treatment", values="primaryValue", aggfunc="sum", fill_value=0.0).reset_index()
    catsum.columns.name = None
    for c in ["v_3706", "v_49", "v_8523", "v_97", "AMBIGUOUS_POOL_v_8523"]:
        if c not in catsum.columns:
            catsum[c] = 0.0
    catsum = catsum.rename(columns={"v_3706": "cat3706", "v_49": "cat49", "v_8523": "cat8523", "v_97": "cat97",
                                    "AMBIGUOUS_POOL_v_8523": "catamb"})
    wide = wide.merge(catsum, on=key, how="left", validate="1:1")
    n_sparse = len(wide)
    assert n_sparse == 211684, n_sparse  # frozen_snapshot_expectations.json sparse_dyad_year_rows

    # ------------------------------------------------------------ C02 crosswalk (corrected only)
    n490_rep = int(wide.reporterCode.eq(490).sum())
    n490_par = int(wide.partnerCode.eq(490).sum())
    if vintage in ("corrected", "corrected2", "corrected2x"):
        rules = pd.read_csv(crosswalk_csv)
        assert list(rules) == ["comtrade_code", "iso3", "applies_to", "source_url", "quote"]
        for role, code, iso in [("reporter", "reporterCode", "reporterISO"), ("partner", "partnerCode", "partnerISO")]:
            mp = rules.loc[rules.applies_to.eq(role)].set_index("comtrade_code").iso3
            wide[iso] = wide[code].map(mp).fillna(wide[iso])

    # ------------------------------------------------------------ country-table filter (base_core.py:103-108)
    valid = wide.reporterISO.str.fullmatch(r"[A-Z]{3}") & wide.partnerISO.str.fullmatch(r"[A-Z]{3}")
    inwin = wide.refYear.between(2007, 2021)
    dom = wide.reporterISO.eq(wide.partnerISO)
    elig = valid & inwin & ~dom
    out = wide.loc[elig].copy()
    out = out.rename(columns={"refYear": "year", "partnerISO": "iso3_o", "reporterISO": "iso3_d"})
    assert not out.duplicated(["year", "iso3_o", "iso3_d"]).any(), "duplicate country dyad-year after mapping"

    for c in codes:
        out["h" + c + "_k"] = out[c] / 1000.0
    out["amb8523_k"] = out["AMB"] / 1000.0
    for c in ["cat3706", "cat49", "cat8523", "cat97", "catamb"]:
        out[c + "_k"] = out[c] / 1000.0
    out["n_source_rows_py"] = out.n_rows.astype("int32")
    out["n_unreported_py"] = out.n_unrep.astype("int32")
    out["any_unreported_py"] = (out.n_unrep > 0).astype("int8")
    out["v_8523_exact_py"] = out.AMB.eq(0).astype("int8")
    out["hs6_row_present"] = np.int8(1)
    if C2:
        out["n_unreported4907_py"] = out.n_unrep4907.astype("int32")
    keep = (["year", "iso3_o", "iso3_d"] + ["h" + c + "_k" for c in codes] + ["amb8523_k"]
            + [c + "_k" for c in ["cat3706", "cat49", "cat8523", "cat97", "catamb"]]
            + ["n_source_rows_py", "n_unreported_py", "any_unreported_py", "v_8523_exact_py", "hs6_row_present"]
            + (["n_unreported4907_py"] if C2 else []))
    out = out[keep].sort_values(["year", "iso3_o", "iso3_d"]).reset_index(drop=True)
    out["year"] = out.year.astype("int16")
    out["iso3_o"] = out.iso3_o.astype(object)
    out["iso3_d"] = out.iso3_d.astype(object)
    labels = {"h" + c + "_k": f"HS2007 {c} ({code_cat[c]}), importer-reported, thousand current USD" for c in codes}
    labels["amb8523_k"] = "Ambiguous pre-H3 recorded-media pool (not in LB), thousand USD"
    labels["hs6_row_present"] = "Dyad-year present in raw importer-reported cultural rows"
    out.to_stata(out_dta, write_index=False, version=118, variable_labels=labels)

    tot = {c: float(out["h" + c + "_k"].sum()) for c in codes}
    done(status="PASS", raw_files=len(files), legitimately_empty_files=len(empty), raw_rows=n_raw,
         sparse_dyad_years_all_areas=n_sparse, reporter_code_490_rows=n490_rep, partner_code_490_rows=n490_par,
         excluded_nonISO3_or_domestic_or_window=int((~elig).sum()), output_country_dyad_years=len(out),
         codes=codes, code_category=code_cat, total_k_by_code=tot,
         note="output keyed year iso3_o(partner/exporter) iso3_d(reporter/importer); CEPII-universe filter applied in Stata merge")
except Exception as exc:  # fail closed: status FAIL with the reason
    done(status="FAIL", error=repr(exc))
    raise
