# digest
VERIFIED 2026-08-17. THE CENTRAL FINDING: the HSDS niche is already occupied. mchav (Michael Chavinda) maintains 25 Hackage packages forming a near-complete DS stack, all pushed 2026-08-14: dataframe 3.5.0.0, dataframe-learn 2.4.1.0 (linear/ridge/lasso/elastic-net, logistic, linear+RFF SVM, decision trees, GBM, AdaBoost, PCA, Nyström kPCA, k-means, GMM, DBSCAN, symbolic regression, feature synthesis, CV, grid search, pipelines — i.e. scikit-learn-shaped, shipped), dataframe-viz 1.3.1.0 (Vega-Lite v5 + terminal via granite), dataframe-lazy 2.4.0.0 (relational-algebra plans, optimizer, pull-based executor, column-oriented spill = out-of-core), plus -parquet/-arrow/-huggingface/-persistent/-hasktorch/-th, ihaskell-dataframe, and cassava. sabela (reactive Haskell notebook, 114 stars) pushed 2026-08-16.

(1) DATAHASKELL. Original era ~2016-2019: produced a docs/library-inventory site, awesome-haskell-ml (last push 2017-11-14), and dh-core (analyze/datasets/dense-linear-algebra) — dh-core now 404s and is absent from the org's 10 repos. 2017 Gitter plan for "a numeric library like NumPy and SciPy" never shipped. Stall causes named in-thread (Discourse 8565, Jan 2024): inventory-without-defaults ("Choosing libraries ends up feeling like ordering from a diner"), unknowable maintenance status. Independent confirmation (Edinburgh 2024 thesis): dataHaskell libs "often not under active development", "compatibility between packages is far from the norm". Revived 2025-11-11 by mchav + Jireh Tan. Q1 2026: 110 Discord members, 31 survey responses, "engagement has been fairly low in the Discord". Lessons stated: "Community and ecosystem are the hard problems"; "time to first plot"; contributors want bite-sized tasks, not maintainer roles. Bet: symbolic/interpretable AI over Python parity.

(2) HLEARN. Izbicki, TFP 2013, monoid/homomorphic models. Last push 2016-05-29; 1,651 stars; sub-packages deprecated on Hackage. Author postmortem (HN 14409595): "emphatically do not recommend anyone use it… Haskell has poor support for numerical computing"; he rewrote the numeric prelude (SubHask) and then blocked on dependent types, estimating a 5-10 year wait. Failure mode: prerequisite-rewrite + betting on unshipped language features.

(3) TWEAG. sparkle: DEPRECATED on Hackage (0.7.4, 2018-02-28), redirected to a Bazel-only GitHub build, "early tech preview"; last push 2025-07-30. inline-r 1.0.2 (2025-07-11) — all Hackage builds FAILED. funflow2 (content-addressed store), jupyenv (Nix). All are bridges, not native DS. Tweag acquired by Modus Create 2022-06-01, now its OSPO.

(4) MOMENTUM IS REAL BUT NARROW. HN "Dataframe 1.0.0.0" got 114 points/17 threads but top comments argued about the four-component version number and the pandas name clash, not the library. HN "State of DataHaskell Q1 2026": 4 points, 1 comment. Haskell Foundation has NO official data-science position (2026 update is about a technical-vision committee; mchav appears only as commenter). GSoC 2026 has one dataframe Parquet project. Benchmarks (mchav): 300M rows Haskell 15.26s vs Polars/Pandas both OOM; groupby 119ms vs 227/376ms — but single-threaded, no SIMD.

(5) DEMAND. Hackage 30-day pulls: dataframe 302 (total 2,168) vs aeson 365, text 392 — high velocity, tiny base. pandas: 755.8M/30d. Segment (a) Haskell devs with occasional data tasks is the only verified buyer (State of Haskell 2025, n=1,417: ML wanted by 14.53%; mchav's own origin was fraud-detection BRMS file generation). Segment (b) Python refugees is contradicted — mchav found DS outsiders "a little hard to get… to complete" the survey. Segment (c) finance is big but unproven: Mercury (~2M LOC Haskell) mentions no DS/ML at all; Standard Chartered Markets is Mu/typed-FP, not DS.

# key_insights
- THE DECISIVE FACT: an empty repo starting today is not entering a vacuum — it is entering a field where one person (mchav) shipped 25 interlocking packages covering dataframes, ML, plotting, out-of-core query execution, Parquet/Arrow/JSON/SQL I/O, and notebooks, with the most recent uploads dated 2026-08-14, three days ago; any HSDS plan must open by answering 'why is this not a contribution to dataframe?'
- DON'T rewrite the numeric foundation first — this is the single repeated killer: HLearn died building SubHask (a replacement numeric prelude) and DataHaskell's 2017 promise of 'a numeric library like NumPy and SciPy' never shipped; two independent efforts died on the same hill, so build on vector/hmatrix/massiv as they are and fix them by upstream patches.
- DON'T make progress contingent on future GHC features — Izbicki explicitly blocked HLearn on dependent types and estimated a 5-10 year wait, and Bryan O'Sullivan noted the dependency was on features with 'no consensus that they'll actually be good when they exist, and (b) don't yet exist'; ship on GHC 9.6-9.12 as it exists today.
- DO stay installable via plain cabal/Stackage forever — sparkle's deprecation notice ('superseded by the github repository which builds with Bazel') and inline-r's all-builds-failed status on Hackage are two separate deaths by unobtainability in the same organization, and setup friction is the #1 problem DataHaskell's own listening sprint identified.
- DON'T build an inventory or a curation layer — the original DataHaskell's main artifact was a library list, and its named failure was 'Choosing libraries ends up feeling like ordering from a diner sometimes' plus 'It's hard to know if a library is maintained or not!'; the revival's explicit correction is 'a single, robust happy path' rather than options.
- DO treat time-to-first-plot as the primary metric, not expressiveness — DataHaskell's stated lesson is that 'Very few people will touch the ecosystem unless they can read their favourite data format, or plot their results, or run machine learning models easily', and the sole HN commenter on their Q1 2026 report wrote 'no one will care about how diffable and optimizable your models are if they can't do the first part of developing them, ie. eyeballing data'.
- DO resolve the typed/untyped tension by tiering rather than choosing — dataframe's three coexisting layers (string-based untyped for exploration, phantom-type schema for production, monadic for pipelines) is the field's best answer to Hellerstein's point that in EDA 'types are used as exploratory lenses' and are 'hypotheses of what ground truth might be rather than a specification'; Frames chose full typing and went stale (last release 2023-10-22).
- THE ONE EMPIRICALLY VERIFIED HASKELL ADVANTAGE IS OUT-OF-CORE STREAMING, from two independent sources: the Edinburgh 2024 thesis found Haskell slower than Python on 10 of 11 Sanzu benchmarks yet concluded 'streaming allows Haskell to compute with large datasets without memory limitations', and mchav's benchmark shows Haskell finishing 300M rows in 15.260s where Polars AND Pandas both ran out of memory.
- THE REALISTIC WEDGE is typed, reproducible, out-of-core ETL and feature pipelines inside existing production Haskell services — where the status quo is shelling out to Python and losing type safety at the process boundary — combined with funflow's insight that static typing catches pipeline-configuration errors at compile time before wasting compute; NOT interactive EDA, where Python's REPL-plus-plot loop is unassailable.
- SEGMENT (b) 'data scientists tired of Python' IS A MIRAGE and must not be the target user: mchav tried to recruit data-science colleagues into the State of Haskell 2025 survey and reported it was 'a little hard to get them to complete it'; DataHaskell's Q1 2026 report drew 4 points and 1 comment on HN; the one documented crossover is a single R blogger's essay, not a user.
- SEGMENT (a) 'Haskell devs with an occasional data task' IS THE ONLY VERIFIED BUYER — State of Haskell 2025 (n=1,417) shows 14.53% (112 respondents) wanting machine-learning content, and dataframe itself was born from exactly this: 'At the time I worked in fraud detection and we needed to automate file generation for our BRMS.'
- SEGMENT (c) finance/fintech is large but UNPROVEN as data-science demand — Mercury runs ~2M lines of Haskell against $248B of 2025 transaction volume yet its own engineering retrospective mentions no data science, analytics, or ML whatsoever, and Standard Chartered's Markets division ($3B operating income) uses typed FP for trading infrastructure, not for DS; treat this as a hypothesis requiring one design-partner conversation, not a market.
- ADOPTION IS REAL BUT MUST BE SIZED HONESTLY: dataframe pulls 302 Hackage downloads in 30 days against aeson's 365 and text's 392 — an excellent relative velocity — but its cumulative total is 2,168 against pandas' 755.8 million PyPI downloads per month, a gap of roughly six orders of magnitude that no toolkit will close.
- HN ATTENTION IS NOT VALIDATION: 'Dataframe 1.0.0.0' scored 114 points, but the top comments litigated the four-component version number ('I can't wait for version 1.0.0.0.0.0.0.1') and the name collision with pandas rather than the library's merits — plan for evaluation to come from Discourse and design partners, not aggregators.
- THE HASKELL FOUNDATION WILL NOT CARRY THIS: its 2026 update commits to 'dedicate most of the Foundation's financial resources to technical work' via a new technical-vision committee but contains no data-science position; the 2024 pre-HFTP dataframe proposal never received a formal decision; and data science was entirely absent from the 182-point, 78-comment HN thread on the Foundation's 2026 plans.
- BUS FACTOR 1 IS THE ECOSYSTEM'S LARGEST STRUCTURAL RISK AND THE CLEAREST OPENING: 25 packages, a reactive notebook, and the DataHaskell revival all depend on one maintainer, while DataHaskell's own survey found contributors want 'concrete, self-contained contributions like tutorials, docs, and bug fixes' and explicitly do NOT want to become long-term maintainers — so design for many casual contributors and a shared maintenance bench from day one.
- DO pick a differentiator Python structurally cannot copy rather than competing on breadth — DataHaskell has already staked out interpretable/symbolic modelling ('searching over programs, not just fitting opaque parameters'), dataframe-learn returns models as manipulable dataframe expressions, and HLearn's genuinely good monoid-structured-models idea (free parallelism, incremental and decremental updates, cheap cross-validation) remains unclaimed and is implementable today without dependent types.
- DO ship parallelism and SIMD, the one concrete unclaimed performance gap: dataframe's author states the engine is 'single-threaded with no SIMD optimization' and names both as future work, and this is the difference between matching Polars on one core and beating it on sixteen.
- DON'T build a bridge as the core value proposition — every Tweag data-science artifact (sparkle to Spark, inline-r to R, dataframe-hasktorch to PyTorch) is a bridge, and bridges decay to their heaviest native dependency and lose their owner: Tweag was acquired by Modus Create in June 2022 and is now its OSPO, with no product mandate to keep any of them alive.
- DO NOT SPLIT THE COMMUNITY: javelin was a competent Series library by a Haskell Foundation contributor that lost to dataframe and now pulls 19 downloads a month, while its author publicly welcomed the DataHaskell revival — in an ecosystem of ~110 interested people, a second implementation does not create competition, it creates fragmentation and one corpse.

# libraries

## dataframe (+ ~20 dataframe-* packages) (Columnar DataFrame with untyped/typed/monadic API layers; CSV, Parquet, JSON, Arrow C Data Interface, HuggingFace hub, SQL via persistent; typed expression DSL)
STATUS: VERY ACTIVE. Hackage 3.5.0.0 uploaded 2026-08-14 (three days before today). GitHub DataHaskell/dataframe: created 2024-02-24, last push 2026-08-14, 261 stars, 49 forks, 25 open issues, MIT. Tested GHC 9.4.8, 9.6.7, 9.8.4, 9.10.3, 9.12.2. Version history 0.1.0.0 -> 3.5.0.0 in ~2.5 years. Hackage downloads: 2,168 total, 302 in last 30 days (vs aeson 365, text 392 — near-top-tier current pull rate on a tiny total base).
ASSESS: STRENGTHS: this IS the incumbent. Three API tiers (string-based exploration, phantom-type compile-time schema, monadic pipeline) is a genuinely good answer to the typed-vs-untyped EDA tension. Benchmarks (author's own): 100M rows 6.343s vs Polars 6.607s vs Pandas 9.874s; 300M rows Haskell 15.260s while Polars AND Pandas both OOM; groupby 119ms vs Polars 227ms vs Pandas 376ms. WEAKNESSES: single-threaded, no SIMD (author names parallelism + vectorization as unstarted future work); author's caveat that benchmarks 'test the underlying array implementations rather than specialized dataframe operations'; 1BRC takes ~10 min; bus-factor 1 (9 subscribers, 25 packages, one person). FIT AS FOUNDATION: a new toolkit should build ON this, not beside it. Duplicating it is the single most likely way to repeat the DataHaskell failure mode. The credible gaps are parallelism/SIMD in the execution engine and the bus-factor.
EVID: https://hackage.haskell.org/package/dataframe ; https://github.com/DataHaskell/dataframe ; https://api.github.com/repos/DataHaskell/dataframe ; https://mchav.github.io/benchmarking-haskell-dataframes/ ; https://discourse.haskell.org/t/ann-dataframe-1-0-0-0/13834

## dataframe-learn (Classical ML on dataframes; 'interpretable, expression-returning machine learning' — models return inspectable records AND dataframe expressions manipulable symbolically)
STATUS: ACTIVE. Version 2.4.1.0 uploaded 2026-08-14. Maintainer mchav.
ASSESS: STRENGTHS: coverage is already scikit-learn-shaped — linear regression, ridge, lasso, elastic net, logistic regression, linear SVM, RFF-kernel SVM, decision trees, gradient boosting, AdaBoost, PCA, Nyström kernel PCA, k-means, GMM, DBSCAN, symbolic regression (genetic programming), feature synthesis, cross-validation, grid search, metrics, preprocessing pipelines that compose as expressions. The expression-returning design is a real Haskell-native differentiator Python cannot copy cheaply. WEAKNESSES: no deep learning (defers to Hasktorch), unverified numerical accuracy/benchmarks vs sklearn, no published validation suite, bus-factor 1. FIT: this is the direct competitor to any 'Haskell scikit-learn' ambition. A new project claiming that scope must first explain what dataframe-learn 2.4.1.0 does not do.
EVID: https://hackage.haskell.org/package/dataframe-learn

## dataframe-lazy (Lazy/out-of-core query engine: relational-algebra plans, optimizer, pull-based executor, column-oriented spill format)
STATUS: ACTIVE. Version 2.4.0.0 uploaded 2026-08-14.
ASSESS: This is the piece that operationalizes Haskell's one empirically-verified DS advantage (larger-than-memory streaming). Depends on async, so some concurrency plumbing exists, but parallel execution is not documented as delivered. The optimizer is young and unbenchmarked publicly. This is the most defensible technical wedge in the whole ecosystem and the least finished.
EVID: https://hackage.haskell.org/package/dataframe-lazy

## dataframe-viz / granite (Plotting: terminal backend via granite, web backend emitting Vega-Lite v5 specs rendered by vega-embed)
STATUS: ACTIVE. dataframe-viz 1.3.1.0 uploaded 2026-08-14.
ASSESS: Closes the historically loudest gap ('a well supported plotting library', named by mchav in Jan 2024 and by Shimuuar as an EDA prerequisite). Marks: Bar, Line, Point, Area, Boxplot, Arc, Rule, Tick; faceting, layering, regression overlays, density estimation, binning, aggregations, full encoding channels. Delegating rendering to Vega-Lite is the correct leverage play — do not rebuild matplotlib. Remaining risk: DataHaskell's own roadmap still lists 'fragmented visualization ecosystem' as a gap, so consolidation is incomplete.
EVID: https://hackage.haskell.org/package/dataframe-viz ; http://www.datahaskell.org/docs/community/roadmap.html

## Hasktorch (Tensors and neural networks; bindings to PyTorch's C++ libtorch, GPU support)
STATUS: MAINTAINED but low-uptake. GitHub last push 2026-07-28, 1,211 stars, 90 open issues, not archived. 0.2.2.0 on Stackage nightly-2026-06-08; recent release added lts-23.24 / GHC 9.8. Hackage: 1,511 total downloads, only 38 in last 30 days.
ASSESS: STRENGTHS: the only serious DL path; typed tensor experiments are academically interesting; dataframe-hasktorch bridge now exists. WEAKNESSES: 38 downloads/30d is near-zero real usage; heavy libtorch native dependency makes installation the classic Haskell setup-friction failure; 90 open issues; GHC support trails. FIT: treat as a dependency to bridge to, never as something to reimplement. Do not attempt a native Haskell autodiff/DL engine — that is HLearn's mistake in modern clothing.
EVID: https://api.github.com/repos/hasktorch/hasktorch ; https://www.stackage.org/nightly-2026-06-08/package/hasktorch-0.2.2.0

## IHaskell / sabela (Notebooks. IHaskell = Jupyter kernel. sabela = reactive notebook (Markdown files + fenced Haskell blocks, dependency graph via ghc-lib-parser, auto re-run of affected cells))
STATUS: BOTH ACTIVE. IHaskell last push 2026-08-15, 2,646 stars, 51 open issues. sabela last push 2026-08-16, 114 stars — brand new, DataHaskell org.
ASSESS: IHaskell is the most-starred asset in the space but notebook ergonomics is an explicit 2026 DataHaskell priority, i.e. it is not good enough. sabela is the interesting move: reactive (Observable/Marimo-style) rather than imitating Jupyter, supports Python interop in the same notebook, compiled cells for heavy work, and widgets. Named for the Ndebele word 'to respond'. FIT: interactivity is where Haskell DS actually dies (Shimuuar flagged weak IHaskell support and slow interpretation as blocking EDA). Any new toolkit must target an existing notebook rather than ship its own.
EVID: https://api.github.com/repos/IHaskell/IHaskell ; https://github.com/DataHaskell/sabela ; https://www.datahaskell.org/blog/2026/01/12/state-of-datahaskell-q1-2026.html

## HLearn (Historic. Algebraic/homomorphic ML — models as monoids giving free parallelism, online/incremental and decremental updates, fast cross-validation)
STATUS: DEAD. Last code push 2016-05-29 (GitHub API, checked 2026-08-17). 1,651 stars, 23 open issues, NOT archived (a zombie repo that still attracts stars). HLearn-algebra, -classification, -distributions, -approximation all deprecated on Hackage.
ASSESS: The most important cautionary tale. Author Mike Izbicki's own postmortem (HN, 2017): 'I've paused the development of HLearn and emphatically do not recommend anyone use it… The main problem is that Haskell (which I otherwise love) has poor support for numerical computing.' He responded by writing SubHask, a replacement numeric prelude, then blocked on the type system: 'Haskell's type system isn't yet powerful enough to do what I want', wanting dependent types and estimating a 5-10 year wait; he judged Idris unusable because it 'gets much less engineering work done on it'. Bryan O'Sullivan characterized the dependency as language features with 'no consensus that they'll actually be good when they exist, and (b) don't yet exist'. THE IDEA WAS GOOD (monoid-structured models genuinely give free parallelism); THE STRATEGY KILLED IT (rewrite the foundation first, then block on unshipped language features).
EVID: https://api.github.com/repos/mikeizbicki/HLearn ; https://news.ycombinator.com/item?id=14409595 ; https://hackage.haskell.org/package/HLearn-algebra ; https://izbicki.me/public/papers/tfp2013-hlearn-a-machine-learning-library-for-haskell.pdf

## sparkle (Tweag) (Historic. Haskell on Apache Spark — distributed analytics via JVM interop)
STATUS: EFFECTIVELY DEAD. Hackage: DEPRECATED, last version 0.7.4 uploaded 2018-02-28. GitHub last push 2025-07-30, 449 stars, not archived. Self-described 'early tech preview, not production ready'.
ASSESS: Failure mode worth naming precisely: the project LEFT HACKAGE for a Bazel-only GitHub build. The deprecation notice reads 'The hackage package has been superseded by the github repository which builds with Bazel.' That simultaneously destroyed discoverability and installability for ordinary users — you cannot `cabal install` it. A DS toolkit that cannot be obtained by the standard package manager is dead regardless of its technical quality. Also: JVM interop plus a Bazel requirement is a two-layer setup tax on top of an ecosystem whose #1 documented problem is setup friction.
EVID: https://hackage.haskell.org/package/sparkle ; https://api.github.com/repos/tweag/sparkle

## HaskellR / inline-r (Tweag) (Historic/current. Embed an R interpreter in a Haskell binary; call R from Haskell via quasiquotation with no marshalling cost)
STATUS: WEAKLY MAINTAINED, BROKEN ON HACKAGE. inline-r 1.0.2 uploaded 2025-07-11, maintainer Mathieu Boespflug (Tweag); ALL reported Hackage builds FAILED. GitHub last push 2026-06-29, 587 stars.
ASSESS: The bridge strategy in its purest form: instead of building Haskell stats, borrow R's. Elegant (quasiquotation, no FFI boilerplate) but it inherits R's install surface and the Hackage build failures mean new users hit a wall immediately. Lesson: a bridge is only as reliable as its heaviest native dependency, and 'builds failed' on Hackage is a silent adoption killer nobody fixes because the bridge has no product owner.
EVID: https://hackage.haskell.org/package/inline-r ; https://api.github.com/repos/tweag/HaskellR

## funflow / jupyenv (Tweag) (funflow: content-addressed reproducible workflow/pipeline DSL. jupyenv: declarative reproducible Jupyter environments via Nix)
STATUS: funflow last push 2026-06-04, 366 stars; funflow2 is a rewrite with funflow1 parked on a branch. jupyenv last push 2026-08-16, 744 stars, 152 forks, 56 open issues — the liveliest Tweag DS asset.
ASSESS: What Tweag actually learned: their durable contribution to data science was REPRODUCIBILITY INFRASTRUCTURE (content-addressed stores, Nix environments), not Haskell numerics. funflow's pitch — static typing catches pipeline-configuration errors at compile time before wasting compute — is the most transferable idea in this whole survey and maps directly onto the typed-ETL wedge. Caveat: Tweag was acquired by Modus Create on 2022-06-01 and is now its OSPO, so all of this is consultancy-funded R&D with no product mandate; funflow already burned one major-version rewrite.
EVID: https://api.github.com/repos/tweag/funflow ; https://api.github.com/repos/tweag/jupyenv ; https://www.businesswire.com/news/home/20220601005262/en/Modus-Create-Acquires-European-Software-Engineering-Firm-Tweag

## Frames (Type-safe tabular data via vinyl records; row types inferred from CSV at compile time, streaming, compile-time column access safety)
STATUS: STALE. Latest 0.7.4.2 uploaded 2023-10-22 (~2.8 years ago). Author/maintainer Anthony Cowley. Hackage: 21,625 total downloads, 103 in last 30 days.
ASSESS: The canonical 'maximally typed' design point and still the intellectual reference — tonyday567 in the 2025 design thread: 'Frames and vinyl are old, for sure, but there's a lot of design ideas in them that could be useful.' Its residual 103 downloads/30d show real legacy usage. It lost because full type-level schemas fight exploratory work: types during EDA are, per Joe Hellerstein quoted by mchav, 'exploratory lenses… hypotheses of what ground truth might be rather than a specification.' Mine it for design, do not revive it.
EVID: https://hackage.haskell.org/package/Frames ; https://discourse.haskell.org/t/design-dataframes-in-haskell/11108

## javelin (Series — labeled one-dimensional arrays combining map and array properties; boxed and unboxed variants (a pandas.Series analogue))
STATUS: STALE. 0.1.4.2 uploaded 2025-03-02 (~17 months). Author Laurent P. René de Cotret. Hackage: 656 total downloads, 19 in last 30 days.
ASSESS: A well-designed, competently-executed library that lost the ecosystem race. Its author is now visible instead as a Haskell Foundation voice who welcomed the DataHaskell revival ('Thanks for taking the lead on this!', 2025-11-12). This is the clearest available evidence for the consolidation lesson: in an ecosystem this small, a second good implementation does not create competition, it creates fragmentation and then one of them dies. Directly relevant to whether a new HSDS should exist as a separate package.
EVID: https://hackage.haskell.org/package/javelin ; https://discourse.haskell.org/t/welcome-to-datahaskell-revived/13256

## statistics (Statistical types, distributions, sample analysis (quantiles, histograms, bootstrap), random variate generation, significance testing)
STATUS: MAINTAINED. 0.16.5.0 uploaded 2026-01-09, maintainer Alexey Khudyakov. GHC 8.4.4 through 9.12.2. 125,150 total downloads, 245 in last 30 days.
ASSESS: The most-used piece of genuine DS infrastructure in Haskell by a wide margin (125k downloads dwarfs dataframe's 2,168) and it is alive. Historically a friction source: the Edinburgh 2024 thesis could NOT benchmark linear regression because `statistics` hit a library conflict (marked 'LC — library conflict, no benchmark possible'). Depend on it; contribute fixes to it; do not fork it.
EVID: https://hackage.haskell.org/package/statistics ; https://project-archive.inf.ed.ac.uk/ug4/20244361/ug4_proj.pdf

## hmatrix / massiv / accelerate / vector (Numeric substrate: hmatrix = BLAS/LAPACK linear algebra; massiv = multidimensional parallel arrays; accelerate = embedded DSL compiled to GPU/multicore; vector = the universal array type)
STATUS: All have active maintainers as of 2026. hmatrix maintained by Dominic Steinitz, in Stackage nightly. accelerate led by Trevor L. McDonell. vector 0.13.2.0. massiv actively developed but its numerical layer is incomplete — Cholesky decomposition, among others, is not implemented.
ASSESS: This layer is the historical root cause. Izbicki's verdict — 'Haskell has poor support for numerical computing' — was aimed here, and it is only partly fixed: the pieces exist and are maintained, but they do not compose into a coherent stack (hmatrix's Matrix, massiv's Array, accelerate's Acc, and vector's Vector are four incompatible universes, and dataframe adds a fifth columnar representation). CRITICAL STRATEGIC WARNING: unifying this layer is exactly the project that killed HLearn (SubHask) and exactly what DataHaskell's 2017 Gitter promised ('a numeric library like NumPy and SciPy') and never delivered. Two independent efforts have died on this hill.
EVID: https://www.stackage.org/package/hmatrix ; https://hackage.haskell.org/package/accelerate ; https://serokell.io/blog/dimensions-and-haskell-introduction ; https://news.ycombinator.com/item?id=14409595

## DataHaskell (the initiative itself) (Umbrella community org: website, docs, roadmap, dev container, examples, Discord)
STATUS: REVIVED AND ACTIVE, BUT TINY. Relaunched 2025-11-11 by Michael Chavinda and Jireh Tan. Q1 2026: 110 Discord members, 31 survey responses, and by their own admission 'engagement has been fairly low in the Discord, making it difficult to mobilize members for tasks.' Org has 10 repos; dh-core (the original 2016-era monorepo containing analyze, datasets, dense-linear-algebra) now returns HTTP 404 and is absent from the org listing; awesome-haskell-ml last pushed 2017-11-14.
ASSESS: The single most important entity to align with or explicitly differentiate from. Their stated 2026 priorities: cut setup friction / 'time to first plot', publish end-to-end workflows, bite-sized contribution boards, IHaskell notebook ergonomics, and pilot with 1-2 production Haskell teams. Their strategic bet is symbolic AI tooling for tabular data — 'tools that help you build and simplify interpretable models by searching over programs - not just fitting opaque parameters' — explicitly leaning on 'typed DSLs, algebraic modelling, compositionality' INSTEAD of chasing Python parity. Their own roadmap names the gaps: 'No community of maintainers and contributors', 'Fragmented visualization ecosystem', 'Limited data I/O format support', 'Incomplete documentation and tutorials', 'Sparse integration examples between major libraries', 'Limited model deployment tooling'. Their listening sprint interviewed Ed Kmett and Michael Snoyman and concluded 'Community and ecosystem are the hard problems.'
EVID: https://www.datahaskell.org/blog/2025/11/11/welcome-to-datahaskell.html ; https://www.datahaskell.org/blog/2026/01/12/state-of-datahaskell-q1-2026.html ; http://www.datahaskell.org/docs/community/roadmap.html ; https://api.github.com/orgs/DataHaskell/repos

# sources
https://www.datahaskell.org/blog/2025/11/11/welcome-to-datahaskell.html
https://www.datahaskell.org/blog/2026/01/12/state-of-datahaskell-q1-2026.html
http://www.datahaskell.org/docs/community/roadmap.html
http://www.datahaskell.org/docs/community/current-environment.html
http://www.datahaskell.org/docs/
https://api.github.com/orgs/DataHaskell/repos
https://discourse.haskell.org/t/welcome-to-datahaskell-revived/13256
https://discourse.haskell.org/t/state-of-datahaskell-q1-2026/13524
https://news.ycombinator.com/item?id=46598661
https://github.com/mikeizbicki/HLearn
https://api.github.com/repos/mikeizbicki/HLearn
https://news.ycombinator.com/item?id=14409595
https://news.ycombinator.com/item?id=14402378
https://izbicki.me/public/papers/tfp2013-hlearn-a-machine-learning-library-for-haskell.pdf
https://hackage.haskell.org/package/HLearn-algebra
https://hackage.haskell.org/package/HLearn-classification
https://hackage.haskell.org/package/sparkle
https://api.github.com/repos/tweag/sparkle
https://github.com/tweag/sparkle/blob/master/README.md
https://api.github.com/repos/tweag/HaskellR
https://hackage.haskell.org/package/inline-r
https://tweag.github.io/HaskellR/
https://api.github.com/repos/tweag/funflow
https://www.tweag.io/blog/2021-09-23-funflow2-intro/
https://tweag.github.io/funflow/
https://api.github.com/repos/tweag/jupyenv
https://www.businesswire.com/news/home/20220601005262/en/Modus-Create-Acquires-European-Software-Engineering-Firm-Tweag
https://www.moduscreate.com/blog/tweag-modus-creates-open-source-innovation-lab-developer-experience
https://hackage.haskell.org/package/dataframe
https://github.com/DataHaskell/dataframe
https://api.github.com/repos/DataHaskell/dataframe
https://hackage.haskell.org/package/dataframe-learn
https://hackage.haskell.org/package/dataframe-lazy
https://hackage.haskell.org/package/dataframe-viz
https://hackage.haskell.org/package/dataframe-th
https://hackage.haskell.org/user/mchav
https://github.com/DataHaskell/sabela
https://mchav.github.io/benchmarking-haskell-dataframes/
https://news.ycombinator.com/item?id=47486915
https://hn.algolia.com/api/v1/items/47486915
https://discourse.haskell.org/t/ann-dataframe-1-0-0-0/13834
https://discourse.haskell.org/t/pre-hftp-proposal-dataframe-library-for-haskell/10973
https://discourse.haskell.org/t/design-dataframes-in-haskell/11108
https://discourse.haskell.org/t/dataframe-january-2026-updates/13512
https://discourse.haskell.org/t/haskell-for-data-processing/8565
https://discourse.haskell.org/t/haskell-foundation-2026-update/14136
https://news.ycombinator.com/item?id=48216983
https://discourse.haskell.org/t/state-of-haskell-2025/13390
https://discourse.haskell.org/t/state-of-haskell-2025-results/13755
https://bagrounds.org/articles/state-of-haskell-2025-results
https://summer.haskell.org/ideas.html
https://discourse.haskell.org/t/haskell-org-accepted-for-google-summer-of-code-2026/13734
https://blog.haskell.org/gsoc-2025/
https://api.github.com/repos/hasktorch/hasktorch
https://www.stackage.org/nightly-2026-06-08/package/hasktorch-0.2.2.0
https://api.github.com/repos/IHaskell/IHaskell
https://hackage.haskell.org/package/Frames
https://hackage.haskell.org/package/javelin
https://hackage.haskell.org/package/statistics
https://www.stackage.org/package/hmatrix
https://hackage.haskell.org/package/accelerate
https://project-archive.inf.ed.ac.uk/ug4/20244361/ug4_proj.pdf
https://doi.org/10.1109/BigData.2017.8257934
https://jcarroll.com.au/2025/12/05/haskell-is-a-great-language-for-data-science/
https://www.r-bloggers.com/2025/12/haskell-is-a-great-language-for-data-science/
https://blog.haskell.org/a-couple-million-lines-of-haskell/
https://dev.to/onsen/a-couple-million-lines-of-haskell-production-engineering-at-mercury-4jd6
https://doi.org/10.1145/3674633
https://www.linkedin.com/pulse/haskell-data-science-good-bad-ugly-tom-hutchins
https://pepy.tech/compare?packages=pandas%2Cpolars
https://gitter.im/dataHaskell/Lobby?at=599fd9e266c1c7c477dc86bd