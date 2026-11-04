# UN Comtrade

UN Comtrade data may not be re-disseminated without UNSD's permission (`../../LICENSES_AND_SOURCES.md`, section 1), so the archived API files are not included. The package uses exactly the files listed in `../RAW_MANIFEST.sha256`; UN Comtrade revises data over time, so a new download can differ from the archive (the archived files carry file dates of August 2026, and the latest `lastReleased` date in the archived availability responses is 2026-08-10; `acquisition_metadata/download_manifest.csv` records every request and its status but has no date column).

Layout (keep the file names):

| Subfolder | Files | Content |
|---|---|---|
| `data_availability/` | `getDa_HS_2007.json` … `getDa_HS_2021.json` (15) | API data-availability responses (reporter-year, HS edition) |
| `trade_api/reported_HS/` | 330 CSV, pattern `HS_<year>_<HS edition>_R<hash>_C<hash>.csv` | importer-reported imports (`flowCode = M`), cultural HS codes in the reported edition; 1,611,818 source rows in total |
| `reference/` | `partnerAreas.json`, `Reporters.json`, `HS-SITC-BEC_Correlations_2022.xlsx` | UN Comtrade reference lists (https://comtradeapi.un.org/files/v1/app/reference/partnerAreas.json , …/Reporters.json); the UNSD HS–SITC–BEC correlation workbook (UNSD classifications pages, https://unstats.un.org/unsd/classifications/Econ ; the exact download URL of the 2022 workbook is not recorded) |
| `acquisition_metadata/` | `download_manifest.csv` | request batches and statuses of the importer-reported files |
| `mirror_exporter_reported/export_flow_availability/` | 60 CSV, pattern `X_TOTAL_<year>_R<hash>.csv` | exporter totals to World (`flowCode = X`), used to establish exporter-year availability |
| `mirror_exporter_reported/trade_api/reported_HS/` | 338 CSV, pattern `X_HS_<year>_<HS edition>_R<hash>_C<hash>.csv` | exporter-reported exports of the same codes |
| `mirror_exporter_reported/acquisition_metadata/` | `export_flow_availability_manifest.csv`, `exporter_trade_download_manifest.csv` | request batches and statuses of the mirror files |

To re-query (a current UN Comtrade API key is needed; it is read from the environment variable `COMTRADE_API_KEY` or asked for, and never written to disk):

1. Importer side: `python 02_code/00_acquisition/01_UN_Comtrade_importer/run_acquire_importer_trade.py` (classification audit from the availability responses, HS concordance targets, then the downloads; query specification: `config/query_specification.json` in that folder, identical to `02_code/00_common/01_UN_Comtrade/config/query_specification.json`).
2. Exporter side (after the importer side): `python 02_code/03_Mobility/01_database_preparation/04_UN_Comtrade_mirror/run_acquire_exporter_mirror.py` (query specification `config/query_specification_exporter.json`, defaults `config/download_defaults.json`).

Attribution: Source: UN Comtrade.
