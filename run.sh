#!/usr/bin/env bash
export LOCALVERSION=
export ZSTD_CLEVEL=1
cp Microsoft/config-wsl .config
opts=(
  # SquashFS
  -e CONFIG_SQUASHFS
  -e CONFIG_SQUASHFS_ZSTD
  -e CONFIG_SQUASHFS_4K_DEVBLK_SIZE
  -e CONFIG_SQUASHFS_ZLIB
  -e CONFIG_SQUASHFS_LZ4
  -e CONFIG_SQUASHFS_LZO
  -e CONFIG_SQUASHFS_XZ
  -e CONFIG_SQUASHFS_XATTR
  -e CONFIG_SQUASHFS_FILE_DIRECT
  -e CONFIG_SQUASHFS_COMP_CACHE_FULL
  # 并行解压（COMPILE只能有一个，且与BY_MOUNT互斥）
  -d CONFIG_SQUASHFS_CHOICE_DECOMP_BY_MOUNT
  -d CONFIG_SQUASHFS_COMPILE_DECOMP_SINGLE
  # -e CONFIG_SQUASHFS_COMPILE_DECOMP_MULTI
  -e CONFIG_SQUASHFS_COMPILE_DECOMP_MULTI_PERCPU
  # 当使用BY_MOUNT的配置项
  # -e CONFIG_SQUASHFS_CHOICE_DECOMP_BY_MOUNT
  # -e CONFIG_SQUASHFS_DECOMP_MULTI
  # -e CONFIG_SQUASHFS_DECOMP_MULTI_PERCPU
  # -e CONFIG_SQUASHFS_DECOMP_SINGLE

  # 内核压缩改 Zstd
  -e CONFIG_KERNEL_ZSTD
  -d CONFIG_KERNEL_GZIP

  # 内核模块压缩
  -e CONFIG_MODULE_COMPRESS
  -e CONFIG_MODULE_COMPRESS_ZSTD
  -e CONFIG_MODULE_DECOMPRESS

  # NTFS3 内置
  -e CONFIG_NTFS3_FS
  -e CONFIG_NTFS3_LZX_XPRESS
  -e CONFIG_NTFS3_FS_POSIX_ACL

  # EROFS
  -e CONFIG_EROFS_FS
  -e CONFIG_EROFS_FS_ZIP_LZMA
  -e CONFIG_EROFS_FS_ZIP_DEFLATE
  -e CONFIG_EROFS_FS_ZIP_ZSTD
  -e CONFIG_EROFS_FS_ZIP_ACCEL
  -e CONFIG_EROFS_FS_PCPU_KTHREAD
  # Android Binder
  -e CONFIG_ANDROID_BINDER_IPC
  -e CONFIG_ANDROID_BINDERFS

  # DMA-BUF Heaps
  -e CONFIG_DMABUF_HEAPS
  -e CONFIG_DMABUF_HEAPS_SYSTEM
  # 禁用WLAN、蓝牙、CAN总线
  -d CONFIG_WLAN
  -d CONFIG_BT
  -d CONFIG_CAN
  # 使vmlinux支持被QEMU启动
  -e CONFIG_PVH
)
./scripts/config "${opts[@]}"
make olddefconfig
make -j$(nproc)
mkdir -p modules modules-debug
make INSTALL_MOD_PATH="$PWD/modules-debug" modules_install
INSTALL_MOD_STRIP=1 make INSTALL_MOD_PATH="$PWD/modules" modules_install

release=$(make -s kernelrelease)
# make -j$(nproc) -C tools/perf NO_JEVENTS=1 NO_JVMTI=1 NO_LIBTRACEEVENT=1 install DESTDIR="$PWD/perf" prefix=/
# 
# for f in "perf/bin/"* "perf/libexec/perf-core/dlfilters/"*.so; do
#   [ -f "$f" ] && strip --strip-debug "$f" 2>/dev/null || true
# done
# 
# cd perf
# mksquashfs . "../perf-$release.sqfs" -comp zstd -b 1M -Xcompression-level 22

for variant in modules modules-debug; do
  tmp_dir=$(mktemp -d)
  staging_dir="$tmp_dir/staging"
  mkdir -p "$staging_dir"
  cp -r "$variant/lib/modules/$release/." "$staging_dir/"
  rm -f "$staging_dir/build" "$staging_dir/source"

  staging_size=$(du -bs "$staging_dir" | awk '{print $1;}')
  image_size=$((staging_size + (16 * (1 << 20))))
  image_blocks=$((image_size / 1024))
  inode_count=$(find "$staging_dir" | wc -l)
  inode_count=$((inode_count + 4096))

  mke2fs -q -L '' -m 0 -O ^has_journal -d "$staging_dir" -N "$inode_count" -b 1024 -t ext4 "$tmp_dir/$variant.img" "$image_blocks"
  debugfs -w "$tmp_dir/$variant.img" -R "rmdir /lost+found"
  qemu-img convert -O vhdx -o block_size=1M "$tmp_dir/$variant.img" "$variant.vhdx"
  rm -rf "$tmp_dir"
done
cp -f arch/x86/boot/bzImage .
# 分开执行以保留大小信息
tar -cvSf kernel.tar modules.vhdx modules-debug.vhdx vmlinux bzImage
rm bzImage
zstd --rm kernel.tar -fvo /mnt/d/wsl/kernel.tar.zst
ls -lh arch/x86/boot/bzImage modules.vhdx modules-debug.vhdx vmlinux
