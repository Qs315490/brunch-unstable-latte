#!/bin/bash

apply_patches()
{
for patch_type in "base" "others" "chromeos" "all_devices" "mipad2"; do
	if [ -d "./kernel-patches/$1/$patch_type" ]; then
		for patch in ./kernel-patches/"$1/$patch_type"/*.patch; do
			echo "Applying patch: $patch"
			patch -d"./kernels/$1" -p1 --no-backup-if-mismatch -N < "$patch" || { echo "Kernel $1 patch failed"; exit 1; }
		done
	fi
done
}

make_config()
{
sed -i -z 's@# Detect buggy gcc and clang, fixed in gcc-11 clang-14.\n\tdef_bool@# Detect buggy gcc and clang, fixed in gcc-11 clang-14.\n\tdef_bool $(success,echo 0)\n\t#def_bool@g' ./kernels/$1/init/Kconfig
echo "Creating $2 config for kernel $1"
cp ./kernel-patches/mipad2_defconfig ./kernels/$1/arch/x86/configs/chromeos_defconfig
make -C ./kernels/$1 O=out chromeos_defconfig || { echo "Kernel $1 configuration failed"; exit 1; }
}

download_and_patch_kernels()
{
kernel_remote_path="$(git ls-remote https://chromium.googlesource.com/chromiumos/third_party/kernel/ | grep "refs/heads/release-$chromeos_version" | head -1 | sed -e 's#.*\t##' -e 's#chromeos-.*##' | sort -u)chromeos-"
[ ! "x$kernel_remote_path" == "x" ] || { echo "Remote path not found"; exit 1; }
echo "kernel_remote_path=$kernel_remote_path"
for kernel in $kernels; do
	kernel_version=$(curl -Ls "https://chromium.googlesource.com/chromiumos/third_party/kernel/+/$kernel_remote_path$kernel/Makefile?format=TEXT" | base64 --decode | sed -n -e 1,4p | sed -e '/^#/d' | cut -d'=' -f 2 | sed -z 's#\n##g' | sed 's#^ *##g' | sed 's# #.#g')
	echo "kernel_version=$kernel_version"
	[ ! "x$kernel_version" == "x" ] || { echo "Kernel version not found"; exit 1; }

	if [ -f "./chromiumos-$kernel.tar.gz" ];then
		echo "Use Cached ChromiumOS kernel source for kernel $kernel version $kernel_version from https://chromium.googlesource.com/chromiumos/third_party/kernel/+archive/$kernel_remote_path$kernel.tar.gz"
		cp "./chromiumos-$kernel.tar.gz" "./kernels/chromiumos-$kernel.tar.gz"
	else
		echo "Downloading ChromiumOS kernel source for kernel $kernel version $kernel_version from https://chromium.googlesource.com/chromiumos/third_party/kernel/+archive/$kernel_remote_path$kernel.tar.gz"
		curl -L "https://chromium.googlesource.com/chromiumos/third_party/kernel/+archive/$kernel_remote_path$kernel.tar.gz" -o "./kernels/chromiumos-$kernel.tar.gz" || { echo "Kernel source download failed"; exit 1; }
	fi
	mkdir "./kernels/$kernel"
	tar -C "./kernels/$kernel" -zxf "./kernels/chromiumos-$kernel.tar.gz" || { echo "Kernel $kernel source extraction failed"; exit 1; }
	rm -f "./kernels/chromiumos-$kernel.tar.gz"
	apply_patches "$kernel"
	make_config "$kernel" "generic"
done
}

rm -rf ./kernels
mkdir ./kernels

chromeos_version="R136"
kernels="6.12"
download_and_patch_kernels

