#!/bin/bash
#
# Compile script for kernel
#

# Initialize flags for options
clean=false
local=false
suonly=false

# Use getopt for parsing long and short options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--clean)
      clean=true
      shift
      ;;
    -l|--local)
      local=true
      shift
      ;;
    -su|--su-only)
      suonly=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

SECONDS=0 # builtin bash timer

if [ "$local" = true ]; then
	ZIPNAME="[AOSP]-Spiteful-sweet-$(date '+%Y%m%d-%H%M').zip"
else
	ZIPNAME="[AOSP]-Spiteful-sweet-$(date '+%Y%m%d').zip"
fi

export ARCH=arm64
export KBUILD_BUILD_USER=vbajs
export KBUILD_BUILD_HOST=tbyool

if [ ! -d "$PWD/clang" ]; then
	git clone https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379.git --depth=1 -b 15.0 clang
else
	echo "Local clang dir found, will not download clang and using that instead"
fi

if [ ! -d "$PWD/gcc32" ] && [ ! -d "$PWD/gcc64" ]; then
       ASSET_URLS=$(curl -s "https://api.github.com/repos/mvaisakh/gcc-build/releases/latest" | grep "browser_download_url" | cut -d '"' -f 4 | grep -E "eva-gcc-arm.*\.xz")
       for url in $ASSET_URLS; do
               wget --content-disposition -L "$url"
       done
       for file in eva-gcc-arm*.xz; do
               #The files are actually just plain tarballs named as .xz, do not call xz to decompress
               if [[ "$file" == *arm64* ]]; then
                       tar -xf "$file" && mv gcc-arm64 gcc64
               else
                       tar -xf "$file" && mv gcc-arm gcc32
               fi
       rm -rf "$file"
       done
else
       echo "Local gcc dirs found, will not download clang and using those instead"
fi

export GCC64_DIR=$PWD/gcc64
export GCC32_DIR=$PWD/gcc32
export PATH="$PWD/clang/bin/:$GCC64_DIR/bin/:$GCC32_DIR/bin/:/usr/bin:$PATH"

#if [ "$local" = true ]; then
#	echo -e "\nLocal build, disabling LTO...\n"
#	patch -p1 < local-build.patch
#fi

if [ "$clean" = true ]; then
	rm -rf out
	echo "Cleaned output folder"
fi

echo -e "\nStarting compilation...\n"
make O=out ARCH=arm64 sweet_defconfig
make -j$(nproc --all) \
    O=out \
    ARCH=arm64 \
    LLVM=1 \
    LLVM_IAS=1 \
    CROSS_COMPILE=$GCC64_DIR/bin/aarch64-elf- \
    CROSS_COMPILE_COMPAT=$GCC32_DIR/bin/arm-eabi-

kernel="out/arch/arm64/boot/Image.gz"
dtbo="out/arch/arm64/boot/dtbo.img"
dtb="out/arch/arm64/boot/dtb.img"

if [ ! -f "$kernel" ] || [ ! -f "$dtbo" ] || [ ! -f "$dtb" ]; then
	echo -e "\nCompilation failed!"
	exit 1
fi

if [ "$suonly" = true ] || [ "$local" = true ]; then
	echo -e "\nNot compiling NSU image..."
	echo -e "\nKernel compiled successfully! Zipping up...\n"
	if [ -d "$AK3_DIR" ]; then
		cp -r $AK3_DIR AnyKernel3
	else
		if ! git clone https://github.com/basamaryan/AnyKernel3.git -b master AnyKernel3; then
			echo -e "\nAnyKernel3 repo not found locally and couldn't clone from GitHub! Aborting..."
			exit 1
		fi
	fi

	sed -i "s/kernel\.string=.*/kernel.string=Staging build/" AnyKernel3/anykernel.sh
	sed -i "s/supported\.versions=.*/supported.versions=11-16/" AnyKernel3/anykernel.sh

	cp $kernel AnyKernel3
	cp $dtbo AnyKernel3
	cp $dtb AnyKernel3
	cd AnyKernel3
	zip -r9 "../$ZIPNAME" * -x .git README.md
	cd ..
	rm -rf AnyKernel3
	if [ "$local" = true ]; then
		git restore arch/arm64/configs/sweet_defconfig
	else
		if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
	   	head=$(git rev-parse --verify HEAD 2>/dev/null); then
	        	HASH="$(echo $head | cut -c1-8)"
		fi
		./telegram -f $ZIPNAME -C "Completed in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) ! Latest commit: $HASH WARNING: KSU ONLY BUILD!"
	fi
	echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
	echo "Zip: $ZIPNAME"
	exit 0
fi
	
echo -e "\n Done compiling KSU, now compiling with disabled KSU.."
mkdir ./out/arch/arm64/boot/ksu/
cp $kernel out/arch/arm64/boot/ksu/Image.gz
ksuboot="out/arch/arm64/boot/ksu/Image.gz"
rm -rf $kernel
make O=out mrproper
make O=out ARCH=arm64 nsu_sweet_defconfig
make -j$(nproc --all) \
    O=out \
    ARCH=arm64 \
    LLVM=1 \
    LLVM_IAS=1 \
    CROSS_COMPILE=$GCC64_DIR/bin/aarch64-elf- \
    CROSS_COMPILE_COMPAT=$GCC32_DIR/bin/arm-eabi-

if [ ! -f "$kernel" ]; then
	echo -e "\nCompilation failed!"
	exit 1
fi

echo -e "\nKernel compiled successfully! Zipping up...\n"
mkdir ./out/arch/arm64/boot/nsu
cp $kernel out/arch/arm64/boot/nsu/Image.gz
nsuboot="out/arch/arm64/boot/nsu/Image.gz"
if [ -d "$AK3_DIR" ]; then
	cp -r $AK3_DIR AnyKernel3
else
	if ! git clone -q https://github.com/tbyool/AnyKernel3.git -b master AnyKernel3; then
		echo -e "\nAnyKernel3 repo not found locally and couldn't clone from GitHub! Aborting..."
		exit 1
	fi
fi
cp $ksuboot AnyKernel3/boot/ksu
cp $nsuboot AnyKernel3/boot/nsu
cp $dtbo AnyKernel3
cp $dtb AnyKernel3
cd AnyKernel3
zip -r9 "../$ZIPNAME" * -x .git README.md
cd ..
rm -rf AnyKernel3
if [ "$local" = true ]; then
	git restore arch/arm64/configs/sweet_defconfig
else
	if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
	   head=$(git rev-parse --verify HEAD 2>/dev/null); then
	        HASH="$(echo $head | cut -c1-8)"
	fi
	./telegram -f $ZIPNAME -C "Completed in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) ! Latest commit: $HASH"
fi
echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
echo "Zip: $ZIPNAME"
exit 0

