<h1 align="center">SystematicSU</h1>
<p align="center">
  <b>A system-embedded, daemonless root binary for Android</b>
</p>

<p align="center">
  <img src="https://github.com/av2xn/SystematicSU/blob/main/SystematicSU.png" alt="SystematicSU Logo" width="512" height="512">
</p>

---

> **Developer Tool — No Security or Privacy Guarantee**
> SystematicSU is a pure developer tool. It makes no claim of providing security or privacy. By using it you accept full responsibility for all consequences. See [DISCLAIMER.md](docs/DISCLAIMER.md).

---

## What is SystematicSU?

SystematicSU is a minimal `su` binary that is embedded directly into `system.img` or `super.img` with setuid permissions and a compile-time SELinux policy. It requires no background daemon, no IPC socket, no runtime policy injection, and no grant UI.

It is the opposite of Magisk or SuperSU: there is no management layer, no safety net, and no mediation. When the binary is executed, the kernel performs a direct UID transition to 0.

## How it works

```
caller → execvp("/system/xbin/su") → kernel setuid → su.c: setresuid(0) + capset(ALL) → execve(shell)
```

No fork. No socket. No thread. One execution chain.

## Differences from other root solutions

| Feature              | SuperSU     | Magisk       | SystematicSU     |
|----------------------|-------------|--------------|------------------|
| Background daemon    | yes         | yes          | **no**           |
| IPC / socket         | yes         | yes          | **none**         |
| Systemless           | no          | yes          | **no**           |
| Partition modified   | /system     | /boot        | **/system**      |
| SELinux method       | runtime     | runtime      | **compile-time** |
| Grant UI             | app         | app          | **none**         |

## Repository Structure

```
SystematicSU/
├── su/                  Core binary (C source)
│   ├── su.c             Main daemonless su binary
│   ├── su.h             Constants and struct definitions
│   ├── pts.c            Pseudo-terminal support
│   ├── pts.h
│   ├── Android.mk       Legacy Make build (AOSP)
│   └── Android.bp       Soong build (AOSP 10+)
├── sepolicy/            SELinux policy patches
│   ├── su.te            Type enforcement rules
│   ├── file_contexts    su_exec type label
│   └── property_contexts
├── fs_config/           Filesystem permission definitions
│   └── system_fs_config 6755 setuid rule for xbin/su
├── tools/               Host-side utilities
│   ├── embed.sh         Embed su into system.img / super.img
│   ├── patch_sepolicy.py Offline / runtime SELinux binary patcher
│   └── verify.sh        7-point adb verification suite
├── docs/
│   ├── ARCHITECTURE.md  Execution flow, SELinux diagram, partition structure
│   ├── BUILD.md         NDK, AOSP in-tree, and image-embed build guides
│   └── DISCLAIMER.md    Developer tool disclaimer
└── Android.mk           Root-level build entry point
```

## Quick Start

### 1. Cross-compile (NDK)

```bash
$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/clang \
    --target=aarch64-linux-android29 \
    -o out/su su/su.c su/pts.c -lcap -DANDROID -O2
```

### 2. Embed into system.img

```bash
sudo bash tools/embed.sh --image system.img --binary out/su
```

### 3. Patch SELinux (offline)

```bash
python3 tools/patch_sepolicy.py offline \
    --policy precompiled_sepolicy \
    --fc plat_file_contexts
```

### 4. Flash and verify

```bash
fastboot flash system system.img
fastboot reboot
bash tools/verify.sh
```

See [docs/BUILD.md](docs/BUILD.md) for full instructions.

## Usage

```
SystematicSU 1.0.0
Usage: su [OPTIONS] [--] [COMMAND [ARGS...]]

  -u, --uid <uid>     target uid (default: 0)
  -g, --gid <gid>     target gid (default: 0)
  -s, --shell <path>  shell to execute (default: /system/bin/sh)
  -c, --command <cmd> command to execute in shell
  -l, --login         simulate login shell
  -p, --preserve-env  preserve environment
  -v, --version       print version
  -h, --help          print this help
```

## Acknowledgements & References

- [lbdroid/AOSP-SU-PATCH](https://github.com/lbdroid/AOSP-SU-PATCH)
- [phhusson/Superuser](https://github.com/phhusson/Superuser)
- [koush/Superuser](https://github.com/koush/Superuser)
- [sepolicy-inject](https://bitbucket.org/joshua_brindle/sepolicy-inject)
- [phhusson/sepolicy-inject](https://github.com/phhusson/sepolicy-inject)
