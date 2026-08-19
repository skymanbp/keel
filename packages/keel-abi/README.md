# keel-abi

Hand-written `Storable` bindings for the two frozen C ABIs of the
data-science world:

- the Apache Arrow **C Data Interface** and **C Stream Interface**
  (`ArrowSchema` / `ArrowArray` / `ArrowArrayStream`), and
- **DLPack**'s `DLManagedTensorVersioned`,

in both directions: import (consume a foreign producer's structs) and
export (produce structs for a foreign consumer, e.g. pyarrow or numpy).

The shipped library contains no C sources and depends only on `base`.
The struct layouts are written out by hand for 64-bit pointers — the
library refuses to build on any other architecture — and a
test-suite-only C file of `_Static_assert(offsetof(...))` checks fails
CI if the hand layouts ever disagree with a real C compiler.

The managed layer (`Keel.Abi.Arrow`, `Keel.Abi.DLPack`) enforces the
protocols' ownership rules: release callbacks run exactly once,
double-release is a no-op, exceptions never escape into the foreign
caller, and consumption is exception-safe under `bracket`/`finally`.
The raw layer (`*.Raw`) is exported for callers who need the bare
structs.

Round-trips against real pyarrow (arrays and streams, both directions)
and numpy (DLPack, both directions) are covered by the test suites.

Part of the keel workspace — see the
[project repository](https://github.com/skymanbp/keel).
