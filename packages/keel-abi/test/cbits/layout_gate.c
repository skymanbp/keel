/* Test-only layout gate for keel-abi. The shipped library has NO C
 * sources; this file exists so the test suite fails to COMPILE (via
 * _Static_assert) or fails at RUN TIME (via the keel_layout_* probes,
 * compared against the Haskell-side layout tables) if the hand-written
 * Storable offsets in Keel.Abi.*.Raw ever disagree with a real C
 * compiler on the build platform.
 *
 * Struct definitions vendored from their frozen-ABI specifications:
 *  - Apache Arrow C Data / C Stream Interface (Apache-2.0), which the
 *    spec instructs consumers to copy verbatim:
 *    https://arrow.apache.org/docs/format/CDataInterface.html
 *    https://arrow.apache.org/docs/format/CStreamInterface.html
 *  - dlpack.h v1.1 (Apache-2.0), trimmed to the exchanged structs:
 *    https://github.com/dmlc/dlpack/blob/main/include/dlpack/dlpack.h
 */
#include <stddef.h>
#include <stdint.h>

/* ------------------------------------------------------------------ */
/* Arrow C Data Interface                                             */

struct ArrowSchema {
  const char* format;
  const char* name;
  const char* metadata;
  int64_t flags;
  int64_t n_children;
  struct ArrowSchema** children;
  struct ArrowSchema* dictionary;
  void (*release)(struct ArrowSchema*);
  void* private_data;
};

struct ArrowArray {
  int64_t length;
  int64_t null_count;
  int64_t offset;
  int64_t n_buffers;
  int64_t n_children;
  const void** buffers;
  struct ArrowArray** children;
  struct ArrowArray* dictionary;
  void (*release)(struct ArrowArray*);
  void* private_data;
};

struct ArrowArrayStream {
  int (*get_schema)(struct ArrowArrayStream*, struct ArrowSchema* out);
  int (*get_next)(struct ArrowArrayStream*, struct ArrowArray* out);
  const char* (*get_last_error)(struct ArrowArrayStream*);
  void (*release)(struct ArrowArrayStream*);
  void* private_data;
};

/* ------------------------------------------------------------------ */
/* DLPack v1.x (versioned exchange structs only)                      */

typedef struct {
  uint32_t major;
  uint32_t minor;
} DLPackVersion;

typedef enum {
  kDLCPU = 1,
  kDLCUDA = 2,
  kDLCUDAHost = 3,
  kDLOpenCL = 4,
  kDLVulkan = 7,
  kDLMetal = 8,
  kDLVPI = 9,
  kDLROCM = 10
} DLDeviceType;

typedef struct {
  DLDeviceType device_type;
  int32_t device_id;
} DLDevice;

typedef struct {
  uint8_t code;
  uint8_t bits;
  uint16_t lanes;
} DLDataType;

typedef struct {
  void* data;
  DLDevice device;
  int32_t ndim;
  DLDataType dtype;
  int64_t* shape;
  int64_t* strides;
  uint64_t byte_offset;
} DLTensor;

struct DLManagedTensorVersioned {
  DLPackVersion version;
  void* manager_ctx;
  void (*deleter)(struct DLManagedTensorVersioned* self);
  uint64_t flags;
  DLTensor dl_tensor;
};

/* ------------------------------------------------------------------ */
/* Compile-time gate: the literals below are the exact numbers the     */
/* Haskell Storable instances use. 64-bit only by design.              */

_Static_assert(sizeof(void*) == 8, "keel-abi targets 64-bit platforms only");

_Static_assert(sizeof(struct ArrowSchema) == 72, "ArrowSchema size");
_Static_assert(offsetof(struct ArrowSchema, format) == 0, "ArrowSchema.format");
_Static_assert(offsetof(struct ArrowSchema, name) == 8, "ArrowSchema.name");
_Static_assert(offsetof(struct ArrowSchema, metadata) == 16, "ArrowSchema.metadata");
_Static_assert(offsetof(struct ArrowSchema, flags) == 24, "ArrowSchema.flags");
_Static_assert(offsetof(struct ArrowSchema, n_children) == 32, "ArrowSchema.n_children");
_Static_assert(offsetof(struct ArrowSchema, children) == 40, "ArrowSchema.children");
_Static_assert(offsetof(struct ArrowSchema, dictionary) == 48, "ArrowSchema.dictionary");
_Static_assert(offsetof(struct ArrowSchema, release) == 56, "ArrowSchema.release");
_Static_assert(offsetof(struct ArrowSchema, private_data) == 64, "ArrowSchema.private_data");

_Static_assert(sizeof(struct ArrowArray) == 80, "ArrowArray size");
_Static_assert(offsetof(struct ArrowArray, length) == 0, "ArrowArray.length");
_Static_assert(offsetof(struct ArrowArray, null_count) == 8, "ArrowArray.null_count");
_Static_assert(offsetof(struct ArrowArray, offset) == 16, "ArrowArray.offset");
_Static_assert(offsetof(struct ArrowArray, n_buffers) == 24, "ArrowArray.n_buffers");
_Static_assert(offsetof(struct ArrowArray, n_children) == 32, "ArrowArray.n_children");
_Static_assert(offsetof(struct ArrowArray, buffers) == 40, "ArrowArray.buffers");
_Static_assert(offsetof(struct ArrowArray, children) == 48, "ArrowArray.children");
_Static_assert(offsetof(struct ArrowArray, dictionary) == 56, "ArrowArray.dictionary");
_Static_assert(offsetof(struct ArrowArray, release) == 64, "ArrowArray.release");
_Static_assert(offsetof(struct ArrowArray, private_data) == 72, "ArrowArray.private_data");

_Static_assert(sizeof(struct ArrowArrayStream) == 40, "ArrowArrayStream size");
_Static_assert(offsetof(struct ArrowArrayStream, get_schema) == 0, "ArrowArrayStream.get_schema");
_Static_assert(offsetof(struct ArrowArrayStream, get_next) == 8, "ArrowArrayStream.get_next");
_Static_assert(offsetof(struct ArrowArrayStream, get_last_error) == 16, "ArrowArrayStream.get_last_error");
_Static_assert(offsetof(struct ArrowArrayStream, release) == 24, "ArrowArrayStream.release");
_Static_assert(offsetof(struct ArrowArrayStream, private_data) == 32, "ArrowArrayStream.private_data");

_Static_assert(sizeof(DLPackVersion) == 8, "DLPackVersion size");
_Static_assert(offsetof(DLPackVersion, major) == 0, "DLPackVersion.major");
_Static_assert(offsetof(DLPackVersion, minor) == 4, "DLPackVersion.minor");

_Static_assert(sizeof(DLDevice) == 8, "DLDevice size");
_Static_assert(offsetof(DLDevice, device_type) == 0, "DLDevice.device_type");
_Static_assert(offsetof(DLDevice, device_id) == 4, "DLDevice.device_id");

_Static_assert(sizeof(DLDataType) == 4, "DLDataType size");
_Static_assert(offsetof(DLDataType, code) == 0, "DLDataType.code");
_Static_assert(offsetof(DLDataType, bits) == 1, "DLDataType.bits");
_Static_assert(offsetof(DLDataType, lanes) == 2, "DLDataType.lanes");

_Static_assert(sizeof(DLTensor) == 48, "DLTensor size");
_Static_assert(offsetof(DLTensor, data) == 0, "DLTensor.data");
_Static_assert(offsetof(DLTensor, device) == 8, "DLTensor.device");
_Static_assert(offsetof(DLTensor, ndim) == 16, "DLTensor.ndim");
_Static_assert(offsetof(DLTensor, dtype) == 20, "DLTensor.dtype");
_Static_assert(offsetof(DLTensor, shape) == 24, "DLTensor.shape");
_Static_assert(offsetof(DLTensor, strides) == 32, "DLTensor.strides");
_Static_assert(offsetof(DLTensor, byte_offset) == 40, "DLTensor.byte_offset");

_Static_assert(sizeof(struct DLManagedTensorVersioned) == 80, "DLManagedTensorVersioned size");
_Static_assert(offsetof(struct DLManagedTensorVersioned, version) == 0, "DLManagedTensorVersioned.version");
_Static_assert(offsetof(struct DLManagedTensorVersioned, manager_ctx) == 8, "DLManagedTensorVersioned.manager_ctx");
_Static_assert(offsetof(struct DLManagedTensorVersioned, deleter) == 16, "DLManagedTensorVersioned.deleter");
_Static_assert(offsetof(struct DLManagedTensorVersioned, flags) == 24, "DLManagedTensorVersioned.flags");
_Static_assert(offsetof(struct DLManagedTensorVersioned, dl_tensor) == 32, "DLManagedTensorVersioned.dl_tensor");

/* ------------------------------------------------------------------ */
/* Run-time probes: fill `out` with offsetof per field in declaration  */
/* order, return sizeof. The Haskell test compares these against the   */
/* layout tables exported by the Raw modules, closing the loop between */
/* the C compiler's view and the Storable instances.                   */

size_t keel_layout_ArrowSchema(size_t* out) {
  out[0] = offsetof(struct ArrowSchema, format);
  out[1] = offsetof(struct ArrowSchema, name);
  out[2] = offsetof(struct ArrowSchema, metadata);
  out[3] = offsetof(struct ArrowSchema, flags);
  out[4] = offsetof(struct ArrowSchema, n_children);
  out[5] = offsetof(struct ArrowSchema, children);
  out[6] = offsetof(struct ArrowSchema, dictionary);
  out[7] = offsetof(struct ArrowSchema, release);
  out[8] = offsetof(struct ArrowSchema, private_data);
  return sizeof(struct ArrowSchema);
}

size_t keel_layout_ArrowArray(size_t* out) {
  out[0] = offsetof(struct ArrowArray, length);
  out[1] = offsetof(struct ArrowArray, null_count);
  out[2] = offsetof(struct ArrowArray, offset);
  out[3] = offsetof(struct ArrowArray, n_buffers);
  out[4] = offsetof(struct ArrowArray, n_children);
  out[5] = offsetof(struct ArrowArray, buffers);
  out[6] = offsetof(struct ArrowArray, children);
  out[7] = offsetof(struct ArrowArray, dictionary);
  out[8] = offsetof(struct ArrowArray, release);
  out[9] = offsetof(struct ArrowArray, private_data);
  return sizeof(struct ArrowArray);
}

size_t keel_layout_ArrowArrayStream(size_t* out) {
  out[0] = offsetof(struct ArrowArrayStream, get_schema);
  out[1] = offsetof(struct ArrowArrayStream, get_next);
  out[2] = offsetof(struct ArrowArrayStream, get_last_error);
  out[3] = offsetof(struct ArrowArrayStream, release);
  out[4] = offsetof(struct ArrowArrayStream, private_data);
  return sizeof(struct ArrowArrayStream);
}

size_t keel_layout_DLPackVersion(size_t* out) {
  out[0] = offsetof(DLPackVersion, major);
  out[1] = offsetof(DLPackVersion, minor);
  return sizeof(DLPackVersion);
}

size_t keel_layout_DLDevice(size_t* out) {
  out[0] = offsetof(DLDevice, device_type);
  out[1] = offsetof(DLDevice, device_id);
  return sizeof(DLDevice);
}

size_t keel_layout_DLDataType(size_t* out) {
  out[0] = offsetof(DLDataType, code);
  out[1] = offsetof(DLDataType, bits);
  out[2] = offsetof(DLDataType, lanes);
  return sizeof(DLDataType);
}

size_t keel_layout_DLTensor(size_t* out) {
  out[0] = offsetof(DLTensor, data);
  out[1] = offsetof(DLTensor, device);
  out[2] = offsetof(DLTensor, ndim);
  out[3] = offsetof(DLTensor, dtype);
  out[4] = offsetof(DLTensor, shape);
  out[5] = offsetof(DLTensor, strides);
  out[6] = offsetof(DLTensor, byte_offset);
  return sizeof(DLTensor);
}

size_t keel_layout_DLManagedTensorVersioned(size_t* out) {
  out[0] = offsetof(struct DLManagedTensorVersioned, version);
  out[1] = offsetof(struct DLManagedTensorVersioned, manager_ctx);
  out[2] = offsetof(struct DLManagedTensorVersioned, deleter);
  out[3] = offsetof(struct DLManagedTensorVersioned, flags);
  out[4] = offsetof(struct DLManagedTensorVersioned, dl_tensor);
  return sizeof(struct DLManagedTensorVersioned);
}
