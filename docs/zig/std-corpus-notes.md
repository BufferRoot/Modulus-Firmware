# Zig std / build / overview — Modulus applicability (2026-06-17)



Sources (master = pinned **0.16.0** language ref):



- [Language reference (master)](https://ziglang.org/documentation/master/)

- [Standard library (master)](https://ziglang.org/documentation/master/std/)

- [Build system guide](https://ziglang.org/learn/build-system/)

- [Overview](https://ziglang.org/learn/overview/)



Local mirrors: `.cursor/projects/.../uploads/{master-0,build-system-2,overview-3}.md`



---



## Already used in Modulus



| Technique | Where |

|-----------|--------|

| `pub fn main(init: std.process.Init) !void` + `init.gpa` / `init.io` / `init.arena` | `host_main.zig` |

| `std.Io` file/dir/HTTP/net (Juicy Main) | `host_io.zig`, `host_http.zig` |

| `std.Io.Writer.Allocating.fromArrayList` | `host_http.zig` |

| `addTranslateC` + `createModule()` + `addImport` | `build.zig` → `modulus_shims` |

| `addOptions` / `build_options.device_nvs` | host vs Tab5 split |

| `addTest` + leak-checked `std.testing.allocator` | all host tests |

| `std.testing.fuzz` + corpus | `parser_fuzz.zig` |

| `@branchHint(.likely/.unlikely/.cold)` | `driver.zig`, `event_bus.zig`, host export paths |

| `@trunc` / explicit casts (not `@intFromFloat`) | envelope, battery, bracket |

| `comptime` generics (`StreamTransport`, `channelIo`) | transport layer |

| `export fn` C ABI | `firmware/abi.zig` |

| Cross-target `resolveTargetQuery` (P4 rv32imafc) | `build.zig` tab5-lib |

| Error return traces (default in Debug tests) | host diagnostics export |



---



## Advanced techniques — **all implemented** (2026-06-17)



### Build system



| # | Item | Where |

|---|------|--------|

| 1 | Single translate-C step, multiple consumers | `build.zig` — `translate-check` + Tab5 `modulus_shims` |

| 2 | `b.addRunArtifact` convenience steps | `run-host`, **`host-diag`** |

| 3 | Build-time NVS key codegen | `tools/gen_nvs_manifest.zig` → `addOutputFileArg` → `nvs_key_manifest` import |

| 4 | CI matrix translate-check + tab5-lib | `.github/workflows/zig-test.yml` |

| 5 | `--summary all` in CI | workflow steps |

| 6 | `installHeader` / ABI headers | `addInstallHeaderFile` + `install-headers` step |



### Language / comptime



| # | Item | Where |

|---|------|--------|

| 7 | `inline else` transport dispatch | `dispatcher.zig` — runtime `switch` + `inline else` → comptime `pollConn`/`stopConn` |

| 8 | Comptime ABI layout proofs | `firmware/abi_layout.zig` — `@offsetOf` all `CncStatus` fields |

| 9 | `@addWithOverflow` override math | `driver_ops.zig` — `addOverrideDelta` |

| 10 | `@branchHint(.cold)` diagnostic paths | `runtime.zig`, `host_diagnostics.zig`, `settings_dump.zig` |



### std (0.16 Io)



| # | Item | Where |

|---|------|--------|

| 11 | `init.arena` CLI one-shots | `host_main.zig` args + HTTP/WS fmt allocs |

| 12 | `readFileAlloc(..., .limited(n))` + HTTP cap | `host_io.readTextFileLimited`, `host_http.max_body_bytes` |

| 13 | `executableDirPathAlloc` | `host_io.resolveBesideExecutable` |

| 14 | `std.log.scoped` host logging | `core/host_log.zig` |

| 15 | `errorReturnTrace` in diagnostics | `host_io.formatErrorReturnTrace`, `host_diagnostics.writeFaultFile` |



### Performance (device)



| # | Item | Where |

|---|------|--------|

| 16 | `@Vector` DRO batch | `ui/dro_batch.zig` → `device_runtime.fillCncStatus` |

| 17 | `@setRuntimeSafety(false)` hot slice | `ext_encoder_poll.zig` delta calc |

| 18 | `+|` wrapping encoder delta | `ext_encoder_util.accumulateDelta`, poll `-%` delta |



### Testing



| # | Item | Where |

|---|------|--------|

| 19 | Continuous fuzz Linux CI | `zig build test -- --fuzz --test-filter "parser fuzz"` |

| 20 | Doctests | `cnc_config.connectionStr`, `settings_keys.btPairKey` |



---



## Not for Modulus (explicit)



| Item | Why |

|------|-----|

| `std.Io.Group` / async on Tab5 | Core 1 / ISR heap-free; hosted wireless on C6 |

| `ReleaseSmall` on UI firmware | Known miscompile risk (zig #35560); use ReleaseSafe |

| `@cImport` | Replaced by `addTranslateC` |

| Linked lists in hot path | Use ring buffers / fixed arrays |

| `packed struct` return @ ReleaseSafe | ABI pitfall #35634 |

| Watch/incremental in `/tmp` | Stale binary pitfall #35365 |



---



## Key 0.16 mental model (overview)



- **No hidden control flow** — every alloc and error path visible; matches Modulus AMP rules.

- **Four optimize modes** — Debug/ReleaseSafe on host tests; ReleaseSafe on Tab5; never ReleaseSmall on device UI.

- **Zig competes with C** — freestanding Tab5 + translate-C shims; libc only where IDF link requires it.

- **Order-independent top-level** — lazy comptime init for `settings_keys` literals and corpus tables.

- **Optional > null pointer** — already idiomatic in Zig HAL mocks.

