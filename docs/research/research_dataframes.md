# digest
HASKELL DATAFRAME/WRANGLING SURVEY, verified 2026-08-17.

(1) MCHAV DATAFRAME IS THE ONLY LIVE CONTENDER. v3.5.0.0 uploaded 2026-08-14; repo created 2026-02-24 [sic 2024-02-24]; 1,267 commits; 261 stars; 49 forks; 25 open issues; MIT; GHC 9.4.8/9.6.7/9.8.4/9.10.3/9.12.2; Windows-safe (`unix` guarded by `if !os(windows)`). Now hosted under the DataHaskell org. ~24-package monorepo (core, csv, fastcsv, parquet, json, lazy, operations, learn, viz, th, hasktorch, huggingface, persistent, arrow, fusion...).

BUS FACTOR = 1: mchav has 1,149 contributions; #2 (jhrcek) has 12. API CHURN IS SEVERE: 68 published versions; 1.0.0.0 announced 2026-03-22, already at 3.5.0.0 five months later. 3.3.0.0 rewrote typed schemas from Column phantom types to type-level lists of promoted pairs `'[("name", Text)]`. ADOPTION IS THIN: only 4 Hackage reverse deps, 3 of them mchav's own (dataframe-arrow, dataframe-persistent, ihaskell-dataframe); sole external consumer is `symbolic-regression`.

(2) COLUMN TYPING = DYNAMIC CORE + OPTIONAL STATIC SHELL. `Column` is an existential GADT: `BoxedColumn :: forall a. Columnable a => Maybe Bitmap -> Vector a -> Column`, plus `UnboxedColumn` (adds `Unbox`), `PackedText`, `MergedColumn`. `Maybe Bitmap` = Arrow-style validity bitmap. `Columnable` is a constraint synonym (Columnable', ColumnifyRep, UnboxIf, IntegralIf, FloatingIf, SBoolI). Three API layers over one runtime type: untyped (string names), typed (phantom schema, TH-derived from CSV/Parquet), monadic. Design doc explicitly REJECTS type-level-first design ("type-level programming...doesn't make for intuitive APIs"), critiques Frames as "more Haskell domain knowledge than data science domain knowledge" and analyze as row-oriented.

(3) ARROW STORY IS WEAK; PARQUET IS SURPRISINGLY STRONG BUT READ-ONLY. Haskell is NOT in Apache Arrow's official implementation list. harrow (1 commit, 5 stars) and hs-arrow (6 commits, 12 stars) are abandoned. No Arrow IPC/Feather reader exists in Haskell. `dataframe-arrow` 1.0.2.0 is EXPORT-ONLY — a foreign library exposing the Haskell engine TO Python (pkg `hyrax`) via the Arrow C Data Interface; Hackage reports build failures. CONTRAST: `dataframe-parquet` 1.5.0.0 (2026-08-06) is PURE HASKELL (Thrift via `pinch`, no libarrow): snappy/zstd/gzip, dictionary decoding, nested lists, predicate pushdown, column projection, row ranges. But `DataFrame.IO.Parquet` exports NO writeParquet — issue #181 open; the Hackage blurb "reader and writer" overstates. Parquet writer is the GSoC 2026 project (mentors mchav + adithyaov, 175–350h). Realistic escape hatch: duckdb-ffi 1.5.0.0 / duckdb-simple 0.1.5.1 (tritlo), needs system libduckdb.

(4) COMPETITORS ARE DEAD OR NICHE. Frames 0.7.4.2 — last commit AND release 2023-10-22, GHC ≤9.4.6, no 9.6+. analyze — 2017. javelin 0.1.4.2 (2025-03-02) is Series-only, 24 stars.

(5) COMPLAINTS: CSV type-inference surprises (Double→Int, #177), verbose qualified names (#152), missing pivot (#5)/transpose (#191)/writeParquet (#181), Columnable over-constrained (#154), GHC 9.10.3 install failure (#192), "two independent type systems" hurting interop with normal Haskell, and the unsolved matplotlib-equivalent plotting gap.

# key_insights
- The strategic question is settled by arithmetic, not taste: mchav's dataframe has 1,267 commits, 68 releases and an entire ~24-package monorepo built in ~2.5 years, so competing means reproducing all of it while splitting an ecosystem whose own roadmap lists 'No community of maintainers and contributors' as its top gap — contribute or build on top, do not fork.
- dataframe's core is dynamically typed by deliberate design: Column is an existential GADT (BoxedColumn/UnboxedColumn/PackedText/MergedColumn) hiding the element type behind a Columnable constraint, with static safety bolted on as an optional phantom-schema layer — so any new work must accept runtime-typed columns as the interchange format or reject the foundation entirely.
- The static layer is the least settled part of the design and therefore the best place to contribute expertise: it changed representation as recently as 3.3.0.0 (phantom Column types to type-level lists of promoted pairs), and Frames (vinyl row polymorphism) and javelin-frames (higher-kinded data) demonstrate two more expressive alternatives that have not been reconciled with it.
- Parquet is the ecosystem's strongest and most tractable asset — dataframe-parquet is a pure-Haskell Parquet 2.0 implementation with no libarrow dependency — but it is READ-ONLY: DataFrame.IO.Parquet exports no writeParquet, issue #181 is open, and the Hackage synopsis claiming 'reader and writer' is simply inaccurate.
- The Arrow story is close to nonexistent in the inbound direction: Haskell is absent from Apache Arrow's official implementation list, both binding attempts (harrow at 1 commit, hs-arrow at 6) are abandoned, no Arrow IPC/Feather reader exists, and dataframe-arrow only exports Haskell data TO Python — inbound C Data Interface support is a well-specified, dependency-free, high-leverage gap.
- DuckDB is the pragmatic interop escape hatch available today (duckdb-ffi 1.5.0.0 March 2026, duckdb-simple 0.1.5.1 April 2026, both tracking DuckDB 1.5.0), buying Parquet write plus Arrow plus a vectorized larger-than-memory engine for the price of one system libduckdb dependency — ideal as a flag-gated optional backend, wrong as a mandatory core dependency.
- Every statically-typed alternative is dead or dormant: Frames' last commit and last release are both 2023-10-22 with GHC support capped at 9.4.6 (so it will not even build on a current compiler), analyze has been untouched since 2017, and javelin is a 24-star Series-only library — the typed-dataframe design space is effectively vacant and open to a serious entrant.
- Stars badly overstate adoption: dataframe has 261 stars but only 4 Hackage reverse dependencies, three of which mchav owns himself, leaving symbolic-regression as the sole external consumer — the library is technically mature but socially unproven, so integration and case-study work may matter more than new features.
- API instability is the dominant practical risk for any downstream consumer: three major-version bumps in five months (1.0.0.0 on 2026-03-22 to 3.5.0.0 on 2026-08-14) across a 68-release history, which argues for depending on granular subpackages like dataframe-core and dataframe-operations with tight bounds rather than the umbrella package.
- The project carries three bespoke runtimes — its own SIMD CSV reader (dataframe-fastcsv, deliberately bypassing cassava), its own Parquet codec, and its own pull-based lazy executor that uses neither streamly nor conduit — which is impressive for one maintainer but is precisely the surface most likely to rot, and open issue #133 shows the maintainer already reconsidering the streaming layer.
- Real user complaints cluster on ergonomics and correctness-of-inference rather than performance: silent Double-to-Int coercion on CSV read (#177), verbose qualified imports (#152), missing pivot (#5) and transpose (#191), over-constrained Columnable (#154), and GHC 9.10.3 install failure (#192) — polish, not raw speed, is the adoption bottleneck.
- The deepest conceptual objection, raised on Discourse, is that a dynamically-typed column universe creates 'two independent type systems' that interoperate poorly with ordinary Haskell libraries — bridging that seam (Generic/HKD-based zero-boilerplate conversion between DataFrames and user record types) is the highest-value design contribution available.
- Performance is already credible enough that speed should not be the pitch: self-reported benchmarks show 119ms groupBy versus Polars 227ms and Pandas 376ms, and completion of a 300M-row scan where both Python libraries OOM'd — but these are custom benchmarks on a Chromebook and the standard duckdblabs db-benchmark entry (#115) is still open, so independent benchmarking is itself a contribution.
- Timing strongly favors engagement now: dataframe is GSoC 2026's only data-science project with funded mentorship aimed squarely at the Parquet writer, a Haskell Foundation Tech Proposal is in flight, and cassava co-maintainership has aligned the CSV substrate with the dataframe effort — a newcomer's marginal influence on direction will never be higher.
- Windows viability is already handled and should be preserved as a differentiator: dataframe guards its unix dependency with `if !os(windows)`, dataframe-parquet is pure Haskell with no libarrow build step, and hasql now offers a C-free pluggable transport — whereas any libduckdb or libarrow dependency reintroduces exactly the native-build friction this stack currently avoids.

# libraries

## dataframe (mchav / DataHaskell) (Flagship DataFrame library: CSV/JSON/Parquet IO, expression DSL, groupBy/join/aggregate, lazy query engine, plotting, classical ML. Monorepo of ~24 packages (dataframe-core, -csv, -fastcsv, -parquet, -json, -lazy, -operations, -learn, -viz, -th, -hasktorch, -huggingface, -persistent, -arrow, -fusion, -expr-serializer, -parsing).)
STATUS: VERY ACTIVE. v3.5.0.0 uploaded 2026-08-14 (3 days before survey). dataframe-core 2.4.0.0 and dataframe-lazy 2.4.0.0 same day. 1,267 commits, 261 stars, 49 forks, 25 open issues, MIT. Repo created 2024-02-24, now under DataHaskell org. tested-with GHC ==9.4.8 || ==9.6.7 || ==9.8.4 || ==9.10.3 || ==9.12.2. Commits in Aug 2026 target memory pressure in CSV reads/groupby/joins. Participating in GSoC 2026.
ASSESS: STRENGTHS: only serious, live dataframe effort in Haskell; columnar with Arrow-style bitmap validity; pure-Haskell Parquet reader (no libarrow); SIMD CSV; relational-algebra lazy engine with filter fusion/predicate pushdown/dead-column elimination; three coherent API layers; Windows-clean (unix dep guarded by `if !os(windows)`); MIT; already the DataHaskell standard. WEAKNESSES: bus factor 1 (mchav 1,149 contributions vs 12 for #2 contributor jhrcek); 68 versions with three major bumps in five months (1.0.0.0 2026-03-22 -> 3.5.0.0 2026-08-14) means no API stability contract; only 4 Hackage reverse deps, 3 self-owned, 1 external (symbolic-regression) — stars greatly exceed real adoption; benchmarks are self-published on non-server hardware and standard db-benchmark entry is still open issue #115. FIT: build ON it, not against it. Rebuilding a dataframe from scratch would duplicate ~2.5 years of work and split a community that has no spare contributors. Highest-leverage contributions are exactly the gaps: Parquet writer, Arrow ingestion, stable API surface, benchmark rigor. Depend on the granular subpackages (dataframe-core/-operations) rather than the umbrella package to limit churn exposure.
EVID: https://hackage.haskell.org/package/dataframe ; https://github.com/mchav/dataframe ; https://api.github.com/repos/mchav/dataframe ; https://api.github.com/repos/mchav/dataframe/commits?per_page=20 ; https://raw.githubusercontent.com/mchav/dataframe/main/dataframe.cabal

## dataframe-parquet (Pure-Haskell Parquet 2.0 reader for the dataframe ecosystem.)
STATUS: ACTIVE. v1.5.0.0 uploaded 2026-08-06. MIT, maintainer Michael Chavinda. GHC 9.4.8–9.12.2. Deps: pinch (Thrift), snappy-hs, zlib, zstd, dataframe-core, dataframe-operations. NO C++ Arrow/parquet-cpp dependency.
ASSESS: STRENGTHS: genuinely rare asset — a from-scratch Parquet implementation in pure Haskell, so no libarrow/libparquet build hell on Windows. Supports snappy/zstd/gzip, dictionary decoding, nested list/repeated columns, predicate pushdown, column projection (selectedColumns), row ranges. WEAKNESS / CORRECTION: the Hackage synopsis says 'reader and writer' but DataFrame.IO.Parquet exports only readParquet, readParquetWithOpts, readParquetFiles, readParquetFilesWithOpts — there is NO writeParquet. GitHub issue #181 'Add the function writeParquet' is still open. Missing BROTLI (#166) and GZIP-for-decoding work (#167); allocation pressure flagged (#151). Round-trip validation against pandas/pyarrow is listed as future GSoC work, i.e. not yet proven. FIT: the single best contribution target in the ecosystem — writer + round-trip conformance would make Haskell a first-class Parquet citizen and is already funded/mentored via GSoC 2026 (175h, expandable to 350h; mentors mchav + adithyaov).
EVID: https://hackage.haskell.org/package/dataframe-parquet ; https://hackage-content.haskell.org/package/dataframe-parquet-1.5.0.0/docs/DataFrame-IO-Parquet.html ; https://summer.haskell.org/ideas.html

## dataframe-arrow / hyrax (Foreign library exposing the Haskell dataframe lazy executor TO Python via the Arrow C Data Interface; backs the `hyrax` Python package.)
STATUS: v1.0.2.0 on Hackage, uploaded 2026-08-14, MIT. Hackage reports ALL BUILDS FAILED as of upload. Exposes module DataFrame.FFI; uses cbits/rts_init.c, arrow_abi.h, dataframe_arrow.h; depends on dataframe:arrow-bridge sublibrary and dataframe-fastcsv.
ASSESS: CRITICAL NUANCE: the direction is Haskell -> Python ONLY. Computation happens in Haskell; results are marshaled out as pyarrow.RecordBatch. It is a way to sell the Haskell engine to Python users, NOT a way to ingest Arrow data into Haskell. There is no ArrowSchema/ArrowArray import path, no Arrow IPC/Feather reader, and dataframe-core exposes no Arrow module at all. Build failures on Hackage mean it is not yet reliably consumable. FIT: the inbound half of the C Data Interface is an open, well-specified, high-value gap — implementing import would give zero-copy interop with pyarrow/polars/DuckDB in-process and is far cheaper than reimplementing Arrow IPC.
EVID: https://hackage.haskell.org/package/dataframe-arrow ; https://api.github.com/repos/mchav/dataframe/contents/dataframe-arrow ; https://raw.githubusercontent.com/mchav/dataframe/main/dataframe-arrow/dataframe-arrow.cabal ; https://raw.githubusercontent.com/mchav/dataframe/main/python/README.md

## Frames (Vinyl/extensible-record based statically typed CSV frames with Template Haskell schema inference (tableTypes).)
STATUS: STALE / EFFECTIVELY UNMAINTAINED. Latest Hackage version 0.7.4.2 uploaded 2023-10-22. Most recent GitHub commit also 2023-10-22 ('Bump ghc-prim bounds'). tested-with GHC 8.6.5–9.4.6 — NO GHC 9.6, 9.8, 9.10, or 9.12 support. 299 stars, 392 commits, 69 issues. Maintainer Anthony Cowley.
ASSESS: STRENGTHS: the most intellectually serious static-typing design in Haskell tabular data — vinyl records give real row polymorphism, rcast/rget projection is compile-time checked, and it pioneered TH schema inference from CSV. Streams rows via pipes in constant memory. WEAKNESSES: ~3 years without a commit; cannot build on any GHC a 2026 project would target; depends on pipes (itself frozen since 2021) and vinyl; type errors are notoriously large; mchav's design doc critiques it as looking 'more like an advanced Haskell tool than a data science tool'. FIT: DO NOT build on it — adopting it means inheriting a GHC-support rescue project plus a frozen streaming substrate. DO mine it for design: its vinyl row-polymorphism is strictly more expressive than dataframe's phantom type-level list of promoted pairs, and is the right reference if the new toolkit wants genuine compile-time schema algebra.
EVID: https://hackage.haskell.org/package/Frames ; https://github.com/acowley/Frames ; https://api.github.com/repos/acowley/Frames/commits?per_page=5

## javelin / javelin-frames / javelin-io (javelin: Series — labeled 1-D arrays (map+array hybrid), boxed/unboxed/generic. javelin-frames: dataframes from user record types via higher-kinded types. javelin-io: Series (de)serialization.)
STATUS: LOW ACTIVITY, NOT DEAD. javelin 0.1.4.2 and javelin-frames 0.1.0.1 uploaded 2025-03-02. GitHub last push 2026-01-02, last updated 2026-02-16, not archived. Only 24 stars, 5 open issues. Maintainer Laurent P. René de Cotret (LaurentRDC). MIT.
ASSESS: STRENGTHS: clean, well-documented, focused. Series is the one primitive dataframe genuinely lacks — an index-aware labeled 1-D array (pandas Series / R named vector), with proper boxed/unboxed/generic split and a dedicated tutorial module. javelin-frames' higher-kinded-data approach (records-of-columns derived from a user record) is a third distinct design point, ergonomically lighter than vinyl and more idiomatic than phantom schemas. WEAKNESSES: tiny mindshare (24 stars), single maintainer, no Parquet/Arrow, no query engine, no groupBy/join story comparable to dataframe. FIT: not a foundation, but the best source of ideas for indexing/alignment semantics, and HKD is worth evaluating as the static layer instead of type-level lists. Possible collaboration target rather than competitor.
EVID: https://hackage.haskell.org/package/javelin ; https://hackage.haskell.org/package/javelin-frames ; https://api.github.com/repos/laurentRDC/javelin

## analyze (Early row-oriented dataframe attempt.)
STATUS: DEAD. v0.1.0.0 uploaded 2017-01-06; last successful build reported 2017-01-06; ~1,203 total downloads, no activity in last 30 days.
ASSESS: Abandoned for ~9.5 years. Row-oriented layout is the wrong shape for analytics — mchav's design doc singles it out: columnar operations are 'slower and less intuitive' on it. Zero value as a foundation; relevant only as a cautionary data point that row-major tabular designs in Haskell have not survived.
EVID: https://hackage.haskell.org/package/analyze

## cassava (RFC 4180 CSV parsing/encoding; index- and name-based record conversion, streaming/incremental decode.)
STATUS: ACTIVELY MAINTAINED. v0.5.4.1 uploaded 2025-09-02. Tested GHC 8.0.2 through 9.14.1 — the widest GHC matrix in this survey. 105 direct / 3,937 indirect reverse deps. Maintainers: Andreas Abel, Herbert Valerio Riedel, Johan Tibell, phadej, AND mchav.
ASSESS: STRENGTHS: the de facto CSV standard, enormous reverse-dep base, broad GHC support, battle-tested, typeclass-driven FromRecord/FromNamedRecord conversion. Notable ecosystem signal: mchav joined as a co-maintainer, so the CSV substrate and the dataframe effort are now aligned rather than competing. WEAKNESSES: row/record-oriented and typeclass-driven, so it is a poor direct fit for bulk columnar ingestion; performance is 'comparable to Python's csv module', which is far off Polars/Arrow-class readers. Evidence the ecosystem agrees: dataframe-csv wraps cassava, but dataframe-fastcsv 1.4.1.0 deliberately does NOT — it is a separate SIMD (AVX2/ARM NEON) + mmap + carryless-multiplication quote-processing reader in cbits/process_csv.c with a pure-Haskell fallback. FIT: keep cassava for correctness/compatibility and per-row typed decoding; do not put it on the bulk-load hot path.
EVID: https://hackage.haskell.org/package/cassava

## streamly (High-performance streaming, concurrency and reactive programming; general-purpose substrate for larger-than-memory pipelines.)
STATUS: ACTIVE. v0.11.1 uploaded 2026-05-30. Tested GHC 8.6.5–9.14.1. 43 direct reverse deps. Maintainers harendra, pranaysashank, adithyaov; commercial backing from Composewell Technologies.
ASSESS: STRENGTHS: fastest of the three streaming libraries, fusion-based with C-like performance claims, actively developed, corporate backing, widest GHC support. Strong ecosystem overlap with dataframe: streamly maintainers pranaysashank (4 commits to dataframe) and adithyaov (co-mentor of the dataframe GSoC 2026 Parquet project) are already involved, and open issue #133 proposes moving the Parquet reader to Streamly-based streaming for bounded memory. WEAKNESSES: large API surface, has broken compatibility across major versions, steeper learning curve than conduit. FIT: the strongest candidate substrate if the new toolkit wants a shared streaming layer, and the choice already has social momentum inside dataframe.
EVID: https://hackage.haskell.org/package/streamly ; https://github.com/mchav/dataframe/issues (issue #133) ; https://summer.haskell.org/ideas.html

## conduit (Constant-memory streaming with deterministic resource handling.)
STATUS: MAINTAINED, MATURE. v1.3.6.1 uploaded 2025-02-23. 632 direct / 4,526 indirect reverse deps — by far the largest streaming footprint. Maintainer Michael Snoyman. MIT.
ASSESS: STRENGTHS: the pragmatic default — largest reverse-dep base of any Haskell streaming library, stable API, excellent resource safety (ResourceT), well documented, Stackage-central. WEAKNESSES: slower than streamly for tight numeric loops; release cadence is maintenance-paced rather than feature-paced. FIT: safest choice for IO-boundary work (HTTP, file, DB cursors) where interop with the existing ecosystem matters more than raw throughput; pair with streamly only if a single substrate is not mandated.
EVID: https://hackage.haskell.org/package/conduit

## pipes (Compositional streaming built on a bidirectional proxy type.)
STATUS: FROZEN. v4.3.16 uploaded 2021-05-07 (latest revision Oct 2022) — over 5 years without a release. 192 direct reverse deps. Maintainer Gabriella Gonzalez.
ASSESS: Elegant theory (category-law-driven) but effectively feature-frozen; plausibly 'done' rather than abandoned, yet a 5-year gap is disqualifying for a new foundation. Compounding risk: Frames depends on pipes, so that stack is stale end-to-end. FIT: avoid for new work.
EVID: https://hackage.haskell.org/package/pipes

## dataframe-lazy (Lazy/streaming query engine: relational-algebra plans, rule-based optimizer, pull-based executor, column-oriented spill format — the larger-than-memory story for dataframe.)
STATUS: ACTIVE. v2.4.0.0 uploaded 2026-08-14. Deps include async, attoparsec, stm, temporary, Glob, dataframe-parquet, dataframe-csv. Modules: DataFrame.Lazy, DataFrame.Lazy.IO.Binary, DataFrame.Lazy.IO.CSV, DataFrame.Typed.Lazy.
ASSESS: STRENGTHS: a real query planner (filter fusion, predicate pushdown, dead column elimination) plus disk spill — this is Polars-shaped architecture, not a toy, and the 1.0 announcement claimed billion-row capability. Has a typed variant (DataFrame.Typed.Lazy). KEY DESIGN FACT: it uses its OWN custom pull-based executor, NOT streamly or conduit — so the project is carrying a bespoke streaming runtime alongside its bespoke Parquet and bespoke CSV readers. WEAKNESS: that is a large surface for a one-person project, and it isolates the engine from the streaming ecosystem's optimization work; issue #133 shows the maintainer is already reconsidering. FIT: evaluate before writing any new execution engine — the planner/optimizer/spill layer is the most expensive piece to rebuild and it already exists.
EVID: https://hackage.haskell.org/package/dataframe-lazy ; https://github.com/mchav/dataframe

## hasql (High-performance PostgreSQL driver.)
STATUS: VERY ACTIVE. v2.0.1.0 uploaded 2026-08-12. Maintainer Nikita Volkov. Self-describes as production-ready with a formal support policy (>=1 year of fixes per major release). Powers PostgREST.
ASSESS: STRENGTHS: fastest Postgres option, actively developed, strong extension ecosystem (transactions, pooling, migrations, notifications). Major recent architectural win: a pluggable transport layer (PQI) that removes the C dependency from the core, with a stable FFI adapter plus an alpha PURE-HASKELL adapter — that materially improves Windows and cross-compilation stories. WEAKNESSES: encoder/decoder API is more verbose and less beginner-friendly than postgresql-simple; alpha pure-Haskell transport not yet proven. FIT: preferred Postgres backend for a performance-oriented toolkit, especially for bulk column extraction.
EVID: https://hackage.haskell.org/package/hasql

## postgresql-simple (Mid-level PostgreSQL client, familiar sqlite-simple-style API.)
STATUS: MAINTAINED BUT SHOWING STRAIN. v0.7.0.1 uploaded 2025-08-02. Maintainers Oleg Grenrus (phadej). Hackage reports documentation build unavailable and reported builds failing at time of survey.
ASSESS: STRENGTHS: by far the most familiar API, huge existing usage, low learning curve, good for ad-hoc queries. WEAKNESSES: slower than hasql; requires libpq; the failing builds and missing docs on Hackage are a caution flag I could not fully diagnose from the package page alone (may be transient Hackage builder infrastructure rather than genuine breakage — treat as unconfirmed). FIT: acceptable convenience backend, but hasql is the better primary.
EVID: https://hackage.haskell.org/package/postgresql-simple

## sqlite-simple (Mid-level SQLite bindings.)
STATUS: MAINTAINED, SLOW CADENCE. v0.4.19.0 uploaded 2024-01-23 (~2.5 years old). 45 direct / 450 indirect reverse deps. Current maintainer Joshua Chia (jchia), with Janne Hellsten and Sergey Bushnyak.
ASSESS: STRENGTHS: stable, embedded, zero-config, bundles via direct-sqlite so no system dependency — excellent for tests, fixtures and local caches on Windows. WEAKNESSES: quiet for 2.5 years; SQLite is row-oriented so it is a poor analytical backend for columnar workloads. FIT: use for local/embedded persistence and test fixtures, not for analytics. Note dataframe-persistent 0.5.0.0 already provides a DataFrame<->DB bridge and is SQLite-centric (persistent + persistent-sqlite, module DataFrame.IO.Persistent.Read.Sqlite).
EVID: https://hackage.haskell.org/package/sqlite-simple

## duckdb-ffi / duckdb-simple (duckdb-ffi: low-level bindings exposing the full DuckDB C API. duckdb-simple: mid-level interface in sqlite-simple/postgresql-simple style.)
STATUS: ACTIVE, RECENT. duckdb-ffi v1.5.0.0 uploaded 2026-03-11; duckdb-simple v0.1.5.1 uploaded 2026-04-24. Both tested with DuckDB 1.5.0; duckdb-simple supports GHC 9.6–9.14. Maintainer Matthias Pall Gissurarson (tritlo). REQUIRES libduckdb installed on the system — not bundled. A third, separate sighingnow/duckdb-haskell v0.1.0.0 also exists.
ASSESS: STRENGTHS: the single most pragmatic answer to 'how do I get real Arrow/Parquet/analytics interop in Haskell today'. DuckDB natively reads/writes Parquet, speaks Arrow, handles larger-than-memory queries, and has a vectorized engine — inheriting all of that costs one FFI dependency instead of years of work. Bindings are current (DuckDB 1.5.0, March/April 2026) and maintained by a credible Haskell researcher. WEAKNESSES: requires a system libduckdb install, which is real friction on Windows and complicates CI and distribution; three competing binding packages means fragmentation risk; a C++ dependency undercuts the pure-Haskell property that makes dataframe-parquet attractive. FIT: strong candidate for an OPTIONAL escape-hatch backend (flag-gated), giving immediate Parquet write + Arrow interop while the pure-Haskell writer is developed. Do not make it a mandatory core dependency.
EVID: https://hackage.haskell.org/package/duckdb-ffi ; https://hackage.haskell.org/package/duckdb-simple ; https://github.com/sighingnow/duckdb-haskell

## harrow / hs-arrow (Apache Arrow bindings) (Two independent attempts at Haskell bindings to Apache Arrow.)
STATUS: BOTH ABANDONED. litxio/harrow: 1 commit, 5 stars, 0 forks, BSD-3-Clause. stephenpascoe/hs-arrow: 6 commits, 12 stars, 3 forks, LGPL-2.1. Neither is on Hackage. Haskell does NOT appear in Apache Arrow's official implementation list (C GLib, C++, .NET, Go, Java, JavaScript, Julia, MATLAB, Python, R, Ruby, Rust, Swift).
ASSESS: Both are dead on arrival (1 and 6 commits respectively) — proof that binding libarrow from Haskell has been attempted and abandoned twice. Combined with hs-arrow's LGPL license, neither is usable. NET CONCLUSION for the Arrow question: Haskell has NO Arrow IPC/Feather reader, NO Arrow ingestion, and no official upstream presence; the only working Arrow surface is dataframe-arrow's outbound C Data Interface. The two credible paths forward are (a) implement the inbound C Data Interface (cheap, ~ABI-only, no build-time dependency on libarrow by design) and (b) implement Arrow IPC/Feather in pure Haskell, reusing the Thrift/encoding machinery already proven in dataframe-parquet.
EVID: https://github.com/litxio/harrow ; https://github.com/stephenpascoe/hs-arrow ; https://arrow.apache.org/faq/

## DataHaskell org / roadmap / GSoC 2026 (Umbrella community organization now hosting dataframe; publishes an ecosystem roadmap and runs GSoC projects.)
STATUS: Roadmap 'Version 1.0' — the fetched page reports a November 2026 datestamp, which is future-dated relative to today (2026-08-17); TREAT THE DATESTAMP AS UNVERIFIED. Six pillars: core data infrastructure, stats/viz, ML/DL (Hasktorch 0.2.2.0, GHC 9.8 via lts-23.24), distributed computing, developer experience, community. Milestones: Q2 2026 dataframe v1 + benchmarking; Q4 2026 10,000+ monthly downloads and Pandas performance parity; Q2 2027 production case studies. GSoC 2026 lists exactly one data-science idea: 'Parquet for Haskell — a production-grade Apache Parquet reader/writer', mentors mchav and adithyaov, 175h medium / 350h extended.
ASSESS: STRENGTHS: there is now a coordinating body, a written roadmap, GSoC mentorship, and an in-progress Haskell Foundation Tech Proposal — the ecosystem has organizational scaffolding it lacked for a decade. Arrow integration is Phase 1 and Parquet is marked high priority, so a new project's goals would be roadmap-aligned rather than duplicative. WEAKNESSES: the roadmap's own top-listed gap is 'No community of maintainers and contributors', and it asks for funding for maintainer stipends — i.e. the org is aspirational, not resourced. A DataHaskell veteran warned in the HFTP thread that 'too ambitious roadmaps kill unpaid projects'. The HFTP has no formal Haskell Foundation decision announced. FIT: engage early — the marginal contributor has outsized influence here, and the roadmap explicitly names the gaps a new toolkit would fill.
EVID: http://www.datahaskell.org/docs/community/roadmap.html ; https://summer.haskell.org/ideas.html ; https://discourse.haskell.org/t/pre-hftp-proposal-dataframe-library-for-haskell/10973 ; https://www.stackage.org/nightly-2026-06-08/package/hasktorch-0.2.2.0

# sources
https://hackage.haskell.org/package/dataframe
https://github.com/mchav/dataframe
https://api.github.com/repos/mchav/dataframe
https://api.github.com/repos/mchav/dataframe/commits?per_page=20
https://api.github.com/repos/mchav/dataframe/contributors?per_page=20
https://api.github.com/repos/mchav/dataframe/issues?state=open&per_page=30
https://api.github.com/repos/mchav/dataframe/contents/
https://api.github.com/repos/mchav/dataframe/contents/dataframe-arrow
https://api.github.com/repos/mchav/dataframe/contents/python
https://raw.githubusercontent.com/mchav/dataframe/main/README.md
https://raw.githubusercontent.com/mchav/dataframe/main/dataframe.cabal
https://raw.githubusercontent.com/mchav/dataframe/main/dataframe-arrow/dataframe-arrow.cabal
https://raw.githubusercontent.com/mchav/dataframe/main/dataframe-fastcsv/dataframe-fastcsv.cabal
https://raw.githubusercontent.com/mchav/dataframe/main/dataframe-persistent/dataframe-persistent.cabal
https://raw.githubusercontent.com/mchav/dataframe/main/dataframe-core/dataframe-core.cabal
https://raw.githubusercontent.com/mchav/dataframe/main/python/README.md
https://hackage.haskell.org/package/dataframe-core
https://hackage.haskell.org/package/dataframe-core-2.4.0.0
https://hackage-content.haskell.org/package/dataframe-core-2.4.0.0/docs/DataFrame-Internal-Column.html
https://hackage.haskell.org/package/dataframe-parquet
https://hackage-content.haskell.org/package/dataframe-parquet-1.5.0.0/docs/DataFrame-IO-Parquet.html
https://hackage.haskell.org/package/dataframe-lazy
https://hackage.haskell.org/package/dataframe-arrow
https://hackage.haskell.org/package/dataframe/preferred
https://hackage.haskell.org/package/dataframe/changelog
https://hackage.haskell.org/package/ihaskell-dataframe
https://packdeps.haskellers.com/reverse/dataframe
https://dataframe.readthedocs.io/en/latest/dataframes_in_haskell.html
https://discourse.haskell.org/t/initial-feedback-request-dataframe-library/10802
https://discourse.haskell.org/t/ann-dataframe-1-0-0-0/13834
https://discourse.haskell.org/t/pre-hftp-proposal-dataframe-library-for-haskell/10973
https://discourse.haskell.org/t/dataframe-january-2026-updates/13512
https://mchav.github.io/benchmarking-haskell-dataframes/
http://www.datahaskell.org/docs/community/roadmap.html
https://summer.haskell.org/ideas.html
https://hackage.haskell.org/package/Frames
https://github.com/acowley/Frames
https://api.github.com/repos/acowley/Frames/commits?per_page=5
https://hackage.haskell.org/package/javelin
https://hackage.haskell.org/package/javelin-frames
https://api.github.com/repos/laurentRDC/javelin
https://hackage.haskell.org/package/analyze
https://hackage.haskell.org/package/cassava
https://hackage.haskell.org/package/streamly
https://hackage.haskell.org/package/conduit
https://hackage.haskell.org/package/pipes
https://hackage.haskell.org/package/hasql
https://hackage.haskell.org/package/postgresql-simple
https://hackage.haskell.org/package/sqlite-simple
https://hackage.haskell.org/package/duckdb-ffi
https://hackage.haskell.org/package/duckdb-simple
https://github.com/sighingnow/duckdb-haskell
https://github.com/litxio/harrow
https://github.com/stephenpascoe/hs-arrow
https://arrow.apache.org/faq/
https://www.stackage.org/nightly-2026-06-08/package/hasktorch-0.2.2.0
https://www.r-bloggers.com/2025/12/haskell-is-a-great-language-for-data-science/