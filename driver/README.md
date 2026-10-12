# Mali GPU Kernel DDK archives

Source archives of the Arm **Mali GPU kernel driver** ("Kbase") used by this lab to
build the `mali_kbase` module for the no-Mali ("dummy model") virtual-platform
fuzzing target.

These are the **kernel** drivers only (the `driver/product/kernel` subtree of each
package). The userspace DDK, firmware binaries, and host tools are *not* included.

## Licence

The kernel driver source is released under **GPL-2.0**. Each archive contains
`driver/product/kernel/license.txt`:

> GPLv2 Licence Agreement for Mali GPUs Linux Kernel Device Drivers Source Code

The uapi headers additionally carry
`SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note`. The archives are
therefore redistributable under those terms, which is why they are committed to
this repository.

## Provenance

Official Arm downloads from the Mali kernel-driver pages on
<https://developer.arm.com/downloads/-/mali-drivers> (5th Gen GPU architecture and
Valhall kernel driver packages). The `VX...` / `AX...` prefixes are Arm package-name
prefixes; see the download page for the exact product mapping.

Machine-readable metadata, sizes and SHA-256 checksums live in
[`manifest.json`](./manifest.json).

## Contents

| Archive | Release | Status | Notes |
|---------|---------|--------|-------|
| `AX504X08X-SW-99002-r41p0-01eac0.tar.gz` | r41p0-01eac0 | **supported** | Dummy model present. No `MALI_NO_MALI_DEFAULT_GPU` Kconfig option — the dummy GPU id is hardcoded to `tMIx` in `backend/gpu/mali_kbase_model_dummy.c`. |
| `VX504X08X-SW-99002-r56p0-19eac0.tar` | r56p0-19eac0 | **supported** | CSF-capable. Ships `config/fragment/*` (incl. `nomali.fragment`). `MALI_NO_MALI_DEFAULT_GPU` defaults to `tMIx`; the dummy model also knows `tKRx` (used by the official G725/G925 virtual-device recipe). |
| `VX504X08X-SW-99002-r31p0-01eac0.tar` | r31p0-01eac0 | **excluded** | Cannot build `CONFIG_MALI_NO_MALI=y`: `backend/gpu/Kbuild` references `backend/gpu/mali_kbase_model_dummy.c` and `backend/gpu/mali_kbase_model_linux.c`, but **neither file is present in the archive**, so the no-Mali build fails to link. Kept for reference / real-HW builds only. |

## Kernel target

Both supported releases are built against **Linux 5.15 LTS** in this lab.
`r41p0` carries version guards up to `KERNEL_VERSION(6, 0, 0)`; `r56p0` up to
`KERNEL_VERSION(6, 17, 0)`. 5.15 is inside both compatibility windows.

## Usage

Integrate a supported archive into a kernel tree:

```
scripts/integrate-mali.sh --driver r41 --kdir /path/to/linux-5.15
scripts/integrate-mali.sh --driver r56 --kdir /path/to/linux-5.15
```

Then merge the matching config fragment before building:

```
kernel/configs/kbase-r41.config
kernel/configs/kbase-r56.config
```

`r31p0` is rejected by the tooling with a clear error.
