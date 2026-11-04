# Methodological audit of the previous Hofstede construction

The previous Stata code is mechanically reproducible from the intermediate DTA, but it has
several issues that should be made explicit in the clean replication package.

1. The XLS -> `hofstede cultural distance 2015.dta` step was undocumented.
   The new pipeline closes that gap by reading the archived XLS directly.

2. The old intermediate DTA contained many blank worksheet rows.
   Stata `summarize` ignored their missing scores, so they did not change the variances, but
   the cross join was unnecessarily performed before blank rows were removed.

3. The old `rowmean()` rule does not implement one fixed six-dimensional denominator when
   scores are missing. A pair with four common dimensions is averaged over four; a pair with
   six is averaged over six. This is why the clean build labels that measure `cd6_ge4` rather
   than silently calling it the unique six-dimensional Kogut-Singh index.

4. The archived source contains regional benchmark rows (Africa East, Africa West, Arab
   countries), and many ISO-country rows reproduce those regional PDI/IDV/MAS/UAI values.
   The clean pipeline flags those observations rather than silently treating them as ordinary
   country-specific measurements.

5. Dimension variances are computed separately on the nonmissing country sample for each
   dimension. This is retained and explicitly archived in diagnostics.

6. The distance is symmetric and time-invariant. The clean build validates symmetry and uses
   `iso3_o + iso3_d` as the merge key.

The final empirical specification can later decide between `cd6_ge4`, `cd6_strict`, and
`cd4_ks`; the upstream data pipeline preserves all three.
