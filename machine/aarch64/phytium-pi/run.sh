#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=scripts/machine-image.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../scripts/machine-image.sh"

machine_image_launcher_init "${BASH_SOURCE[0]}" "$@"

case "${MACHINE_IMAGE_BOOT_MODE}" in
    firmware) required_images=("${FIRMWARE_IMAGES[@]}") ;;
    linux) required_images=("${LINUX_IMAGES[@]}") ;;
    *) machine_image_die "unimplemented boot mode: ${MACHINE_IMAGE_BOOT_MODE}" ;;
esac

machine_image_prepare \
    "${MACHINE_IMAGE_REPO_ROOT}" \
    "${ARCHITECTURE}" \
    "${QEMU_MACHINE}" \
    "${RELEASE_ASSET_PREFIX}" \
    "${required_images[@]}"

case "${MACHINE_IMAGE_BOOT_MODE}" in
    firmware)
        boot_arguments=(
            -drive "file=${MACHINE_IMAGE_DIR}/sdcard.img,if=sd,format=raw"
        )
        ;;
    linux)
        boot_arguments=(
            -kernel "${MACHINE_IMAGE_DIR}/Image.gz"
            -dtb "${MACHINE_IMAGE_DIR}/phytiumpi_firefly.dtb"
            -initrd "${MACHINE_IMAGE_DIR}/rootfs.cpio.gz"
            -append "${QEMU_LINUX_APPEND:-console=ttyAMA1,115200 earlycon=pl011,mmio32,0x2800d000 rdinit=/init}"
        )
        ;;
esac

machine_image_exec "${QEMU_EXECUTABLE}" \
    -machine "${QEMU_MACHINE}" \
    -smp 4 \
    -m 4G \
    -display none \
    -monitor none \
    -serial null \
    -serial stdio \
    "${boot_arguments[@]}" \
    "${MACHINE_IMAGE_QEMU_ARGUMENTS[@]}"
