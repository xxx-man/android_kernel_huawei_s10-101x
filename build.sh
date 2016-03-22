#!/bin/bash

# location
export KERNELDIR=`readlink -f .`
export PARENTDIR=`readlink -f ../..`
export INITRAMFS_SOURCE=`readlink -f ${KERNELDIR}/-initrd`
export INITRAMFS_TMP="/tmp/initramfs-source"
export PATH=${PARENTDIR}/prebuilts/gcc/linux-x86/arm/arm-eabi-4.6/bin/:${PATH}

# kernel
export ARCH=arm
export KERNEL_CONFIG="hisi-s10_A_wifi_defconfig"

# system compiler
export CROSS_COMPILE=${PARENTDIR}/prebuilts/gcc/linux-x86/arm/arm-eabi-4.6/bin/arm-eabi-

# build script
export USER=`whoami`
export HOST_CHECK=`uname -n`
export OLDMODULES=`find -name *.ko`

# CPU numbers
NUMBEROFCPUS=`grep 'processor' /proc/cpuinfo | wc -l`

if [ "${1}" != "" ]; then
	export KERNELDIR=`readlink -f ${1}`
fi;

echo ""
echo "==================================================================="
echo "Number of CPU cores:	" $NUMBEROFCPUS
echo "Parent dir:		" $PARENTDIR
echo "Kernel build dir:	" $KERNELDIR
echo "Config:			" $KERNEL_CONFIG
echo "==================================================================="
echo ""
read -rsp $'Press any key or wait 5 seconds to continue...\n' -n 1 -t 5;
echo ""

if [ ! -f ${KERNELDIR}/.config ]; then
	cp ${KERNELDIR}/arch/arm/configs/${KERNEL_CONFIG} .config
	make ${KERNEL_CONFIG}
fi;

. ${KERNELDIR}/.config

# remove previous zImage files
if [ -e ${KERNELDIR}/zImage ]; then
	rm ${KERNELDIR}/zImage
fi;
if [ -e ${KERNELDIR}/arch/arm/boot/zImage ]; then
	rm ${KERNELDIR}/arch/arm/boot/zImage
fi;

# remove all old modules before compile
cd ${KERNELDIR}
for i in $OLDMODULES; do
	rm -f $i
done;

# remove previous initramfs files
if [ -d ${INITRAMFS_TMP} ]; then
	echo "removing old temp iniramfs"
	rm -rf ${INITRAMFS_TMP}
	rm -rf ${INITRAMFS_SOURCE}/lib
fi;
if [ -f "/tmp/cpio*" ]; then
	echo "removing old temp iniramfs_tmp.cpio"
	rm -rf /tmp/cpio*
fi;

# clean initramfs old compile data
rm -f usr/initramfs_data.cpio
rm -f usr/initramfs_data.o

cd ${KERNELDIR}/

if [ $USER != "root" ]; then
	make -j${NUMBEROFCPUS} modules || exit 1
else
	nice -n -15 make -j${NUMBEROFCPUS} modules || exit 1
fi;

# copy initramfs files to tmp directory
cp -ax $INITRAMFS_SOURCE ${INITRAMFS_TMP}

# clear git repositories in initramfs
if [ -e ${INITRAMFS_TMP}/.git ]; then
	rm -rf /tmp/initramfs-source/.git
fi;

# remove empty directory placeholders
find ${INITRAMFS_TMP} -name EMPTY_DIRECTORY -exec rm -rf {} \;

# remove mercurial repository
if [ -d ${INITRAMFS_TMP}/.hg ]; then
	rm -rf ${INITRAMFS_TMP}/.hg
fi;

# remove update initramfs scripts
rm -f ${INITRAMFS_TMP}/update*

# copy modules into initramfs
mkdir -p ${INITRAMFS_SOURCE}/lib/modules
mkdir -p ${INITRAMFS_TMP}/lib/modules
find -name '*.ko' -exec cp -av {} ${INITRAMFS_TMP}/lib/modules/ \;
${CROSS_COMPILE}strip --strip-debug ${INITRAMFS_TMP}/lib/modules/*.ko
chmod 755 ${INITRAMFS_TMP}/lib/modules/*
cp $INITRAMFS_TMP/lib/modules/*.ko $INITRAMFS_SOURCE/lib/modules

# make initramfs package
cd $INITRAMFS_SOURCE
find . | cpio -o -H newc | gzip > ${KERNELDIR}/initrd.cpio.gz
cd ${KERNELDIR}

# make zImage
if [ $USER != "root" ]; then
	time make -j${NUMBEROFCPUS} zImage
else
	time nice -n -15 make -j${NUMBEROFCPUS} zImage
fi;

# make boot
if [ -e ${KERNELDIR}/arch/arm/boot/zImage ]; then
	cp ${KERNELDIR}/arch/arm/boot/zImage ${KERNELDIR}/zImage
	${KERNELDIR}/mkbootimg --kernel zImage --ramdisk initrd.cpio.gz --base 0x00008000 --pagesize 2048 --ramdiskaddr 0x01000000 --cmdline 'console=ttyS0 k3v2_pmem=1 vmalloc=512M androidboot.hardware=hws10101l mmcparts=mmcblk0:p1(xloader),p3(nvme),p4(misc),p5(splash),p6(oeminfo),p7(logo),p8(vrcb),p9(recovery2),p10(recovery),p11(boot),p12(modemimage),p13(modemnv),p14(modemnvm2),p15(cache),p16(system),p17(cust),p18(userdata),p19(reserve1),p20(reserve2),p21(reserve3),p22(data);mmcblk1:p1(sdcard2)' -o ${KERNELDIR}/boot.img
	cp ${KERNELDIR}/.config ${KERNELDIR}/-OUT/
	cp ${KERNELDIR}/boot.img ${KERNELDIR}/-OUT/
	cp ${KERNELDIR}/zImage ${KERNELDIR}/-OUT/
	echo ""
	stat ${KERNELDIR}/boot.img
	cd ${KERNELDIR}/-OUT/
	zip -r Kernel-`date +"[%d-%m-%y]-[%H-%M]-JB"`.zip ".config" "boot.img" "zImage"
	rm -f ${KERNELDIR}/initrd.cpio.gz ${KERNELDIR}/boot.img ${KERNELDIR}/zImage
echo ""
echo "==================================================================="
echo "Done. Check /-OUT folder"
echo "==================================================================="
else
	echo "Kernel STUCK in BUILD! no zImage exist"
fi;
