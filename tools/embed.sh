#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

IMAGE=""
BINARY=""
DISABLE_VERITY=0
SUPER_MODE=0
SLOT=""
DRY_RUN=0

BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()   { echo -e "${RED}[ERR]${NC}  $*"; }
die()       { log_err "$*"; exit 1; }

require_tool() {
    for t in "$@"; do
        command -v "$t" &>/dev/null || die "Required tool not found: $t"
    done
}

usage() {
    echo -e "${BOLD}SystematicSU embed.sh${NC}"
    echo ""
    echo "Embeds the su binary into a system.img or super.img."
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "  -i, --image   <path>   Path to system.img or super.img"
    echo "  -b, --binary  <path>   Path to compiled su binary"
    echo "  -s, --slot    <name>   Slot suffix for super.img (e.g. a, b)"
    echo "      --super            Image is a super.img (dynamic partitions)"
    echo "      --disable-verity   Patch vbmeta to disable dm-verity"
    echo "      --dry-run          Print actions without executing"
    echo "  -h, --help             Show this help"
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--image)         IMAGE="$2";         shift 2 ;;
            -b|--binary)        BINARY="$2";        shift 2 ;;
            -s|--slot)          SLOT="$2";           shift 2 ;;
            --super)            SUPER_MODE=1;        shift   ;;
            --disable-verity)   DISABLE_VERITY=1;   shift   ;;
            --dry-run)          DRY_RUN=1;           shift   ;;
            -h|--help)          usage ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    [[ -z "$IMAGE"  ]] && die "--image is required"
    [[ -z "$BINARY" ]] && die "--binary is required"
    [[ ! -f "$IMAGE"  ]] && die "Image not found: $IMAGE"
    [[ ! -f "$BINARY" ]] && die "Binary not found: $BINARY"
}

run_cmd() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
    else
        "$@"
    fi
}

extract_system_from_super() {
    local super_img="$1"
    local out_dir="$2"

    log_info "Extracting system partition from super.img..."

    local slot_suffix=""
    [[ -n "$SLOT" ]] && slot_suffix="_$SLOT"

    run_cmd lpunpack \
        --partition "system${slot_suffix}" \
        "$super_img" \
        "$out_dir"

    local extracted="$out_dir/system${slot_suffix}.img"
    [[ ! -f "$extracted" ]] && die "lpunpack failed: $extracted not found"

    echo "$extracted"
}

repack_super() {
    local super_img="$1"
    local system_img="$2"

    local slot_suffix=""
    [[ -n "$SLOT" ]] && slot_suffix="_$SLOT"

    log_info "Repacking system partition into super.img..."
    run_cmd lpadd \
        --partition "system${slot_suffix}" \
        "$super_img" \
        "$system_img"
}

embed_into_system_img() {
    local img="$1"
    local binary="$2"
    local work_dir="$3"

    local raw_img="$work_dir/system_raw.img"
    local mount_dir="$work_dir/mnt"

    log_info "Converting sparse image to raw..."
    run_cmd simg2img "$img" "$raw_img"

    log_info "Resizing image to ensure free space..."
    run_cmd e2fsck -f -y "$raw_img" || true
    run_cmd resize2fs "$raw_img" "$(du -sm "$raw_img" | awk '{print $1 + 32}')M" || true

    mkdir -p "$mount_dir"
    log_info "Mounting image..."
    run_cmd mount -t ext4 -o loop,rw "$raw_img" "$mount_dir"

    log_info "Creating /system/xbin if missing..."
    run_cmd mkdir -p "$mount_dir/xbin"

    log_info "Copying su binary..."
    run_cmd cp "$binary" "$mount_dir/xbin/su"

    log_info "Setting ownership and permissions..."
    run_cmd chown 0:0 "$mount_dir/xbin/su"
    run_cmd chmod 6755 "$mount_dir/xbin/su"

    local fc_source="$ROOT_DIR/sepolicy/file_contexts"
    if [[ -f "$fc_source" ]]; then
        log_info "Patching file_contexts..."
        local fc_target="$mount_dir/etc/selinux/plat_file_contexts"
        if [[ -f "$fc_target" ]]; then
            if ! grep -q "su_exec" "$fc_target"; then
                run_cmd bash -c "cat '$fc_source' >> '$fc_target'"
            else
                log_warn "su_exec already present in file_contexts, skipping"
            fi
        else
            log_warn "file_contexts not found at $fc_target"
        fi
    fi

    log_info "Unmounting image..."
    run_cmd umount "$mount_dir"

    log_info "Converting back to sparse image..."
    run_cmd img2simg "$raw_img" "$img"

    log_ok "Embedding complete: $img"
}

disable_verity_in_vbmeta() {
    local img_dir
    img_dir="$(dirname "$IMAGE")"
    local vbmeta="$img_dir/vbmeta.img"

    if [[ ! -f "$vbmeta" ]]; then
        log_warn "vbmeta.img not found in $(dirname "$IMAGE"), skipping verity patch"
        return
    fi

    log_info "Disabling dm-verity in vbmeta.img..."
    run_cmd avbtool make_vbmeta_image \
        --flag 2 \
        --output "$vbmeta"

    log_ok "dm-verity disabled in $vbmeta"
}

main() {
    echo -e "${BOLD}"
    echo "  ____            _                     _   _      ____  _   _"
    echo " / ___| _   _ ___| |_ ___ _ __ ___    / \ | |_   / ___|| | | |"
    echo " \___ \| | | / __| __/ _ \ '_ \` _ \  / _ \| __|  \___ \| | | |"
    echo "  ___) | |_| \__ \ ||  __/ | | | | |/ ___ \ |_   ___) | |_| |"
    echo " |____/ \__, |___/\__\___|_| |_| |_/_/   \_\__| |____/ \___/ "
    echo "        |___/  embed.sh — system image patcher"
    echo -e "${NC}"

    parse_args "$@"
    require_tool simg2img img2simg mount umount e2fsck resize2fs

    local work_dir
    work_dir="$(mktemp -d /tmp/systematicsu_XXXXXX)"
    trap 'rm -rf "$work_dir"' EXIT

    local target_img="$IMAGE"

    if [[ $SUPER_MODE -eq 1 ]]; then
        require_tool lpunpack lpadd
        local extracted
        extracted="$(extract_system_from_super "$IMAGE" "$work_dir")"
        embed_into_system_img "$extracted" "$BINARY" "$work_dir"
        repack_super "$IMAGE" "$extracted"
    else
        embed_into_system_img "$target_img" "$BINARY" "$work_dir"
    fi

    if [[ $DISABLE_VERITY -eq 1 ]]; then
        require_tool avbtool
        disable_verity_in_vbmeta
    fi

    log_ok "Done. Run tools/verify.sh to confirm the embedding."
}

main "$@"
