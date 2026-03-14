#!/bin/bash
set -e
source build.env

echo "======================================================="
echo "   [4/4] The Transplant (Final Build)"
echo "======================================================="
echo ">>> Target: Beryllium | User: $USERNAME | UI: $UI_NAME"
echo ">>> ---------------------------------------------------"

OUTPUT_IMG="ubuntu_beryllium.img"

# --- Debootstrap Phase ---
echo ">>> [Debootstrap] Building Ubuntu $UBUNTU_RELEASE (arm64)..."
sudo debootstrap --arch=arm64 --foreign "$UBUNTU_RELEASE" ubuntu_rootfs http://ports.ubuntu.com/
sudo cp /usr/bin/qemu-aarch64-static ubuntu_rootfs/usr/bin/
sudo chroot ubuntu_rootfs /debootstrap/debootstrap --second-stage

# --- Injection Phase ---
echo ">>> [Merge] Injecting pmOS kernels & firmware..."
sudo cp -a pmos_harvest/lib/modules/. ubuntu_rootfs/lib/modules/
sudo cp -a pmos_harvest/lib/firmware/. ubuntu_rootfs/lib/firmware/

echo ">>> [Merge] Injecting stashed Mobian hardware profiles..."
if [ -d "$FIRMWARE_STASH/usr/share/alsa/ucm2" ]; then
    sudo mkdir -p ubuntu_rootfs/usr/share/alsa/ucm2/
    sudo cp -a "$FIRMWARE_STASH/usr/share/alsa/ucm2/." ubuntu_rootfs/usr/share/alsa/ucm2/ || true
fi

if [ -d "$FIRMWARE_STASH/etc/ModemManager" ]; then
    sudo mkdir -p ubuntu_rootfs/etc/ModemManager/
    sudo cp -a "$FIRMWARE_STASH/etc/ModemManager/." ubuntu_rootfs/etc/ModemManager/ || true
fi

if [ -d "$FIRMWARE_STASH/lib/udev/rules.d" ]; then
    sudo mkdir -p ubuntu_rootfs/lib/udev/rules.d/
    sudo cp -a "$FIRMWARE_STASH/lib/udev/rules.d/." ubuntu_rootfs/lib/udev/rules.d/ || true
fi

# --- Setup Phase ---
echo ">>> [Config] Installing UI and user..."
sudo chroot ubuntu_rootfs /bin/bash << CHROOT_EOF
echo "nameserver 8.8.8.8" > /etc/resolv.conf
useradd -m -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
usermod -aG sudo,video,audio,plugdev $USERNAME
apt-get update && apt-get upgrade -y
export DEBIAN_FRONTEND=noninteractive
apt-get install -y $UI_PKG modemmanager network-manager systemd-resolved
echo "/usr/sbin/lightdm" > /etc/X11/default-display-manager
dpkg-reconfigure lightdm
CHROOT_EOF

# --- Build Phase ---
echo ">>> [Packing] Allocating 6GB and packing final image..."
dd if=/dev/zero of="$OUTPUT_IMG" bs=1M count=6144 status=progress
mkfs.ext4 -L pmOS_root "$OUTPUT_IMG"
mkdir -p mnt_final
sudo mount -o loop "$OUTPUT_IMG" mnt_final/
sudo cp -a ubuntu_rootfs/. mnt_final/

# Safely unmount before checking
sudo umount mnt_final

# --- Filesystem Check ---
echo ">>> [Check] Running filesystem check (e2fsck) on the final rootfs..."
sudo e2fsck -f -y "$OUTPUT_IMG"

echo ">>> [Cleanup] Sweeping workspace..."
rm -rf ubuntu_rootfs mnt_final
echo ">>> ---------------------------------------------------"
echo ">>> DONE! Your final ROM ($OUTPUT_IMG) and Fastboot kernel (pmos_boot.img) are ready."
