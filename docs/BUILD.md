# SystematicSU — Build Guide

## Requirements

### Host Tools

| Tool | Purpose |
|------|---------|
| Android NDK (r25+) | Cross-compile su binary |
| AOSP source tree | Full in-tree build |
| `simg2img` / `img2simg` | Image format conversion |
| `e2fsck` / `resize2fs` | ext4 image manipulation |
| `lpunpack` / `lpadd` | Dynamic partition (super.img) handling |
| `avbtool` | AVB / vbmeta patching |
| `adb` | Device communication for verify.sh |
| `sepolicy-inject` | Binary SELinux policy patching |
| Python 3.8+ | patch_sepolicy.py |

---

## Method 1: Standalone Cross-Compile (NDK)

Use this method to produce a prebuilt binary without a full AOSP source tree.

```bash
export NDK=$HOME/android-ndk-r25c
export API=29
export ARCH=aarch64
export TARGET=aarch64-linux-android

$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/clang \
    --target=${TARGET}${API} \
    -o out/su \
    su/su.c su/pts.c \
    -lcap \
    -DANDROID \
    -Wall -Wextra -O2

file out/su
```

For arm (32-bit):

```bash
export TARGET=armv7a-linux-androideabi

$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/clang \
    --target=${TARGET}${API} \
    -o out/su_arm \
    su/su.c su/pts.c \
    -lcap -DANDROID -O2
```

---

## Method 2: AOSP In-Tree Build

Place SystematicSU anywhere inside the AOSP source tree and include it in your device configuration.

### 2.1 Copy Sources

```bash
cp -r SystematicSU/ $AOSP/device/<vendor>/<device>/systematicsu/
```

### 2.2 device.mk Integration

```makefile
PRODUCT_PACKAGES += su

BOARD_SEPOLICY_DIRS += device/<vendor>/<device>/systematicsu/sepolicy

TARGET_FS_CONFIG_GEN += device/<vendor>/<device>/systematicsu/fs_config/system_fs_config
```

### 2.3 BoardConfig.mk (disable verity for development)

```makefile
BOARD_AVB_ENABLE := false
```

### 2.4 Build

```bash
source build/envsetup.sh
lunch <device>-userdebug
make su -j$(nproc)
```

The binary will be placed in `out/target/product/<device>/system/xbin/su`.

---

## Method 3: Embed into Existing Image

Use this when you have a prebuilt `system.img` or `super.img`.

### 3.1 Prerequisites

```bash
sudo apt install android-tools-adb android-tools-fastboot \
    e2fsprogs python3 curl
```

Build or download `lpunpack`, `lpadd`, `avbtool` from AOSP platform-tools.

### 3.2 Cross-compile the binary (see Method 1)

### 3.3 Run embed.sh

For `system.img`:

```bash
sudo bash tools/embed.sh \
    --image /path/to/system.img \
    --binary out/su
```

For `super.img` (dynamic partitions):

```bash
sudo bash tools/embed.sh \
    --image /path/to/super.img \
    --binary out/su \
    --super \
    --slot a
```

With dm-verity disabled:

```bash
sudo bash tools/embed.sh \
    --image /path/to/system.img \
    --binary out/su \
    --disable-verity
```

### 3.4 Flash

```bash
adb reboot bootloader
fastboot flash system system.img
fastboot flash vbmeta vbmeta.img   # if verity was patched
fastboot reboot
```

---

## Method 4: SELinux-only Patch (existing ROM)

If your ROM already has su placed but SELinux blocks execution:

### Offline patch (before flashing)

```bash
python3 tools/patch_sepolicy.py offline \
    --policy /path/to/precompiled_sepolicy \
    --fc /path/to/plat_file_contexts
```

### Runtime patch (running device, requires root or permissive)

```bash
python3 tools/patch_sepolicy.py runtime
```

---

## Verification

```bash
bash tools/verify.sh
```

Expected output:

```
[PASS] /system/xbin/su exists
[PASS] Setuid bit is set
[PASS] Owned by root:root
[PASS] SELinux context is u:object_r:su_exec:s0
[PASS] Version output OK: SystematicSU 1.0.0
[PASS] UID escalation to root succeeded
[PASS] No su-related AVC denials in dmesg
[PASS] /system is mounted WITHOUT nosuid

ALL CHECKS PASSED
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Permission denied` on exec | nosuid mount flag | Remove `nosuid` from fstab |
| `setuid/setgid failed` | setuid bit not set in image | Re-run embed.sh, check fs_config |
| `avc: denied { execute }` | SELinux blocking su_exec | Run patch_sepolicy.py |
| Boot loop | dm-verity mismatch | Flash patched vbmeta.img |
| `capset failed` | Missing kernel capability support | Use kernel with `CONFIG_SECURITY_FILE_CAPABILITIES=y` |
