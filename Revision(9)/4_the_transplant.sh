# ==============================================================================
#                      START OF SCRIPT 4: THE TRANSPLANT
# ==============================================================================

cat << 'EOF_4' > 4_the_transplant.sh
#!/bin/bash
set -e
source build.env

echo "======================================================="
echo "   [4/4] The Transplant (Final Build)"
echo "======================================================="
echo ">>> Target: Beryllium | User: $USERNAME | UI: $UI_NAME"
echo ">>> Image Size: ${IMAGE_SIZE}GB"
echo ">>> Extra Pkgs: ${EXTRA_PKG:-None}"
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
echo ">>> [Config] Expanding repositories, installing UI and user..."
sudo chroot ubuntu_rootfs /bin/bash << CHROOT_EOF
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# Injecting full ARM64 repositories (Main, Restricted, Universe, Multiverse)
cat << APT_EOF > /etc/apt/sources.list
deb http://ports.ubuntu.com/ubuntu-ports/ $UBUNTU_RELEASE main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ $UBUNTU_RELEASE-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ $UBUNTU_RELEASE-security main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ $UBUNTU_RELEASE-backports main restricted universe multiverse
APT_EOF

useradd -m -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
usermod -aG sudo,video,audio,plugdev $USERNAME

apt-get update && apt-get upgrade -y
export DEBIAN_FRONTEND=noninteractive
apt-get install -y $UI_PKG $EXTRA_PKG modemmanager network-manager systemd-resolved
echo "/usr/sbin/lightdm" > /etc/X11/default-display-manager 2>/dev/null || true
dpkg-reconfigure lightdm 2>/dev/null || true
CHROOT_EOF

# --- Build Phase ---
IMG_MB=$((IMAGE_SIZE * 1024))
echo ">>> [Packing] Allocating ${IMAGE_SIZE}GB (${IMG_MB}MB) and packing final image..."
dd if=/dev/zero of="$OUTPUT_IMG" bs=1M count=$IMG_MB status=progress
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
echo ">>> DONE! The master rootfs is compiled."

echo ""
echo "======================================================="
echo "   Flashing & Deployment Options"
echo "======================================================="
read -p "How do you plan to flash the RootFS? (1: SD Card, 2: Fastboot/Internal) [Default: 1]: " FLASH_CHOICE
FLASH_CHOICE=${FLASH_CHOICE:-1}

if [ "$FLASH_CHOICE" == "2" ]; then
    echo ">>> [Fastboot Prep] Converting raw ext4 image to sparse image..."
    if ! command -v img2simg &> /dev/null; then
        echo ">>> Installing android-sdk-libsparse-utils for img2simg conversion..."
        sudo apt-get update && sudo apt-get install -y android-sdk-libsparse-utils || sudo apt-get install -y android-tools-fsutils
    fi
    SPARSE_IMG="${OUTPUT_IMG%.img}_sparse.img"
    img2simg "$OUTPUT_IMG" "$SPARSE_IMG"
    
    echo ">>> Sparse image created successfully!"
    echo ">>> "
    echo ">>> LOCATION:"
    echo ">>> Boot Image:      $(pwd)/pmos_boot.img"
    echo ">>> RootFS (Raw):    $(pwd)/$OUTPUT_IMG"
    echo ">>> RootFS (Sparse): $(pwd)/$SPARSE_IMG"
    echo ">>> "
    echo ">>> FLASHING INSTRUCTIONS (Fastboot):"
    echo ">>> 1. Reboot your Beryllium into Fastboot mode."
    echo ">>> 2. Flash the boot image:"
    echo ">>>    fastboot flash boot $(pwd)/pmos_boot.img"
    echo ">>> "
    echo ">>> 3. Flash the sparse RootFS image (e.g., to userdata):"
    echo ">>>    fastboot flash userdata $(pwd)/$SPARSE_IMG"
    echo ">>> "
    echo ">>> 4. Reboot your device:"
    echo ">>>    fastboot reboot"
else
    echo ">>> "
    echo ">>> LOCATION:"
    echo ">>> Boot Image:   $(pwd)/pmos_boot.img"
    echo ">>> RootFS Image: $(pwd)/$OUTPUT_IMG"
    echo ">>> "
    echo ">>> FLASHING INSTRUCTIONS (SD Card):"
    echo ">>> 1. Reboot your Beryllium into Fastboot mode."
    echo ">>> 2. Flash the boot image:"
    echo ">>>    fastboot flash boot $(pwd)/pmos_boot.img"
    echo ">>> "
    echo ">>> 3. Flash the RootFS to your SD card (Replace /dev/sdX with your actual SD card!):"
    echo ">>>    sudo dd if=$(pwd)/$OUTPUT_IMG of=/dev/sdX bs=4M status=progress"
    echo ">>> "
    echo ">>> Insert the SD card, reboot, and enjoy!"
fi
echo "======================================================="
EOF_4

# ==============================================================================
#                        END OF SCRIPT 4: THE TRANSPLANT
# ==============================================================================
