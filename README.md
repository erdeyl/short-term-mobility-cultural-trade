# Replication package: Bilateral Human Mobility and Cultural-Goods Trade

Revised manuscript: "Bilateral Human Mobility and Cultural-Goods Trade: Evidence from a Three-Way Fixed-Effects Gravity Panel, 2007–2021", submitted to *Economies* (MDPI).

Authors: Tianji Gao, Sándor Kovács and László Erdey.

This package rebuilds the tables and figures of the revised manuscript and of its Supplementary Materials from the raw source files: the UN Comtrade and CEPII common base, the UN Tourism mobility series, the master panel and the analysis inputs, the analysis sample, every estimate, and the formatted tables and Figures 1 and 2. One command (`python run_all.py`) runs this chain for the final data version. The entries that read the earlier data versions (Supplementary Table S11.1 and the corresponding entries of Tables 5 and 7) need `python run_all.py --reconciliation` and, for the submitted version, a second copy of the package built with the correction rules off (Section 3); the data screens of `02_code/11_data_screens/` are not part of the chain (Section 8). All paths are relative to the package folder, so the folder can be placed anywhere, including paths that contain spaces.

> **Validation.** One full run in a clean room (new folder with spaces in its path, raw files copied, new Python environment from `requirements.txt`, one call of `python run_all.py`), followed in the same clean room by separate runs of the steps changed or added after it, reproduced all 68 compared result files of the revision: the table files, the data of Figures 1 and 2, the estimate files (including the stacked tests with unordered-pair clusters) and the additional tables. It passed all 56 Figure 1 controls, all 296 controls of the lead-power step and the checks of the unordered-pair step, and an exhibit-level ledger traces the source-key entries of all 43 exhibits of the revised numbering (Section 3) to these files. The run computes the final data version only; the reconciliation with earlier data versions (Supplementary Table S11.1) and the data screens of `02_code/11_data_screens/` were not part of it. `run_all.py` was also checked from a folder without spaces in its path (check stage and one analysis step). Details and run times in `VALIDATION.md`.

## 1. Quick start

1. Install Stata 18 or newer (tested: StataNow 19.5 MP) and Python 3.10 or newer (tested: 3.13.2).
2. Create a Python environment and install the pinned modules:
   `python3 -m venv .venv`, activate it, then `python -m pip install -r requirements.txt`.
3. Place the raw files in `01_raw/` as described in `01_raw/README.md` (Section 4). Three small files are included; the others must be obtained from their providers.
4. Install the Stata packages once (network): `python run_all.py --install-stata-packages --stages check`.
5. Run everything: `python run_all.py`.

`python run_all.py --dry-run` prints every command without running it. `python run_all.py --stages check` checks Python, Stata, the Stata packages and the raw files only. The launcher uses only the Python standard library and also runs as `python -I run_all.py`.

Stata is found from `--stata PATH`, the environment variable `STATA_EXE`, the `PATH`, or the standard install folders (`/Applications/Stata*` and `/Applications/StataNow` on macOS; `/usr/local/stata*` and `/opt/stata*` on Linux; `%ProgramFiles%\Stata*` and `%ProgramFiles%\StataNow*` on Windows). Batch mode uses `-b -q` on macOS and Linux and `/e /q` on Windows. Every Stata do-file receives the package root as an argument.

## 2. Structure

| Folder | Content |
|---|---|
| `run_all.py` | single entry point (stages check, build, analysis, results) |
| `requirements.txt` | pinned Python modules (with hashes) |
| `install/` | `install_stata_packages.do` (network), `check_stata_packages.do` (exact tested versions) |
| `01_raw/` | raw inputs (Section 4), `RAW_MANIFEST.sha256` (SHA-256 of every raw file that the default run uses), one `README.md` per source |
| `02_code/00_acquisition/` | UN Comtrade API acquisition scripts for the importer-reported files (needs an API key; not run by `run_all.py`) |
| `02_code/00_common/` | common base: UN Comtrade importer-reported cultural trade, HS concordance, CEPII Gravity variables |
| `02_code/03_Mobility/` | Mobility data build (UN Tourism, Hofstede, master panel, analysis inputs, exporter-reported mirror) and the original estimation do-files |
| `02_code/99_rescue/` | correction switch (`rescue_switch.py`, Stata `rescue_on`), correction modules, `nflow` 1.0.1 (sample-size log), Stata launcher shim |
| `02_code/10_analysis/` | analysis of the revision: data preparation, positive controls, all estimates, tables, figure |
| `02_code/11_data_screens/` | screening scripts behind the data-quality flag lists (not run by `run_all.py`; Section 8) |
| `derived/` | shared derived files: product list, concordance, sample flags (keys only), World Bank mapping, Hofstede construction tables, table layout (Section 5) |
| `tools/` | `verify_raw_inputs.py` (raw files against the manifest), `scan_portability.py` (no absolute path in any file), `compare_outputs.py` (cell-wise comparison of produced and reference tables), `make_release.py` (anonymized copy for double-anonymized review and its check) |
| created by the run | `03_intermediate/`, `04_analysis data/`, `05_output/` (logs, estimates), `06_results/` (tables, figures) |

## 3. Run order and outputs

`python run_all.py` runs four stages; each step is logged with its wall-clock time in `05_output/_run/run_times.csv`, and the launcher log is `05_output/_run/run_all.log`.

| Stage | What runs | Main outputs |
|---|---|---|
| check | Python modules; Stata executable; `install/check_stata_packages.do`; `tools/verify_raw_inputs.py` | `05_output/_run/check_stata_packages.log`; the run stops with a list if a raw file is missing or changed |
| build | `02_code/00_common/run_common.py`; `02_code/03_Mobility/run_chapter.py all` with the correction rules on (Section 6) | `03_intermediate/00_common/cultural_trade_gravity_base_2007_2021.dta`; `03_intermediate/03_Mobility/master/mobility_merged_2007_2021.dta`; `04_analysis data/03_Mobility/mobility_analysis_2007_2021.dta`; `03_intermediate/03_Mobility/sensitivity/04_mirror_trade/mirror_analysis_ready.dta`; the original Mobility estimation outputs in `05_output/03_Mobility/` (reference values for the positive controls) |
| analysis | `02_code/10_analysis`: `A1_names.py`, `A2_00a_hofstede_sheets.py`, `A2_00_hofstede.py`; then, for the revised baseline (vintage `corrected2x`): `01_prep`, `C2_01_mirror_ex4907.py`, `02_positive_controls`, `A1_01_flow_coverage`, `A1_02_measurement`, `C2_A1_07_sweep2`, `A1_04_directional`, `A1_05_did`, `A2_01_build`, `A2_1` … `A2_7`, `A2_7b`, `C2_A2_7c_narrowA`, `A2_99_combine`, `C2_04_compN`, `FIG_03_cd_slopes`, `FIG_01_new_checks`, `TAB_01`, `TAB_02`, `C2_02_bias`, `A1_03_time`, `C2_A1_11_leadpower_mu`, `C2_A1_11b_common_sample`, `C2_03_extras`, `C2_A1_10_boot` (three calls), `C2_A1_08_overlap`, `C2_A1_09_natfirst`, and the eight unordered-pair copies `UP_A2_5`, `UP_A2_6`, `UP_A2_7`, `UP_A2_7b`, `UP_C2_A2_7c_narrowA`, `UP_A1_02_measurement`, `UP_C2_A1_08_overlap`, `UP_C2_A1_09_natfirst` (below) | `05_output/10_analysis/corrected2x/`: `prepared.dta`, `positive_controls.csv`, `results/A1.csv`, `results/A2.csv`, `results/A2_7c.csv`, `TAB_results.csv`, `tables/`, `logs/`, sample-size flow logs (`*nflow*.csv`); `05_output/10_analysis/corrected2x_upair/` (the same stacked tests with unordered-pair clusters) |
| results | `A1_combine.py`, `C2_A1_12_make_upair.py --check`, `C2_A1_12_upair_table.py`, `C2_A1_13_sample_overlap.py`, `C2_post.py`, `C2_A1_11_check.py`, `C2_TAB_build.py`, `C2_supplement.py`, `FIG_02_coefplot.py`, `FIG_03_cd_slopes.py`, `C2_05_panel_tables.py` | `05_output/10_analysis/corrected2x/tables/`: `clustering_pvalues_extra.csv`, `S5_2_unordered_pair_tests.csv`, `benchmark_basket_family.csv`, `S5_3_benchmark_family.csv`, `sample_overlap.csv`; `06_results/tables/final/Table1.csv` … `Table7.csv`, `TableA1.csv` … `TableA5.csv`; `06_results/tables/final/supplement/TableS_sample_economies.{csv,md}`, `TableS_sample_economies_wide.csv`; `06_results/figures/Figure_coefplot.{pdf,png,tif}` and `Figure_coefplot_data.csv`; Figure 1: `06_results/figures/Figure_cd_slopes.{pdf,png,tif}` and `Figure_cd_slopes_data.csv` |

Vintages. `corrected2x` is the revised baseline (correction rules on, the Pakistan and Belarus–Liechtenstein quarantines, the 30-code basket). The default run computes it only. The reconciliation switch `python run_all.py --reconciliation` also runs `corrected` (correction rules on, 31-code basket) and `corrected2` (plus the two quarantines, 31 codes), the controls between vintages and the vintage comparison (`06_results/reconciliation/`, `06_results/tables/RECONCILIATION.csv`). The vintage `submitted` (the data as originally submitted) needs a second copy of this package built with the correction rules off (`python run_all.py --corrections none --stages check,build` in that copy) and the stored outputs of the first-submission replication package; set `PKG_SUBMITTED_ROOT` (the second copy) and `PKG_SUBMITTED_PUBLISHED` (the first-submission package) before `--reconciliation`. The reconciliation path is implemented but was not part of the clean-room validation. In `RECONCILIATION.csv` the difference columns (`difference_corrected_minus_submitted` and the later ones) are filled for coefficients, standard errors and observation counts alike wherever both values exist; for an N row the difference is the integer change in the count.

Unordered-pair clusters. `C2_A1_12_make_upair.py` generates `UP_A2_5.do`, `UP_A2_6.do`, `UP_A2_7.do`, `UP_A2_7b.do`, `UP_C2_A2_7c_narrowA.do`, `UP_A1_02_measurement.do`, `UP_C2_A1_08_overlap.do` and `UP_C2_A1_09_natfirst.do` from the producers of the stacked tests of Tables 6, 7 and 8 (Panel A) and Supplementary Table S3.3, and `C2_A2_7c_narrowA.do` (the benchmark comparison of Table 7 for Narrow-A) from `A2_7b.do`. Each copy differs from its source only in the cluster variable (`unordered_pair_id` instead of `pair_id`, which puts both trade directions of a pair of economies in one cluster), in its output folder (`05_output/10_analysis/corrected2x_upair/`) and in reading its two inputs from `05_output/10_analysis/corrected2x/`. The results stage checks that the copies on disk equal a regeneration from their sources (`C2_A1_12_make_upair.py --check`, exit 1 otherwise); `C2_A1_12_upair_table.py` pairs every unordered-pair test with its directed-pair counterpart, stops unless both have the same N, the same estimate and the same degrees of freedom, and writes the tables of Supplementary Section S5 (`S5_2_unordered_pair_tests.csv`; `S5_3_benchmark_family.csv` with Holm-adjusted p values within the four basket-minus-benchmark differences).

### Exhibits of the revised manuscript → scripts → output files

Revised numbering: manuscript Tables 1–8 and Figures 1–2, Appendix Tables A1–A5, and Supplementary Tables S2.1–S11.1 of the Supplementary Materials, with the long tables in Supplementary File S2 (43 exhibits; the supplement has no figures). Each row lists the scripts that write the numbers shown in the exhibit and the files that hold them. Paths without a folder prefix are under `05_output/10_analysis/corrected2x/`. The rows of `results/A1.csv` and `results/A2.csv` are written by the scripts named and assembled by `A1_combine.py` and `A2_99_combine.do`. "(reconciliation run)" marks files written only by `python run_all.py --reconciliation` (Section 3, Vintages). A few numbers in the exhibits are documented facts (data checks, provider documentation); `VALIDATION.md` counts them per exhibit.

| Exhibit | Scripts (`02_code/10_analysis`) | Output files |
|---|---|---|
| Table 1 | `C2_TAB_build.py`, `TAB_01.do` | `06_results/tables/final/Table1.csv` |
| Table 2 | `A1_01_flow_coverage.do` | `tables/A1_A1.1_flow.csv`; `tables/A1_A1.2_summary.csv` |
| Table 3 | `A1_01_flow_coverage.do`, `A2_1.do`, `C2_04_compN.do` | `results/A1.csv`; `results/A2.csv`; `tables/A2_A2.1e_composition_N.csv` |
| Table 4 | `A1_03_time.do` | `results/A1.csv`; `tables/A1_A1.6_window_shares.csv` |
| Table 5 | `A2_3.do`, `C2_TAB_build.py --reconciliation` | `results/A2.csv`; `06_results/tables/RECONCILIATION.csv` (reconciliation run) |
| Table 6 | `02_positive_controls.do` (runs the original `07_table5_moderators.do`), `A2_5.do` | `pc/diag/moderator-influence-results.csv`; `results/A2.csv` |
| Table 7 | `A1_01_flow_coverage.do`, `A2_6.do`, `A2_7.do`, `A2_7b.do`, `C2_A1_12_upair_table.py`, `C2_A2_7c_narrowA.do`, `UP_*.do` | `05_output/10_analysis/corrected2/results/A1.csv` (reconciliation run); `results/A2.csv`; `results/A2_7c.csv`; `tables/A2_A2.6.csv`; `tables/benchmark_basket_family.csv` |
| Table 8 | `A1_01_flow_coverage.do`, `A1_02_measurement.do`, `A1_04_directional.do`, `A2_3.do`, `C2_A1_07_sweep2.do` | `results/A1.csv`; `results/A2.csv` |
| Figure 1 | `FIG_03_cd_slopes.do`, `FIG_03_cd_slopes.py` | `06_results/figures/Figure_cd_slopes.{pdf,png,tif}`; `06_results/figures/Figure_cd_slopes_data.csv` |
| Figure 2 | `FIG_01_new_checks.do`, `FIG_02_coefplot.py` | `06_results/figures/Figure_coefplot.{pdf,png,tif}`; `06_results/figures/Figure_coefplot_data.csv` |
| Table A1 | `A2_4.do`, `C2_TAB_build.py` | `results/A2.csv`; `06_results/tables/final/TableA1.csv` |
| Table A2 | `A1_01_flow_coverage.do`, `A2_3.do`, `C2_TAB_build.py` | `results/A1.csv`; `results/A2.csv`; `06_results/tables/final/TableA2.csv` |
| Table A3 | `C2_02_bias.do` (runs the original `03_ppml_bias_correction.do`) | `C2_bias_results.csv` |
| Table A4 | `A2_3.do` | `results/A2.csv` |
| Table A5 | `A2_4.do`, `A2_6.do`, `C2_05_panel_tables.py`, `TAB_01.do` | `TAB_results.csv`; `results/A2.csv`; `tables/A2_A2.6_recmedia_exact_N.csv` |
| Supplementary Table S2.1 | `A1_01_flow_coverage.do` | `tables/A1_A1.1_flow.csv` |
| Supplementary Table S2.2 | `A1_01_flow_coverage.do` | `tables/A1_A1.1_condition_counts.csv` |
| Supplementary Table S2.3 | `A1_01_flow_coverage.do` | `tables/A1_A1.2_summary.csv` |
| Supplementary Table S2.4 | `A1_01_flow_coverage.do` | `tables/A1_A1.2_by_year.csv` |
| Supplementary Table S2.5 | `A1_01_flow_coverage.do` | `tables/A1_A1.2_composition.csv` |
| Supplementary Table S2.6 | `A1_01_flow_coverage.do` | `tables/A1_A1.2_economy_lists.csv` |
| Supplementary Table S2.7 | `C2_supplement.py` | `06_results/tables/final/supplement/TableS_sample_economies.md` |
| Supplementary Table S3.1 | `A1_02_measurement.do` | `tables/A1_A1.3_basis_shares.csv` |
| Supplementary Table S3.2 | `A1_02_measurement.do` | `tables/A1_A1.3_switches.csv` |
| Supplementary Table S3.3 | `A1_01_flow_coverage.do`, `C2_A1_08_overlap.do`, `C2_A1_09_natfirst.do` | `results/A1.csv`; `tables/A1_A1.5_m_natfirst.csv`; `tables/A1_A1.5_m_overlap.csv` |
| Supplementary Table S4.1 |  | `derived/products/unesco_fcs2009_benchmark.csv` (input table) |
| Supplementary Table S4.2 | `C2_05_panel_tables.py` | `tables/hs_concordance_print.csv` |
| Supplementary Table S4.3 | `C2_05_panel_tables.py` | `tables/hs_concordance_print_editions.csv` |
| Supplementary Table S5.1 | `C2_05_panel_tables.py` | `tables/clustering_pvalues.csv` |
| Supplementary Table S5.2 | `C2_A1_12_upair_table.py`, `UP_*.do` | `tables/S5_2_unordered_pair_tests.csv`; `tables/clustering_pvalues_extra_summary.csv` |
| Supplementary Table S5.3 | `C2_A1_12_upair_table.py`, `UP_*.do` | `tables/S5_3_benchmark_family.csv` |
| Supplementary Table S6.1 | `A2_1.do` | `tables/A2_A2.1.csv` |
| Supplementary Table S6.2 | `A1_01_flow_coverage.do`, `A2_1.do` | `results/A1.csv`; `results/A2.csv` |
| Supplementary Table S6.3 | `A1_04_directional.do`, `A2_1.do` | `results/A1.csv`; `results/A2.csv` |
| Supplementary Table S7.1 | `A2_2.do` | `results/A2.csv` |
| Supplementary Table S7.2 | `A1_01_flow_coverage.do`, `A2_4.do` | `results/A1.csv`; `results/A2.csv` |
| Supplementary Table S8.1 | `A2_5.do` | `tables/A2_A2.5.csv` |
| Supplementary Table S8.2 | `A2_5.do`, `FIG_03_cd_slopes.do` | `FIG_cd_slopes_bins.csv`; `results/A2.csv` |
| Supplementary Table S9.1 | `A1_01_flow_coverage.do`, `A1_03_time.do` | `results/A1.csv`; `tables/A1_A1.6_window_shares.csv` |
| Supplementary Table S9.2 | `A1_03_time.do` | `results/A1.csv` |
| Supplementary Table S9.3 | `A1_03_time.do`, `C2_A1_11_leadpower_mu.do` | `tables/A1_A1.7_lead_power.csv`; `tables/A1_A1.7_lead_power_mu.csv` |
| Supplementary Table S10.1 | `FIG_01_new_checks.do`, `FIG_02_coefplot.py` | `06_results/figures/Figure_coefplot.{pdf,png,tif}`; `06_results/figures/Figure_coefplot_data.csv` |
| Supplementary Table S11.1 | `C2_TAB_build.py --reconciliation` | `06_results/tables/RECONCILIATION.csv` (reconciliation run) |

### Package table files (`06_results/tables/final/`) → revised exhibits

The CSV table files keep the layout of the submitted tables (`derived/table_templates/`); their numbers are those of the revised exhibits shown here. Revised Tables 2 and 7 and Panels C–D of Table 8 have no table file of their own; their numbers are read from the result files listed above.

| Package file | Revised exhibit | Producer (02_code/10_analysis unless stated) | Stored result read by `C2_TAB_build.py` |
|---|---|---|---|
| `Table1.csv` | Table 1 | `TAB_01.do` (summary statistics on the full panel) | `TAB_table1.csv`, `TAB_01_corrected2x.log` |
| `Table2.csv`, `Table3.csv`, `Table4.csv`, `Table6.csv`, `TableA1.csv` | `Table2.csv`: Table 3; `Table3.csv`: Table 4, Panel A; `Table4.csv`: Table 5, Panel A; `Table6.csv`: Table 4, Panel C (columns 5–6), Figure 2 and Supplementary Table S10.1 (other columns); `TableA1.csv`: Table A1 | `02_positive_controls.do` runs the original do-files `02_code/03_Mobility/02_empirical_analysis/01_core/04`–`09` unmodified on `prepared.dta` | `pc/tables/*.csv`, `positive_controls.csv` |
| `Table5.csv` | Table 6, Panel A | the same (columns 1–4); columns 3–4 main coefficients centred on each model's realized sample: `A2_5.do` | `pc/tables/table5_moderators.csv`, `results/A2.csv` (item A2.5) |
| `Table7.csv` | Panel A: Table 3; Panel B: Table 8, Panel B, and Figure 2; Panel C: Table 8, Panel A; Panels D–E: Table 5, Panels B–C; Panel F: Table 4, Panels A–B | Panels A–C: `TAB_01.do` (new cells), `A1_02_measurement.do` and `C2_A1_07_sweep2.do` (Panel B clean-measurement row); Panels D–E: `A2_3.do`; Panel F (directed-pair trends, `separation(fe simplex ir mu)`): `A1_03_time.do` | `TAB_results.csv`, `results/A1.csv` (A1.1, A1.5, A1.8), `results/A2.csv` (A2.3) |
| `TableA2.csv` | Table A2 | exact common support: `02_positive_controls.do` (original `01_common_support_visitors_tourists.do`); upper-bound basket: `TAB_02.do` | `positive_controls.csv`, `TAB_02_corrected2x.log` |
| `TableA3.csv` | Table A3 | `C2_02_bias.do` runs the original `03_ppml_bias_correction.do` (Weidner–Zylkin) | `C2_bias_results.csv` |
| `TableA4.csv` | Table A4 | `A2_3.do` (reporting-side comparison with the 30-code exporter-reported mirror built by `C2_01_mirror_ex4907.py`) | `results/A2.csv` (A2.3) |
| `TableA5.csv` | Table A5 | `TAB_01.do`, `A2_4.do`, `A2_6.do` | `TAB_results.csv`, `results/A2.csv` (A2.4, A2.6) |
| `supplement/TableS_sample_economies.{csv,md}`, `TableS_sample_economies_wide.csv` | Supplementary Table S2.7 | `C2_supplement.py` (estimation-sample flags of `prepared.dta`) | `06_results/tables/final/supplement/` |
| `06_results/figures/Figure_cd_slopes.*` | Figure 1 (mobility slopes over cultural distance) | `FIG_03_cd_slopes.do` (same fits as `A2_5.do`; slope and 95% interval on a grid; positive control against the A2.5 slopes), `FIG_03_cd_slopes.py` (drawing) | `FIG_cd_slopes_grid.csv`, `FIG_cd_slopes_bins.csv`, `FIG_cd_slopes_controls.csv` |
| `06_results/figures/Figure_coefplot.*` | Figure 2 (coefficient plot) and Supplementary Table S10.1 | `FIG_01_new_checks.do` (unordered-pair clustering; top 0.1% trimming), `FIG_02_coefplot.py` (assembly and drawing) | `results/A1.csv`, `results/A2.csv`, `FIG_new_checks.csv`, `C2_bias_results.csv`, `TAB_02_corrected2x.log` |

Every cell of the CSV tables carries its source (file and row) in the column `source`; `out/<vintage>/…` there means `05_output/10_analysis/<vintage>/…`.

### Reviewer requests → outputs

Request ids are those of the response letter (Reviewer 1: R1-…; Reviewer 2: R2-…).

| Request ids | Analysis item and script | Where the numbers are |
|---|---|---|
| R1-1.1, R1-1.2 | A1.1 sample flow: `A1_01_flow_coverage.do`; `nflow` logs | `results/A1.csv` (A1.1); `tables/A1_A1.1_*`; `*nflow*.csv` |
| R1-1.3–R1-1.9, R2-4a, R2-6a, R2-6b | A1.2 coverage: `A1_01_flow_coverage.do`; economies and years per sample: `C2_supplement.py`; World Bank groups: `01_prep.do` part E | `results/A1.csv` (A1.2); `06_results/tables/final/supplement/`; `derived/worldbank/` |
| R1-2.1–R1-2.5 | series, units, selection rules: build code `02_code/03_Mobility/01_database_preparation/01_UN_Tourism/01_build_UN_Tourism.do`; `01_raw/05_Mobility/README.md` | logs of the build |
| R1-2.6–R1-2.10 | A1.3 measurement audit: `A1_02_measurement.do` | `results/A1.csv` (A1.3) |
| R1-2.11, R2-9c, R2-9d | A1.4 unit-break screen for all reporters: `A1_02_measurement.do`; quarantine rules (Section 6); SWEEP2 flags: `C2_A1_07_sweep2.do` | `results/A1.csv` (A1.4, A1.5); `derived/flags/` |
| R1-2.12, R2-9a, R2-9b | A1.5 measurement versus composition: restricted samples against their complements, `A1_02_measurement.do`; fixed-observation comparisons, `C2_A1_08_overlap.do`, `C2_A1_09_natfirst.do`; data-check exclusions, `C2_A1_07_sweep2.do` | `results/A1.csv` (A1.5); Table 8, Panels A and B; Supplementary Table S3.3 |
| R1-3.1–R1-3.10, R2-13 | A2.1 bilateral versus directional: `A2_1.do` | `results/A2.csv` (A2.1); Table 3; Supplementary Tables S6.1–S6.3 |
| R1-4.1–R1-4.8, R2-5a, R2-5b | A2.5 interactions on identical observations, slopes across the moderator range, official-only Hofstede and CEPII language measures: `A2_5.do`, `A2_00a_hofstede_sheets.py`, `A2_00_hofstede.py`, `A2_01_build.do` | `results/A2.csv` (A2.5); Table 6; Figure 1; `derived/hofstede/` |
| R1-5.1–R1-5.6, R2-11 | A2.3 stacked equality tests, directed and unordered pairs, Holm adjustment: `A2_3.do`; directional test: `A1_04_directional.do`; the stacked tests of Tables 6, 7 and 8 (Panel A) and Supplementary Table S3.3 with unordered-pair clusters: `UP_*.do`, `C2_A1_12_upair_table.py` | `results/A2.csv` (A2.3); `results/A1.csv` (A1.9); `tables/clustering_pvalues.csv`, `tables/clustering_pvalues_extra.csv`, `tables/S5_2_unordered_pair_tests.csv`; Supplementary Tables S5.1 and S5.2 |
| R1-5.7–R1-5.11, R2-15 | A2.4 scales, LPM effects, "fully reported" and "positive in every year" samples: `A2_4.do`, `01_prep.do` part C3 | `results/A2.csv` (A2.4); Tables A1, A5 |
| R1-5.12, R2-8 | this package; sample flags, concordance, harmonization code | `derived/`; `02_code/` |
| R1-6.1–R1-6.10, R2-7a, R2-7b | A2.6 product baskets (31 codes, 30 codes, Narrow-A/B, no recorded media), UNESCO FCS 2009 benchmark, LB/UB: `A2_6.do`, `01_prep.do` part C, `TAB_02.do`; benchmark comparison for Narrow-A: `C2_A2_7c_narrowA.do` | `results/A2.csv` (A2.6); `results/A2_7c.csv`; Tables 7, A2, A5; Supplementary Table S4.1; `derived/products/`, `derived/concordance/` |
| R1-7.1, R1-7.2 | common support and dynamic model: original do-files via `02_positive_controls.do` | Table 4, Panel A; Table 8, Panel C; Table A2 |
| R1-7.3, R1-7.4, R2-3a, R2-3b, R2-12a–R2-12c, R2-16 | A1.6 time windows and directed-pair trends, A1.7 static baseline on the dynamic sample, A1.8 lead intervals: `A1_03_time.do`; lead-test power on the `separation(fe simplex ir mu)` fits: `C2_A1_11_leadpower_mu.do`; the dynamic pair-trend model refitted on the sample of its static reference (Supplementary Section S9.3): `C2_A1_11b_common_sample.do` | `results/A1.csv` (A1.6–A1.8); `tables/A1_A1.7_common_sample_check.csv`; Table 4 |
| R2-10 | A2.2 alternatives to the IHS: `A2_2.do` | `results/A2.csv` (A2.2) |
| R2-14 | coefficient plot: `FIG_01_new_checks.do`, `FIG_02_coefplot.py` | Figure 2; Supplementary Table S10.1; `06_results/figures/` |
| R2-17 | A1.9 directional result and the reporting side: `A1_04_directional.do`; Table A4: `A2_3.do` | `results/A1.csv` (A1.9); Table A4 |
| R2-18 | A2.7 non-cultural benchmark (CEPII `tradeflow_comtrade_d`), A2.7b with Narrow-B and without recorded media, A2.7c with Narrow-A: `A2_7.do`, `A2_7b.do`, `C2_A2_7c_narrowA.do`; Holm adjustment within the four basket-minus-benchmark differences: `C2_A1_12_upair_table.py` | `results/A2.csv` (A2.7, A2.7b); `results/A2_7c.csv`; `tables/benchmark_basket_family.csv`, `tables/S5_3_benchmark_family.csv`; Table 7, Panel A; Supplementary Table S5.3 |
| — (design check) | A1.10 difference-in-differences design characterization: `A1_05_did.do`, `C2_A1_10_boot.do` | `results/A1.csv` (A1.10) |
| R1-1.10, R1-7.5–R1-7.7, R1-m1, R1-m2, R2-1a, R2-1b, R2-2, R2-5c, R2-19 | text revisions; no computation | revised manuscript |
| R2-4b | economies in both the visitor and the tourist baseline sample: `C2_A1_13_sample_overlap.py` (from `tables/A1_A1.2_economy_lists.csv`) | `tables/sample_overlap.csv`; Section 1 and the abstract |

## 4. Data

Redistribution terms were checked on the providers' own pages; the governing sentences, URLs and access dates are in `LICENSES_AND_SOURCES.md`. Files that may be redistributed are included; for the others the package gives retrieval instructions and the SHA-256 of the exact files used (`01_raw/RAW_MANIFEST.sha256`; `python tools/verify_raw_inputs.py` checks a user's files, as does `shasum -a 256 -c 01_raw/RAW_MANIFEST.sha256` from the package root). The run stops with a list of missing files.

| Folder | Source | Files | Included? |
|---|---|---|---|
| `01_raw/01_Gravity` | CEPII Gravity database V202211 | `Gravity_V202211.dta`, `Countries_V202211.dta` | no (1.4 GB; license allows redistribution) |
| `01_raw/02_UN_Comtrade` | UN Comtrade API: importer-reported HS six-digit imports (330 files), exporter-reported mirror (338 files + 60 availability files + 2 manifests), data availability (15), reference files (3), download manifest | 749 files | no (UN Comtrade terms) |
| `01_raw/05_Mobility` | UN Tourism Tourism Statistics Database, inbound arrivals of tourists and of visitors by country of residence and by nationality, release of 23 December 2025 (344 workbooks); optional: the Hofstede workbook of the submitted paper (rebuilt from the official file when absent; Section 8) | 344 files + 1 optional | no (UN Tourism terms; Hofstede, Section 7) |
| `01_raw/06_WorldBank` | World Bank country classifications by income, current (FY27) and historical (FY89–FY27) | `CLASS.xlsx`, `OGHIST.xlsx` | yes (CC BY 4.0) |
| `01_raw/07_CEPII_Language` | CEPII Language database (Melitz and Toubal) | `ling_web.dta` | yes (Etalab Open Licence 2.0) |
| `01_raw/08_Hofstede_official` | official Hofstede six-dimension file, 2015-08-16 version | `6-dimensions-for-website-2015-08-16.xls` | no (redistribution not addressed by the provider) |

No row-level UN Tourism value is included anywhere in the package, and no derived file that carries such values. The shared derived files in `derived/` hold keys, codes and flags only.

## 5. Shared derived files (`derived/`)

| File | Content |
|---|---|
| `products/hs6_product_list.csv` | the 31 HS 2007 six-digit codes with their category and membership of each basket: 30-code revised baseline (without 490700), Narrow-A (22 codes), Narrow-B (24 codes), no recorded media (27 codes: the 30-code baseline without the three recorded-media codes), artworks 9701–9703, core publications (13 codes); UNESCO FCS 2009 status and domain |
| `products/unesco_fcs2009_benchmark.csv` | the UNESCO FCS 2009 benchmark of all candidate codes (codes, basket membership, FCS status and domain, notes; HS descriptions omitted) |
| `concordance/reported_HS_to_H3_concordance.csv` | reported HS version and code → HS 2007 code and category (219 rows: 211 `SAFE_CATEGORY_MAPPING`, 8 `AMBIGUOUS_PARTIAL_MAPPING`); rules in `derived/concordance/README.md` |
| `flags/sample_flags_corrected2x.csv.gz` | estimation-sample and quarantine flags by `year`, `iso3_o`, `iso3_d` (keys and 0/1 flags only) |
| `flags/C09_zero_fill_no_rows.csv` | the 36 importer-years with zero archived basket rows (flag C09) |
| `flags/sweep2_*.csv` | data-quality screen results (keys, screen, verdict and treatment) |
| `worldbank/wb_income_region_by_economy_year.csv` | World Bank region and income group by economy and year as used (FY(t+1) and FY(t) conventions) |
| `hofstede/*.csv` | official-only construction: Hofstede code → ISO3 map, unmapped rows, and the regional-proxy construction of the build's workbook (which regional row supplies which country; no scores) |
| `table_templates/submitted_manuscript_tables.md` | table blocks of the submitted manuscript: the layout the revised tables follow |

## 6. Data-correction rules

The build applies the correction rules of the corrected data through the switch `RESCUE_CORRECTIONS` (set by `run_all.py`; `02_code/99_rescue/rescue_switch.py`, Stata `rescue_on`). Values are never rescaled or imputed; a quarantined cell is set to missing with a flag, and the raw files are not changed.

| Id | Rule | Where |
|---|---|---|
| C02, C02-M | Trade records that UN Comtrade reports under code 490 ("Other Asia, not elsewhere specified"), which UNSD documents as covering Taiwan Province of China, had not been mapped to the harmonized partner list in the original submission; following the UNSD documentation, they are now included (reporter, partner and availability; importer- and exporter-reported files). Group reporters 97 and 975 are excluded. | `02_code/00_common/01_UN_Comtrade/config/special_area_crosswalk.csv`; `05_build_cultural_trade.py`; `02_code/00_common/03_base/base_core.py`; `02_code/99_rescue/I-M2/mirror_crosswalk.py` |
| C12 | Paraguay, residence-based tourist and visitor workbooks, 2020–2022: stored values in "thousand trips" are single trips (a factor of 1,000); every value is quarantined (missing, flag `pry_res_quarantine`), the nationality series is used where it exists. Evidence: the nationality series and the national tourist totals of INE/SENATUR. | `01_build_UN_Tourism.do` (block C12) |
| corrected2: Pakistan | Pakistan residence-based workbooks 2020–2021 (same unit error): quarantined by the same rule (flags `pak_res_quarantine_*`). | `02_code/10_analysis/01_prep.do`, section A0 |
| corrected2: Belarus–Liechtenstein | Belarus visitors by residence book Lithuania under Liechtenstein, 2020–2022 (2020–2021 inside the sample window): the cells are quarantined by the same rule (flags `blr_lie_quarantine_*`). | `01_prep.do`, section A0 |
| corrected2x: HS 490700 | The revised baseline outcome is the 30-code basket: HS 490700 (unused stamps, banknotes, cheque forms, securities and similar documents; it includes banknotes recorded at face value) is excluded from the basket on both trade sides; the 31-code basket is kept for comparison. | `01_prep.do`, section C2x; `C2_01_mirror_ex4907.py` |
| C09, C09-M | Flags only: 36 importer-years with zero archived basket rows; France customs area 251 and the separate Monaco / French Guiana mobility areas. | `base_core.py`; `03_master/01_build_master_panel.py` |
| C11a | Code only: the historical validation assertions of `10_validation.do` are replaced by an old/new/difference report. | `02_code/99_rescue/I-M/validation_delta.do` |
| C11b, C11c | Flags only: tourists-only values inside visitor series; reporting basis, series hierarchy, source spans and regional-proxy provenance. | `01_build_UN_Tourism.do`; `02_code/99_rescue/I-M/source_flags.do`; `04_build_analysis_inputs.do` |
| C03 | Regional trade agreements: CEPII Gravity V202211 records `fta_wto` = 0 for the pairs of Romania with the other member states of the European Union in 2007–2017, although Romania joined the EU on 1 January 2007 (European Central Bank press release of 2 January 2007); these 582 directed pair-years are set to 1, and the old and new value of each are listed. `fta_wto` enters only the robustness check with an RTA/FTA control (the original `08_table6_robustness.do`, run by `02_positive_controls.do`; Figure 2 and Supplementary Table S10.1); the baseline and every other estimate do not use it. | `02_code/00_common/02_Gravity/config/rta_overrides.csv`; `02_code/99_rescue/ia_common.py` (`apply_rta_overrides`) |
| C01, C05, C10 | Common-base rules active in the corrected build: separate log for check runs (C01); discordance diagnostics only (C05); product-variant variables (`v_4907_k`, recorded-media variants) and label clarifications without baseline changes (C10). | `run_common.py`; `02_Gravity/01_audit_and_extract_gravity_v202211.py`; `05_build_cultural_trade.py` |

`run_all.py` lists the twelve ids queried by the package's build code (`C01,C02,C02-M,C03,C05,C09,C09-M,C10,C11a,C11b,C11c,C12`); this is equivalent to switching every correction on. `--corrections none` reproduces the data as originally submitted.

## 7. Software

| Item | Tested version | Install source |
|---|---|---|
| Stata | StataNow 19.5 MP (every do-file sets `version 18`) | — |
| ftools | 2.50.0 | GitHub sergiocorreia/ftools |
| reghdfe | 6.14.1 | GitHub sergiocorreia/reghdfe (master) |
| ppmlhdfe | 2.3.4 | GitHub sergiocorreia/ppmlhdfe (master) |
| ppml_fe_bias | SSC distribution 2021-03-06 | SSC |
| gtools | 1.10.1 | SSC |
| require | 1.3.1 | SSC |
| estout | 3.33 | SSC |
| hdfe, outreg (frmttable), rowmat_utils, moremata | distributions 2016-08-06, 2015-09-18, 2014-08-15, 2026-01-11 | SSC (used by the original estimation do-files) |
| did_multiplegt_dyn | SSC distribution 2026-06-29 | SSC |
| whichdidshouldiuse | 1.0.0 | SSC |
| did_had, distinct, nprobust (lprobust) | distributions 2024-08-24, 2012-03-21, 2026-05-17 | SSC; GitHub nppackages/nprobust |
| nflow | 1.0.1 | included (`02_code/99_rescue/ado`) |
| Python | 3.13.2; pandas 3.0.5, numpy 2.2.3, openpyxl 3.1.5, xlrd 2.0.2, matplotlib 3.11.2, requests 2.34.2 | `requirements.txt` |

SSC keeps only the current release of a package, so exact versions cannot be pinned at installation; `install/check_stata_packages.do` verifies the tested versions (version lines through `require`, otherwise the distribution date in `stata.trk`) and stops on a difference unless `PKG_ALLOW_VERSION_DIFF=1` is set. The same check runs in the stage `check`.

## 8. Known limitations and technical notes

- **did_multiplegt_dyn.** Variable-name abbreviation must be on around each call (`set varabbrev on`): the installed ado (lines 2010–2014) reads `getmata (scalars_XX*)` as `scalars_XX`, which fails with r(111) under `set varabbrev off`. When the placebo is not estimable, `placebo()` with `bootstrap()` stops with r(122) (ado lines 1976–1989); the analytic path either stops with r(111) or returns the named effect scalars without `e(b)`/`e(V)`, depending on the data, so it does not always stop. For visitors, the bootstrap stops with rc 301 "e(b) not found" when a resample draws too few of the three control observations; the command reports insufficient observations. Reported bootstrap rows omit placebo(); analytic effects are read from named e() scalars after a with-placebo call returns rc0, or from a no-placebo retry when that call stops. The command also saves and reloads a temporary file without quotes, so Stata's temporary folder must not contain a space; `run_all.py` sets `STATATMP` accordingly (or set `PKG_STATATMP`).
- **Stata `about` output.** `02_code/99_rescue/I-M/source_flags.do` records the Stata environment with `about`, which prints the licensee of the Stata copy into `05_output/03_Mobility/03_logs/batch_transcripts/01_build_UN_Tourism/01_build_UN_Tourism.log`; the anonymized copy of the package removes those lines (`tools/make_release.py`).
- **Stata data files** carry a time stamp, so rebuilt `.dta` files are not byte-identical to earlier builds; compare them with Stata's `datasignature`.
- **Figures.** The image files depend on the matplotlib version; the validation compares the figure data (`Figure_coefplot_data.csv`).
- **Hofstede inputs: only the public official file is needed.** The build and the analysis read the Hofstede workbook of the submitted paper (`01_raw/05_Mobility/6-dimensions-for-website-2015-08-16 (1).xls`): the official 2015-08-16 file with ISO-3 code columns, 36 countries added and 14 countries' missing scores filled from the official regional rows (Arab countries, Africa West, Africa East). That workbook is not public, and it is not needed: when it is absent, `run_all.py` rebuilds its first sheet from the official file with `tools/rebuild_hofstede_inputs.py` and two score-free tables, `derived/hofstede/hofstede_package_workbook_layout.csv` (for every cell of the sheet: the official cell it copies, the regional row it takes, or the text or ISO code it holds) and `hofstede_regional_proxy_construction.csv` (which economy takes which dimensions from which regional row; every regional cell is checked against it). The rebuilt sheet equals the workbook in all 1,410 cells (type and exact value), its text export is byte-identical to the one the analysis read, and a clean-room build and the Hofstede steps of the analysis without the workbook reproduced the Hofstede outputs: 24 of the 27 Hofstede-dependent files are byte-identical, the two analysis datasets have identical data and differ only in their file header (save time and padding bytes), and the source manifest differs because it names the source it read (`VALIDATION.md`). The official file is downloadable (Section 4, `01_raw/08_Hofstede_official/README.md`; neither file is redistributed, the provider's pages do not address redistribution), and `run_all.py` stops with the retrieval instructions if it is missing.
- **Platforms.** The clean-room validation runs on macOS (Apple silicon). The launcher, the Stata location, the quoting of paths with spaces and the shell calls of the analysis code (`pkg_py`, `pkg_fs.py`) are written for Windows and Linux as well but were not run there.
- **Data screens.** `02_code/11_data_screens/` contains the screening scripts behind the data-quality flags (`derived/flags/sweep2_*`); they read the UN Tourism bulk download (`01_raw/09_UN_Tourism_bulk/`, not in the manifest) and are not run by `run_all.py`. The flags used by the estimates are written out in `C2_A1_07_sweep2.do`.
- **Comments in the analysis code** refer to the authors' working notes and to internal checks; these documents are not part of the package and are not needed to run it.

## 9. Code provenance

- `02_code/00_common`, `02_code/03_Mobility` and the listed `02_code/99_rescue` files are the dissertation build code at the corrected state used for the reported results, limited to the common base and the Mobility chapter (the Windows `.bat` runners and the LB/UB appendix validation are omitted). Changes: the hard-coded Stata drive paths in `chapter_runtime.py` are replaced by the `ProgramFiles` environment variables, and two variable labels use the UN designation "Taiwan Province of China (TWN)"; `00_check_raw_inputs.py` and `02_Hofstede/00_extract_and_audit_hofstede_source.py` of the Mobility build accept the Hofstede sheet rebuilt from the official file when the workbook is absent (Section 8).
- `02_code/10_analysis` is the analysis code that produced the reported results. Changes for the package: all paths are built from the package root (`00_config.do`, the Python constants); POSIX shell one-liners are replaced by `pkg_fs.py` with the same effect (`rm -rf`, `mkdir -p`, `ln -s`, the SHA-256 table identity check, `cmp` against the original file's SHA-256, `cp` → Stata `copy`); Python is called through `pkg_py`; `02_positive_controls.do` reports instead of stopping when the vintages corrected2 and corrected2x differ from corrected (by design); `C2_TAB_build.py` writes the final tables only unless `--reconciliation` is given, and `C2_post.py` skips vintages that were not run; `A2_00_hofstede.py` takes its folders as arguments; `A2_00a_hofstede_sheets.py` (new) reproduces the two spreadsheet exports the analysis read, byte for byte (without the build's workbook it exports the official file only, and `tools/rebuild_hofstede_inputs.py` writes the second export).
- `C2_A2_7c_narrowA.do` and the eight `UP_*.do` files in `02_code/10_analysis` are generated by `C2_A1_12_make_upair.py` from the package's own sources (Section 3); `run_all.py` checks that they equal a regeneration.
- `02_code/00_acquisition/01_UN_Comtrade_importer` is the acquisition code of the first-submission package.

## 10. Run time

One full clean-room run on an Apple M5 Pro (18 logical CPUs, 48 GB RAM, macOS 27.2) with StataNow 19.5 MP and Python 3.13.2, wall clock:

| stage | minutes |
|---|---|
| check | 0.0 |
| build | 4.7 |
| analysis | 28.1 |
| results | 0.3 |
| total | 33.1 |

This full run used the code before its last two changes: the added step `C2_A1_11b_common_sample.do` (0.7 minutes in the same clean room, run with the results stage afterwards) and the quoting of every Stata argument in `run_all.py`, which leaves the command line unchanged in a folder with spaces (`VALIDATION.md`). A full run of the final code therefore takes about 33.8 minutes on this machine.

The longest steps are the bootstrap of `C2_A1_10_boot.do` for tourists (about 7 minutes) and `A1_03_time.do` (about 6 minutes, pair-trend models). Per-step times: `05_output/_run/run_times.csv`.

## 11. License and citation

Code: MIT License (`LICENSE`). Documentation and the derived key files in `derived/`: CC BY 4.0 (`LICENSE-CC-BY-4.0.md`). Data files keep their providers' terms (`LICENSES_AND_SOURCES.md`).

Please cite the article (reference to be added on publication) and the data sources listed in `LICENSES_AND_SOURCES.md`.
