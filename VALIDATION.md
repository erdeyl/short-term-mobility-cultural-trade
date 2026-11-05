# Validation of the replication package (clean-room run)

The package was copied to a new folder whose path contains no spaces (`<clean-room folder>/Replication_Package`), the raw files were copied into its `01_raw/` (no links; `tools/verify_raw_inputs.py`: 1,100 files, 0 missing, 0 changed), a new Python environment was created from `requirements.txt` (PyPI), and `python run_all.py` ran every stage (check, build, analysis, results). The outputs were then compared with the results reported in the revision (frozen 2026-11-05 01:41:52; SHA-256 manifest of 187 files), cell by cell: non-numeric text identical apart from the reworded free-text notes listed below, integers (N) identical, other numbers within a relative tolerance of 1e-6.

This is one full run of the final code: every step of the four stages ran in this clean room in one call of `run_all.py`, and no step was run separately.

Scope. The default run computes the final data version (`corrected2x`) only. The earlier data versions behind Supplementary Table S11.1 (reconciliation) need `python run_all.py --reconciliation` and, for the submitted version, a second copy of the package built with the correction rules off (`README.md`, Section 3); they were not part of this run, and the entries that read them are listed as not compared below. The data-screen scripts in `02_code/11_data_screens/` are not run by `run_all.py`: they read the UN Tourism bulk files, which are not in `01_raw/RAW_MANIFEST.sha256`, and they produced the flag lists `derived/flags/sweep2_*.csv` (`README.md`, Section 8); these lists were not recomputed here, while the flags the estimates use are written by `C2_A1_07_sweep2.do`, which the run includes.

Machine: Apple M5 Pro, 18 logical CPUs, 48 GB RAM, macOS-27.2-arm64-arm-64bit-Mach-O. Stata: 19.5 MP; Python 3.13.2.

Result: 68 of 68 files match; 0 differ (4 of the matching files differ in the wording of some free-text notes, 1 of them also in its line ends; every number is identical). Figure 1 controls: 56 of 56 checks PASS. Controls of `C2_A1_11_leadpower_mu.do` (`C2_A1_11_check.py`): 296 of 296 PASS.

## Run time (wall clock)

| stage | seconds | minutes |
|---|---|---|
| check | 2 | 0.0 |
| build | 272 | 4.5 |
| analysis | 1624 | 27.1 |
| results | 18 | 0.3 |
| total | 1916 | 31.9 |

Per step: `05_output/_run/run_times.csv`, which lists the 60 steps of this run (1 check, 2 build, 45 analysis and 12 results steps), each with status OK; their times add up to the 1916 seconds above.

## Comparison

The reference column names the files of the authors' frozen copy of the results that the comparison read; these files are outside the package. The package writes the corresponding files under 05_output/ (and the tables under 06_results/), which the result column compares with them.

| group | reference file (authors' frozen copy, outside the package) | in freeze manifest | result | cells | first difference |
|---|---|---|---|---|---|
| Tables | `tables_revised/final/Table1.csv` | yes | IDENTICAL (bytes) | 70 cells, 70 identical, 0 beyond tolerance |  |
| Tables | `tables_revised/final/Table2.csv` | yes | IDENTICAL (bytes) | 80 cells, 80 identical, 0 beyond tolerance |  |
| Tables | `tables_revised/final/Table3.csv` | yes | IDENTICAL (bytes) | 24 cells, 24 identical, 0 beyond tolerance |  |
| Tables | `tables_revised/final/Table4.csv` | yes | IDENTICAL (bytes) | 30 cells, 30 identical, 0 beyond tolerance |  |
| Tables | `tables_revised/final/Table5.csv` | yes | IDENTICAL (bytes) | 48 cells, 48 identical, 0 beyond tolerance |  |
| Tables | `tables_revised/final/Table6.csv` | yes | IDENTICAL (bytes) | 40 cells, 40 identical, 0 beyond tolerance |  |
| Tables | `tables_revised/final/Table7.csv` | yes | IDENTICAL (bytes) | 84 cells, 84 identical, 0 beyond tolerance |  |
| Tables | `tables_revised/final/TableA1.csv` | yes | IDENTICAL (bytes) | 16 cells, 16 identical, 0 beyond tolerance |  |
| Tables | `tables_revised/final/TableA2.csv` | yes | IDENTICAL (bytes) | 42 cells, 42 identical, 0 beyond tolerance |  |
| Tables | `tables_revised/final/TableA3.csv` | yes | IDENTICAL (bytes) | 24 cells, 24 identical, 0 beyond tolerance |  |
| Tables | `tables_revised/final/TableA4.csv` | yes | IDENTICAL (bytes) | 24 cells, 24 identical, 0 beyond tolerance |  |
| Tables | `tables_revised/final/TableA5.csv` | yes | IDENTICAL (bytes) | 48 cells, 48 identical, 0 beyond tolerance |  |
| Tables | `tables_revised/final/supplement/TableS_sample_economies.csv` | yes | IDENTICAL (bytes) | 12122 cells, 12122 identical, 0 beyond tolerance |  |
| Tables | `tables_revised/final/supplement/TableS_sample_economies_wide.csv` | yes | IDENTICAL (bytes) | 2856 cells, 2856 identical, 0 beyond tolerance |  |
| Figure data | `figures/Figure_coefplot_data.csv` | yes | IDENTICAL (bytes) | 590 cells, 590 identical, 0 beyond tolerance |  |
| Figure data | `figures/Figure_cd_slopes_data.csv` | yes | IDENTICAL (bytes) | 14705 cells, 14705 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A1.csv` | yes | IDENTICAL (cells) except the note text | 6308 cells, 6308 identical, 0 beyond tolerance (column note left out: the text of 7 notes is worded differently; see below) |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A1_parts/A1_01.csv` | yes | IDENTICAL (bytes) | 340 cells, 340 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A1_parts/A1_02.csv` | yes | IDENTICAL (bytes) | 1620 cells, 1620 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A1_parts/A1_03.csv` | yes | IDENTICAL (cells) except the note text | 1539 cells, 1539 identical, 0 beyond tolerance (column note left out: the text of 2 notes is worded differently; see below) |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A1_parts/A1_04.csv` | yes | IDENTICAL (bytes) | 1860 cells, 1860 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A1_parts/A1_05.csv` | yes | IDENTICAL (bytes) | 200 cells, 200 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A1_parts/A1_05b_tour_cont1boot.csv` | yes | IDENTICAL (bytes) | 40 cells, 40 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A1_parts/A1_05b_tour_cont1strictboot.csv` | yes | IDENTICAL (bytes) | 40 cells, 40 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A1_parts/A1_05b_vis_cont1boot.csv` | yes | IDENTICAL (cells) except the note text | 38 cells, 38 identical, 0 beyond tolerance (column note left out: the text of 1 notes is worded differently; see below) |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A1_parts/A1_07.csv` | yes | IDENTICAL (cells) except the note text | 133 cells, 133 identical, 0 beyond tolerance (column note left out: the text of 4 notes is worded differently; see below) |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A1_parts/A1_08.csv` | yes | IDENTICAL (bytes) | 400 cells, 400 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A1_parts/A1_09.csv` | yes | IDENTICAL (bytes) | 540 cells, 540 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A2.csv` | yes | IDENTICAL (bytes) | 16644 cells, 16644 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A2_1.csv` | yes | IDENTICAL (bytes) | 2793 cells, 2793 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A2_2.csv` | yes | IDENTICAL (bytes) | 475 cells, 475 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A2_3.csv` | yes | IDENTICAL (bytes) | 4123 cells, 4123 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A2_4.csv` | yes | IDENTICAL (bytes) | 703 cells, 703 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A2_5.csv` | yes | IDENTICAL (bytes) | 6916 cells, 6916 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A2_6.csv` | yes | IDENTICAL (bytes) | 703 cells, 703 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A2_7.csv` | yes | IDENTICAL (bytes) | 361 cells, 361 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A2_7b.csv` | yes | IDENTICAL (bytes) | 703 cells, 703 identical, 0 beyond tolerance |  |
| Estimates (corrected2x) | `analysis/out/corrected2x/results/A2_7c.csv` | yes | IDENTICAL (bytes) | 361 cells, 361 identical, 0 beyond tolerance |  |
| Additional tables (corrected2x) | `analysis/out/corrected2x/tables/A1_A1.7_common_sample_check.csv` | yes | IDENTICAL (bytes) | 84 cells, 84 identical, 0 beyond tolerance |  |
| Additional tables (corrected2x) | `analysis/out/corrected2x/tables/A1_A1.7_lead_power_mu.csv` | yes | IDENTICAL (bytes) | 340 cells, 340 identical, 0 beyond tolerance |  |
| Additional tables (corrected2x) | `analysis/out/corrected2x/tables/A2_A2.1e_composition_N.csv` | yes | IDENTICAL (bytes) | 135 cells, 135 identical, 0 beyond tolerance |  |
| Additional tables (corrected2x) | `analysis/out/corrected2x/tables/A2_A2.6_recmedia_exact_N.csv` | yes | IDENTICAL (bytes) | 95 cells, 95 identical, 0 beyond tolerance |  |
| Additional tables (corrected2x) | `analysis/out/corrected2x/tables/A2_A2.7c.csv` | yes | IDENTICAL (bytes) | 117 cells, 117 identical, 0 beyond tolerance |  |
| Additional tables (corrected2x) | `analysis/out/corrected2x/tables/S5_2_unordered_pair_tests.csv` | yes | IDENTICAL (bytes) | 1148 cells, 1148 identical, 0 beyond tolerance |  |
| Additional tables (corrected2x) | `analysis/out/corrected2x/tables/S5_3_benchmark_family.csv` | yes | IDENTICAL (bytes) | 187 cells, 187 identical, 0 beyond tolerance |  |
| Additional tables (corrected2x) | `analysis/out/corrected2x/tables/benchmark_basket_family.csv` | yes | IDENTICAL (bytes) | 221 cells, 221 identical, 0 beyond tolerance |  |
| Additional tables (corrected2x) | `analysis/out/corrected2x/tables/clustering_pvalues.csv` | yes | IDENTICAL (bytes) | 954 cells, 954 identical, 0 beyond tolerance |  |
| Additional tables (corrected2x) | `analysis/out/corrected2x/tables/clustering_pvalues_extra.csv` | yes | IDENTICAL (bytes) | 3608 cells, 3608 identical, 0 beyond tolerance |  |
| Additional tables (corrected2x) | `analysis/out/corrected2x/tables/clustering_pvalues_extra_summary.csv` | yes | IDENTICAL (bytes) | 16 cells, 16 identical, 0 beyond tolerance |  |
| Additional tables (corrected2x) | `analysis/out/corrected2x/tables/hs_concordance_print.csv` | yes | IDENTICAL (bytes) | 330 cells, 330 identical, 0 beyond tolerance |  |
| Additional tables (corrected2x) | `analysis/out/corrected2x/tables/hs_concordance_print_editions.csv` | yes | IDENTICAL (bytes) | 21 cells, 21 identical, 0 beyond tolerance |  |
| Additional tables (corrected2x) | `analysis/out/corrected2x/tables/sample_overlap.csv` | yes | IDENTICAL (bytes) | 14 cells, 14 identical, 0 beyond tolerance |  |
| Estimates with unordered-pair clusters (corrected2x_upair) | `analysis/out/corrected2x_upair/results/A1_parts/A1_02.csv` | yes | IDENTICAL (bytes) | 1620 cells, 1620 identical, 0 beyond tolerance |  |
| Estimates with unordered-pair clusters (corrected2x_upair) | `analysis/out/corrected2x_upair/results/A1_parts/A1_08.csv` | yes | IDENTICAL (bytes) | 400 cells, 400 identical, 0 beyond tolerance |  |
| Estimates with unordered-pair clusters (corrected2x_upair) | `analysis/out/corrected2x_upair/results/A1_parts/A1_09.csv` | yes | IDENTICAL (bytes) | 540 cells, 540 identical, 0 beyond tolerance |  |
| Estimates with unordered-pair clusters (corrected2x_upair) | `analysis/out/corrected2x_upair/results/A2_5.csv` | yes | IDENTICAL (bytes) | 6916 cells, 6916 identical, 0 beyond tolerance |  |
| Estimates with unordered-pair clusters (corrected2x_upair) | `analysis/out/corrected2x_upair/results/A2_6.csv` | yes | IDENTICAL (bytes) | 703 cells, 703 identical, 0 beyond tolerance |  |
| Estimates with unordered-pair clusters (corrected2x_upair) | `analysis/out/corrected2x_upair/results/A2_7.csv` | yes | IDENTICAL (bytes) | 361 cells, 361 identical, 0 beyond tolerance |  |
| Estimates with unordered-pair clusters (corrected2x_upair) | `analysis/out/corrected2x_upair/results/A2_7b.csv` | yes | IDENTICAL (bytes) | 703 cells, 703 identical, 0 beyond tolerance |  |
| Estimates with unordered-pair clusters (corrected2x_upair) | `analysis/out/corrected2x_upair/results/A2_7c.csv` | yes | IDENTICAL (bytes) | 361 cells, 361 identical, 0 beyond tolerance |  |
| Figure 1 and other controls | `analysis/out/corrected2x/FIG_cd_slopes_controls.csv` | not in manifest | IDENTICAL (bytes) | 456 cells, 456 identical, 0 beyond tolerance |  |
| Figure 1 and other controls | `analysis/out/corrected2x/FIG_cd_slopes_grid.csv` | not in manifest | IDENTICAL (bytes) | 8855 cells, 8855 identical, 0 beyond tolerance |  |
| Figure 1 and other controls | `analysis/out/corrected2x/FIG_cd_slopes_bins.csv` | not in manifest | IDENTICAL (bytes) | 427 cells, 427 identical, 0 beyond tolerance |  |
| Figure 1 and other controls | `analysis/out/corrected2x/positive_controls.csv` | not in manifest | IDENTICAL (cells) | 2330 cells, 2330 identical, 0 beyond tolerance (column source = file path of the reference value, left out) |  |
| Figure 1 and other controls | `analysis/out/corrected2x/TAB_results.csv` | not in manifest | IDENTICAL (bytes) | 400 cells, 400 identical, 0 beyond tolerance |  |
| Figure 1 and other controls | `analysis/out/corrected2x/C2_bias_results.csv` | not in manifest | IDENTICAL (bytes) | 51 cells, 51 identical, 0 beyond tolerance |  |
| Figure 1 and other controls | `analysis/out/corrected2x/FIG_new_checks.csv` | not in manifest | IDENTICAL (bytes) | 85 cells, 85 identical, 0 beyond tolerance |  |
| Figure 1 and other controls | `analysis/out/corrected2x/tables/A1_A1.7_lead_power_mu_check.csv` | not in manifest | IDENTICAL (bytes) | 340 cells, 340 identical, 0 beyond tolerance |  |

Not produced by the default run (reconciliation switch `--reconciliation`): 23 frozen CSV files of the vintages corrected and corrected2 and of the earlier figure versions.

Figure image files (`.pdf`, `.png`, `.tif`) depend on the matplotlib version and are compared through their data files.

Notes worded differently. In the files below every number and every other cell is identical; only the free-text column `note` differs in the rows listed. The authors' frozen copy names their internal working files or an internal label in these notes; the package code refers to them generically. Wording in the package (number of rows):

- `analysis/out/corrected2x/results/A1.csv`: 2 × "absorb(exporter_year importer_year pair_id pair_id#c.year): alternative form; equivalence check only"
- `analysis/out/corrected2x/results/A1.csv`: 1 × "FAILED rc=301: bootstrap(100,20261103) stops when a bootstrap sample draws too few of the 3 control (non-switching) observations: the command reports insufficient observations and that no effect can be estimated (replay: working notes of the au"
- `analysis/out/corrected2x/results/A1.csv`: 1 × "SWEEP2 exclusion (authors' working notes); baseline e(sample) rows excluded 953"
- `analysis/out/corrected2x/results/A1.csv`: 1 × "SWEEP2 exclusion (authors' working notes); baseline e(sample) rows excluded 6"
- `analysis/out/corrected2x/results/A1.csv`: 1 × "SWEEP2 exclusion (authors' working notes); baseline e(sample) rows excluded 590"
- `analysis/out/corrected2x/results/A1.csv`: 1 × "SWEEP2 exclusion (authors' working notes); baseline e(sample) rows excluded 0"
- `analysis/out/corrected2x/results/A1_parts/A1_03.csv`: 2 × "absorb(exporter_year importer_year pair_id pair_id#c.year): alternative form; equivalence check only"
- `analysis/out/corrected2x/results/A1_parts/A1_05b_vis_cont1boot.csv`: 1 × "FAILED rc=301: bootstrap(100,20261103) stops when a bootstrap sample draws too few of the 3 control (non-switching) observations: the command reports insufficient observations and that no effect can be estimated (replay: working notes of the au"
- `analysis/out/corrected2x/results/A1_parts/A1_07.csv`: 1 × "SWEEP2 exclusion (authors' working notes); baseline e(sample) rows excluded 953"
- `analysis/out/corrected2x/results/A1_parts/A1_07.csv`: 1 × "SWEEP2 exclusion (authors' working notes); baseline e(sample) rows excluded 6"
- `analysis/out/corrected2x/results/A1_parts/A1_07.csv`: 1 × "SWEEP2 exclusion (authors' working notes); baseline e(sample) rows excluded 590"
- `analysis/out/corrected2x/results/A1_parts/A1_07.csv`: 1 × "SWEEP2 exclusion (authors' working notes); baseline e(sample) rows excluded 0"

## Exhibit-level scope (revised numbering)

All 43 exhibits of the revised numbering (manuscript Tables 1–8 and Figures 1–2, Appendix Tables A1–A5, Supplementary Tables S2.1–S11.1) were traced, entry by entry, to the files their numbers are read from, and each file was compared with the clean-room output under the rule above (comparison of stored files; no further run). Text state: revised manuscript, appendix and supplement drafts as of 2026-11-05 16:54:32. Counting unit: a source-key entry is one distinct reference in the text to a value or to a table in a file, counted once per exhibit. An entry can insert a single number or a whole table (for example Supplementary Tables S2.7 and S10.1, one entry each), so the totals below count source-key entries, not printed numeric cells; the files behind the entries are compared cell by cell (Comparison above). Columns: source-key entries in the exhibit; entries read from a compared file that is identical in every number; entries computed from such entries (sums, shares, differences); documented facts that the run does not compute (data checks, provider documentation); entries not compared, with the reason. Table 1, Figure 1 and Figure 2 are compared as whole files. The comparison table above names the package table files `Table1.csv` … `Table7.csv`, which keep the layout of the submitted tables; `README.md`, Section 3, maps them to the revised exhibits.

| Exhibit | source-key entries | read from compared files (identical in every number) | computed from compared entries | documented facts (not computed) | not compared |
|---|---|---|---|---|---|
| Table 1 | 0 | whole exhibit file: `06_results/tables/final/Table1.csv` identical | 0 | 0 | 0 |
| Table 2 | 83 | 76 | 6 | 1 | 0 |
| Table 3 | 42 | 42 | 0 | 0 | 0 |
| Table 4 | 100 | 100 | 0 | 0 | 0 |
| Table 5 | 70 | 69 | 0 | 0 | 1: vintage reconciliation |
| Table 6 | 127 | 126 | 0 | 1 | 0 |
| Table 7 | 154 | 144 | 0 | 4 | 6: reconciliation vintage |
| Table 8 | 166 | 164 | 1 | 1 | 0 |
| Figure 1 | 0 | whole exhibit file: `06_results/figures/Figure_cd_slopes_data.csv` identical | 0 | 0 | 0 |
| Figure 2 | 1 | 0; whole file `06_results/figures/Figure_coefplot_data.csv` identical | 0 | 1 | 0 |
| Table A1 | 12 | 12 | 0 | 0 | 0 |
| Table A2 | 23 | 22 | 0 | 1 | 0 |
| Table A3 | 12 | 12 | 0 | 0 | 0 |
| Table A4 | 26 | 26 | 0 | 0 | 0 |
| Table A5 | 66 | 66 | 0 | 0 | 0 |
| Table S2.1 | 1 | 1 | 0 | 0 | 0 |
| Table S2.2 | 1 | 1 | 0 | 0 | 0 |
| Table S2.3 | 1 | 1 | 0 | 0 | 0 |
| Table S2.4 | 1 | 1 | 0 | 0 | 0 |
| Table S2.5 | 1 | 1 | 0 | 0 | 0 |
| Table S2.6 | 1 | 1 | 0 | 0 | 0 |
| Table S2.7 | 1 | 1 | 0 | 0 | 0 |
| Table S3.1 | 1 | 1 | 0 | 0 | 0 |
| Table S3.2 | 1 | 1 | 0 | 0 | 0 |
| Table S3.3 | 72 | 72 | 0 | 0 | 0 |
| Table S4.1 | 1 | 0 | 0 | 0 | 1: input table |
| Table S4.2 | 1 | 1 | 0 | 0 | 0 |
| Table S4.3 | 1 | 1 | 0 | 0 | 0 |
| Table S5.1 | 2 | 2 | 0 | 0 | 0 |
| Table S5.2 | 2 | 2; whole file `tables/S5_2_unordered_pair_tests.csv` identical | 0 | 0 | 0 |
| Table S5.3 | 1 | 1; whole file `tables/S5_3_benchmark_family.csv` identical | 0 | 0 | 0 |
| Table S6.1 | 1 | 1 | 0 | 0 | 0 |
| Table S6.2 | 94 | 94 | 0 | 0 | 0 |
| Table S6.3 | 102 | 102 | 0 | 0 | 0 |
| Table S7.1 | 40 | 40 | 0 | 0 | 0 |
| Table S7.2 | 23 | 22 | 0 | 1 | 0 |
| Table S8.1 | 1 | 1 | 0 | 0 | 0 |
| Table S8.2 | 288 | 288 | 0 | 0 | 0 |
| Table S9.1 | 38 | 38 | 0 | 0 | 0 |
| Table S9.2 | 40 | 40 | 0 | 0 | 0 |
| Table S9.3 | 31 | 30 | 0 | 1 | 0 |
| Table S10.1 | 1 | 1 | 0 | 0 | 0 |
| Table S11.1 | 1 | 0 | 0 | 0 | 1: vintage reconciliation |
| **all 43 exhibits** | 1631 | 1604 | 7 | 11 | 9 |

Not compared, by reason:

- reconciliation vintage (6 entries, all in Table 7): the 31-code reference rows (`corrected2`, `05_output/10_analysis/corrected2/results/A1.csv`) are written only by `python run_all.py --reconciliation`, which was not part of the clean-room run.
- vintage reconciliation table (2 entries, one in Table 5 and one in Supplementary Table S11.1): both read `06_results/tables/RECONCILIATION.csv`, which also needs the `submitted` vintage, built in a second copy of the package with the correction rules off (`README.md`, Section 3).
- input table (1 entry, Supplementary Table S4.1): the UNESCO FCS 2009 code list is shipped as `derived/products/unesco_fcs2009_benchmark.csv` and is not computed by the run.

## Notes

- `results/A1.csv`: every number is identical; besides the note wording listed in the Comparison, the file differs from the reference in its line ends (CRLF here, LF in the reference), because `run_all.py` writes A1.csv once more after the vintage relabel of its parts (`A1_combine.py` uses the csv module, `C2_post.py` pandas). The reported results of the first code freeze had CRLF line ends for the same file.
- `positive_controls.csv`: the column `source` holds the file path of each reference value and is machine-specific; every other cell is identical.
- Earlier clean-room runs. In a first clean room: on the first code freeze (run 1 stopped in the results stage and, after a fix, matched every frozen file; run 2, full, 1,664 s), on code freeze 2 (full, 1,712 s) and on code freeze 3 (its one added step run separately, 61 s, then the results stage). In a second clean room, whose path contains spaces: one full run of code freeze 4 (59 steps, 1,985 s; all 67 files then compared matched), after two attempts that were stopped during the analysis stage because results-stage scripts were changed after the copy (display tables of the unordered-pair recomputation, the count differences of the reconciliation table, Figure 2 labels and its added row for trips in millions, the vintage label of the unordered-pair folder; the clean room was reset each time); then, on 2026-11-05, separate runs of the steps changed or added after it (the common-sample check of Supplementary Section S9.3, a new label of one row of Figure 2, and the launcher fix below), whose outputs matched the frozen files. Each of these runs matched every frozen file, `A1.csv` up to its line ends. In a third clean room, whose path contains no spaces, a first full run of the code as released stopped at `C2_A1_10_boot.do` for visitors (see "Release wording fix" below). All these runs are superseded by the run reported above: one full run of the final code in a fourth, newly created clean room.
- Build stage: the rebuilt exporter-reported mirror reproduces the build's 31-code totals on all 178,908 sparse rows (`05_output/10_analysis/corrected2x/mirror_ex4907_controls.csv`, 7 of 7 PASS), and the original Mobility estimation outputs serve as the reference of `02_positive_controls.do`.
- Unordered-pair clusters: `05_output/10_analysis/corrected2x_upair/results/` holds the estimates of the eight `UP_*.do` copies. In this run `C2_A1_12_make_upair.py --check` confirmed that the copies equal a regeneration from their sources, and `C2_A1_12_upair_table.py` checked that each of the 596 rows they post exists under both clusterings with the same N and estimate, reproduced the 24 Holm-adjusted p values of `A2_3.do` as a positive control, and wrote 163 paired tests (largest change of a p value between the two clusterings: 0.086).
- Launcher fix. `run_all.py` used to quote an argument for Stata only when it contained a space. On macOS, Stata names its batch log after the last argument when that argument is not quoted, so from a folder without spaces in its path every Stata step of the analysis stage stopped with "no batch log"; the runs in the second clean room, from a folder with spaces, were not affected. The problem was found on 2026-11-05, when a partial run of the new common-sample step was started from a folder without spaces and stopped in this way (recorded with status FAIL in that clean room's `run_all.log` and `run_times.csv`; the step was then repeated from the folder with spaces). `run_all.py` now quotes every argument; from a folder with spaces it passes Stata the same command line as before. The run reported above, from a folder without spaces in its path, used the corrected file.
- Release wording fix. Before release, references to the authors' working files were removed from the code. In one line this put an apostrophe inside a Stata macro expression (`C2_A1_10_boot.do`, line 93, the note written when the visitor bootstrap stops with rc 301), so in the code as released that step stopped with r(132) ("too few quotes"); the code of the second clean room still had the original wording and was not affected. The first full run of the code as released (third clean room, 2026-11-05) stopped there. The line now reads "working notes of the authors"; the same step then ran without error in that clean room, and the run reported above used the corrected file. The same cleaning reworded a few other notes; they are listed in the Comparison above where they reach a result file. One more file read by the exhibit-level ledger has such a difference: in `analysis/out/corrected2x/tables/A1_A1.2_economy_lists.csv` (Supplementary Table S2.6) the column `name_source` reads "UNSD designation" in 2 rows where the authors' frozen copy names their internal terminology file; every other cell is identical, and the ledger counts the file as identical except free text.

## Hofstede inputs with and without the build's workbook

The build and the analysis read the Hofstede workbook of the submitted paper, which is not public. `tools/rebuild_hofstede_inputs.py` rebuilds its first sheet from the public official 2015-08-16 file and `derived/hofstede/hofstede_package_workbook_layout.csv`: the rebuilt sheet equals the workbook in 1,410 of 1,410 cells (type and exact value), and its text export is byte-identical to the export of the workbook. Two runs in the earlier clean room on code freeze 3, compared with the 27 Hofstede-dependent outputs of that clean room's full run on code freeze 2 (Hofstede extraction, bilateral cultural distance, master panel, analysis datasets, the Hofstede exports and tables of the analysis, build diagnostics):

| run | check | build | Hofstede steps of the analysis | outputs byte-identical |
|---|---|---|---|---|
| without the workbook (sheet rebuilt from the official file) | PASS (workbook reported as optional and absent) | OK, 283 s | OK | 24 of 27 |
| with the workbook (current code) | (not rerun) | OK, 275 s | OK | 25 of 27 |

In both runs the two analysis datasets `04_analysis data/03_Mobility/mobility_analysis(_UB)_2007_2021.dta` differ from the full run only in their header: the save time and padding bytes after string terminators. Their data, value labels and characteristics (every byte from the characteristics section to the end, 578,059,196 of 578,091,647 bytes) and every variable name, label, format and type are identical, so the difference is from run to run, not from the rebuilt sheet. Without the workbook, the diagnostic `05_output/03_Mobility/01_diagnostics/Hofstede/source_manifest.csv` also differs, because it names the source it read.

The build code these two runs test (`02_code/00_common`, `02_code/03_Mobility`, `02_code/99_rescue`, `tools/rebuild_hofstede_inputs.py` and the Hofstede steps of the analysis) has not changed since; the run reported above used the build's workbook.
