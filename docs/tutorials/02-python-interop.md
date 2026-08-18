# Tutorial 2 — Exchanging data with the Python world via keel-abi

`keel-abi` speaks the two frozen C ABIs the data-science ecosystem
standardized on: the **Arrow C Data / C Stream Interface** (tables and
columns) and **DLPack** (tensors). Anything that speaks them — pyarrow,
numpy, polars, DuckDB, PyTorch — can hand data to Haskell and take it
back, without keel linking against any of them.

## Receiving an Arrow array (consumer side)

The protocol: *you* allocate the two structs, the producer fills them,
whoever holds the filled structs must release them exactly once. The
`with*Import` brackets make that unforgettable:

```haskell
import Keel.Abi.Arrow
import Keel.Abi.Arrow.Raw

withArrowArrayImport $ \arr ->
  withArrowSchemaImport $ \sch -> do
    -- hand the two pointers to any producer, e.g. pyarrow:
    --   arr._export_to_c(<addr arr>, <addr sch>)
    someProducerFillsThem arr sch
    a <- peek arr
    print (arrayLength a, arrayNullCount a)
    -- buffers: arrayBuffers a — validity bitmap at 0, data at 1 for
    -- primitive arrays. Release happens automatically at scope exit.
```

## Producing an Arrow array (producer side)

`exportArrowArray` installs a release callback that runs your cleanup
exactly once, when the consumer (say, Python's GC) is done:

```haskell
exportArrowArray outPtr
  emptyArrowArray { arrayLength = 3, arrayNBuffers = 2, arrayBuffers = bufs }
  (free dataBuf >> free bufs)   -- your cleanup, called from the consumer
```

Streams work the same way: implement `ArrowStreamProducer` (get_schema /
get_next / cleanup as plain Haskell functions) and `exportArrowArrayStream`
turns it into a C-consumable `ArrowArrayStream` — pyarrow reads it with
`RecordBatchReader._import_from_c` and `read_all()`.

## DLPack tensors

```haskell
import Keel.Abi.DLPack
import Keel.Abi.DLPack.Raw

-- produce: a 2x3 float64 tensor over a buffer you own
mt <- newManagedTensor (DLDataType kDLFloat 64 1) [2, 3] (castPtr buf) 0
        (free buf)          -- runs when the consumer's deleter fires
-- numpy consumes it: np.from_dlpack(<capsule around mt>)

-- consume: verify, read, and the deleter is called for you
vals <- consumeManagedTensor theirTensor $ \m -> do
  let t = mtvTensor m
  peekArray (fromIntegral (dltNDim t)) (dltShape t)
```

`consumeManagedTensor` checks the producer's DLPack major version and
refuses (after deleting) anything newer than it understands.

## What the conformance suites actually prove

In CI, on Windows, Linux and macOS (arm64), against real pyarrow and
numpy loaded **in the same process** through keel-dyn:

- Arrow arrays round-trip both directions (values, null bitmaps, and
  release callbacks verified on both sides);
- Arrow streams round-trip both directions (multi-batch, end-of-stream
  convention, Python-GC-driven cleanup);
- DLPack tensors round-trip both directions with numpy ≥ 2.1;
- a 10,000-cycle leak gate keeps the export machinery honest.

*Working code:*
[`packages/keel-abi/test/PyArrow.hs`](../../packages/keel-abi/test/PyArrow.hs),
[`packages/keel-abi/test/DLPackNumpy.hs`](../../packages/keel-abi/test/DLPackNumpy.hs),
[`packages/keel-abi/test/Managed.hs`](../../packages/keel-abi/test/Managed.hs).
