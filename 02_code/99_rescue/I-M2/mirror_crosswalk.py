"""C02-M shared-crosswalk application; no action on import."""  # RESCUE C02-M
from pathlib import Path  # RESCUE C02-M
import hashlib  # RESCUE C02-M
import pandas as pd  # RESCUE C02-M

EXPECTED_SHA256 = "dbde29b726f64adbe03375959a29bbd0782a16d5a800b74e27dc41cd3ca446a2"  # RESCUE C02-M
SCHEMA = ["comtrade_code", "iso3", "applies_to", "source_url", "quote"]  # RESCUE C02-M
NOTE = "UN Comtrade 490 convention; unspecified Asian territories may also enter this source area"  # RESCUE C02-M

def load_crosswalk(path: Path) -> pd.DataFrame:  # RESCUE C02-M
    data = Path(path).read_bytes()  # RESCUE C02-M
    digest = hashlib.sha256(data).hexdigest()  # RESCUE C02-M
    if digest != EXPECTED_SHA256:  # RESCUE C02-M
        raise ValueError(f"C02-M shared crosswalk SHA256 mismatch: {digest}")  # RESCUE C02-M
    rules = pd.read_csv(path, dtype={"comtrade_code": "int64", "iso3": "string", "applies_to": "string"})  # RESCUE C02-M
    if list(rules.columns) != SCHEMA or rules.duplicated(["comtrade_code", "applies_to"]).any():  # RESCUE C02-M
        raise ValueError("C02-M invalid shared crosswalk schema/key")  # RESCUE C02-M
    if rules[SCHEMA].isna().any().any() or not rules.iso3.str.fullmatch("[A-Z]{3}").all():  # RESCUE C02-M
        raise ValueError("C02-M missing crosswalk metadata/invalid ISO3")  # RESCUE C02-M
    if set(rules.applies_to) != {"reporter", "partner", "availability"}:  # RESCUE C02-M
        raise ValueError("C02-M invalid/incomplete shared crosswalk roles")  # RESCUE C02-M
    return rules  # RESCUE C02-M

def _apply(frame: pd.DataFrame, rules: pd.DataFrame, role: str, code: str, iso: str, stem: str) -> pd.DataFrame:  # RESCUE C02-M
    x = frame.copy()  # RESCUE C02-M
    codes = pd.to_numeric(x[code], errors="raise")  # RESCUE C02-M
    mapping = rules.loc[rules.applies_to.eq(role)].set_index("comtrade_code").iso3  # RESCUE C02-M
    x[f"{stem}_iso_source"] = x[iso]  # RESCUE C02-M
    x[f"{stem}_code_source"] = x[code]  # RESCUE C02-M
    x[f"comtrade_490_{stem}"] = codes.eq(490).astype("int8")  # RESCUE C02-M
    x[iso] = codes.map(mapping).fillna(x[iso])  # RESCUE C02-M
    return x  # RESCUE C02-M

def country_eligible(frame: pd.DataFrame) -> pd.Series:  # RESCUE C02-M
    return (frame.reporterISO.fillna("").astype(str).str.fullmatch("[A-Z]{3}")  # RESCUE C02-M
            & frame.partnerISO.fillna("").astype(str).str.fullmatch("[A-Z]{3}")  # RESCUE C02-M
            & ~pd.to_numeric(frame.reporterCode, errors="raise").isin([97, 975])  # RESCUE C02-M
            & frame.reporterISO.ne(frame.partnerISO))  # RESCUE C02-M

def trade(frame: pd.DataFrame, rules: pd.DataFrame) -> pd.DataFrame:  # RESCUE C02-M
    x = _apply(frame, rules, "reporter", "reporterCode", "reporterISO", "reporter")  # RESCUE C02-M
    x = _apply(x, rules, "partner", "partnerCode", "partnerISO", "partner")  # RESCUE C02-M
    eligible = country_eligible(x)  # RESCUE C02-M
    source_keys = ["refYear", "reporterCode", "partnerCode", "reporterISO", "partnerISO"]  # RESCUE C02-M
    unique_source = x.loc[eligible, source_keys].drop_duplicates()  # RESCUE C02-M
    if unique_source.duplicated(["refYear", "reporterISO", "partnerISO"]).any():  # RESCUE C02-M
        raise ValueError("C02-M canonical158/490 collision before aggregation; no priority or summing")  # RESCUE C02-M
    x["comtrade_country_eligible"] = eligible.astype("int8")  # RESCUE C02-M
    x["comtrade_490_residual"] = (x.comtrade_490_reporter.eq(1) | x.comtrade_490_partner.eq(1)).astype("int8")  # RESCUE C02-M
    x["comtrade_special_area_note"] = x.comtrade_490_residual.map({0: "", 1: NOTE})  # RESCUE C02-M
    return x  # RESCUE C02-M

def availability(frame: pd.DataFrame, rules: pd.DataFrame) -> pd.DataFrame:  # RESCUE C02-M
    x = _apply(frame, rules, "availability", "reporter_code", "reporter_iso", "reporter")  # RESCUE C02-M
    if x.duplicated(["year", "reporter_iso"]).any():  # RESCUE C02-M
        raise ValueError("C02-M reporter158/490 availability collision; no priority or summing")  # RESCUE C02-M
    x["comtrade_490_residual"] = x.comtrade_490_reporter  # RESCUE C02-M
    x["comtrade_special_area_note"] = x.comtrade_490_residual.map({0: "", 1: NOTE})  # RESCUE C02-M
    return x  # RESCUE C02-M

def sparse_provenance(frame: pd.DataFrame) -> pd.DataFrame:  # RESCUE C02-M
    keys = ["refYear", "reporterCode", "partnerCode", "classificationCode"]  # RESCUE C02-M
    columns = ["reporter_iso_source", "reporter_code_source", "partner_iso_source", "partner_code_source",  # RESCUE C02-M
               "comtrade_490_reporter", "comtrade_490_partner", "comtrade_country_eligible",  # RESCUE C02-M
               "comtrade_490_residual", "comtrade_special_area_note"]  # RESCUE C02-M
    x = frame[keys + columns].drop_duplicates()  # RESCUE C02-M
    if x.duplicated(keys).any():  # RESCUE C02-M
        raise ValueError("C02-M inconsistent source provenance within numeric-code dyad-year")  # RESCUE C02-M
    return x  # RESCUE C02-M
