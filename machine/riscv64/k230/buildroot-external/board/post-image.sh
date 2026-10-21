#!/bin/sh

set -eu

"${HOST_DIR}/bin/mkimage" \
    -A riscv -O linux -T kernel -C none \
    -a 0x08000000 -e 0x08000000 -n opensbi \
    -d "${BINARIES_DIR}/fw_jump.bin" "${BINARIES_DIR}/fw_jump.uImage"
