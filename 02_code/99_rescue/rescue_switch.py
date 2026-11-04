"""RESCUE correction switch (owner rule: "Everything must remain fully replicable.").

RESCUE_CORRECTIONS = all | none | comma-separated ledger ids (e.g. "C02,C03").
Unset or empty = none, so the untouched pipeline behaviour (baseline) is the default.
Usage from the student's code (any depth below 02_code):
    import importlib.util, pathlib
    _p = next(p for p in pathlib.Path(__file__).resolve().parents if p.name == "02_code") / "99_rescue" / "rescue_switch.py"
    _s = importlib.util.spec_from_file_location("rescue_switch", _p); rescue_switch = importlib.util.module_from_spec(_s); _s.loader.exec_module(rescue_switch)
    if rescue_switch.enabled("C02"): ...
"""
import os

def setting() -> str:
    return os.environ.get("RESCUE_CORRECTIONS", "").strip() or "none"

def enabled(cid: str) -> bool:
    v = setting()
    if v.lower() == "none":
        return False
    if v.lower() == "all":
        return True
    return cid.strip().upper() in {x.strip().upper() for x in v.split(",") if x.strip()}
