#!/bin/bash

set -e

script_path="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
workspace_dir=.workspace
kernel_name=vmlinuz
fs_name=disk.ext4

# Assumptions:
# 1. "The script should run within the working directory and not consume any other locations on the host file system"
#    I interpreted this as meaning no containers since storage drivers consume locations on the host fs.
# 2. qemu-system (Tested: 6.2.0) and gcc (Tested: 11.4.0) apt packages installed.
# 3. Host is amd64 arch.
# 4. Host has sudo and the script is not being executed as root.
# 5. Has basic utils wget, sha256sum etc.
# 6. Host is not air-gapped.


# Helper function that prints formatted stage
print_stage() {
    local str=$1
    local border=======================================

    echo -e """
$border
$str
$border
"""
}

download_kernel() {
    local package_name=linux-image-unsigned-6.8.0-060800-generic_6.8.0-060800.202403131158_amd64.deb
    
    # Download mainline ubuntu Kernel as apt package.
    local base_url=https://kernel.ubuntu.com/mainline/v6.8/amd64
    local checksum_name=CHECKSUMS
    
    print_stage "Downloading ubuntu 6.8 kernel"
    
    wget $base_url/$package_name
    wget $base_url/$checksum_name
    
    # Verify checksum of deb package before continuing. 
    print_stage "Verifying checksum"
    sha256sum $package_name -c $checksum_name 2>&1 | grep OK

    # Cleanup checksum file
    rm $checksum_name

    # Extract Kernel from deb package.
    local tmp_dir=.tmp
    
    print_stage "Unpacking '$package_name'"
    dpkg --debug=10 -x $package_name $tmp_dir
    
    orig_kernel_name=$(ls $tmp_dir/boot)
    echo "Extracted kernel '$orig_kernel_name'"
    mv $tmp_dir/boot/$orig_kernel_name $kernel_name
    
    rm -rf $tmp_dir && rm $package_name
}

# Using busybox because it's a great way to get a minimal and customizable rootfs.
compile_busybox() {
    local install_dir=$1
    local bb_name=busybox-1.36.1
    local tar_name=$bb_name.tar.bz2

    # Download and decompress busybox directory.
    wget https://busybox.net/downloads/$tar_name
    tar -xf $tar_name && rm $tar_name

    print_stage "Compiling $bb_name"

    pushd $bb_name
    # Compile busybox project
    make defconfig
    sed -i '/# CONFIG_STATIC is not set/c\CONFIG_STATIC=y' .config 
    make
    make install CONFIG_PREFIX=$install_dir
    popd

    # Cleanup busybox directory
    rm -rf $$bb_name
}

create_rootfs() {
    # Initialize ext4 disk
    print_stage "Creating ext4 filesystem '$fs_name'"
    dd if=/dev/zero of=$fs_name bs=4k count=2048
    mkfs.ext4 $fs_name

    # Mount ext4 disk so we can install busybox into it
    print_stage "SUDO REQUIRED: Mounting ext4 filesystem"
    local cwd=$(pwd)
    local mount_target=$cwd/mnt

    user=$(whoami)

    mkdir -p $mount_target
    sudo mount -t ext4 $cwd/$fs_name $mount_target
    sudo chown -R $user:$user $mount_target
    # Trap unmounting and syncing in case the shell script fails
    # during busybox compiling below.
    trap "sudo umount $mount_target && rm -rf $mount_target && sync" EXIT
    
    compile_busybox $mount_target

    pushd $mount_target
    # Credit: https://embeddedstudy.home.blog/2019/01/23/building-the-minimal-rootfs-using-busybox/
    mkdir -p etc var var/log proc sys dev etc/init.d usr/lib
    mkdir -p home home/root
    echo -e """
    #!bin/sh
    mount -t proc none /proc
    mount -t sysfs none /sys
    mount -t tmpfs none /var
    mount -t tmpfs none /dev
    
    echo /sbin/mdev > /proc/sys/kernel/hotplug
    /sbin/mdev -s

    echo
    echo "hello world"
    """ > etc/init.d/rcS
    chmod +x etc/init.d/rcS
    popd
}

# Helper function used to determine if kernel and rootfs
# need to be built.
workspace_ready() {
    if test -f $workspace_dir/$kernel_name && 
       test -f $workspace_dir/$fs_name; then
        print_stage "Using existing build artifacts"
        echo "kernel:   $kernel_name"
        echo "ext4:     $fs_name"
        ec=0
    else
        rm -rf $workspace_dir
        mkdir $workspace_dir
        ec=1
    fi    

    # Make working directory relative to script location.
    pushd $script_path/$workspace_dir &>/dev/null
    trap "popd" EXIT
    
    return $ec
}

# Check if workspace is ready, if not then
# kernel needs to be downloaded, and rootfs needs
# to be built.
if ! workspace_ready; then
    download_kernel
    create_rootfs
fi

print_stage "SUDO REQUIRED: Starting qemu with KVM"

sudo qemu-system-x86_64 \
    -cpu host \
    --enable-kvm \
    -display none \
    -m 1024 \
    -kernel vmlinuz \
    -drive format=raw,file=disk.ext4  \
    -append "ro root=/dev/sda rootfstype=ext4 console=ttyS0 " \
    -nographic