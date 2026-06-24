#!/usr/bin/env python3

import sys
import os
import struct
import argparse
import shutil
import tempfile
import subprocess

SELINUX_MAGIC = 0xF97CFF8C

POLICYDB_VERSION_MIN = 15
POLICYDB_VERSION_MAX = 33

SU_TE_FRAGMENT = """
type su, domain;
type su_exec, exec_type, file_type, system_file_type;
domain_auto_trans(shell, su_exec, su)
permissive su;
"""

FILE_CONTEXT_LINE = "/system/xbin/su    u:object_r:su_exec:s0\n"


def run(cmd, **kwargs):
    result = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    return result


def check_tool(name):
    if shutil.which(name) is None:
        print(f"[WARN] '{name}' not found in PATH", file=sys.stderr)
        return False
    return True


def patch_file_contexts(fc_path, dry_run=False):
    if not os.path.isfile(fc_path):
        print(f"[WARN] file_contexts not found: {fc_path}")
        return False

    with open(fc_path, "r") as f:
        content = f.read()

    if "su_exec" in content:
        print(f"[INFO] su_exec already present in {fc_path}")
        return True

    print(f"[INFO] Patching file_contexts: {fc_path}")
    if not dry_run:
        with open(fc_path, "a") as f:
            f.write(FILE_CONTEXT_LINE)

    print(f"[OK]   Appended su_exec context")
    return True


def patch_via_sepolicy_inject(policy_path, dry_run=False):
    if not check_tool("sepolicy-inject"):
        print("[WARN] sepolicy-inject not available, skipping binary policy patch")
        return False

    rules = [
        ["--type", "su"],
        ["--type", "su_exec"],
        ["--attr", "su", "domain"],
        ["--attr", "su_exec", "exec_type"],
        ["--attr", "su_exec", "file_type"],
        ["--attr", "su_exec", "system_file_type"],
        ["--transition", "shell", "su_exec", "su"],
        ["--allow", "su", "self", "capability", "setuid"],
        ["--allow", "su", "self", "capability", "setgid"],
        ["--allow", "su", "self", "capability", "dac_override"],
        ["--allow", "su", "self", "capability", "sys_admin"],
        ["--allow", "su", "shell_exec", "file", "read"],
        ["--allow", "su", "shell_exec", "file", "execute"],
        ["--allow", "su", "shell_exec", "file", "open"],
        ["--allow", "su", "devpts", "chr_file", "read"],
        ["--allow", "su", "devpts", "chr_file", "write"],
        ["--allow", "su", "devpts", "chr_file", "open"],
        ["--allow", "su", "devpts", "chr_file", "ioctl"],
        ["--permissive", "su"],
    ]

    backup = policy_path + ".bak"
    if not dry_run and not os.path.exists(backup):
        shutil.copy2(policy_path, backup)
        print(f"[INFO] Backup created: {backup}")

    for rule in rules:
        cmd = ["sepolicy-inject"] + rule + ["-P", policy_path, "-o", policy_path]
        print(f"[INFO] {' '.join(cmd)}")
        if not dry_run:
            result = run(cmd)
            if result.returncode != 0:
                print(f"[WARN] Rule failed: {result.stderr.strip()}")

    print("[OK]   Binary policy patched")
    return True


def patch_runtime(dry_run=False):
    adb = shutil.which("adb")
    if not adb:
        print("[WARN] adb not found, skipping runtime patch")
        return False

    result = run(["adb", "get-state"])
    if result.returncode != 0 or result.stdout.strip() != "device":
        print("[WARN] No adb device connected")
        return False

    print("[INFO] Attempting runtime SELinux patch via adb...")

    policy_local = tempfile.NamedTemporaryFile(suffix=".policy", delete=False)
    policy_local.close()

    pull = run(["adb", "pull", "/sys/fs/selinux/policy", policy_local.name])
    if pull.returncode != 0:
        print("[ERR]  Could not pull policy from device")
        os.unlink(policy_local.name)
        return False

    patched = patch_via_sepolicy_inject(policy_local.name, dry_run=dry_run)

    if patched and not dry_run:
        push = run(["adb", "push", policy_local.name, "/sys/fs/selinux/load"])
        if push.returncode != 0:
            print("[WARN] Could not push patched policy (may require root)")

    os.unlink(policy_local.name)
    return patched


def patch_offline(policy_path, fc_path, dry_run=False):
    if policy_path:
        patch_via_sepolicy_inject(policy_path, dry_run=dry_run)
    if fc_path:
        patch_file_contexts(fc_path, dry_run=dry_run)


def main():
    parser = argparse.ArgumentParser(
        prog="patch_sepolicy.py",
        description="SystematicSU — SELinux policy patcher"
    )

    sub = parser.add_subparsers(dest="mode", required=True)

    p_offline = sub.add_parser("offline", help="Patch policy files offline (before flashing)")
    p_offline.add_argument("--policy",  metavar="PATH", help="Path to precompiled_sepolicy binary")
    p_offline.add_argument("--fc",      metavar="PATH", help="Path to plat_file_contexts")
    p_offline.add_argument("--dry-run", action="store_true")

    p_runtime = sub.add_parser("runtime", help="Patch running device via adb")
    p_runtime.add_argument("--dry-run", action="store_true")

    args = parser.parse_args()

    print("SystematicSU — patch_sepolicy.py")
    print("")

    if args.mode == "offline":
        patch_offline(
            policy_path=args.policy,
            fc_path=args.fc,
            dry_run=args.dry_run
        )
    elif args.mode == "runtime":
        patch_runtime(dry_run=args.dry_run)

    print("")
    print("[OK] Done.")


if __name__ == "__main__":
    main()
