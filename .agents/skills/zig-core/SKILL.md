---
name: zig-core
description: >-
  Zig language mechanics for Modulus Zig — explicit allocators, defer/errdefer,
  comptime generics, error unions with return traces, @cImport C interop.
  Use when writing, reviewing, or debugging Zig code, build.zig, or C bindings.
---

# Zig Core Mechanics

## Quick reference

| Topic | Rule |
|-------|------|
| Memory | Explicit `Allocator` param; no GC, no hidden `new` |
| defer | Unconditional cleanup at scope exit (LIFO) |
| errdefer | Cleanup only when block exits via error |
| Errors | `!T` = error set + payload; `try` propagates |
| Comptime | Types are values; generics = `comptime T: type` |
| C | `@cImport` invokes clang at compile time; native ABI |

## Memory semantics

Zig has **no** implicit allocation. Every heap use goes through `std.mem.Allocator` (or a wrapper).

```zig
pub fn process(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, data.len);
    errdefer list.deinit(allocator); // free partial state on error
    defer list.deinit(allocator);    // always free container

    try list.appendSlice(allocator, data);
    return list.toOwnedSlice(allocator); // ownership → caller
}
```

**defer vs errdefer**

- `defer` — runs when scope ends regardless of success/error (unless never reached).
- `errdefer` — runs only if scope exits by returning an error (`try` failure, `return error.X`).
- Order: defers run in **reverse** declaration order.
- Neither may contain `return`.

**errdefer |err|** — optional capture of the error being propagated (use sparingly; prefer separate cleanup paths).

**Ownership idioms**

- Caller owns returned slices unless docs say otherwise.
- `errdefer` for "keep on success, free on failure" (e.g. half-built struct).
- `ArenaAllocator` — many allocs, one `deinit`.
- `DebugAllocator` (0.16) — leak + double-free detection; tests use `std.testing.allocator`. Host helpers: `modulus.testing.LeakGuard`.

## Comptime

Compile-time execution is the same language — not a separate macro system.

**Generics** — functions/types parameterized by `comptime` values (usually `type`):

```zig
fn ArrayList(comptime T: type) type {
    return struct {
        items: []T,
        // ...
    };
}
```

**Key mechanisms**

- `comptime var` — mutable at compile time (`inline while` loops).
- `inline for` / `inline while` — unroll when bounds are comptime-known.
- `@TypeOf`, `@typeInfo`, `@sizeOf`, `@alignOf` — reflection.
- `comptime { }` blocks — run entirely at compile time.
- Branch on comptime values → dead branches stripped (no runtime cost).

**Constraint**: comptime args must be known at the call site; runtime values → compile error.

## Error handling

**Error sets** — tagged integers; each error name is one variant. `anyerror` = global union (avoid in APIs).

**Error unions** — `ErrorSet!Payload` or inferred `!Payload`:

```zig
const FileError = error{ NotFound, AccessDenied };
fn readFile(path: []const u8) FileError![]u8 { ... }
```

**Propagation**

- `try expr` — return error to caller on failure.
- `catch |err| { }` — handle locally; `catch unreachable` asserts no error (debug trap).
- Unchecked `!` return is a **compile error** unless explicitly handled.

**Payload capture**

```zig
if (foo()) |value| {
    use(value);
} else |err| {
    switch (err) {
        error.NotFound => { },
        else => return err,
    }
}
```

**Error return traces** (not stack traces)

- Record instruction address at each `return error` / failed `try` on the error path.
- Final print shows **error propagation chain** — which function returned which error.
- Enabled: Debug, ReleaseSafe. Off: ReleaseFast, ReleaseSmall.
- `@errorReturnTrace()` → `?*StackTrace`; null when disabled.

## C interoperability

No separate FFI layer — Zig and C share the C ABI.

**@cImport** — compile-time clang parse of headers:

```zig
const c = @cImport({
    @cDefine("_GNU_SOURCE", {});
    @cInclude("mylib.h");
});
// use c.my_function(), c.MY_CONSTANT
```

- Expression inside `@cImport` is **comptime** (`@cInclude`, `@cDefine`, `@cUndef`, `if`).
- Prefer **one** `@cImport` per binary (single clang invocation).
- Link: `zig build-exe foo.zig -lc` or `exe.linkLibC()` / `linkSystemLibrary("foo")`.
- C types: `c_int`, `c_void` → `anyopaque`, `[*c]T` for C pointers.
- Alternative: `zig translate-c header.h` → edit → commit generated Zig.

**Zig exported to C**

```zig
export fn my_callback(x: c_int) c_int { return x + 1; }
```

## Anti-patterns

| Bad | Why |
|-----|-----|
| Global allocator hidden in module | Breaks testability, composability |
| `defer` after conditional that might skip | Leak if branch not taken |
| `anyerror!T` public API | Loses exhaustive `switch` |
| Runtime type dispatch for generics | Use `comptime T: type` instead |
| Many `@cImport` blocks | Slow builds, duplicated inline fns |

## Deep dive

See [reference.md](reference.md) for allocator interfaces, build.zig skeleton, and testing patterns.
