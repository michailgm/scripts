#!/bin/bash

deboostrap_rootfs() {
	dist="$1"
	tgz="$(readlink -f "$2")"
	TEMP=$(mktemp -d)

	[ "$TEMP" ] || exit 1
	cd $TEMP && pwd

	# this is updated very seldom, so is ok to hardcode
	debian_archive_keyring_deb="${SOURCES}/pool/main/d/debian-archive-keyring/debian-archive-keyring_2019.1_all.deb"
	wget -O keyring.deb "$debian_archive_keyring_deb"
	ar -x keyring.deb && rm -f control.tar.gz debian-binary && rm -f keyring.deb
	DATA=$(ls data.tar.*) && compress=${DATA#data.tar.}

	KR=debian-archive-keyring.gpg
	bsdtar --include ./usr/share/keyrings/$KR --strip-components 4 -xvf "$DATA"
	rm -f "$DATA"

	apt-get -y install debootstrap qemu-user-static

	qemu-debootstrap --arch=${ROOTFS_ARCH} --keyring=$TEMP/$KR $dist rootfs ${SOURCES}
	rm -f $KR

	# keeping things clean as this is copied later again
	rm -f rootfs"${QEMU}"

	bsdtar -C $TEMP/rootfs -a -cf $tgz .
	rm -fr $TEMP/rootfs
}

do_chroot() {
	# Add qemu emulation.
	cp ${QEMU} "$DEST/usr/bin"

	cmd="$@"
	chroot "$DEST" mount -t proc proc /proc || true
	chroot "$DEST" mount -t sysfs sys /sys || true
	chroot "$DEST" $cmd
	chroot "$DEST" umount /sys
	chroot "$DEST" umount -fR /proc

	# Clean up
	rm -f "${DEST}${QEMU}"
}

do_conffile() {
        mkdir -p $DEST/opt/boot

	BOARD_FILE="$EXTER/chips/${CHIP}"
	
	case "${PLATFORM}" in
		
		"OrangePiH2" | "OrangePiH3" | "OrangePiH5" | "OrangePiA64" | "OrangePiH6_Linux4.9")
	       	 	[[ -d ${BOARD_FILE}/boot_emmc ]] && cp ${BOARD_FILE}/boot_emmc/* $DEST/opt/boot/ -f
	        	cp ${BOARD_FILE}/resize_rootfs.sh $DEST/usr/local/sbin/ -f
	       	 	cp ${BOARD_FILE}/install_to_emmc $DEST/usr/local/sbin/install_to_emmc -f
	       	 	cp ${BOARD_FILE}/orangepi"${BOARD}"/sbin/* $DEST/usr/local/sbin/ -f
	       	 	cp ${BOARD_FILE}/orangepi"${BOARD}"/modules.conf $DEST/etc/modules-load.d/ -f
			;;
			
		"OrangePiH2_mainline" | "OrangePiH3_mainline" | "OrangePiH6_mainline")
	       	 	[[ -d ${BOARD_FILE}/mainline/boot_emmc ]] && cp ${BOARD_FILE}/mainline/boot_emmc/* $DEST/opt/boot/ -f
			cp $BUILD/uboot/u-boot-sunxi-with-spl.bin-${BOARD} $DEST/opt/boot/u-boot-sunxi-with-spl.bin -f
	       	 	cp ${BOARD_FILE}/mainline/install_to_emmc_$OS $DEST/usr/local/sbin/install_to_emmc -f
	        	cp ${EXTER}/common/mainline/resize_rootfs.sh $DEST/usr/local/sbin/ -f
	       	 	cp ${BOARD_FILE}/mainline/orangepi"${BOARD}"/sbin/* $DEST/usr/local/sbin/ -f
	       	 	cp ${BOARD_FILE}/mainline/orangepi"${BOARD}"/modules.conf $DEST/etc/modules-load.d/ -f
			;;

		*)	
		        echo -e "\e[1;31m Pls select correct platform \e[0m"
		        exit 0
			;;
	esac

        cp $EXTER/common/rootfs/sshd_config $DEST/etc/ssh/ -f
        cp $EXTER/common/rootfs/networking.service $DEST/lib/systemd/system/networking.service -f
        cp $EXTER/common/rootfs/profile_for_root $DEST/root/.profile -f
        cp $EXTER/common/rootfs/cpu.sh $DEST/usr/local/sbin/ -f

        chmod +x $DEST/usr/local/sbin/*
}

add_bt_service() {
	cat > "$DEST/lib/systemd/system/bt.service" <<EOF
[Unit]
Description=OrangePi BT Service

[Service]
ExecStart=/usr/local/sbin/bt.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
	do_chroot systemctl enable bt.service
}

add_audio_service() {
	cat > "$DEST/lib/systemd/system/audio.service" <<EOF
[Unit]
Description=OrangePi Audio Service

[Service]
ExecStart=/usr/local/sbin/audio.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        do_chroot systemctl enable audio.service
}

add_ssh_keygen_service() {
	cat > "$DEST/etc/systemd/system/ssh-keygen.service" <<EOF
[Unit]
Description=Generate SSH keys if not there
Before=ssh.service
ConditionPathExists=|!/etc/ssh/ssh_host_key
ConditionPathExists=|!/etc/ssh/ssh_host_key.pub
ConditionPathExists=|!/etc/ssh/ssh_host_rsa_key
ConditionPathExists=|!/etc/ssh/ssh_host_rsa_key.pub
ConditionPathExists=|!/etc/ssh/ssh_host_dsa_key
ConditionPathExists=|!/etc/ssh/ssh_host_dsa_key.pub
ConditionPathExists=|!/etc/ssh/ssh_host_ecdsa_key
ConditionPathExists=|!/etc/ssh/ssh_host_ecdsa_key.pub
ConditionPathExists=|!/etc/ssh/ssh_host_ed25519_key
ConditionPathExists=|!/etc/ssh/ssh_host_ed25519_key.pub

[Service]
ExecStart=/usr/bin/ssh-keygen -A
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=ssh.service
EOF
	do_chroot systemctl enable ssh-keygen
}

add_opi_python_gpio_libs() {
        cp $EXTER/common/OPi.GPIO $DEST/usr/local/sbin/ -rfa

        cat > "$DEST/install_opi_gpio" <<EOF
#!/bin/bash

cd /usr/local/sbin/OPi.GPIO
python3 setup.py install
EOF
        chmod +x "$DEST/install_opi_gpio"
        do_chroot /install_opi_gpio
	rm $DEST/install_opi_gpio

	cp ${BOARD_FILE}/orangepi"${BOARD}"/test_gpio.py $DEST/usr/local/sbin/ -f
}

add_opi_config_libs() {
        cp $EXTER/common/opi_config_libs $DEST/usr/local/sbin/ -rfa
        cp $EXTER/common/opi_config_libs/opi-config $DEST/usr/local/sbin/ -rfa

	rm -rf $DEST/etc/update-motd.d/* 
        cp $EXTER/common/rootfs/update-motd.d/* $DEST/etc/update-motd.d/ -rf
}

add_opi_wallpaper() {
	WPDIR="$DEST/usr/share/xfce4/backdrops/"

	if [ $TYPE = "1" -o -d $DEST/usr/share/xfce4/backdrops ]; then
		cp $EXTER/common/rootfs/orangepi*.jpg ${WPDIR} -f
		cd ${WPDIR}
		rm -f xubuntu-wallpaper.png
		ln -sv orangepi1.jpg xubuntu-wallpaper.png 
		cd -
	fi
}

add_debian_apt_sources() {
	local release="$1"
	local aptsrcfile="$DEST/etc/apt/sources.list"
	cat > "$aptsrcfile" <<EOF
deb ${SOURCES} ${release} main contrib non-free
#deb-src ${SOURCES} ${release} main contrib non-free
EOF
	# No separate security or updates repo for unstable/sid
	[ "$release" = "sid" ] || cat >> "$aptsrcfile" <<EOF
deb ${SOURCES} ${release}-updates main contrib non-free
#deb-src ${SOURCES} ${release}-updates main contrib non-free

deb http://security.debian.org/ ${release}/updates main contrib non-free
#deb-src http://security.debian.org/ ${release}/updates main contrib non-free
EOF
}

add_ubuntu_apt_sources() {
	local release="$1"
	cat > "$DEST/etc/apt/sources.list" <<EOF
deb ${SOURCES} ${release} main restricted universe multiverse
deb-src ${SOURCES} ${release} main restricted universe multiverse

deb ${SOURCES} ${release}-updates main restricted universe multiverse
deb-src ${SOURCES} ${release}-updates main restricted universe multiverse

deb ${SOURCES} ${release}-security main restricted universe multiverse
deb-src $SOURCES ${release}-security main restricted universe multiverse

deb ${SOURCES} ${release}-backports main restricted universe multiverse
deb-src ${SOURCES} ${release}-backports main restricted universe multiverse
EOF
}

prepare_env()
{
	if [ ${ARCH} = "arm" ];then
		QEMU="/usr/bin/qemu-arm-static"
		ROOTFS_ARCH="armhf"
	elif [ ${ARCH} = "arm64" ];then
		QEMU="/usr/bin/qemu-aarch64-static"
		ROOTFS_ARCH="arm64"
	fi

	if [ ! -d "$DEST" ]; then
		echo "Destination $DEST not found or not a directory."
		echo "Create $DEST"
		mkdir -p $DEST
	fi

	if [ "$(ls -A -Ilost+found $DEST)" ]; then
		echo "Destination $DEST is not empty."
		echo "Clean up space."
		rm -rf $DEST
	fi

	cleanup() {
		if [ -e "$DEST/proc/cmdline" ]; then
			umount "$DEST/proc"
		fi
		if [ -d "$DEST/sys/kernel" ]; then
			umount "$DEST/sys"
		fi
		if [ -d "$TEMP" ]; then
			rm -rf "$TEMP"
		fi
	}
	trap cleanup EXIT

	case $DISTRO in
		"xenial" | "bionic" | "focal")
			case $SOURCES in
				"OFCL")
					SOURCES="http://ports.ubuntu.com"
					ROOTFS="http://cdimage.ubuntu.com/ubuntu-base/releases/${DISTRO}/release/ubuntu-base-${DISTRO_NUM}-base-${ROOTFS_ARCH}.tar.gz"
					;;
				"ALIYUN")
					SOURCES="http://mirrors.aliyun.com/ubuntu-ports"
					ROOTFS="https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/ubuntu-base/releases/${DISTRO}/release/ubuntu-base-${DISTRO_NUM}-base-${ROOTFS_ARCH}.tar.gz"
					;;
				"USTC")
					SOURCES="http://mirrors.ustc.edu.cn/ubuntu-ports"
					ROOTFS="https://mirrors.ustc.edu.cn/ubuntu-cdimage/ubuntu-base/releases/${DISTRO}/release/ubuntu-base-${DISTRO_NUM}-base-${ROOTFS_ARCH}.tar.gz"
					;;
				"TSINGHUA")
					SOURCES="http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports"
					ROOTFS="https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/ubuntu-base/releases/${DISTRO}/release/ubuntu-base-${DISTRO_NUM}-base-${ROOTFS_ARCH}.tar.gz"
					;;
				"HUAWEI")
					SOURCES="http://mirrors.huaweicloud.com/ubuntu-ports"
					ROOTFS="https://mirrors.huaweicloud.com/ubuntu-cdimage/ubuntu-base/releases/${DISTRO}/release/ubuntu-base-${DISTRO_NUM}-base-${ROOTFS_ARCH}.tar.gz"
					;;
				*)
					SOURCES="http://ports.ubuntu.com"
					ROOTFS="http://cdimage.ubuntu.com/ubuntu-base/releases/${DISTRO}/release/ubuntu-base-${DISTRO_NUM}-base-${ROOTFS_ARCH}.tar.gz"
					;;
			esac
			;;
		"stretch" | "buster" | "bullseye")
			ROOTFS="${DISTRO}-base-${ARCH}.tar.gz"
			METHOD="debootstrap"

			case $SOURCES in
				"OFCL")
					SOURCES="http://ftp.debian.org/debian"
					;;

				"ALIYUN")
					SOURCES="http://mirrors.aliyun.com/debian"
					;;

				"USTC")
					SOURCES="http://mirrors.ustc.edu.cn/debian"
					;;

				"TSINGHUA")
					SOURCES="https://mirrors.tuna.tsinghua.edu.cn/debian"
					;;
				"HUAWEI")
					SOURCES="https://mirrors.huaweicloud.com/debian"
					;;
				*)
					SOURCES="http://httpredir.debian.org/debian"
					;;
		        esac
			;;
		*)
			echo "Unknown distribution: $DISTRO"
			exit 1
			;;
	esac

	TARBALL="$EXTER/$(basename $ROOTFS)"
	if [ ! -e "$TARBALL" ]; then
		if [ "$METHOD" = "download" ]; then
			echo "Downloading $DISTRO rootfs tarball ..."
			wget -O "$TARBALL" "$ROOTFS"
		elif [ "$METHOD" = "debootstrap" ]; then
			deboostrap_rootfs "$DISTRO" "$TARBALL"
		else
			echo "Unknown rootfs creation method"
			exit 1
		fi
	fi

	# Extract with BSD tar
	echo -n "Extracting ... "
	mkdir -p $DEST
	$UNTAR "$TARBALL" -C "$DEST"
	echo "OK"
}

prepare_rootfs_server()
{
	DEBUSER="orangepi"

	if [ -f $DEST/etc/resolv.conf ]; then
		rm -f $DEST/etc/resolv.conf
	fi
	
	cp /etc/resolv.conf "$DEST/etc/resolv.conf"
	
	if [ -f $DEST/etc/apt/sources.list.d/proposed.list ]; then
		rm -rf $DEST/etc/apt/sources.list.d/proposed.list
	fi
	
	add_${OS}_apt_sources $DISTRO

	case "${DISTRO}" in

		"xenial" | "bionic" | "focal")
			EXTRADEBS="software-properties-common libjpeg8-dev usbmount ubuntu-minimal"
			;;
			
		"stretch" | "buster" | "bullseye")
			EXTRADEBS="initscripts software-properties-common sudo libjpeg-dev" 
			;;

		*)	
			echo "Unknown DISTRO=$DISTRO"
			exit 2
			;;
	esac

	case "${DISTRO}" in

		"xenial")
			EXTRADEBS="${EXTRADEBS} libmpfr4 libisl15 libxtables11 ntfs-config hostap-utils"
			LLVM_V=""
			;;
			
		"bionic")
			EXTRADEBS="${EXTRADEBS} libmpfr6 libisl19 libxtables12 ntfs-config"
			LLVM_V="10"
			;;
			
		"focal")
			EXTRADEBS="${EXTRADEBS} libmpfr6 libisl22 libxtables12"
			LLVM_V="10"
			;;
			
		"stretch")
			EXTRADEBS="${EXTRADEBS} libmpfr4 libisl15 libxtables12 ntfs-config hostap-utils"
			LLVM_V="7"
			;;

		"buster")
			EXTRADEBS="${EXTRADEBS} libmpfr6 libisl19 libxtables12" 
			LLVM_V="7"
			;;

		"bullseye")
			EXTRADEBS="${EXTRADEBS} libmpfr6 libisl22 libxtables12" 
			LLVM_V="10"
			;;

		*)	
			echo "Unknown DISTRO=$DISTRO"
			exit 2
			;;		
	esac
	
	MANUFACTURER="Manufacturer: Xunlong"
	BRAND="Brand: OrangePi"
	BOARDNAME="Board name: ${BOARD_NAME}"
	ARCHITECTURE="Architecture: ${ARCH}"
	MAINCHIP="Main chip: ${CHIP}"
	BOARDCHIP="Board chip: ${CHIP_BOARD}"
	
	cat > "$DEST/second-phase" <<EOF
#!/bin/bash
apt-get update -y
apt-get install -y locales-all

export LANG=en_US.UTF-8 
export LANGUAGE=en_US.UTF-8
export LC_CTYPE='en_US.UTF-8'
export LC_NUMERIC=en_US.UTF-8
export LC_TIME=en_US.UTF-8
export LC_COLLATE='en_US.UTF-8'
export LC_MONETARY=en_US.UTF-8
export LC_MESSAGES='en_US.UTF-8'
export LC_PAPER=en_US.UTF-8
export LC_NAME=en_US.UTF-8
export LC_ADDRESS=en_US.UTF-8
export LC_TELEPHONE=en_US.UTF-8
export LC_MEASUREMENT=en_US.UTF-8
export LC_IDENTIFICATION=en_US.UTF-8
export LC_ALL=en_US.UTF-8

export DEBIAN_FRONTEND=noninteractive
locale-gen en_US.UTF-8

apt-get -y install openssh-server
apt-get -y install python3-pip python3-setuptools

echo "Installing $EXTRADEBS"
apt-get -y --no-install-recommends install $EXTRADEBS

apt-get install -f
apt-get -y remove --purge ureadahead
apt-get -y update
adduser --gecos $DEBUSER --disabled-login $DEBUSER --uid 1000
adduser --gecos root --disabled-login root --uid 0
echo root:orangepi | chpasswd
chown -R 1000:1000 /home/$DEBUSER
echo "$DEBUSER:$DEBUSER" | chpasswd
usermod -a -G sudo $DEBUSER
usermod -a -G adm $DEBUSER
usermod -a -G video $DEBUSER
usermod -a -G plugdev $DEBUSER
apt-get -y autoremove
apt-get clean

export BOARDINFO="/etc/board_info"
echo -e "$MANUFACTURER" > \$BOARDINFO
echo -e "$BRAND" >> \$BOARDINFO
echo -e "$BOARDNAME" >> \$BOARDINFO
echo -e "$ARCHITECTURE" >> \$BOARDINFO
echo -e "$MAINCHIP" >> \$BOARDINFO
echo -e "$BOARDCHIP" >> \$BOARDINFO

EOF

if [ ! -f $ROOT/jool-4.1.3.tar.gz ]; then
	cd $ROOT
	wget https://jool.mx/download/jool-4.1.3.tar.gz
fi

cd $ROOT
tar xvf jool-4.1.3.tar.gz

if [ ! -d /usr/local/src ]; then
	mkdir -p /usr/local/src
fi

cp $ROOT/jool-4.1.3 $DEST/usr/local/src/ -rfa
rm -fr $ROOT/jool-4.1.3

	cat > "$DEST/install_packages" <<EOF
#!/bin/bash

export LOGFILE="/root/install_packages.log"

install_package() {
	export DEBIAN_FRONTEND=noninteractive 
	apt-get -y -qq install \$1

	if [ \$? -ne 0 ]; then
		echo -e "\${1} - fail" >> \$LOGFILE
	else
		echo -e "\${1} - success" >> \$LOGFILE
	fi
}

echo -n "" > \$LOGFILE

declare -a List=(
			"geoip-database"
			"iputils-arping"
			"arping"
			"autotools-dev"
			"automake"
			"libnl-genl-3-dev"
			"resolvconf"
            "build-essential"
			"dosfstools"
			"xz-utils"
			"alsa-utils"
			"rsync"
			"u-boot-tools"
			"vim parted"
			"libsysfs-dev"
			"libdrm-dev"
			"xutils-dev"
			"man"
			"subversion"
			"imagemagick"
			"libv4l-dev"
			"cmake"
			"dialog"
			"expect"
			"bc"
			"cpufrequtils"
			"figlet"
			"toilet"
			"lsb-core"
			"genisoimage"
            "util-linux"
            "bluetooth"
            "bluez"
            "bluez-tools"
            "rfkill"
            "dirmngr"
            "gnupg"
            "apt-transport-https"
            "ca-certificates"
            "apt-offline"
            "autoconf"
            "gettext"
            "pkg-config"
            "libtool"
            "debhelper"
            "libpcap0.8-dev"
            "libnl-genl-3-dev"
            "libunwind8"
            "libcups2"
            "libmpc-dev"
            "libmpc3"
            "libmpfr-dev"
            "libgmp-dev"
            "libgmp10"
            "libisl-dev"
            "libppl-dev"
            "libppl-c4"
            "libppl14"
            "libcloog-isl-dev"
            "libcloog-isl4"
            "libcloog-ppl-dev"
            "libcloog-ppl1"
            "systemd"
            "ntpdate"
            "xzip"
            "bzip2"
            "gzip"
            "libfsntfs-utils"
            "libpam0g"
            "lprng"
            "lshw"
            "manpages"
            "mc"
            "ifenslave"
            "ifmetric"
			"ifupdown"
            "ifupdown-extra"
            "ifupdown-multi"			
            "git"
            "docbook-xsl"
            "dos2unix"
            "attr"
            "avahi-autoipd"
            "avahi-daemon"
            "e2fsprogs"
            "software-properties-common"
            "python"
            "python3"
            "ntfs-3g"           
            "scrounge-ntfs"
            "libcap-ng0"
            "libcap-dev"
            "arping"
            "bind9"
            "bind9-doc"
            "bind9utils"
            "bridge-utils"
            "cifs-utils"
            "dnsutils"
            "arptables"
            "ethtool"
            "hostapd"
            "ntp"
            "iptraf"
            "iptraf-ng"
            "isatapd"
            "isc-dhcp-client"
            "isc-dhcp-server"
            "iw"
            "miredo"            
            "netplan"
            "net-tools"
            "nslcd"
            "telnet"
            "wireless-tools"
            "wpasupplicant"
            "wakeonlan"
            "wide-dhcpv6-client"
            "wide-dhcpv6-server"
            "iptables-dev"
            "macchanger"
            "sendmail-base"
            "ucarp"
            "vlan"
            "samba-common"
            "samba"
            "smbclient"
            "libnss-winbind"
            "libpam-winbind"
            "winbind"
            "tasksel"
            "curl"
			"xtables-addons-common"
			"xtables-addons-dkms"
			"libllvm${LLVM_V}"
			"llvm-${LLVM_V}"
			"llvm-${LLVM_V}-dev"
			"llvm-${LLVM_V}-examples"
			"llvm-${LLVM_V}-runtime"
			"libllvm-${LLVM_V}-ocaml-dev"
			"clang-${LLVM_V}"
			"clang-tools-${LLVM_V}"
			"libclang-common-${LLVM_V}-dev"
			"libclang-${LLVM_V}-dev"
			"libclang1-${LLVM_V}"
			"clang-format-${LLVM_V}"
			"libfuzzer-${LLVM_V}-dev"
			"lldb-${LLVM_V}"
			"lld-${LLVM_V}"
			"libc++-${LLVM_V}-dev"
			"libc++abi-${LLVM_V}-dev"
			"libomp-${LLVM_V}-dev"
				)

apt-get -y autoremove
apt-get -y update

for package in "\${List[@]}";
   do
	 echo "installing \${package}"
	 install_package \$package
   done

apt-get install -f
apt-get -y remove --purge ureadahead
apt-get -y update
dpkg --configure -a

apt-get -y autoremove
apt-get clean

ln -sf /usr/bin/genisoimage /usr/bin/mkisofs
ln -sf /usr/bin/make /usr/bin/gmake
ln -sf /run/resolvconf/resolv.conf /etc/resolv.conf

echo $(echo "" | select-editor | grep "mcedit" | head -n1 | cut -d"." -f1) | select-editor
systemctl daemon-reload
timedatectl set-timezone 'Europe/Sofia'
ntpdate bg.pool.ntp.org
systemctl enable ntp
systemctl enable systemd-timesyncd

chown root /etc/rc.local
chmod 755 /etc/rc.local
systemctl restart rc-local

apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF
echo "deb https://download.mono-project.com/repo/${OS} stable-${DISTRO} main" | sudo tee /etc/apt/sources.list.d/mono-official-stable.list
apt-get -y -qq install ca-certificates-mono mono-xsp4 mono-complete mono-devel

cd /usr/local/src/jool-4.1.3
./configure --prefix=/usr
make
make install
cd ..
rm -fr jool-4.1.3

EOF

	chmod +x $DEST/second-phase
	do_chroot /second-phase
	
	if [ -f $DEST/second-phase ]; then
		rm -f $DEST/second-phase
	fi

	chmod +x $DEST/install_packages
	do_chroot /install_packages
	
	if [ -f $DEST/install_packages ]; then
		rm -f $DEST/install_packages
	fi
	
	if [ -f $DEST/etc/resolv.conf ]; then
        rm -f $DEST/etc/resolv.conf
	fi
	
	cd $BUILD
	tar czf ${DISTRO}_${ARCH}_server_rootfs.tar.gz rootfs
}

prepare_rootfs_desktop()
{
	cp /etc/resolv.conf "$DEST/etc/resolv.conf"
	add_${OS}_apt_sources $DISTRO

	if [ $DISTRO = "xenial" ]; then
		if [ ${ARCH} = "arm64" ];then
	cat > "$DEST/type-phase" <<EOF
#!/bin/bash
apt-get update -y
apt-get install -y locales-all

export LANG=en_US.UTF-8 
export LANGUAGE=en_US.UTF-8
export LC_CTYPE='en_US.UTF-8'
export LC_NUMERIC=en_US.UTF-8
export LC_TIME=en_US.UTF-8
export LC_COLLATE='en_US.UTF-8'
export LC_MONETARY=en_US.UTF-8
export LC_MESSAGES='en_US.UTF-8'
export LC_PAPER=en_US.UTF-8
export LC_NAME=en_US.UTF-8
export LC_ADDRESS=en_US.UTF-8
export LC_TELEPHONE=en_US.UTF-8
export LC_MEASUREMENT=en_US.UTF-8
export LC_IDENTIFICATION=en_US.UTF-8
export LC_ALL=en_US.UTF-8

export DEBIAN_FRONTEND=noninteractive
locale-gen en_US.UTF-8

apt-get -y install openssh-server
apt-get -y install python3-pip python3-setuptools

apt-get -y install xubuntu-desktop

apt-get -y autoremove
EOF
		else
	cat > "$DEST/type-phase" <<EOF
#!/bin/bash
apt-get update
apt-get -y install lubuntu-desktop

apt-get -y autoremove
EOF
		fi
	else
	cat > "$DEST/type-phase" <<EOF
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y install xorg xfce4 xfce4-goodies vlc network-manager-gnome

apt-get -y autoremove
EOF
	fi

	chmod +x $DEST/type-phase
	do_chroot /type-phase
	
	if [ -f $DEST/type-phase ]; then
		rm -f $DEST/type-phase
	fi

	if [ -f $DEST/etc/resolv.conf ]; then
        rm -f $DEST/etc/resolv.conf
	fi
	
	cd $BUILD
	tar czf ${DISTRO}_${ARCH}_desktop_rootfs.tar.gz rootfs
}

server_setup()
{
	# cat > "$DEST/etc/network/interfaces.d/eth0" <<EOF
# auto eth0
# iface eth0 inet dhcp
# EOF

	cat > "$DEST/etc/network/interfaces" <<EOF
# interfaces(5) file used by ifup(8) and ifdown(8)
# Include files from /etc/network/interfaces.d:
source-directory /etc/network/interfaces.d

auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

EOF

	cat > "$DEST/etc/hostname" <<EOF
orangepi$BOARD
EOF
	cat > "$DEST/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 orangepi$BOARD

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
	cat > "$DEST/run/resolvconf/resolv.conf" <<EOF
nameserver 1.0.0.1
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 8.8.4.4
#nameserver 2606:4700:4700::64
#nameserver 2606:4700:4700::6400
#nameserver 2001:4860:4860::6464
#nameserver 2001:4860:4860::64
#nameserver 2001:67c:2b0::4
#nameserver 2001:67c:2b0::6
EOF

	cat > "$DEST/etc/modules-load.d/cups-filters.conf" <<EOF
# Parallel printer driver modules loading for cups
# LOAD_LP_MODULE was 'yes' in /etc/default/cups
#lp
#ppdev
#parport_pc
EOF

	cp -rfa $BUILD/usr/* $DEST/usr/
	
	do_conffile
	add_ssh_keygen_service
	add_opi_python_gpio_libs
	add_opi_config_libs
	add_audio_service

	case ${BOARD} in 
		"3" | "lite2" | "zeroplus2h5" | "zeroplus2h3" | "prime" | "win")
			add_bt_service
			;;
		*)
			;;
	esac

	sed -i 's|After=rc.local.service|#\0|;' "$DEST/lib/systemd/system/serial-getty@.service"
	rm -f "$DEST"/etc/ssh/ssh_host_*

	# Bring back folders
	mkdir -p "$DEST/lib"
	mkdir -p "$DEST/usr"

	# Create fstab
	cat  > "$DEST/etc/fstab" <<EOF
# <file system>	<dir>	<type>	<options>			<dump>	<pass>
LABEL=BOOT	/boot	vfat	defaults			0		2
LABEL=rootfs	/	ext4	defaults,noatime		0		1
EOF

	if [ ! -d $DEST/lib/modules ]; then
		mkdir "$DEST/lib/modules"
	else
		rm -rf $DEST/lib/modules
		mkdir "$DEST/lib/modules"
	fi

	# Install Kernel modules
	make -C $LINUX ARCH="${ARCH}" CROSS_COMPILE=$TOOLS modules_install INSTALL_MOD_PATH="$DEST"
	# Install Kernel headers
	make -C $LINUX ARCH="${ARCH}" CROSS_COMPILE=$TOOLS headers_install INSTALL_HDR_PATH="$DEST/usr/local"

	cp $EXTER/common/firmware $DEST/lib/ -rfa
	
	echo -e "\e[1;31m Start installing sunxi mali driver ... \e[0m"
	
	SUNXI_MALI="${ROOT}/sunxi-mali"
	cd $SUNXI_MALI
	
	export CROSS_COMPILE=$TOOLS
	export KDIR=$LINUX
	export INSTALL_MOD_PATH=$DEST
	export ARCH=$ARCH
	
	./build.sh -r $MALI_REL -i
	./build.sh -r $MALI_REL -u
	
	echo -e "\e[1;31m Complete sunxi mali installation ... \e[0m"
	
	MALI_BLOBS="${ROOT}/mali-blobs"
	
	cd $MALI_BLOBS
	
	# install module
	echo -e "\e[1;31m Start installing mali blobs ... \e[0m"
	cp -a $MALI_REL/$ARCH/fbdev/lib* $DEST/usr/lib
	echo -e "\e[1;31m Complete mali blobs installation ... \e[0m"	
	
	echo -e "\e[1;31m Start installing kernel sources ... \e[0m"
	cd $ROOT/kernel
	
	KERNEL_SOURCE_ARC="${DEST}/usr/src/linux_kernel_sources.tar.xz"
	
	if [ ! -f $KERNEL_SOURCE_ARC ]; then
		tar cvfJ $KERNEL_SOURCE_ARC *
	fi

	echo -e "\e[1;31m Complete kernel sources installation ... \e[0m"
}

build_rootfs()
{
	prepare_env

	if [ $TYPE = "1" ]; then
		if [ -f $BUILD/${DISTRO}_${ARCH}_desktop_rootfs.tar.gz ]; then
			rm -rf $DEST
			tar zxf $BUILD/${DISTRO}_${ARCH}_desktop_rootfs.tar.gz -C $BUILD
		fi
		
		if [ -f $BUILD/${DISTRO}_${ARCH}_server_rootfs.tar.gz ]; then
			rm -rf $DEST
			tar zxf $BUILD/${DISTRO}_${ARCH}_server_rootfs.tar.gz -C $BUILD
		fi

		prepare_rootfs_desktop
	else
		if [ -f $BUILD/${DISTRO}_${ARCH}_server_rootfs.tar.gz ]; then
			rm -rf $DEST
			tar zxf $BUILD/${DISTRO}_${ARCH}_server_rootfs.tar.gz -C $BUILD
		fi

		prepare_rootfs_server
	fi
	
	server_setup	
}
