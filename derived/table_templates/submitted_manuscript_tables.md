<!-- Table layout of the submitted manuscript (captions, rows, columns, printed values), extracted verbatim:
     only the table blocks are kept. Read by 02_code/10_analysis/TAB_build.py (read_ms_tables) as the layout
     template of the revised tables and for the submitted-vintage control (reconciliation switch). -->

**Table 1.** Descriptive Statistics

| Variable | Observations (N) | Mean | Standard Deviation (SD) | Minimum | Maximum |
| Trade (thousand USD) | 612,082 | 2,181.635 | 40,937.245 | 0.000 | 4,211,790.465 |
| Bilateral visitors | 25,656 | 456,120.898 | 4,296,455.797 | 0.000 | 1.679 × 10 8 |
| Reverse visitors: importer→exporter | 106,957 | 100,650.119 | 1,327,701.478 | 0.000 | 1.677 × 10 8 |
| Same-direction visitors: exporter→importer | 106,957 | 100,650.119 | 1,327,701.478 | 0.000 | 1.677 × 10 8 |
| Bilateral tourists | 34,830 | 198,468.398 | 2,110,737.296 | 0.000 | 1.679 × 10 8 |
| Reverse tourists: importer→exporter | 136,612 | 59,385.687 | 748,026.489 | 0.000 | 1.677 × 10 8 |
| Same-direction tourists: exporter→importer | 136,612 | 59,385.687 | 748,026.489 | 0.000 | 1.677 × 10 8 |
| Common language | 756,000 | 0.174 | 0.379 | 0.000 | 1.000 |
| Cultural distance | 209,686 | 2.000 | 1.513 | 0.000 | 13.380 |

**Table 2.** Baseline PPML Estimates and Directional Mobility Decomposition

| Independent Variables | (1) Bilateral Visitors | (2) Importer→Exporter Visitors | (3) Exporter→ Importer Visitors | (4) Joint Visitors | (5) Bilateral Tourists | (6) Importer→Exporter Tourists | (7) Exporter→ Importer Tourists | (8) Joint Tourists |
| Bilateral visitors | 0.243*** (0.091) |  |  |  |  |  |  |  |
| Reverse visitors |  | 0.254*** (0.068) |  | 0.247*** (0.069) |  |  |  |  |
| Same-direction visitors |  |  | 0.088 (0.057) | 0.059 (0.056) |  |  |  |  |
| Bilateral tourists |  |  |  |  | 0.240*** (0.064) |  |  |  |
| Reverse tourists |  |  |  |  |  | 0.028 (0.042) |  | 0.029 (0.045) |
| Same-direction tourists |  |  |  |  |  |  | -0.002 (0.052) | -0.006 (0.055) |
| N | 20,543 | 20,543 | 20,543 | 20,543 | 26,682 | 26,682 | 26,682 | 26,682 |

**Table 3.** Dynamic PPML Estimates of Bilateral Mobility and Cultural-Goods Trade

| Independent Variables | Visitors | Tourists |
| Lag bilateral mobility | -0.075 (0.150) | 0.121 (0.101) |
| Contemporaneous bilateral mobility | 0.372*** (0.079) | 0.157 (0.101) |
| Future bilateral mobility | -0.033 (0.068) | 0.025 (0.057) |
| Future-term p-value | 0.620 | 0.654 |
| N | 13,599 | 19,122 |

**Table 4.** Product-Category PPML Estimates

| Variables | Film (Visitors) | Film (Tourists) | Publications (Visitors) | Publications (Tourists) | Recorded Media (Visitors) | Recorded Media (Tourists) | Artworks (Visitors) | Artworks (Tourists) |
| Bilateral mobility | -0.767 (0.468) | 0.089 (0.333) | 0.186** (0.090) | 0.238*** (0.076) | 0.167 (0.107) | 0.271** (0.131) | 0.266*** (0.079) | -0.100 (0.090) |
| Observations ( N ) | 3,968 | 4,631 | 19,932 | 25,771 | 15,931 | 19,222 | 15,285 | 18,850 |

**Table 5.** Cultural-Proximity Heterogeneity in Bilateral-Mobility Slopes

| Independent Variables | Language (Visitors) | Language (Tourists) | Cultural Distance (Visitors) | Cultural Distance (Tourists) |
| Bilateral visitors | 0.233*** (0.088) |  | 0.331*** (0.095) |  |
| Visitors × common language | -0.087* (0.052) |  |  |  |
| Bilateral tourists |  | 0.220*** (0.063) |  | 0.247*** (0.067) |
| Tourists × common language |  | 0.050 (0.055) |  |  |
| Visitors × cultural distance |  |  | 0.045* (0.026) |  |
| Tourists × cultural distance |  |  |  | -0.039** (0.020) |
| N | 20,543 | 26,502 | 11,730 | 11,091 |

**Table 6.** Robustness, Influence, and Policy-Control Checks

| Variables | (1) Two-way (Visitors) | (2) Two-way (Tourists) | (3) Excluding top five (Visitors) | (4) Excluding top five (Tourists) | (5) Excluding 2008/2020 (Visitors) | (6) Excluding 2008/2020 (Tourists) | (7) RTA (Visitors) | (8) RTA (Tourists) |
| Bilateral mobility | 0.243** (0.108) | 0.240*** (0.090) | 0.095 (0.065) | 0.218*** (0.070) | 0.215** (0.102) | 0.240*** (0.072) | 0.243*** (0.090) | 0.246*** (0.064) |
| RTA/FTA indicator |  |  |  |  |  |  | 0.010 (0.116) | -0.165 (0.163) |
| Observations (N) | 20,543 | 26,682 | 19,509 | 25,260 | 15,855 | 22,074 | 20,543 | 26,682 |

**Table 7.** Additional Robustness Checks

| Check | Visitors | Tourists |
| A. Baseline (Table 2) |
| Baseline | 0.243*** (0.091) N = 20,543 | 0.240*** (0.064) N = 26,682 |
| B. Extreme mobility values |
| Excluding top 0.1% directional mobility values | 0.121* (0.071) N = 20,509 | 0.222*** (0.073) N = 26,626 |
| Excluding unit-break reporter-years (Paraguay, 2020–2021) | 0.243*** (0.091) N = 20,455 | 0.241*** (0.064) N = 26,591 |
| C. Origin classification |
| Same origin classification, stored direction | 0.087 (0.069) N = 6,538 | 0.307** (0.133) N = 7,402 |
| Same origin classification, both directions | 0.150* (0.090) N = 2,494 | 0.158 (0.097) N = 2,494 |
| D. Common category support |
| Cinematographic film | −0.534 (0.486) N = 3,666 | 0.109 (0.335) N = 4,403 |
| Publications | 0.303*** (0.116) N = 3,666 | 0.183** (0.073) N = 4,403 |
| Recorded media | 0.399** (0.160) N = 3,666 | 0.227 (0.177) N = 4,403 |
| Artworks | 0.225*** (0.085) N = 3,666 | −0.012 (0.139) N = 4,403 |
| Joint equality of category coefficients | χ²(3) = 3.990, p = 0.263 | χ²(3) = 1.954, p = 0.582 |
| E. Visitor–tourist difference on identical observations |
| Artworks: visitor–tourist difference | −0.011 (0.042) N = 1,816 p = 0.792 |  |
| Recorded media: visitor–tourist difference | 0.048 (0.077) N = 1,913 p = 0.538 |  |
| F. Lead mobility, 90% confidence interval |
| Lead mobility, no pair trends | −0.033 (0.068) N = 13,599 [−0.145, 0.078] | 0.025 (0.057) N = 19,122 [−0.068, 0.119] |
| Lead mobility, pair trends | −0.017 (0.048) N = 13,320 [−0.096, 0.063] | 0.102* (0.053) N = 19,122 [0.014, 0.189] |

**Table A1.** Positive-Trade Presence Check

| Statistic | Bilateral visitors | Bilateral tourists |
| Mobility coefficient | 0.011* (0.006) | 0.000 (0.004) |
| Observations (N) | 23,527 | 32,003 |
| Adjusted R² | 0.693 | 0.703 |

**Table A2.** Trade Harmonization and Visitor–Tourist Common Support

| Mobility Measure | Specification | Coefficient (β) | Standard Error (SE) | Observations (N) |
| Visitors | LB own support | 0.243 | 0.091 | 20,543 |
| Visitors | UB own support | 0.243 | 0.091 | 20,543 |
| Visitors | Exact visitor–tourist support | 0.043 | 0.091 | 2,611 |
| Tourists | LB own support | 0.240 | 0.064 | 26,682 |
| Tourists | UB own support | 0.242 | 0.064 | 26,694 |
| Tourists | Exact visitor–tourist support | 0.027 | 0.099 | 2,611 |

**Table A3. Analytical Three-Way PPML Finite-Sample Correction**

| **Mobility Measure** | **Original *β*** | **Original SE** | **Corrected *β*** | **Corrected SE** | **Corrected *p*-value** |
|----|----|----|----|----|----|
| Visitors | 0.243 | 0.091 | 0.275 | 0.119 | 0.021 |
| Tourists | 0.240 | 0.064 | 0.236 | 0.075 | 0.002 |

**Table A4.** Trade-Reporting-Side Sensitivity on Exact Common Support

| Mobility | Importer-reported β (SE) | Exporter-reported β (SE) | Simple average β (SE) | Observations (N) | p -value: imp = exp | p -value: all three |
| Visitors | 0.246 (0.091) | 0.021 (0.081) | 0.139 (0.077) | 17,612 | 0.003 | 0.012 |
| Tourists | 0.240 (0.064) | 0.189 (0.071) | 0.245 (0.068) | 21,992 | 0.489 | 0.332 |

**Table A5.** Further Robustness Checks

| Check | Visitors | Tourists |
| Positive trade only | 0.243*** (0.091) N = 16,709 | 0.243*** (0.064) N = 20,264 |
| Positive trade in every year 2007–2021 | 0.231** (0.095) N = 11,469 | 0.244*** (0.068) N = 12,629 |
| Same sample: expected trade, % per IHS unit | 24.29*** (9.06) N = 20,543 | 24.05*** (6.42) N = 26,682 |
| Same sample: probability of positive trade, percentage points | 1.28* (0.71) N = 20,543 | 0.34 (0.60) N = 26,682 |
| Fully reported trade only | 0.255*** (0.092) N = 13,575 | 0.267*** (0.075) N = 16,478 |
| Artworks HS 9701–9703 | 0.163* (0.091) N = 14,514 | −0.111 (0.094) N = 17,705 |
| Publications excluding HS 4907/4908/4911 | 0.171** (0.071) N = 18,545 | 0.109** (0.043) N = 23,967 |
| Recorded media, exact HS 852329/852340/852380 | 0.163 (0.107) N = 15,609 | 0.275** (0.133) N = 18,402 |
| Visitor-minus-tourist difference, alone | 0.030 (0.022) N = 2,505 | — |
| Visitor-minus-tourist difference, controlling for tourists | 0.009 (0.026) N = 2,505 | — |
| Cultural distance, all six dimensions: interaction | 0.051* (0.027) N = 9,504 | −0.040** (0.020) N = 9,085 |

