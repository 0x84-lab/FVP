# Arm GPU Bug Bounty Program — Documentation Summary

This directory contains the official Arm GPU Bug Bounty Program documentation. These PDFs define the program scope, rewards, submission requirements, and testing infrastructure for Mali GPU vulnerability research.

---

## Document Index

| File | Size | Description |
|------|------|-------------|
| `arm_gpu_bug_bounty_how_to_guide.pdf` | 256 KB | Main participation guide — scope, rewards, submission process |
| `arm_gpu_bug_bounty_faq.pdf` | 56 KB | Frequently asked questions — FVP, kernels, source access, disclosure |
| `arm_gpu_bug_bounty_device_configuration_guidelines.pdf` | 25 KB | FVP/device setup for validation — kernel configs, boot args, rootfs |
| `arm_gpu_virtual_platform_how_to_guide.pdf` | 70 KB | Deep dive on Fixed Virtual Platforms (FVP) with Mali GPU models |

---

## Quick Reference

### Program Scope
- **Target:** Mali GPU Kernel Mode Driver (Kbase), GPU firmware, Valhall/Utgard/Bifrost architectures
- **Eligible Bugs:** UAF, OOB read/write, integer overflow, type confusion, privilege escalation, info leak
- **Out of Scope:** Physical access required, DoS without security impact, theoretical issues without PoC

### Reward Tiers
| Severity | Max Reward | Typical Bug Class |
|----------|------------|-------------------|
| Critical | $10,000+ | Kernel UAF/RCE, privilege escalation |
| High | $5,000 | Kernel OOB, info leak with impact |
| Medium | $2,500 | Kernel logic bugs, firmware issues |
| Low | $1,000 | Minor info leaks, low-impact bugs |

### Submission Requirements
1. Working PoC on supported device **or** FVP
2. Root cause analysis
3. Affected versions (rXXpY format, e.g., r54p0, r56p0)
4. Reproduction steps
5. Kernel config used (`.config` or `defconfig` + fragments)

---

## Testing Infrastructure

### Supported Platforms
| Platform | Mali GPU | Kbase Probe | Bounty Valid |
|----------|----------|-------------|--------------|
| **Arm FVP + Mali Model** | ✅ Yes | ✅ Works | ✅ **Yes** |
| **Physical Device** | ✅ Yes | ✅ Works | ✅ **Yes** |
| **QEMU `virt`** | ❌ No | ❌ Fails | ❌ Infrastructure only |

> **Critical:** QEMU `virt` has no Mali GPU model. It cannot probe Kbase. Use FVP or physical device for valid submissions.

### Required Kernel Configuration
```bash
# Mandatory for kernel bug validation
CONFIG_MALI_MIDGARD=y        # or CONFIG_MALI_BIFROST, CONFIG_MALI_VALHALL
CONFIG_MALI_KBASE=y
CONFIG_DEBUG_FS=y
CONFIG_KASAN=y
CONFIG_KASAN_GENERIC=y
CONFIG_KASAN_INLINE=y
CONFIG_KCOV=y
CONFIG_KCOV_INSTRUMENT_ALL=y
CONFIG_DEBUG_INFO=y
CONFIG_KALLSYMS=y
```

### Mali Release ↔ Kernel Version Mapping
| Mali Release | Kernel Version | Notes |
|--------------|----------------|-------|
| r54p0 | 5.15 LTS | Midgard/Bifrost |
| r56p0 | 6.1 LTS | Valhall |
| r58p0 | 6.6 LTS | Valhall (current LTS) |
| rXXpY | Matching LTS | Check Arm release notes |

---

## FVP (Fixed Virtual Platform) Setup

### Obtain FVP
1. Register at [Arm Developer Portal](https://developer.arm.com/)
2. Download: `FVP_Base_RevC-2xAEMvA` (or newer)
3. Mali GPU model included with Bug Bounty registration

### Launch Command
```bash
./FVP_Base_RevC-2xAEMvA \
  -C bp.gpu.mali.enabled=1 \
  -C bp.gpu.mali.version=G710 \
  -C bp.flashloader0.fname=bl1.bin \
  -C bp.secureflashloader.fname=fip.bin \
  -a linux-kernel.img --dtb fdt.dtb \
  -c "console=ttyAMA0 root=/dev/vda rw init=/bin/bash"
```

### GPU Model Versions
| Mali Arch | FVP Model String |
|-----------|------------------|
| Midgard (G71/G72) | `G71` |
| Bifrost (G51/G52/G76) | `G76` |
| Valhall (G77/G78/G68/G710) | `G710` |

---

## Relevance to This Lab

### What This Lab Provides (Infrastructure Validation)
✅ Kernel build with KCOV+KASAN (`kcov-kasan` profile)  
✅ ARM64 QEMU guest boot (`virt` machine, TCG)  
✅ Syzkaller framework (host tools + config validation)  
✅ LibAFL harness (standalone, structured input format)  
✅ Artifact manifests + reproducibility  

### What This Lab Does NOT Provide (Bounty Blockers)
❌ Mali GPU hardware model → Kbase never probes  
❌ `/dev/mali0` in guest → fuzzers cannot reach driver  
❌ Kbase source code → requires Arm license/NDA  
❌ Physical device / FVP access → required for valid PoC  

### Path to Bounty Submission
```
Current Lab (QEMU virt)          →  Arm FVP + Mali Model  →  Physical Device
   Infrastructure only                 Valid PoC platform      Valid PoC platform
   No /dev/mali0                       Has /dev/mali0          Has /dev/mali0
   Kbase build fails                   Kbase loads             Kbase loads
   Syzkaller/LibAFL ready              Fuzz Kbase              Fuzz Kbase
                                         │                        │
                                         └─────→ Submit to Arm Bug Bounty
```

---

## Integration with This Repository

### Current Configs Match Bounty Requirements
```bash
# kernel/configs/kcov-kasan.config already contains:
CONFIG_KASAN=y
CONFIG_KASAN_GENERIC=y
CONFIG_KASAN_INLINE=y
CONFIG_KCOV=y
CONFIG_KCOV_INSTRUMENT_ALL=y
CONFIG_DEBUG_FS=y
CONFIG_DEBUG_INFO=y
CONFIG_KALLSYMS=y
```

### To Adapt for FVP/Device
1. **Add Mali Kconfig fragments** to `kernel/configs/kcov-kasan.config`:
   ```bash
   CONFIG_MALI_MIDGARD=y      # or BIFROST/VALHALL per target GPU
   CONFIG_MALI_KBASE=y
   CONFIG_MALI_KBASE_PLATFORM_CONFIG=y
   ```

2. **Update boot args** in `scripts/boot_qemu.sh`:
   ```bash
   # For FVP/device with rootfs on disk:
   -append "console=ttyAMA0 root=/dev/vda rw init=/bin/bash nokaslr"
   ```

3. **Provide Kbase source** (licensed):
   ```bash
   cp /path/to/kbase-src.tar.xz workdir/
   make build-kbase PROFILE=kcov-kasan
   ```

---

## Program Links

- **Bug Bounty Portal:** https://www.arm.com/security-on-arm/bug-bounty
- **FVP Downloads:** https://developer.arm.com/tools-and-software/simulation-models/fixed-virtual-platforms
- **Mali GPU Docs:** https://developer.arm.com/ip-products/graphics-and-multimedia/mali-gpus
- **Kernel Configs:** https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/arch/arm64/configs

---

## Summary for Researchers

| Step | Action | Tool |
|------|--------|------|
| 1 | Register for Arm GPU Bug Bounty | Arm Developer Portal |
| 2 | Obtain FVP + Mali GPU model | Arm Developer Portal |
| 3 | Get Kbase source under NDA | Arm partner program |
| 4 | Build kernel with KCOV+KASAN + Mali config | `make build-kernel PROFILE=kcov-kasan` |
| 5 | Build Kbase module + userspace | `make build-kbase PROFILE=kcov-kasan` |
| 6 | Boot on FVP/device with `/dev/mali0` | FVP launch script |
| 7 | Fuzz with Syzkaller/LibAFL | `make syzkaller-check` / `make build-libafl` |
| 8 | Validate bug with KASAN report + KCOV trace | `verify_kasan.sh` + `verify_kcov.sh` |
| 9 | Submit PoC + root cause to Arm | Bug Bounty portal |

---

*Generated from Arm GPU Bug Bounty Program documentation (doc.zip).  
See individual PDFs for complete details.*
