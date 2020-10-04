#!/bin/bash

set -e

ROOT=`pwd`
UBOOT="${ROOT}/uboot"
BUILD="${ROOT}/output"
LINUX="${ROOT}/kernel"
EXTER="${ROOT}/external"
SCRIPTS="${ROOT}/scripts"
DEST="${BUILD}/rootfs"
UBOOT_BIN="$BUILD/uboot"
PACK_OUT="${BUILD}/pack"

OS=""
BT=""
CHIP=""
CHIP_BOARD=""
ARCH=""
DISTRO=""
ROOTFS=""
IMAGETYPE=""
UBOOT_PATH=""
BUILD_KERNEL=""
BUILD_MODULE=""

BOARD=""
BOARD_NAME=""
MALI_REL="r6p2"

VER="v2.0.7"
SOURCES="OFCL"
METHOD="download"
KERNEL_NAME="linux"
UNTAR="bsdtar -xpf"
PLATFORM="$(basename `pwd`)"
BOOT_PATH="/media/$(logname)/BOOT"
ROOTFS_PATH="/media/$(logname)/rootfs"
CORES=$(nproc --ignore=1)

if [[ "${EUID}" == 0 ]]; then
        :
else
	echo " "
        echo -e "\e[1;31m This script requires root privileges, trying to use sudo \e[0m"
	echo " "
        sudo "${ROOT}/build.sh"
	exit $?
fi

source "${SCRIPTS}"/lib/general.sh
source "${SCRIPTS}"/lib/pack.sh
source "${SCRIPTS}"/lib/compilation.sh
source "${SCRIPTS}"/lib/distributions.sh
source "${SCRIPTS}"/lib/build_image.sh

prepare_host

MENUSTR="Welcome to Orange Pi Build System. Pls choose Platform."
#################################################################
case "${PLATFORM}" in 

	"OrangePiH2" | "OrangePiH2_mainline")

		OPTION=$(whiptail --title "Orange Pi Build System" \
			--menu "${MENUSTR}" 20 80 10 --cancel-button Exit --ok-button Select \
			"0"  "OrangePi R1" \
			"1"  "OrangePi Zero" \
			3>&1 1>&2 2>&3)

		case "${OPTION}" in 
			"0") 
				BOARD="r1"
				BOARD_NAME="OrangePi R1"
				;;
				
			"1") 
				BOARD="zero" 
				BOARD_NAME="OrangePi Zero"
				;;
				
			*)
			echo -e "\e[1;31m Pls select correct board \e[0m"
			exit 2 ;;
		esac

		if [ "${PLATFORM}" = "OrangePiH2" ]; then
			TOOLS=$ROOT/toolchain/gcc-linaro-1.13.1-2012.02-x86_64_arm-linux-gnueabi/bin/arm-linux-gnueabi-
			UBOOT_COMPILE="${TOOLS}"
			KERNEL_NAME="linux3.4.113"
		elif [ "${PLATFORM}" = "OrangePiH2_mainline" ]; then
			TOOLS=$ROOT/toolchain/gcc-linaro-7.2.1-2017.11-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-
			UBOOT_COMPILE="${TOOLS}"
			KERNEL_NAME="linux5.3.5"
		fi

		ARCH="arm"
		CHIP="sun8iw7p1";
		;;

	"OrangePiH3" | "OrangePiH3_mainline")

		OPTION=$(whiptail --title "Orange Pi Build System" \
			--menu "${MENUSTR}" 20 80 10 --cancel-button Exit --ok-button Select \
			"0"  "OrangePi 2" \
			"1"  "OrangePi Pc" \
			"2"  "OrangePi One" \
			"3"  "OrangePi Lite" \
			"4"  "OrangePi Plus"  \
			"5"  "OrangePi Plus 2e" \
			"6"  "OrangePi Pc Plus" \
			"7"  "OrangePi Zero Plus 2" \
			3>&1 1>&2 2>&3)

		case "${OPTION}" in 
			"0") 
				BOARD="2" 
				BOARD_NAME="OrangePi 2"
				;;
				
			"1") 
				BOARD="pc"	
				BOARD_NAME="OrangePi Pc"
				;;
				
			"2") 
				BOARD="one" 
				BOARD_NAME="OrangePi One"
				;;
				
			"3") 
				BOARD="lite" 
				BOARD_NAME="OrangePi Lite"
				;;
				
			"4") 
				BOARD="plus" 
				BOARD_NAME="OrangePi Plus"
				;;
				
			"5") 
				BOARD="plus2e" 
				BOARD_NAME="OrangePi Plus 2e"
				;;
				
			"6") 
				BOARD="pcplus" 
				BOARD_NAME="OrangePi Pc Plus"
				;;
				
			"7") 
				BOARD="zeroplus2h3" 
				BOARD_NAME="OrangePi Zero Plus 2"
				;;
				
			*)
			echo -e "\e[1;31m Pls select correct board \e[0m"
			exit 2 ;;
		esac

		if [ "${PLATFORM}" = "OrangePiH3" ]; then
			TOOLS=$ROOT/toolchain/gcc-linaro-1.13.1-2012.02-x86_64_arm-linux-gnueabi/bin/arm-linux-gnueabi-
			UBOOT_COMPILE="${TOOLS}"
			KERNEL_NAME="linux3.4.113"
		elif [ "${PLATFORM}" = "OrangePiH3_mainline" ]; then
			TOOLS=$ROOT/toolchain/gcc-linaro-7.2.1-2017.11-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-
			UBOOT_COMPILE="${TOOLS}"
			KERNEL_NAME="linux5.3.5"
		fi

		ARCH="arm"
		CHIP="sun8iw7p1";
		;;

	"OrangePiH5")
	
		OPTION=$(whiptail --title "Orange Pi Build System" \
		        --menu "$MENUSTR" 15 60 5 --cancel-button Exit --ok-button Select \
			"0"  "OrangePi Pc 2" \
			"1"  "OrangePi Prime" \
			"2"  "OrangePi Zero Plus" \
			"3"  "OrangePi Zero Plus 2" \
		        3>&1 1>&2 2>&3)

		case "${OPTION}" in 
			"0") 
				BOARD="pc2" 
				BOARD_NAME="OrangePi Pc 2"
				;;
				
			"1") 
				BOARD="prime" 
				BOARD_NAME="OrangePi Prime"
				;;
				
			"2") 
				BOARD="zeroplus" 
				BOARD_NAME="OrangePi Zero Plus"
				;;
				
			"3") 
				BOARD="zeroplus2h5" 
				BOARD_NAME="OrangePi Zero Plus 2"
				;;
				
			*) 
			echo -e "\e[1;31m Pls select correct board \e[0m"
			exit 2 ;;
		esac

		ARCH="arm64"
		CHIP="sun50iw2p1"
		CHIP_BOARD="cheetah-p1"
		CHIP_FILE="${EXTER}"/chips/"${CHIP}"
		TOOLS=$ROOT/toolchain/gcc-linaro-4.9-2015.01-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
		UBOOT_COMPILE=$ROOT/toolchain/gcc-linaro-4.9-2015.01-x86_64_aarch64-linux-gnu/gcc-linaro/bin/arm-linux-gnueabi-
		KERNEL_NAME="linux3.10"
		;;
	
	"OrangePiA64")
	
		OPTION=$(whiptail --title "Orange Pi Build System" \
		        --menu "$MENUSTR" 15 60 5 --cancel-button Exit --ok-button Select \
			"0"  "OrangePi Win" \
		        3>&1 1>&2 2>&3)

		case "${OPTION}" in 
			"0") BOARD="win" ;;
			*) 
			echo -e "\e[1;31m Pls select correct board \e[0m"
			exit 2 ;;
		esac

		ARCH="arm64"
		CHIP="sun50iw1p1"
		CHIP_BOARD="t1"
		CHIP_FILE="${EXTER}"/chips/"${CHIP}"
		TOOLS=$ROOT/toolchain/gcc-linaro-4.9-2015.01-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
		UBOOT_COMPILE=$ROOT/toolchain/gcc-linaro-4.9-2015.01-x86_64_aarch64-linux-gnu/gcc-linaro/bin/arm-linux-gnueabi-
		KERNEL_NAME="linux3.10"
		;;

	"OrangePiH6" | "OrangePiH6_Linux4.9" | "OrangePiH6_mainline")
	
		OPTION=$(whiptail --title "Orange Pi Build System" \
		        --menu "$MENUSTR" 15 60 5 --cancel-button Exit --ok-button Select \
		        "0"  "OrangePi 3" \
		        "1"  "OrangePi Lite 2" \
		        "2"  "OrangePi One Plus" \
		        "3"  "OrangePi Zero 2" \
		        3>&1 1>&2 2>&3)

		case "${OPTION}" in 
			"0") BOARD="3" ;;
			"1") BOARD="lite2" ;;
			"2") BOARD="zero2" ;;
			"3") BOARD="oneplus" ;;
			*) 
			echo -e "\e[1;31m Pls select correct board \e[0m"
			exit 2 ;;
		esac

		ARCH="arm64"
		CHIP="sun50iw6p1"
		CHIP_BOARD="petrel-p1"
		CHIP_FILE="${EXTER}"/chips/"${CHIP}"
		TOOLS=$ROOT/toolchain/gcc-linaro-4.9-2015.01-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
		UBOOT_COMPILE=$ROOT/toolchain/gcc-linaro-4.9-2015.01-x86_64_aarch64-linux-gnu/gcc-linaro/bin/arm-linux-gnueabi-

		if [ "${PLATFORM}" = "OrangePiH6" ]; then
			KERNEL_NAME="linux3.10"
		elif [ "${PLATFORM}" = "OrangePiH6_Linux4.9" ]; then
			KERNEL_NAME="linux4.9.118"
		elif [ "${PLATFORM}" = "OrangePiH6_mainline" ]; then
			KERNEL_NAME="linux5.3.5"
			TOOLS=$ROOT/toolchain/gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
			UBOOT_COMPILE="${TOOLS}"
		fi
		;;
	*)
		echo -e "\e[1;31m Pls select correct platform \e[0m"
		exit 0
		;;
esac

MENUSTR="Pls select build option"
OPTION=$(whiptail --title "OrangePi Build System" \
	--menu "$MENUSTR" 20 60 10 --cancel-button Finish --ok-button Select \
	"0"   "Build Release Image" \
	"1"   "Build Rootfs" \
	"2"   "Build Uboot" \
	"3"   "Build Linux" \
	"4"   "Update Kernel & Module " \
	"5"   "Update Uboot" \
	3>&1 1>&2 2>&3)

case "${OPTION}" in 
	"0")
		select_distro
		select_mali_realease
		compile_uboot
		compile_kernel
		build_rootfs
		build_image 

		whiptail --title "OrangePi Build System" --msgbox "Succeed to build Image" \
			10 40 0 --ok-button Continue
		;;
	"1")
		select_distro
		select_mali_realease
		build_rootfs
		whiptail --title "OrangePi Build System" --msgbox "Succeed to build rootfs" \
			10 40 0 --ok-button Continue
		;;
	"2")	
		compile_uboot
		;;
	"3")
		compile_kernel
		;;
	"4")
		kernel_update
		;;
	"5")
		uboot_check
		uboot_update
		;;
	*)
		whiptail --title "OrangePi Build System" \
			--msgbox "Pls select correct option" 10 50 0
		;;
esac
