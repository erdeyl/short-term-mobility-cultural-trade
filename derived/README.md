# Shared derived files

Keys, codes and flags only: no UN Tourism value, no Hofstede score and no HS description text (`../LICENSES_AND_SOURCES.md`). The run regenerates the same information from the raw files; these copies let readers inspect the definitions and the samples without the restricted data.

| Folder | Files | Built from |
|---|---|---|
| `products/` | `hs6_product_list.csv`, `unesco_fcs2009_benchmark.csv` | `02_code/00_common/01_UN_Comtrade/config/product_definition_H3.csv`; basket definitions of `02_code/10_analysis/01_prep.do` part C; UNESCO FCS 2009 Table 3 |
| `concordance/` | `reported_HS_to_H3_concordance.csv` | output of `02_code/00_common/01_UN_Comtrade/02_build_HS_concordance.py` (UNSD HS correlation tables) |
| `flags/` | `sample_flags_corrected2x.csv.gz`, `C09_zero_fill_no_rows.csv`, `sweep2_mobility_flags.csv`, `sweep2_trade_flags.csv`, `sweep2_new_findings_counts.csv` | estimation-sample flags of `05_output/10_analysis/corrected2x/prepared.dta`; flag C09 of the common base; data screens (`02_code/11_data_screens`) |
| `worldbank/` | `wb_income_region_by_economy_year.csv` | `01_raw/06_WorldBank` via `01_prep.do` part E |
| `hofstede/` | `hofstede_official_ctr_iso3_map.csv`, `hofstede_official_unmapped_rows.csv`, `hofstede_regional_proxy_construction.csv`, `hofstede_package_workbook_layout.csv` | `02_code/10_analysis/A2_00_hofstede.py`; comparison of the build's workbook with the official file |
| `table_templates/` | `submitted_manuscript_tables.md` | table blocks of the submitted manuscript (layout read by `02_code/10_analysis/TAB_build.py`) |

## products/hs6_product_list.csv

One row per HS 2007 six-digit code of the 31-code basket: `category` (`v_3706` cinematographic film, `v_49` printed matter, `v_8523` selected recording media, `v_97` works of art and antiques) and 0/1 membership of `baseline_30_excl_490700` (revised baseline), `narrow_A_22`, `narrow_B_24` (Narrow-A plus 852329 and 852380), `no_recorded_media_27` (the 30-code baseline without the three recorded-media codes), `artworks_9701_9703`, `publications_core_13` (Chapter 49 without 4907, 4908, 4911); `unesco_fcs2009_status` and `unesco_fcs2009_domain` from the benchmark. `unesco_fcs2009_benchmark.csv` covers every candidate code with its membership of the basket, FCS status (core, equipment, not listed) and domain, and notes.

## concordance/reported_HS_to_H3_concordance.csv

One row per reported HS edition (`source_version` H0–H5) and source code: the HS 2007 codes it touches according to the official correlation tables, which of them are target codes, and `mapping_status`:

- `SAFE_CATEGORY_MAPPING` (211 rows): every HS 2007 code the source code touches is a target code of one category, so its value is assigned to that category (and its canonical code) without any split. Several source codes can map to the same HS 2007 code (many-to-one); their values are summed.
- `AMBIGUOUS_PARTIAL_MAPPING` (8 rows: 852390 in H0, H1, H2; 852490 in H0; 852491 and 852499 in H1 and H2): the source code also touches non-target HS 2007 codes (852321, 852351, 852359), so its value cannot be allocated. These rows form the ambiguous recorded-media pool (`pipeline_treatment` `AMBIGUOUS_POOL_v_8523`): excluded from the lower-bound basket (LB, used for every reported estimate) and added in the upper-bound basket (UB, Table A2).

No value is split across categories, so there is no double counting; the build checks that the 31 code values add up to the basket total and the four category totals (`01_prep.do` part C, `product_controls.csv`).

## flags/

- `sample_flags_corrected2x.csv.gz`: rows `year`, `iso3_o` (exporter), `iso3_d` (importer) with any estimation-sample or quarantine flag; 0/1 columns `s_base_vis`, `s_base_tour` (Table 3), `s_dyn_*` (Table 4), `s_lang_*`, `s_cd_*` (Table 6), `s_cs_candidate`, `s_cs_exact` (common support), the quarantine flags `pry_res_quarantine_*`, `pak_res_quarantine_*`, `blr_lie_quarantine_*` (`_rev` = arrivals in the exporter from the importer, `_same` = arrivals in the importer from the exporter), and `fully_reported`, `pos_every_year`. Row sums: `s_base_vis` 20,598; `s_base_tour` 26,339.
- `C09_zero_fill_no_rows.csv`: the 36 importer-years requested from the API with zero archived basket rows (read by `A1_02_measurement.do` and `C2_A1_07_sweep2.do`).
- `sweep2_*.csv`: results of the data-quality screens: screen, keys, verdict and treatment (values and ratios removed). The flags used by the estimates are written out in `02_code/10_analysis/C2_A1_07_sweep2.do`.

## hofstede/

`hofstede_official_ctr_iso3_map.csv` maps the official file's country codes (`ctr`) to ISO-3 (taken from the build's workbook); `hofstede_official_unmapped_rows.csv` lists the seven official rows without an ISO-3 economy (language groups within a country and historical or population subgroups); `hofstede_regional_proxy_construction.csv` lists the 50 economies whose scores in the build's workbook come from an official regional row (36 rows added, 14 rows with missing scores filled; regional rows Arab countries 20, Africa East 16, Africa West 14), with the dimensions concerned. Country labels follow the workbook except TWN, which carries the UN designation "Taiwan Province of China". `hofstede_package_workbook_layout.csv` describes the first sheet of the build's workbook row by row (141 rows, 10 columns): each cell is `O` (the official cell of the row's code `official_ctr`), `R:<ctr>` (the official cell of a regional row), `T:` text (codes, country names, headers), `N:` an ISO numeric code, `B:` empty or `E:` an error code; no score is stored. `tools/rebuild_hofstede_inputs.py` rebuilds the sheet from the official file with it when the workbook is absent.
