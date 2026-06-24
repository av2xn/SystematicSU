# SystematicSU — Architecture

## Overview

SystematicSU is a daemonless, system-embedded `su` binary for Android. Unlike daemon-based root solutions (SuperSU, Magisk), it operates through a direct `setuid` execution chain with no background processes, sockets, or IPC of any kind.

## Execution Flow

```
caller process
    │
    └─► execvp("/system/xbin/su", args)
            │
            ▼
        kernel: setuid bit set → effective UID = 0
            │
            ▼
        su.c: main()
            ├─ parse args (-u, -g, -s, -c, -l, -p)
            ├─ prctl(PR_SET_KEEPCAPS, 1)
            ├─ setgroups(0, NULL)
            ├─ setresgid(gid, gid, gid)
            ├─ setresuid(uid, uid, uid)
            ├─ capset(ALL capabilities)
            └─ execve(shell or command)
                    │
                    ▼
                target process running as uid=0 (root)
```

**No fork. No socket. No thread. One exec chain.**

## Comparison

| Feature              | SuperSU          | Magisk            | SystematicSU       |
|----------------------|------------------|-------------------|--------------------|
| Background daemon    | yes (daemonsu)   | yes (magiskd)     | **no**             |
| IPC mechanism        | Unix socket      | Unix socket       | **none**           |
| Systemless           | no               | yes               | **no**             |
| Partition modified   | /system          | /boot             | **/system**        |
| su binary location   | /system/xbin/su  | /sbin/su          | **/system/xbin/su**|
| SELinux method       | runtime inject   | runtime inject    | **compile-time**   |
| Grant UI             | app              | app               | **none**           |
| Setuid mechanism     | setuid bit       | daemon transition | **setuid bit**     |

## SELinux Domain Transition

```
[untrusted_app / shell]
        │
        │  execve(/system/xbin/su)
        │  file labeled: u:object_r:su_exec:s0
        │
        ▼
    domain_auto_trans(caller, su_exec, su)
        │
        ▼
    [su domain]
        │  permissive (developer mode)
        │  or enforcing with explicit allow rules
        ▼
    execve(shell / command)
        │
        ▼
    [sh / target process, uid=0]
```

## Partition Structure

### system.img (ext4, pre-dynamic partitions)

```
/system/
  └── xbin/
        └── su      ← owner: root:root, mode: 6755, context: u:object_r:su_exec:s0
```

### super.img (dynamic partitions, Android 10+)

```
super.img
  └── [lpunpack] → system_a.img (or system_b.img)
                     └── /system/xbin/su
```

## fs_config Integration

`fs_config` controls the UID, GID, and mode bits applied when the system image is built by AOSP.
The entry `xbin/su 0 0 6755` ensures the binary receives:

- Owner UID: 0 (root)
- Owner GID: 0 (root)
- Mode: `6755` = setuid + setgid + rwxr-xr-x

This is registered via `TARGET_FS_CONFIG_GEN` in the device's `device.mk`:

```makefile
TARGET_FS_CONFIG_GEN += $(LOCAL_PATH)/../../fs_config/system_fs_config
```

## dm-verity Considerations

Android Verified Boot (AVB) uses `dm-verity` to verify the system partition hash tree at boot.
Modifying `system.img` without disabling verity causes a boot loop.

Options:

1. **Disable at build time**: Set `BOARD_AVB_ENABLE := false` in `BoardConfig.mk`
2. **Patch vbmeta**: `avbtool make_vbmeta_image --flag 2 --output vbmeta.img`
3. **fastboot**: `fastboot --disable-verity flash vbmeta vbmeta.img`

The `tools/embed.sh --disable-verity` option uses method 2.

## EROFS (Android 12+)

Android 12+ often uses EROFS (read-only) instead of ext4 for the system partition.
EROFS images cannot be mounted read-write. Workaround: extract the image with `fsck.erofs` or `erofs-utils`, rebuild with `mkfs.erofs` after modification.

## Mount Flags

The `nosuid` mount flag on `/system` renders the setuid bit ineffective.
Verify with:

```
cat /proc/mounts | grep ' /system '
```

If `nosuid` is present, it must be removed from the device's `fstab.*` file.
