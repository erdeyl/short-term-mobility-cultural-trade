# Raw inputs

Every raw file the reported results were computed from is listed with its SHA-256 in `RAW_MANIFEST.sha256` (1,100 files; paths relative to the package root). Check your files with

    python tools/verify_raw_inputs.py            # from the package root; per-folder counts, then every missing or changed file
    shasum -a 256 -c 01_raw/RAW_MANIFEST.sha256  # the same check with standard tools

`run_all.py` runs the same check in its first stage and stops if a file is missing or differs. Keep the provider file names unchanged; the build code reads them by name and counts them.

| Folder | Source | Files | Included | Instructions |
|---|---|---|---|---|
| `01_Gravity/` | CEPII Gravity V202211 | 2 | no | `01_Gravity/README.md` |
| `02_UN_Comtrade/` | UN Comtrade API (importer-reported, exporter-reported mirror, availability, references) | 749 | no | `02_UN_Comtrade/README.md` |
| `05_Mobility/` | UN Tourism inbound arrivals (344 workbooks) and, optionally, the Hofstede workbook of the submitted paper (rebuilt from the official file when absent) | 344 + 1 optional | no | `05_Mobility/README.md` |
| `06_WorldBank/` | World Bank classifications by income | 2 | yes | `06_WorldBank/README.md` |
| `07_CEPII_Language/` | CEPII Language database | 1 | yes | `07_CEPII_Language/README.md` |
| `08_Hofstede_official/` | official Hofstede six-dimension file, 2015-08-16 | 1 | no | `08_Hofstede_official/README.md` |
| `09_UN_Tourism_bulk/` | UN Tourism bulk download (only for the optional data screens in `02_code/11_data_screens`) | — | no | not in the manifest |

Licenses and the providers' governing texts: `../LICENSES_AND_SOURCES.md`.
