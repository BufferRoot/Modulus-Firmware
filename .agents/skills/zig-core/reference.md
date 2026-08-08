# Zig Core — Extended Reference

## Allocator interface

All allocators implement:

```zig
alloc: fn (*Allocator, len: usize, alignment: Alignment, ret_addr: usize) Error![]u8,
free:  fn (*Allocator, buf: []u8, alignment: Alignment, ret_addr: usize) void,
// optional: resize, remap, freeRemotely
```

Common implementations:

| Allocator | Use |
|-----------|-----|
| `std.heap.page_allocator` | OS pages; coarse, infallible free |
| `std.heap.DebugAllocator` | Debug leaks + double-free; `gpa.allocator()` (0.16; replaces GPA) |
| `ArenaAllocator` | Bump pointer; bulk free |
| `FixedBufferAllocator` | Stack/static buffer |
| `std.testing.allocator` | Tests; fails on leak |

## defer / errdefer control flow

```
Scope enter
  alloc A → errdefer free(A)
  alloc B → defer free(B)      // temp
  try step()                   // on fail: errdefer A, defer B, exit
  return success               // errdefer A skipped; defer B runs
Scope exit → defers LIFO
```

**errdefer comptime unreachable** — after point of no failure; tells compiler no error path remains (enables optimization).

## Comptime evaluation stages

1. Parse → AST
2. Comptime analysis (`comptime` blocks, `@cImport`, type fn bodies)
3. Monomorphization (`ArrayList(u8)` vs `ArrayList(i32)` are distinct types)
4. LLVM IR → machine code

`@compileLog(x)` — debug print during comptime (does not emit runtime code).

## Error set coercion

- Subset → superset: implicit
- Superset → subset: compile error (must handle or cast with language assert)
- Merge: `const E = error{A} || error{B};`

Inferred return: `fn foo() !void` — error set inferred from function body.

## Error return trace internals (summary)

- Secret `*StackTrace` param on failable functions (first arg, often in register).
- Success path: one write to init trace index in first failable→non-failable boundary.
- Error path: `__zig_return_error` records `@returnAddress()` per hop.
- Circular buffer of N frames (call-graph depth, recursion ≈ 2).

## C type mapping

| C | Zig |
|---|-----|
| `void*` | `*anyopaque` or `[*c]u8` |
| `int` | `c_int` |
| `size_t` | `c_size_t` |
| `long double` | `c_longdouble` |
| function pointer | `*const fn (...) callconv(.c) ...` |

## build.zig skeleton

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "modulus",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.linkLibC(); // if @cImport
    b.installArtifact(exe);

    const tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
```

## Testing

```zig
test "leak detect" {
    const a = std.testing.allocator;
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(a);
    try list.append(a, 'x');
}
```

Filter: `zig build test -- --test-filter "name"`

## Version note

Project targets Zig **0.16.0**. Langref: https://ziglang.org/documentation/master/
