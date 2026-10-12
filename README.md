# FVP
# Arm Mali Kbase Fuzzing Lab

A reproducible research workspace for **authorized** security testing of the
Arm Mali **Kbase** kernel-mode driver (`mali_kbase`), using Docker, an ARM64
Linux guest under QEMU, KCOV coverage, KASAN, Syzkaller, and LibAFL.

> This lab targets an isolated research VM. It is for authorized testing only.
> It does **not** bundle the proprietary Mali Kbase driver source; you must
> supply a source archive you are licensed to use.

## Current status

| Area | State |
|------|-------|
| Docker image + toolchain | VERIFIED (`mali-kbase-lab:latest`) |
| `baseline` kernel + rootfs + boot + manifest | VERIFIED |
| `kcov-kasan` kernel build | RUNNING (slow: external host CPU contention) |
| KCOV / KASAN runtime verification | pending that build |
| Syzkaller host tools + config check | VERIFIED (rev `4f92358f82f6`) |
| Syzkaller arm64 executor | pending |
| LibAFL standalone harness + corpus | VERIFIED (kernel feedback gated) |
| Kbase build/load/probe/fuzz | BLOCKED — no `KBASE_ARCHIVE` |

See [`research/state.md`](research/state.md) for the authoritative status.


## Architecture

```
 host (x86_64 or arm64)
  └── Docker (Ubuntu 24.04)
       ├── cross toolchain (aarch64-linux-gnu-gcc, clang/lld)
       ├── kernel build profiles: baseline | kcov-kasan
       ├── QEMU ARM64 `virt` guest  (TCG by default, KVM optional)
       │     ├── busybox initramfs + optional ext4 rootfs
       │     ├── KCOV  (/sys/kernel/debug/kcov)
       │     └── KASAN (generic)
       ├── Stage A: Syzkaller (syz-manager + syz-executor + Kbase descriptions)
       └── Stage B: LibAFL specialized harness
```

### Critical constraint

A generic QEMU ARM64 `virt` machine is **not** a Mali GPU emulator. The lab
tracks these outcomes separately and never conflates them:

1. kernel compiles → 2. Kbase module compiles → 3. module loads →
4. module probes → 5. userspace interface usable → 6. target code paths run →
7. validation on real/supported virtualized GPU.

See [`research/limitations.md`](research/limitations.md) and
[`docs/BOOT.md`](docs/BOOT.md).

## Prerequisites

- Docker (rootless is fine) + Docker Compose v2.
- Network access to fetch the kernel source and toolchains (or pre-seeded
  caches under `workdir/`).
- A user-supplied Mali Kbase source archive for driver-specific stages.
- Recommended: ≥8 GiB free disk, ≥4 GiB RAM, ≥2 CPUs. `/dev/kvm` optional.

## Quick start

```bash
make inventory          # environment + workspace inventory
make preflight          # prerequisite checks
make docker-build       # build the lab container
make verify             # repository + artifact verification

make build-kernel PROFILE=baseline      # reference kernel
make build-kernel PROFILE=kcov-kasan    # KCOV + KASAN kernel
make build-rootfs   PROFILE=kcov-kasan
make boot           PROFILE=kcov-kasan
make guest-check    PROFILE=kcov-kasan
make verify-kcov    PROFILE=kcov-kasan
make verify-kasan   PROFILE=kcov-kasan

# Driver (needs KBASE_ARCHIVE in configs/target.env)
make build-kbase    PROFILE=kcov-kasan
make verify-kbase   PROFILE=kcov-kasan

# Fuzzers
make build-syzkaller
make syzkaller-check PROFILE=kcov-kasan
make build-libafl
```

## Supported target configurations

| Target | Status |
|--------|--------|
| Upstream ARM64 kernel (pinned 6.6.x) on QEMU `virt` | supported (infrastructure) |
| KCOV / KASAN instrumentation | supported |
| Mali Kbase r54p0 | requires user-supplied source |
| Mali Kbase r56p0 | requires user-supplied source |
| `MALI_NO_MALI` simulation | release-dependent; see `research/findings.md` |

## Current status

See [`research/state.md`](research/state.md). Runtime milestones are marked
`PASS` / `FAIL` / `BLOCKED` / `NOT RUN` with evidence.

## Documentation

- [`docs/INSTALL.md`](docs/INSTALL.md) — install & prerequisites
- [`docs/BUILD.md`](docs/BUILD.md) — kernel & Kbase builds
- [`docs/BOOT.md`](docs/BOOT.md) — QEMU guest
- [`docs/SYSCALLER.md`](docs/SYSCALLER.md) — Stage A
- [`docs/LIBAFL.md`](docs/LIBAFL.md) — Stage B
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)
- [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md)

## License

MIT (see [`LICENSE`](LICENSE)). Third-party components retain their own licenses.
