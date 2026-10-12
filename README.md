# Arm GPU Bug Bounty Program — Documentation Summary

> **Status: corrected summary.** Verified against Arm's own documentation and the live
> [Intigriti program page](https://app.intigriti.com/programs/arm/arm/detail) on 2026-10-12.
> The official PDFs are distributed by Arm via that page and are **not** stored in this
> repository.

This note summarises the Arm GPU Bug Bounty Program — the Mali GPU Kernel Driver ("Kbase")
and the Mali Command Stream Frontend (CSF) firmware — the supported test platforms, and how
those pieces relate to a local fuzzing lab.

---

## Official documents (hosted by Arm / Intigriti, not in this repo)

| File | Contents |
|------|----------|
| `arm_gpu_bug_bounty_how_to_guide.pdf` | Scope, process, submission |
| `arm_gpu_bug_bounty_faq.pdf` | FVP, kernels, source access, virtual environment |
| `arm_gpu_bug_bounty_device_configuration_guidelines.pdf` | Eligible device configurations |
| `arm_gpu_virtual_platform_how_to_guide.pdf` | Running Kbase on a virtual device |
| `patches_for_virtual_device.zip` | Kernel/Kbase patches that enable the virtual device |

Download requires a free Intigriti account (the Mali DDK additionally needs an Arm account).

---

## Quick Reference

### Program scope

- **Firmware:** Mali Command Stream Frontend (CSF) Firmware ("CSFFW") — **Tier 2**
- **Software:** Mali GPU Kernel Driver ("Kbase") — **Tier 3**
- The attack must be **local, unprivileged, userspace (EL0)**.
- A **proof-of-concept** demonstrating impact is required.
- The bug must reproduce with an **unmodified driver and unmodified CSFFW**. Inserted
  delays and the config changes listed in the scope are allowable.

Eligible bug classes: UAF, OOB read/write, integer overflow, type confusion, privilege
escalation, info leak.

### Reward tiers

Values are maxima and are granted at Arm's discretion. Which asset sits in which tier is
taken from the program page.

| CVSS severity | Tier 2 (CSF Firmware) | Tier 3 (Kbase) |
|---------------|-----------------------|----------------|
| Low (0.1–3.9) | $1,000 | $500 |
| Medium (4.0–6.9) | $3,000 | $1,500 |
| High (7.0–8.9) | $10,000 | $5,000 |
| Critical (9.0–9.4) | $20,000 | $10,000 |
| Exceptional (9.5–10.0) | $20,000 | $10,000 |

### Submission requirements

1. Working PoC on a physical Mali device **or** a supported virtual device.
2. Root cause analysis.
3. Affected DDK version(s) in `rXXpY` form (e.g. `r54p0`, `r56p0`).
4. Reproduction steps.
5. Test-environment details (device/config used).

### Out of scope (Kbase-specific highlights)

- Bugs only reachable via `debugfs` (even if world-readable/writable) or privileged
  `sysfs`/`procfs`.
- Bugs only reachable with TEST config options.
- Bugs in the **"dummy model"** code.
- Bugs in the **virtual-device patches** (`patches_for_virtual_device.zip`).
- Non-Kbase Mali drivers (Lima, Panfrost, Panthor) and Linux kernel bugs generally.
- Vendor/OEM platform-specific code — report those to the device vendor.
- Undefined behaviour without demonstrable exploitability, local temporary DoS, side
  channels, fingerprinting, TZMP bypass, already-known issues, purely theoretical issues.

---

## Test platforms — what actually works

| Platform | Mali GPU present | Kbase probes → `/dev/mali0` | Bounty-valid |
|----------|------------------|-----------------------------|--------------|
| Physical device (rooted, Mali GPU) | ✅ yes | ✅ yes | ✅ yes |
| Virtual device: Kbase built with `CONFIG_MALI_NO_MALI=y` + `patches_for_virtual_device.zip` | ➖ simulated | ✅ yes | ✅ yes* |
| Arm FVP (Base / TC2 / etc.) | ❌ no Mali model | ❌ no | ❌ no |
| QEMU `virt` (stock) | ❌ no | ❌ no | ❌ no |

\* Real Kbase code paths are in scope. The dummy-model code and the virtual-device patches
themselves are explicitly **out of scope**.

Key facts:

- **Publicly available Arm FVPs do not model a Mali GPU.** The Arm Total Compute (TC2) FVP
  documentation states outright: *"the GPU is not modelled in the FVP."* Base FVPs model
  CPUs (AEM) and generic peripherals, not a Mali GPU.
- Consequently, **no FVP makes Kbase probe and exposes `/dev/mali0` on its own.**
- Arm's supported way to exercise Kbase without hardware is the **virtual device**: build
  the real Kbase with `CONFIG_MALI_NO_MALI=y` and apply `patches_for_virtual_device.zip`.
  This runs the real driver logic against a simulated GPU backend and can be hosted on
  QEMU or a local VM.

---

## Required kernel configuration

For a debug/fuzzing kernel (physical or virtual device):

```bash
# Mali Kbase
CONFIG_MALI_MIDGARD=y         # or CONFIG_MALI_BIFROST=y on Bifrost+/newer DDKs
CONFIG_MALI_EXPERT=y          # required to expose MALI_NO_MALI
CONFIG_MALI_NO_MALI=y         # virtual device: test the driver without real hardware
CONFIG_MALI_ERROR_INJECT=y    # optional; only meaningful with MALI_NO_MALI

# Debug / fuzzing
CONFIG_DEBUG_FS=y
CONFIG_DEBUG_INFO=y
CONFIG_KALLSYMS=y
CONFIG_KASAN=y
CONFIG_KASAN_GENERIC=y
CONFIG_KASAN_INLINE=y
CONFIG_KCOV=y
CONFIG_KCOV_INSTRUMENT_ALL=y
```

Notes:

- `CONFIG_MALI_NO_MALI` is an expert option (`depends on MALI_MIDGARD && MALI_EXPERT`).
  `CONFIG_MALI_REAL_HW` is auto-selected as `!MALI_NO_MALI`.
- The built module is `mali_kbase.ko`; it registers `/dev/mali<id>` (usually `/dev/mali0`).
- On a physical device do **not** enable `MALI_NO_MALI` — use the real GPU.
- `CONFIG_DEBUG_FS` is needed for much of the driver's introspection, but remember that
  debugfs-only bugs are **out of scope**.

---

## Mali DDK (Kbase) source

Kbase is out-of-tree. Arm publishes the DDK kernels on developer.arm.com:

| Architecture | Download page | Archive pattern |
|--------------|---------------|-----------------|
| Bifrost (3rd Gen) | [Bifrost Mali 3rd Gen GPU Architecture](https://developer.arm.com/downloads/-/Bifrost%20Mali%203rd%20Gen%20GPU%20Architecture) | `BX304*-SW-99002-rXXpY-*.tar` |
| Valhall (4th Gen) | [Valhall Mali 4th Gen GPU Architecture](https://developer.arm.com/downloads/-/Valhall%20Mali%204th%20Gen%20GPU%20Architecture) | `VX504X08X-SW-99002-rXXpY-*.tar` |
| 5th Gen (CSF) | [Mali 5th Gen GPU Architecture](https://developer.arm.com/downloads/-/Mali%205th%20Gen%20GPU%20Architecture) | `*SW-99002-rXXpY-*.tar` |

- Releases are named `rXXpY` (e.g. `r54p0`, `r56p0`). Pick one matching your target kernel
  and GPU generation.
- **JM vs CSF:** early Valhall GPUs are Job Manager (JM); later Valhall and 5th Gen are
  Command Stream Frontend (CSF). Packages differ in JM/CSF support, so the program advises
  using the **Mali 5th Gen GPU Architecture** downloads for CSF testing and targeting the
  latest GPU when compiling (the page explicitly calls out `CONFIG_MALI_NO_MALI=y` here).
- The driver tree is typically `driver/product/kernel/drivers/gpu/arm/midgard/`.

---

## Virtual-device workflow (the supported virtual environment)

1. Register on Intigriti, open the Arm program page, and download
   `arm_gpu_virtual_platform_how_to_guide.pdf` and `patches_for_virtual_device.zip`.
2. Download a Mali DDK from the table above (Arm account may be required).
3. Apply `patches_for_virtual_device.zip` to your kernel/DDK as described in the guide.
4. Build the kernel and `mali_kbase.ko` with the config block above (`CONFIG_MALI_NO_MALI=y`).
5. Boot the VM/QEMU guest and confirm the driver came up:
   ```bash
   dmesg | grep -i mali
   ls -l /dev/mali0
   ```
6. Fuzz the ioctl surface via `/dev/mali0` (Syzkaller/LibAFL/etc.), validating with KASAN
   and KCOV.
7. Report only bugs in real Kbase code paths — dummy-model and virtual-device-patch bugs are
   out of scope.

---

## Physical-device workflow (the other supported platform)

1. Use a rooted device with an in-scope Mali DDK version.
2. Confirm `/dev/mali0` exists and `mali_kbase` is loaded (`lsmod | grep mali`).
3. Attach your fuzzer/debugger; validate with KASAN (debug kernel) or reproduce impact.
4. Report the exact DDK version (`rXXpY`) and device details.

---

## FVP reality check

This file previously showed a launch command such as:

```bash
./FVP_Base_RevC-2xAEMvA \
  -C bp.gpu.mali.enabled=1 \
  -C bp.gpu.mali.version=G710 ...
```

Those are **not real FVP parameters**, and no Mali GPU model is attached this way. Real FVP
invocations configure CPUs/clusters and peripherals, for example:

```bash
./FVP_Base_RevC-2xAEMvA \
  -C pctl.startup=0.0.0.0 \
  -C cluster0.NUM_CORES=4 \
  -C bp.secureflashloader.fname=tf-bl1.bin \
  -C bp.flashloader0.fname=fip.bin \
  -C bp.virtioblockdevice.image_path=rootfs.img \
  --data cluster0.cpu0=Image@0x80080000
```

Even then there is no Mali GPU in the model, so Kbase has nothing to bind to. Use a physical
device or the virtual-device setup above.

---

## Relevance to this lab

This repository implements a local Mali-kbase fuzzing lab. Implemented so far:

- ✅ **Phase 1 — driver integration.** `scripts/integrate-mali.sh` integrates an Arm DDK
  tree into a Linux kernel following the virtual-device guide recipe; validated for
  `r41p0` and `r56p0`, `r31p0` rejected (its archive lacks the no-Mali backend sources).
- ✅ **Phase 2 — boot stack.** Modern TF-A `fvp` platform with the kernel as BL33.
  Upstream TF-A/U-Boot removed the `aemfvp-a` board, so the stack is
  `BL1/BL2/BL31 → Linux Image → BusyBox initramfs` (`scripts/build-stack.sh`).
- ✅ **Phase 3 — device tree.** `scripts/build-dtb.sh` splices the Mali "dummy model"
  node (`fvp/dtb/mali-node.dts`) into the kernel's `fvp-base-revc.dtb` per the guide.
- ✅ **Phase 4 — kernel.** `scripts/build-kernel.sh` builds Linux 5.15 LTS (arm64) with
  the driver config fragments under `kernel/configs/`.
- ✅ **Phase 5 — boot & smoke test.** `scripts/run-fvp.sh` and `scripts/check-mali.sh`
  boot `FVP_Base_RevC-2xAEMvA` on the host and verify `/dev/mali0` appears.

Not yet implemented: Phase 6 (Syzkaller) and Phase 7 (LibAFL) harnesses.

### What a local lab can provide

- ✅ Kernel build with the DDK's no-Mali ("dummy model") backend (`CONFIG_MALI_NO_MALI=y`).
- ✅ KASAN/KCOV-capable arm64 guest kernel on an Arm FVP (Base RevC AEMvA) — KCOV is a
  *lab-only* flag of `build-kernel.sh` (`--kcov`), never enabled in repro configs.
- ✅ `/dev/mali0` probed from the Device Tree path (no x86 patches needed).
- ⬜ Syzkaller framework (host tools + config validation).
- ⬜ LibAFL harness (standalone, structured input format).

### Bounty blockers that remain

- ⬜ Kbase source requires an Arm account/download (DDK archives are GPL but obtained via
  the bounty program landing page; provenance logged in `driver/manifest.json`).
- ⬜ Real-GPU corner cases cannot be exercised on the FVP (dummy model only).

### Directory layout (implemented)

| Path | Purpose |
|------|---------|
| `driver/` + `driver/manifest.json` | DDK source archives (GPL-2.0) + registry |
| `scripts/integrate-mali.sh` | Phase 1: DDK → kernel tree |
| `scripts/build-kernel.sh` | Phase 4: 5.15 + config fragment → `out/<driver>/` |
| `scripts/build-stack.sh` | Phase 2: TF-A + BusyBox initramfs |
| `scripts/build-dtb.sh` | Phase 3: splice Mali node + `/chosen` |
| `scripts/run-fvp.sh`, `scripts/check-mali.sh` | Phase 5: boot + smoke-test |
| `fvp/dtb/mali-node.dts` | Mali node DT fragment |
| `kernel/configs/kbase-r41.config`, `kbase-r56.config` | Driver config fragments |

### Build & run

```bash
scripts/build-kernel.sh --driver r56          # Image, dtb, mali_kbase.ko
scripts/build-stack.sh  --driver r56          # bl1.bin, fip.bin, rootfs.cpio.gz
scripts/check-mali.sh   --driver r56          # boot FVP, expect /dev/mali0
```

Boot addresses on the FVP (TF-A `fvp` platform defaults): kernel at `0x80080000`
(`PRELOADED_BL33_BASE`), DTB at `0x82000000` (`HW_CONFIG_BASE`), initramfs at
`0x84000000` with `/chosen/linux,initrd-*` set by `build-dtb.sh`.

### Path to a bounty submission

```
Stock QEMU virt            →   Virtual device (NO_MALI)      →   Physical device
  no /dev/mali0                 Kbase + patches_for_             real GPU, /dev/mali0
  Kbase cannot probe            virtual_device.zip               KASAN via debug kernel
  docs/tooling only             Kbase probes, /dev/mali0                │
                                     │                                  │
                                     └──────────→ Submit to ────────────┘
                                                  Arm Bug Bounty
                                                  (Intigriti)
```

---

## Program links

- **Program (Intigriti):** https://app.intigriti.com/programs/arm/arm/detail
- **Mali 5th Gen GPU Architecture (CSF) DDK:** https://developer.arm.com/downloads/-/Mali%205th%20Gen%20GPU%20Architecture
- **Valhall Mali 4th Gen GPU Architecture DDK:** https://developer.arm.com/downloads/-/Valhall%20Mali%204th%20Gen%20GPU%20Architecture
- **Bifrost Mali 3rd Gen GPU Architecture DDK:** https://developer.arm.com/downloads/-/Bifrost%20Mali%203rd%20Gen%20GPU%20Architecture
- **TF-A FVP documentation (real FVP usage):** https://trustedfirmware-a.readthedocs.io/en/latest/plat/arm/fvp/index.html
- **TC2 FVP docs ("the GPU is not modelled in the FVP"):** https://arm-reference-solutions-docs.readthedocs.io/en/tc2-2022.12.07/docs/totalcompute/tc2/user-guide.html

---

## Summary for researchers

| Step | Action | Source |
|------|--------|--------|
| 1 | Register on Intigriti; read the program page + PDFs | Intigriti |
| 2 | Pick a platform: physical Mali device **or** virtual device | — |
| 3 | (Virtual) download DDK + `patches_for_virtual_device.zip` | Arm / Intigriti |
| 4 | Build kernel + `mali_kbase.ko` (add `CONFIG_MALI_NO_MALI=y` for virtual) | DDK + kernel |
| 5 | Boot and confirm `/dev/mali0` and `mali_kbase` load | `dmesg`, `ls` |
| 6 | Fuzz the ioctl surface via `/dev/mali0` | Syzkaller/LibAFL |
| 7 | Validate with KASAN report + KCOV trace | your tooling |
| 8 | Submit PoC + root cause + DDK version + config to Arm | Intigriti |

---

## Revision notes

Corrections applied to the previous version of this file:

- Reward tiers fixed: Kbase is **Tier 3** ($500–$10,000); CSF firmware is **Tier 2**
  ($1,000–$20,000). The old table used invented tiers.
- Removed fictional FVP launch flags (`bp.gpu.mali.enabled`, `bp.gpu.mali.version`) and the
  "GPU Model Versions" table. Replaced with the real supported virtual-device route
  (`CONFIG_MALI_NO_MALI=y` + `patches_for_virtual_device.zip`).
- Noted that public Arm FVPs — including TC2 — do **not** model a Mali GPU, so no FVP alone
  yields `/dev/mali0`.
- Fixed Kconfig symbols: removed the non-existent `CONFIG_MALI_KBASE` and
  `CONFIG_MALI_KBASE_PLATFORM_CONFIG`; added `CONFIG_MALI_EXPERT` and `CONFIG_MALI_NO_MALI`.
- Replaced the speculative "Mali release ↔ kernel version" table with the actual DDK
  download pages and archive naming.
- Reframed the "lab provides" list to reflect that this repository currently ships only
  documentation.

*Sources: Arm/Intigriti program page, Arm reference-solutions and TF-A documentation
(retrieved 2026-10-12).*
