# K230 source and build inputs

| Input | Revision |
| --- | --- |
| [Official K230 Linux SDK](https://github.com/kendryte/k230_linux_sdk) | `fc6cc2151d54cb307be47f81815023f7ffb0eae6` |
| Buildroot | SDK-selected `2025.02.1`, verified by `tools/download/buildroot.hash` |
| [Linux Xuantie kernel](https://github.com/ruyisdk/linux-xuantie-kernel) | Linux `6.6.36`, SDK-selected commit `7d4e1f444f461dbe3833bd99a4640e7b6c2cd529` |
| U-Boot | SDK overlay applied to upstream `2022.10` |
| OpenSBI | SDK overlay applied to upstream `1.4` |
| Toolchain | SDK-selected Xuantie GCC `14.1.1`, Linux `6.6.0` headers, V3.0.2 dated `20250410` |
| Container | Ubuntu 22.04, `sha256:0a9887931b0e38af2e3487ed39e29436b0535c4f3f52e57745baaf79d1898956` |

The toolchain comes from the URL in `Dockerfile.sdk`. Its SHA-256 is
`2215e1ffe1b9b9277b1f5af2f61102e83973163404f29b04da7097fdafa9e1b7`.
This was computed after checking the archive against the MD5 published in
the SDK's `tools/install_toolchain_and_depend.sh`.

The kernel is downloaded as an archive of the SDK's pinned Git commit to
avoid fetching the full kernel repository history. The source archive is
checked by `buildroot-external/patches/linux/linux.hash`. Buildroot retains
its normal source hash and external-toolchain compatibility checks. The
external tree also supplies source hashes for the SDK's OpenSBI and U-Boot
versions, which differ from Buildroot's default package versions.

## QEMU profile

`buildroot-external/` is a standard br2-external tree registered through
`scripts/configure-buildroot.sh`. Its defconfig selects the SDK's kernel,
firmware versions, and preinstalled toolchain. The SDK's existing package
rules and source overlays perform the component builds.

The changes for QEMU are confined to configuration and board integration:

- A minimal kernel and BusyBox initramfs provide UART0 login, procfs, sysfs,
  devtmpfs, and writable temporary filesystems.
- `board/k230-qemu.dts` describes the emulated devices. It follows the SDK
  device addresses and the QEMU machine's RAM, hart, and timer configuration.
- A U-Boot configuration fragment sets the text address to `0x08000000`
  and uses an in-memory environment. A pre-configure hook selects hart 0
  and adjusts the embedded device tree's timer frequency and ISA to match
  QEMU after the SDK has installed its U-Boot overlay.
- OpenSBI uses the generic platform, with firmware at `0x08000000`, Linux
  at `0x08200000`, and the DTB at `0x0a000000`.
- The post-image script wraps `fw_jump.bin` with a standard U-Boot image
  header. The SDK's physical-board post-build and post-image scripts are
  replaced by this QEMU-specific post-image step.

`BR2_REPRODUCIBLE` enables Buildroot's timestamp handling. Locally compiled
outputs are checked by the normal image packaging and release mechanisms;
they are not compared with historical binary checksums.

## Validation

The SDK was built with its native Makefile and the pinned Xuantie toolchain.
The five exported files passed the shared assembly, finalization, packaging,
and archive checksum checks. Both launchers were tested from the packaged
archive with QEMU `11.1.50` (`113931b509`): root login and guest file reads
and writes succeeded, and `sleep 2` took approximately 2.04 host seconds in
both boot modes. The Docker Bake definition was validated; the container
build itself requires a Docker builder and was not run in this environment.
