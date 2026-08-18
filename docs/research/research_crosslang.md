# digest
All facts verified 2026-08-17 via primary sources (GitHub API, Hackage, opam, project docs).

PYTHON. NumPy's win is a memory model, not an API: ndarray = one contiguous buffer + dtype + strides, so slicing yields views not copies, and broadcasting is a shape-compatibility rule (dims equal or 1) executed without materializing copies. Extensibility came later and messily via `__array_ufunc__` (NEP 13) then `__array_function__` (NEP 18); the Consortium's Array API standard (current version 2025.12) supersedes both by specifying a *namespace* rather than dispatch hooks. Polars (39,375 stars; 2,848 open issues; rs-0.55.2 2026-08-06; 1.0 on 2024-07-01) won mindshare on three things, not speed alone: (a) Arrow columnar memory, (b) a *lazy IR* whose documented optimizations are predicate/projection/slice pushdown, common-subplan elimination, expression simplification, join ordering, type coercion, cardinality estimation, and (c) an **expression API** where `Expr` is a first-class value reused unchanged across `select`/`with_columns`/`group_by`/window contexts — Polars explicitly treats "user must pass a lambda" as an API failure, because UDFs are opaque to the optimizer. New streaming engine uses TUM morsel-driven parallelism (~128k-row morsels) with spill-to-disk. pandas answered in 3.0.0 (2026-01-21): copy-on-write is now the only mode, PyArrow-backed `str` dtype, and a `pd.col()` expression builder copied from Polars. Downloads still favour pandas ~755.8M/30d vs polars ~59.8M/30d (secondary). scikit-learn's durable contribution is the 5-principle estimator contract (Buitinck et al. 2013, arXiv:1309.0238): consistency, inspection, non-proliferation of classes, composition, sensible defaults — `fit`/`transform`/`predict` plus `get_params`/`set_params` is what makes `Pipeline`, `GridSearchCV`, `clone` possible. sklearn 1.9.0 (2026-06-02) added **narwhals** as a dependency after Polars deprecated `__dataframe__` in 1.40 — the interchange protocol failed; the thin API-shim layer won.

R. dplyr = fixed verb vocabulary (filter/select/mutate/arrange/summarise/group_by) + tidy evaluation (data masking + tidyselect). Because verbs are a grammar, not methods, the same code retargets to SQL (dbplyr), data.table (dtplyr), Arrow — lazily, materialized only at `collect()`.

JULIA. Cautionary. TTFX was structurally fixed in 1.9 pkgimages but remains **opt-in** per package via PrecompileTools workloads. arXiv:2410.10908 documents fragmentation: AD split across ForwardDiff/Zygote/Enzyme (ChainRulesCore is the shared rule registry, DifferentiationInterface the later facade), plus weak tooling/error messages. Flux 4,735 stars vs Lux 722 = live duplication. Tables.jl is the counter-example: a ~minimal row/column protocol that unified the whole tabular ecosystem.

TYPED FP. Owl: single author (ryanrhymes 3,862 commits vs #2 jzstark 232), founder handed off March 2024, last tag 1.2 (opam 2025-01-13) — technically excellent (functor stack: Ndarray → Algodiff → CGraph), bus factor 1. Breeze README: "mostly retired at this point." DiffSharp last push 2024-04-15. Deedle 8.0.0 (2026-05-18) but 8,822 downloads vs 2.7M lifetime. Spark: Catalyst cannot see through typed-Dataset lambdas, so the untyped DataFrame API won.

HASKELL INCUMBENT: `dataframe` 3.5.0.0 (2026-08-14, DataHaskell org, 261 stars) already ships Arrow C Data Interface, Parquet, three API layers, lazy streaming.

# key_insights
- The reified expression AST is the single most transferable idea in the survey: Polars made `Expr` a first-class inspectable value reused identically across select/with_columns/group_by/window, and pandas 3.0 (2026-01-21) capitulated by adding `pd.col()` — Haskell can express this as a GADT more naturally than either.
- Spark's typed `Dataset[T]` lost to the untyped DataFrame because Catalyst cannot optimize through lambda closures, which is the precise trap a Haskell toolkit will fall into if its flagship API is `row -> value` functions instead of an inspectable plan — types must describe the plan, not hide closures inside it.
- Optimizations are only possible on data you can see, so any API that requires a user-supplied function is an admission of missing vocabulary; Polars states outright that needing a lambda reflects 'a lack of expressiveness of its API'.
- Standardize the memory format at the bottom (Arrow) and the expression vocabulary at the top, but never in the middle: the formally-designed `__dataframe__` interchange protocol was deprecated by Polars 1.40 and dropped by scikit-learn 1.9.0, while the Arrow C Data Interface (two frozen C structs, zero library dependency) and the pragmatic narwhals shim both won.
- The Arrow C Data Interface plus DLPack are the entire interop surface that matters — two copy-into-your-source C structs with explicit release-callback ownership semantics — and implementing them buys zero-copy round-trips with Polars, DuckDB, pandas, PyArrow, R, PyTorch, JAX and CuPy for a few hundred lines.
- scikit-learn's real invention is not fit/predict but hyperparameters-as-inspectable-data (`get_params`/`set_params`), because that is what makes Pipeline, GridSearchCV and clone generic over third-party estimators; in Haskell this comes free from Generic over a plain record and should be locked in before any algorithm is written.
- Owl is the definitive warning: one person wrote 3,862 of its commits (the next contributor has 232), the founder left in March 2024, and a technically superb full numerical stack — three swappable Ndarray backends, a functor stack, nested higher-order AD — has had no release since opam 1.2 on 2025-01-13.
- Breadth built by a single author becomes unmaintainable breadth; the Owl community itself proposed splitting deep learning out so the core could just be numpy/scipy, which is the scope discipline a new project should adopt on day one rather than after burnout.
- A numerical library that sits beside the ecosystem's real data workflow dies regardless of quality: Breeze (3,455 stars) is 'mostly retired at this point' because Scala's data work all flowed into Spark's DataFrame API, and DiffSharp (615 stars) has not been pushed since 2024-04-15 despite correctly reusing LibTorch.
- Backing onto a mature C++ runtime (LibTorch, BLAS/LAPACK, Arrow C++) is the right engineering choice and is never sufficient — Hasktorch and DiffSharp both did it — so the differentiator has to be the workflow and API, not the kernels.
- Time-to-first-result is a P0 product requirement, not an optimization item: Julia's TTFX was structurally fixed in 1.9 pkgimages yet is still opt-in per package via PrecompileTools, the reputational damage persists, and DataHaskell independently names 'time to first plot' plus IHaskell setup as its top friction points in its Q1 2026 assessment.
- Ship the minimal protocol package before the implementation: Julia's Tables.jl unified an entire tabular ecosystem with a tiny row/column interface, and ChainRulesCore did the same for AD rules — whereas Flux (4,735 stars) and Lux (722 stars) duplicating the user-facing layer over shared NNlib/Optimisers backends is the fragmentation to avoid.
- Lux/JAX-style explicit parameters — model as a pure function of (params, state, input) with params as a plain data tree — is free in Haskell and makes optimizers, checkpointing, serialization and vmap fall out; adopt it as the only neural-network API rather than shipping a mutable-state alternative.
- A grammar of fixed verbs beats a bag of methods because it retargets: dplyr's same six verbs execute against R data frames, SQL via dbplyr, data.table via dtplyr, and Arrow — lazily, materializing only at explicit `collect()` — but the NSE machinery that makes it feel good in R must be replaced by typed combinators, not imitated.
- Do not port pandas' implicit row index: it is the design decision pandas spent a major version escaping (copy-on-write became the only mode in 3.0), and Deedle's faithful index-centric port to .NET has 2.7M lifetime downloads but only 8,822 on its current version.
- Version stability is a marketing asset — Polars' explicit 1.0 stable/unstable API split on 2024-07-01 signalled production-readiness, while Deedle shipping 4.0.1 through 8.0.0 between 2026-03-22 and 2026-05-18 signals the opposite.
- Prioritize ONNX inference over ONNX export: loading trained models is a cheap capability multiplier, while export remains genuinely broken upstream (open PyTorch issues on dynamo export failures for transducer decoders, FakeQuantize, and rotary embeddings).
- A Parquet reader that ignores footer row-group min/max/null statistics is a CSV reader with extra steps — pushdown hooks must be wired into the lazy IR from version one, and Parquet is also the format Hugging Face datasets ship in, making it the gateway to real-world data.
- Being callable FROM Python matters more than calling Python: arXiv:2410.10908 identifies one-way interop as a core Julia adoption bottleneck ('the converse is often extremely difficult and unintuitive'), and the Arrow C Data Interface plus a C-ABI shim is the concrete way a Haskell toolkit avoids that trap.
- BLOCKING FINDING FOR THIS PROJECT: the 'empty repo' premise has a live, well-advanced incumbent — Haskell `dataframe` 3.5.0.0 (Hackage, 2026-08-14; DataHaskell org, 261 stars) already ships the Arrow C Data Interface, Parquet with Hugging Face reads, three API layers including a fully schema-tracked `DataFrame.Typed`, a lazy query engine that finishes the 1-billion-row challenge in ~10 minutes, and basic ML — so the project must differentiate or collaborate, not silently rebuild.
- The incumbent's published design doc already litigated the central Haskell question and chose runtime-typed GADT columns over type-level schemas, arguing Frames 'has a syntax that looks more like an advanced Haskell tool than a data science tool' — any new project going type-level-first must answer that argument with evidence, not taste.
- The genuinely unfilled gaps in Haskell DS as of 2026-08-17 are the reusable contracts, not the containers: a scikit-learn-style estimator/pipeline protocol, a Polars-style optimizer IR, DLPack tensor exchange, and a single ChainRulesCore-equivalent AD rule registry — none of which currently exist, while hmatrix's last release was 2021-03-08 and massiv 1.0.5.0 dates to 2025-05-31.

# libraries

## NumPy (Reference n-d array: contiguous buffer + dtype + strides, views, broadcasting, ufuncs)
STATUS: Actively maintained; docs current at v2.5 (numpy.org/doc/stable). Extension protocols NEP 13 (__array_ufunc__) and NEP 18 (__array_function__) are legacy; NEP 47 / the Array API standard is the forward path.
ASSESS: STRENGTH: the whole ecosystem hangs off a *memory layout contract* (offset = sum(stride_k * n_k)), not off classes — any library can produce/consume the buffer. Slicing returns views (`base` attribute tracks ownership); broadcasting is a pure shape rule (dims equal or one of them 1) that avoids copies. WEAKNESS: extensibility was retrofitted three times (NEP13 -> NEP18 -> NEP47) because dispatch was not designed in. LESSON FOR HASKELL: design the strided-view + dtype contract and the dispatch/backend story on day one; Haskell can express the strided view as a real type (shape/stride/offset over a pinned ByteArray#) rather than convention.
EVID: https://numpy.org/doc/stable/reference/arrays.ndarray.html ; https://numpy.org/doc/stable/user/basics.broadcasting.html ; https://numpy.org/neps/nep-0018-array-function-protocol.html ; https://numpy.org/neps/nep-0047-array-api-standard.html

## Python Array API Standard (data-apis) (Cross-library array namespace spec so downstream code works on numpy/cupy/torch/jax alike)
STATUS: Current version 2025.12 (data-apis.org/array-api/latest). Consumed in production: scikit-learn 1.9.0 expanded Array API support to LogisticRegression, LinearRegression, Ridge, RidgeClassifier, LDA, PoissonRegressor, several metrics and scalers.
ASSESS: Proof that a *specification* separate from any implementation is the durable artifact. Notably it abandoned the hook-based dispatch of NEP 13/18 in favour of 'pass me a namespace' — closer to a Haskell typeclass/record-of-functions than to OO dispatch. LESSON: a new Haskell toolkit should define an `Array`/`Tensor` class (or backend record) whose surface is deliberately a subset, and version it (YYYY.MM), rather than exporting one concrete type.
EVID: https://data-apis.org/array-api/latest/ ; https://scikit-learn.org/stable/whats_new/v1.9.html

## pandas (Incumbent Python dataframe)
STATUS: 3.0.0 released 2026-01-21; 3.0.5 published 2026-07-22. Copy-on-Write is now the default AND only mode; string columns infer to a PyArrow-backed `str` dtype; chained assignment raises; requires Python >= 3.11; new `pd.col()` expression builder.
ASSESS: WEAKNESSES that created the opening for Polars: NumPy-backed row/object memory, an implicit row Index that leaks into every operation, eager single-threaded execution, no query optimizer, `object` dtype strings, and copy-vs-view ambiguity that took ~5 years and a major version to fix. STRENGTH: an enormous, forgiving surface that beginners can flail in. LESSON: pandas 3.0 adopting Polars' expression builder and Arrow strings shows which design was right — start where pandas ended up, not where it began. Do NOT ship an implicit row index.
EVID: https://pandas.pydata.org/docs/whatsnew/v3.0.0.html ; https://github.com/pandas-dev/pandas/releases/latest

## Polars (Rust/Arrow dataframe + query engine; the mindshare winner)
STATUS: Very active. GitHub 39,375 stars / 3,022 forks / 2,848 open issues, last push 2026-08-17. Latest Rust release rs-0.55.2 (2026-08-06); Python py-1.43.0 (2026-07-21). 1.0 shipped 2024-07-01 with an explicit stable/unstable API split. Deprecated the `__dataframe__` interchange protocol in 1.40.
ASSESS: THE model to copy. Three separable design wins: (1) Arrow columnar memory => zero-copy handoff and no bespoke dtype zoo; (2) LazyFrame is a real IR with documented rewrites — predicate pushdown, projection pushdown, slice pushdown, common-subplan elimination, expression simplification/constant folding, join ordering, type coercion, cardinality estimation; (3) the **expression API**: `Expr` is a first-class, composable, inspectable value that means the same thing in `select`, `with_columns`, `group_by(...).agg`, and `over(...)` windows. Polars states that needing a Python lambda is 'a lack of expressiveness of its API' because UDFs cannot be logically optimized. New streaming engine = TUM morsel-driven parallelism, ~128k-row morsels, spillable sinks, out-of-core group-by/join/sort. LESSON: in Haskell, `Expr` should be a GADT/free-applicative AST interpreted by backends — this is the single highest-leverage thing to steal, and Haskell is *better* suited to it than Python is.
EVID: https://docs.pola.rs/user-guide/lazy/optimizations/ ; https://pola.rs/posts/announcing-polars-1/ ; https://github.com/pola-rs/polars/releases/tag/py-1.40.0 ; https://api.github.com/repos/pola-rs/polars ; https://docs.pola.rs/user-guide/migration/pandas/

## scikit-learn (The reusable ML API pattern: estimator / predictor / transformer + pipelines)
STATUS: 1.9.0 released 2026-06-02. Took `narwhals` as a new hard dependency to handle dataframe in/out for `set_output`, explicitly because 'the dataframe interchange protocol (__dataframe__) ... got deprecated by polars and has run its course'.
ASSESS: The canonical evidence is Buitinck et al. 2013 (arXiv:1309.0238), which names five principles: consistency, inspection, non-proliferation of classes, composition, sensible defaults. The mechanism that actually makes it compose is small: `fit` returns self and writes trailing-underscore attributes; `get_params`/`set_params` expose hyperparameters as plain data; therefore `Pipeline`, `ColumnTransformer`, `GridSearchCV`, and `clone` are generic and third-party estimators drop in for free. 'Non-proliferation of classes' — data is arrays, hyperparameters are strings/numbers — is what kept the type surface small. LESSON FOR HASKELL: the analogue is a typeclass or record-of-functions `Estimator p m` where hyperparameters `p` are a plain, serializable, inspectable record and `fit :: p -> Data -> m Model`; the *inspectability of hyperparameters as data* is what enables tuning/serialization, and Haskell gets it free via Generic. Adopt this before writing a single algorithm.
EVID: https://arxiv.org/abs/1309.0238 ; https://scikit-learn.org/stable/developers/develop.html ; https://scikit-learn.org/stable/whats_new/v1.9.html

## Narwhals (Zero-dependency compatibility shim exposing a Polars-subset API over pandas/Polars/PyArrow/DuckDB/PySpark/Dask/Ibis)
STATUS: Actively developed and now depended on by scikit-learn 1.9.0; also used by Altair, Bokeh, Plotly, Marimo.
ASSESS: The most instructive recent datapoint in the whole survey: the formally-designed `__dataframe__` interchange protocol DIED (deprecated by Polars 1.40) while a pragmatic API-translation shim with zero dependencies got adopted by scikit-learn as a dependency. LESSON: standardize the *memory format* (Arrow) at the bottom and the *expression vocabulary* at the top; a middle-layer 'interchange object protocol' is the layer that fails.
EVID: https://narwhals-dev.github.io/narwhals/ ; https://scikit-learn.org/stable/whats_new/v1.9.html ; https://github.com/pola-rs/polars/releases/tag/py-1.40.0

## dplyr / tidyverse (R) (Grammar of data manipulation; the interactive-use gold standard)
STATUS: Actively maintained; the ecosystem paper is Wickham et al., 'Welcome to the Tidyverse', JOSS, 2019-11-21.
ASSESS: STRENGTH: a small closed verb set (filter, select, mutate, arrange, summarise, group_by) that composes by pipeline. Because verbs form a grammar rather than methods on one type, dbplyr retargets them to SQL, dtplyr to data.table, and the arrow package to Arrow — all lazily, executing only at `collect()`. Tidy evaluation splits cleanly into 'data masking' (bare column names evaluated in a data mask) and 'tidy selection' (a mini-DSL for choosing columns by name/position/type). WEAKNESS FOR HASKELL: NSE/quasiquotation is exactly what Haskell cannot and should not imitate; the naming ergonomics must come from typed expression combinators or OverloadedLabels/OverloadedRecordDot, not metaprogramming. LESSON: steal the *closed verb vocabulary + multi-backend retargeting + explicit collect()*, discard the evaluation trickery.
EVID: https://dplyr.tidyverse.org/articles/programming.html ; https://dbplyr.tidyverse.org/articles/translation-verb.html ; https://joss.theoj.org/papers/10.21105/joss.01686

## DataFrames.jl + Tables.jl (Julia) (Julia tabular data and the minimal table protocol beneath it)
STATUS: DataFrames.jl active: 1,830 stars, 160 open issues, last push 2026-08-12 (created 2012).
ASSESS: Tables.jl is Julia's best ecosystem decision: a deliberately tiny row/column-access interface that DataFrames.jl, TypedTables.jl, CSV.jl, Query.jl and others all implement, so consumers work against any table. It is the structural analogue of Arrow-at-the-bottom but at the *type* level. LESSON: define the minimal Haskell `Table` class (schema + column access + row iteration) as a separate, dependency-light package released BEFORE any concrete dataframe, so competing implementations cannot fork the ecosystem.
EVID: https://github.com/JuliaData/Tables.jl ; https://api.github.com/repos/JuliaData/DataFrames.jl ; https://dataframes.juliadata.org/stable/

## Flux.jl (Julia's original deep learning framework (implicit params inside model structs))
STATUS: Active: 4,735 stars, 44 open issues, last push 2026-08-16 (created 2016).
ASSESS: Works, but shares the field with Lux.jl — two frameworks over the same NNlib.jl/Optimisers.jl backends. That duplication splits maintainer attention and documentation in a community already an order of magnitude smaller than Python's. LESSON: one model API, many backends — never two model APIs over one backend.
EVID: https://api.github.com/repos/FluxML/Flux.jl ; https://fluxml.ai/Flux.jl/stable/ecosystem/

## Lux.jl (Explicit-parameter reimagining of Flux (model / params tree / state tree separated))
STATUS: Active: 722 stars, 100 open issues, last push 2026-08-10 (created 2022).
ASSESS: Technically the better design for a *pure functional* toolkit — the model is a pure function of (params, state, input), which is exactly what Haskell wants and what JAX/Equinox converged on. But its existence alongside Flux is the fragmentation lesson: Lux shares Flux's NNlib/Optimisers backends yet duplicates the user-facing layer. LESSON FOR HASKELL: adopt Lux/JAX-style explicit params-as-data from the start (it is free in Haskell, and makes optimizers, checkpointing and vmap trivial), and do not ship a mutable-state alternative.
EVID: https://api.github.com/repos/LuxDL/Lux.jl ; https://lux.csail.mit.edu/stable/manual/autodiff

## Julia TTFX / precompilation (The canonical 'onboarding latency kills adoption' case study)
STATUS: Structurally addressed in Julia 1.9+ (native code cached into pkgimages) but the fix is OPT-IN: package authors must add PrecompileTools.jl precompile workloads to get it.
ASSESS: The technical fix landed years ago and the reputational damage persists; 'time to first plot' is still the phrase people use. Note DataHaskell independently names 'time to first plot' as a top Haskell friction point (Q1 2026 post), alongside IHaskell setup and toolchain management. LESSON: treat first-run latency, install time, and REPL/notebook startup as P0 product requirements with measured budgets, not as an optimization backlog item. For Haskell that means: no mandatory C++ toolchain build, binary-cacheable deps, and a working `ghci`/notebook path in one command.
EVID: https://github.com/JuliaLang/PrecompileTools.jl ; https://docs.julialang.org/en/v1/manual/performance-tips/ ; https://www.datahaskell.org/blog/2026/01/12/state-of-datahaskell-q1-2026.html

## Julia SciML/AD ecosystem (ChainRules, Zygote, Enzyme, DifferentiationInterface) (Autodiff layer)
STATUS: ChainRulesCore.jl is the shared backend-agnostic rule registry; Zygote's own @adjoint primitives take precedence over rrules; Enzyme imports frules/rrules but its rule-writing differs because of activity annotations; DifferentiationInterface.jl succeeds AbstractDifferentiation.jl as a generic facade.
ASSESS: arXiv:2410.10908 ('The State of Julia for Scientific Machine Learning', Berman & Ginesin) documents the cost: 'Navigating the maze of different tools is often counter intuitive'; forward and reverse mode live in separate packages; testing infrastructure is 'significantly less mature' than pytest/unittest; error messages and stack traces are a 'continually unaddressed pain point'; reverse interop (calling Julia from Python) is 'extremely difficult'. LESSON: publish ONE rule-registration interface (the ChainRulesCore analogue) as a tiny package before any AD backend exists, and make interop bidirectional from day one — being callable from Python is worth more than calling Python.
EVID: https://arxiv.org/html/2410.10908v1 ; https://juliadiff.org/ChainRulesCore.jl/stable/ ; https://juliadiff.org/DifferentiationInterface.jl/DifferentiationInterface/

## Apache Arrow (columnar format + IPC) (The mandatory in-memory/interchange standard)
STATUS: Very active. Latest release apache-arrow-25.0.1, 2026-08-10. Implementations in C++, C#, Go, Java, JavaScript, Julia, Rust, Swift plus C/GLib, MATLAB, Python, R, Ruby bindings.
ASSESS: Arrow's own justification is the ecosystem thesis in one line: 'Without a standard columnar data format, every database and language has to implement its own internal data format', yielding no-cost transfer, no per-system connectors, and cross-language algorithm reuse. VERDICT: non-negotiable. A 2026 DS toolkit whose in-memory column layout is not Arrow-compatible is choosing to be an island. Parquet, Polars, DuckDB, Spark, pandas 3.0 strings, and ADBC all assume it.
EVID: https://arrow.apache.org/overview/ ; https://api.github.com/repos/apache/arrow/releases/latest

## Arrow C Data Interface (Frozen-ABI zero-copy handoff: two plain C structs, ArrowSchema and ArrowArray)
STATUS: Stable and frozen post-release; explicitly designed to be copied into a project with no compile-time or runtime dependency on any Arrow library. Companion Arrow C Stream Interface covers multi-batch streams.
ASSESS: THE cheapest possible entry ticket for a new language ecosystem, and the single highest-ROI first deliverable. ArrowSchema carries format string / name / metadata / flags / children / dictionary / release; ArrowArray carries length / null_count / offset / buffers / children / dictionary / release. Ownership is explicit: the producer allocates and owns, the consumer calls `release`, which recursively frees and NULLs itself; `private_data` is the producer's bookkeeping. Bitwise-moving the struct and NULLing the source transfers ownership. LESSON: implement this FIRST — it buys zero-copy round-trips with Polars, DuckDB, pandas, PyArrow and R for the cost of two structs and an FFI shim, and it is exactly the kind of resource-ownership contract Haskell's ForeignPtr/bracket idioms handle well. Note the Haskell `dataframe` package already ships it.
EVID: https://arrow.apache.org/docs/format/CDataInterface.html

## ADBC (Arrow Database Connectivity) (Arrow-native database client API; the ODBC/JDBC replacement for analytics)
STATUS: Spec at version 1.1.0, semantically versioned separately from driver components. Implementations in C/C++, C#/.NET, Go, Java, Python, Ruby; drivers for PostgreSQL, SQLite and any Flight SQL system.
ASSESS: Key property: 'result sets of queries in ADBC are all returned as streams of Arrow data, not row-by-row' — which removes the per-row marshalling tax that makes every language's DB layer slow. For a Haskell toolkit, an ADBC binding is a cheaper, higher-value path to 'read from real databases' than writing native drivers, and it lands data already in the toolkit's columnar representation.
EVID: https://arrow.apache.org/docs/format/ADBC.html ; https://arrow.apache.org/adbc/

## Apache Parquet (De facto on-disk columnar format)
STATUS: Ubiquitous default in Spark, DuckDB, pandas, Arrow, Snowflake, BigQuery, Athena, Databricks, Trino, Presto (secondary sources).
ASSESS: Structure that matters for implementation: file -> row groups (~64-512 MB) -> per-column chunks -> pages; per-row-group min/max/null-count statistics in the footer drive predicate pushdown, and Parquet 2.x adds page indexes, column indexes and Bloom filters. Column pruning plus row-group skipping is where the 80-95% I/O reduction comes from — i.e. the reader must expose pushdown hooks to the query planner, not just decode bytes. Reported 70-90% size reduction vs uncompressed CSV. LESSON: a Parquet reader that ignores footer statistics is a CSV reader with extra steps; wire scan-level pushdown into the lazy IR from the first version. Also: this is the format Hugging Face datasets ship in, so it is the gateway to real data.
EVID: https://clickhouse.com/resources/engineering/columnar-storage-formats ; https://motherduck.com/learn/why-choose-parquet-table-file-format/ ; https://arrow.apache.org/docs/format/CDataInterface.html

## DLPack (Frozen C struct for zero-copy tensor exchange across frameworks and devices)
STATUS: v1.3 released 2026-01-26 (capsule-convention update). Adopted by NumPy, CuPy, PyTorch, TensorFlow, MXNet, TVM, JAX, Paddle, mpi4py, Hidet; device coverage includes CPU, CUDA, ROCm, Metal, Vulkan, OpenCL, WebGPU.
ASSESS: The tensor-side twin of Arrow's C Data Interface: only a pointer plus shape/dtype/strides/device metadata crosses the boundary, no bytes copied. Producers expose `__dlpack__` and `__dlpack_device__`. VERDICT: this is how a Haskell tensor type talks to PyTorch/JAX/CuPy without owning a GPU stack. Implement DLPack import/export for the tensor type and Arrow C Data for the dataframe type — those two structs are the entire interop surface that matters.
EVID: https://github.com/dmlc/dlpack/releases/latest ; https://dmlc.github.io/dlpack/latest/ ; https://docs.cupy.dev/en/stable/user_guide/interoperability.html ; https://arrow.apache.org/docs/python/dlpack.html

## ONNX (Portable trained-model graph format + opset)
STATUS: v1.22.0 released 2026-06-15, adding LinearAttention-27 and CausalConvWithState-27 to opset 27, plus shape-inference hardening and SLSA provenance.
ASSESS: MIXED. As a *consumption* target it is genuinely valuable: an ONNX runtime binding lets a Haskell toolkit run models it could never train. As an *export* target it is leaky — PyTorch's `torch.onnx.export(dynamo=True)` still fails on real architectures (open pytorch issues #168969, #167063, #145100 cover transducer decoders, FakeQuantize, and rotary-embedding ops). LESSON: prioritize ONNX *inference* (load-and-run) over ONNX *export*; treat it as a deployment/consumption bridge, not as the ecosystem's interchange backbone — that role belongs to Arrow and DLPack.
EVID: https://github.com/onnx/onnx/releases/latest ; https://github.com/pytorch/pytorch/issues/168969 ; https://github.com/pytorch/pytorch/issues/145100

## Apache Spark (Scala) (Distributed analytics; the typed-vs-untyped API natural experiment)
STATUS: Active: 4.0.0 shipped, 4.0.2 on 2026-02-05, 4.0.3 on 2026-06-11, 4.1.0 released. 4.0 resolved 5,100+ tickets from 390+ contributors.
ASSESS: THE most directly relevant cautionary tale for a typed-FP DS toolkit. Spark shipped BOTH a strongly typed `Dataset[T]` and an untyped `DataFrame` (= `Dataset[Row]`). Catalyst treats typed-lambda operations as a black box and does not optimize through them — predicate pushdown and projection pruning are lost, plus encoder serialization overhead — so the untyped, declarative API is the faster one and the one that won. LESSON FOR HASKELL, stated bluntly: types must describe the *plan*, not hide arbitrary closures inside it. A `Expr`-style reified AST (inspectable, optimizable) with types on the outside beats `a -> b` functions with types on the inside. Do not repeat the Dataset mistake by making the flagship API 'just write a Haskell lambda over each row'.
EVID: https://spark.apache.org/releases/spark-release-4-0-0.html ; https://www.databricks.com/blog/2016/07/14/a-tale-of-three-apache-spark-apis-rdds-dataframes-and-datasets.html ; https://spark.apache.org/news/

## Breeze (Scala) (Scala's numerical processing library (linalg, optimization); ScalaNLP core)
STATUS: EFFECTIVELY RETIRED. README states Breeze is 'mostly retired at this point'; maintainer @dlwh: 'I will review bug fix PRs and sometimes answer questions, but that's about all I can offer' and 'If someone wants to take of the reins I'd be happy to hand it off.' Repo description literally reads 'Breeze is/was a numerical processing library for Scala.' Last push 2025-10-04; 3,455 stars; 89 open issues; latest 2.1.0 cross-built for Scala 3.1/2.13/2.12; visualization code deprecated.
ASSESS: A 3,455-star library in a language with major industry deployment still could not sustain a numerical stack, because the DS work in Scala all flowed to Spark's DataFrame API instead. LESSON: a typed-FP numerical library that is not on the path of the ecosystem's actual data workflow will not survive on technical merit. Scala had no successor either — Saddle and Spire cover fragments, ND4J is a JVM bridge. Corollary for Haskell: the toolkit must BE the data path (ingest -> transform -> model), not a matrix library beside it.
EVID: https://github.com/scalanlp/breeze ; https://api.github.com/repos/scalanlp/breeze ; https://index.scala-lang.org/scalanlp/breeze

## Owl (OCaml) — STUDY CLOSELY (Full OCaml numerical stack: Ndarray, linalg, stats, ODE, FFT, Algodiff, optimization, regression, neural networks/NLP, dataframe, plotting)
STATUS: Alive but fragile. Repo not archived, last push 2026-08-05, 1,350 stars, 45 open issues, MIT. Latest tag 1.2, published to opam 2025-01-13 — no new release in ~19 months. Founder Liang Wang (@ryanrhymes) announced the project's conclusion, then in March 2024 Jianxin Zhao (@jrzhao42) took over: 'I will assume the role of project leader to ensure Owl remains maintained.' README: 'we aim to actively maintain it and keep it stable, utilizing the limited time and human resource we have.'
ASSESS: WHAT HAPPENED: one person built essentially all of it. Contributor counts: ryanrhymes 3,862 commits; jzstark 232; tachukao 79; mseri 69; mor1 28 — a bus factor of 1, and the bus left. The design paper is single-authored (Liang Wang, arXiv:1707.09616, 'Owl: A General-Purpose Numerical Library in OCaml', 2017), originating from a Cambridge Computer Lab project. TECHNICALLY EXCELLENT and worth copying: three interchangeable Ndarray implementations (OCaml+C for speed, pure-OCaml `owl-base`, and a CGraph-Ndarray for symbolic/lazy TensorFlow-v1-style graphs); a **functor stack** where memory management and graph optimization are added by layering modules — the OCaml analogue of Haskell typeclass/backend abstraction; Algodiff implements nested forward+reverse AD with arbitrary higher-order derivatives, parameterized over the Ndarray module. THE LESSONS: (1) technical brilliance does not create an ecosystem — Owl has more numerical surface area than most Haskell users will ever build, and it still stalled; (2) breadth built by one author becomes unmaintainable breadth (thread on Discourse proposed splitting deep learning out so Owl could focus on being numpy/scipy); (3) governance and contributor onboarding are the deliverable, not an afterthought; (4) Owl invested in its own vertical stack rather than in interop — no Arrow C Data Interface, no DLPack — so it could never borrow the outside world's momentum. Design the Haskell project to be maintainable by five part-timers and to import external work, not to be a monument.
EVID: https://github.com/owlbarn/owl ; https://api.github.com/repos/owlbarn/owl ; https://api.github.com/repos/owlbarn/owl/contributors ; https://api.github.com/repos/owlbarn/owl/tags ; https://opam.ocaml.org/packages/owl/ ; https://discuss.ocaml.org/t/owl-project-restructured/14226 ; https://arxiv.org/abs/1707.09616 ; https://link.springer.com/chapter/10.1007/978-1-4842-8853-5_6

## Deedle (F#/.NET) (Typed data frame + time series for .NET)
STATUS: Alive but small. Not archived; last push 2026-08-02; 1,007 stars, 8 open issues. NuGet 8.0.0 published 2026-05-18; version churn 4.0.1 (2026-03-22) -> 8.0.0 (2026-05-18) in two months. Lifetime downloads 2.7M, but 3.0.0 (2023-01-17) alone accounts for 578,425 while the current 8.0.0 has only 8,822.
ASSESS: The download curve is the finding: a decade of accumulated installs, a current-version user base in the thousands. Deedle imitated pandas' design (row index + heterogeneous typed columns) in a typed language and got a competent library nobody switched to — .NET data work went to Spark/Python or to Microsoft.Data.Analysis. Five major versions in five months also signals API instability at exactly the moment a library needs to look dependable. LESSON: (a) do not port pandas' index-centric design; (b) version stability is a marketing asset — Polars' explicit 1.0 stable/unstable split (2024-07-01) is the model.
EVID: https://api.github.com/repos/fslaborg/Deedle ; https://www.nuget.org/packages/Deedle

## DiffSharp (F#) (Differentiable tensor programming for .NET; torch-backed autodiff)
STATUS: STALE. Last push 2024-04-15 — approximately 2 years 4 months ago as of 2026-08-17. 615 stars, 37 open issues, not archived. A successor/rename effort 'Furnace' surfaced in F# Weekly Feb 2025; status not independently confirmed.
ASSESS: DiffSharp did the technically right thing — reuse LibTorch as backend rather than reimplement kernels — and still stalled, because the .NET DS user base never reached critical mass and the project depended on a small academic team. Note the parallel with Hasktorch (also LibTorch-backed, also small). LESSON: backing onto a mature C++ tensor runtime is the correct engineering choice and is NOT sufficient; the bottleneck is users and contributors, and 615 stars over a decade is the honest ceiling for a typed-FP autodiff library that offers no workflow advantage over PyTorch.
EVID: https://api.github.com/repos/DiffSharp/DiffSharp ; https://diffsharp.github.io/ ; https://sergeytihon.com/2025/02/16/f-weekly-7-2025-furnace-tensor-library-with-support-for-differentiable-programming/

## Haskell `dataframe` (DataHaskell) — INCUMBENT, READ BEFORE STARTING (Haskell dataframe library: CSV/Parquet/JSON, untyped + typed + monadic APIs, lazy streaming, basic ML)
STATUS: Very active. Hackage 3.5.0.0 uploaded 2026-08-14, maintainer mchav (mschavinda@gmail.com). GitHub DataHaskell/dataframe: created 2024-02-24, last push 2026-08-14, 261 stars, 49 forks, 25 open issues. v1.0.0.0 announced 2026-03-22 after ~2 years of work. Split into dataframe-core / -csv / -parquet / -learn / -operations, plus dataframe-persistent, dataframe-hasktorch, dataframe-symbolic-regression.
ASSESS: CRITICAL FOR THIS PROJECT: the 'empty repo, brand-new Haskell DS toolkit' premise has a live incumbent that already ships (a) Apache Arrow **C Data Interface** for zero-copy round-trips with Python/Polars, (b) Parquet including Hugging Face dataset reads, (c) three API layers over one DataFrame type — untyped, `DataFrame.Typed` with full compile-time schema tracking, and monadic, (d) lazy/query-engine execution that completes the one-billion-row challenge in ~10 minutes without OOM, (e) decision trees, k-means, linear models, k-folds/random-split. Its published design doc explicitly rejects type-level schemas as the default: it says Frames 'has a syntax that looks more like an advanced Haskell tool than a data science tool' and chooses heterogeneous GADT columns with runtime type information, 'to keep the implementation as close to vanilla Haskell as possible', prioritizing 'domain, domain domain'. DataHaskell's own roadmap page (Version 1.0, stamped 'November 2026' — a future date relative to 2026-08-17, so treat the stamp as unverified) names dataframe, Hasktorch and distributed-process as its three pillars and targets Pandas parity by end-2026. STRATEGIC READ: differentiate or collaborate, but do not silently rebuild this. The genuinely open gaps are the ones nobody has filled: a scikit-learn-style estimator/pipeline contract, a Polars-style reified `Expr` optimizer IR, DLPack, and a unified AD rule registry.
EVID: https://hackage.haskell.org/package/dataframe ; https://api.github.com/repos/mchav/dataframe ; https://discourse.haskell.org/t/ann-dataframe-1-0-0-0/13834 ; https://discourse.haskell.org/t/dataframe-january-2026-updates/13512 ; https://dataframe.readthedocs.io/en/latest/dataframes_in_haskell.html ; http://www.datahaskell.org/docs/community/roadmap.html

## Hasktorch (Haskell bindings to LibTorch (PyTorch's C++ core), typed and untyped tensors)
STATUS: Active: last push 2026-07-28, 1,211 stars, 90 open issues, not archived. Hackage package `hasktorch` plus `libtorch-ffi`.
ASSESS: Architecture worth copying: rather than hand-writing FFI, it code-generates bindings by parsing PyTorch's `Declarations.yaml`, with an inline-cpp fork for the C++ boundary — so it tracks upstream LibTorch as the API evolves. It supports both typed (shape/dtype in types) and untyped tensors, which is precisely the dual-API pattern a Haskell toolkit needs. RISK: heavyweight LibTorch dependency is a direct hit on install time / time-to-first-result, the exact friction DataHaskell itself flags. FIT: the right partner for the deep-learning tier; do not rebuild a tensor backend.
EVID: https://api.github.com/repos/hasktorch/hasktorch ; https://hackage.haskell.org/package/hasktorch ; https://www.stackbuilders.com/insights/hasktorch-libtorch-haskell-bindings-for-deep-learning-using-ffi/

## hmatrix (Haskell BLAS/LAPACK linear algebra, with a statically-dimension-checked variant)
STATUS: STALE. Latest version 0.20.2, uploaded 2021-03-08 — over five years old as of 2026-08-17. Maintainer Dominic Steinitz. No deprecated versions and no preferred version ranges on Hackage.
ASSESS: Still the default answer for 'linear algebra in Haskell', which is itself the problem: a five-year-old release means no GHC-9.x-era maintenance signal, and its `Static` module is the existing precedent for dimension-checked matrices. FIT AS FOUNDATION: usable for LAPACK-backed decompositions, but building a 2026 toolkit's core array type on it would inherit a stalled dependency and a non-Arrow memory layout. Prefer a fresh Arrow-compatible buffer type with BLAS/LAPACK called through FFI directly.
EVID: https://hackage.haskell.org/package/hmatrix ; https://hackage.haskell.org/package/hmatrix/preferred

## massiv (Haskell multi-dimensional arrays with fusion, stencils, and parallel computation)
STATUS: Maintained: 1.0.5.0 uploaded 2025-05-31, maintainer Alexey Kuleshevich (lehins).
ASSESS: The strongest existing Haskell candidate for the n-d array tier: real multi-dimensional indexing, delayed/manifest representation distinction (Haskell's answer to views-vs-copies), fusion, stencils, and built-in parallelism. GAPS relative to NumPy: no dtype-level Arrow compatibility, no broadcasting semantics as a first-class rule, no dispatch/backend standard, no GPU story. FIT: a plausible CPU array backend to wrap rather than replace, provided the toolkit owns the public `Array` interface itself so backends stay swappable. Relevant enabler: GHC 9.12+ added 128-bit SIMD vector primops to the x86-64 native code generator (shuffle, FMA, and/or/xor), narrowing the historical 'Haskell can't vectorize' objection.
EVID: https://hackage.haskell.org/package/massiv ; https://gitlab.haskell.org/ghc/ghc/-/merge_requests/12860 ; https://minoki.github.io/posts/2025-01-13-ghc-simd.html

# sources
https://numpy.org/doc/stable/reference/arrays.ndarray.html
https://numpy.org/doc/stable/user/basics.broadcasting.html
https://numpy.org/neps/nep-0018-array-function-protocol.html
https://numpy.org/neps/nep-0013-ufunc-overrides.html
https://numpy.org/neps/nep-0047-array-api-standard.html
https://data-apis.org/array-api/latest/
https://pandas.pydata.org/docs/whatsnew/v3.0.0.html
https://api.github.com/repos/pandas-dev/pandas/releases/latest
https://docs.pola.rs/user-guide/lazy/optimizations/
https://docs.pola.rs/user-guide/migration/pandas/
https://pola.rs/posts/announcing-polars-1/
https://github.com/pola-rs/polars/releases/tag/py-1.40.0
https://api.github.com/repos/pola-rs/polars
https://api.github.com/repos/pola-rs/polars/releases/latest
https://deepwiki.com/pola-rs/polars/5.2-streaming-engine
https://arxiv.org/abs/1309.0238
https://scikit-learn.org/stable/developers/develop.html
https://scikit-learn.org/stable/whats_new/v1.9.html
https://api.github.com/repos/scikit-learn/scikit-learn/releases/latest
https://narwhals-dev.github.io/narwhals/
https://dplyr.tidyverse.org/articles/programming.html
https://dbplyr.tidyverse.org/articles/translation-verb.html
https://joss.theoj.org/papers/10.21105/joss.01686
https://arxiv.org/html/2410.10908v1
https://github.com/JuliaLang/PrecompileTools.jl
https://docs.julialang.org/en/v1/manual/performance-tips/
https://github.com/JuliaData/Tables.jl
https://api.github.com/repos/JuliaData/DataFrames.jl
https://api.github.com/repos/FluxML/Flux.jl
https://api.github.com/repos/LuxDL/Lux.jl
https://lux.csail.mit.edu/stable/manual/autodiff
https://juliadiff.org/ChainRulesCore.jl/stable/
https://juliadiff.org/DifferentiationInterface.jl/DifferentiationInterface/
https://arrow.apache.org/overview/
https://arrow.apache.org/docs/format/CDataInterface.html
https://arrow.apache.org/docs/format/ADBC.html
https://arrow.apache.org/docs/python/dlpack.html
https://api.github.com/repos/apache/arrow/releases/latest
https://clickhouse.com/resources/engineering/columnar-storage-formats
https://motherduck.com/learn/why-choose-parquet-table-file-format/
https://github.com/dmlc/dlpack/releases/latest
https://dmlc.github.io/dlpack/latest/
https://docs.cupy.dev/en/stable/user_guide/interoperability.html
https://github.com/onnx/onnx/releases/latest
https://github.com/pytorch/pytorch/issues/168969
https://github.com/pytorch/pytorch/issues/145100
https://spark.apache.org/releases/spark-release-4-0-0.html
https://spark.apache.org/news/
https://www.databricks.com/blog/2016/07/14/a-tale-of-three-apache-spark-apis-rdds-dataframes-and-datasets.html
https://github.com/scalanlp/breeze
https://api.github.com/repos/scalanlp/breeze
https://index.scala-lang.org/scalanlp/breeze
https://github.com/owlbarn/owl
https://api.github.com/repos/owlbarn/owl
https://api.github.com/repos/owlbarn/owl/contributors
https://api.github.com/repos/owlbarn/owl/tags
https://opam.ocaml.org/packages/owl/
https://discuss.ocaml.org/t/owl-project-restructured/14226
https://arxiv.org/abs/1707.09616
https://link.springer.com/chapter/10.1007/978-1-4842-8853-5_6
https://ocaml.xyz/
https://api.github.com/repos/fslaborg/Deedle
https://www.nuget.org/packages/Deedle
https://api.github.com/repos/DiffSharp/DiffSharp
https://diffsharp.github.io/
https://sergeytihon.com/2025/02/16/f-weekly-7-2025-furnace-tensor-library-with-support-for-differentiable-programming/
https://hackage.haskell.org/package/dataframe
https://api.github.com/repos/mchav/dataframe
https://discourse.haskell.org/t/ann-dataframe-1-0-0-0/13834
https://discourse.haskell.org/t/dataframe-january-2026-updates/13512
https://dataframe.readthedocs.io/en/latest/dataframes_in_haskell.html
http://www.datahaskell.org/docs/community/roadmap.html
https://www.datahaskell.org/blog/2026/01/12/state-of-datahaskell-q1-2026.html
https://api.github.com/repos/hasktorch/hasktorch
https://hackage.haskell.org/package/hasktorch
https://www.stackbuilders.com/insights/hasktorch-libtorch-haskell-bindings-for-deep-learning-using-ffi/
https://hackage.haskell.org/package/hmatrix
https://hackage.haskell.org/package/hmatrix/preferred
https://hackage.haskell.org/package/massiv
https://gitlab.haskell.org/ghc/ghc/-/merge_requests/12860
https://minoki.github.io/posts/2025-01-13-ghc-simd.html