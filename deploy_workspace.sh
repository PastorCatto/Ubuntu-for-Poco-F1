#!/bin/bash
set -e

echo "======================================================="
echo "   Beryllium ROM Cooker - Modular Workspace Generator"
echo "======================================================="
echo ">>> Generating independent scripts..."
echo ""


# ==============================================================================
#
#                      START OF SCRIPT 1: PREFLIGHT
#
# ==============================================================================

cat << 'EOF_1' > 1_preflight.sh
#!/bin/bash
set -e
echo "======================================================="
echo "   [1/4] Pre-Flight & Workspace Setup"
echo "======================================================="

echo ">>> Checking and installing host dependencies..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    debootstrap qemu-user-static sudo e2fsprogs curl wget \
    xz-utils gzip ca-certificates file fdisk git python3 python3-pip python3-venv sshpass tar

echo "======================================================="
echo "   Configuration Prompts"
echo "======================================================="
read -p "Enter desired username [default: ubuntu]: " USERNAME
USERNAME=${USERNAME:-ubuntu}

read -s -p "Enter desired password [default: ubuntu]: " PASSWORD
echo ""
PASSWORD=${PASSWORD:-ubuntu}

echo "Select Desktop UI:"
echo "1) Lomiri (Ubuntu Touch experience)"
echo "2) XFCE (Lightweight, best for performance)"
echo "3) GNOME (Modern, heavy, tablet-friendly)"
echo "4) Custom (Provide your own package names)"
read -p "Choice [1-4, default 1]: " UI_CHOICE

case $UI_CHOICE in
    2) UI_PKG="xfce4 xfce4-goodies xorg"; UI_NAME="xfce" ;;
    3) UI_PKG="ubuntu-desktop-minimal"; UI_NAME="gnome" ;;
    4) 
       read -p "Enter full package name(s) (e.g., kde-standard): " CUSTOM_PKG
       UI_PKG="$CUSTOM_PKG xorg lightdm"
       UI_NAME="custom"
       ;;
    *) UI_PKG="lomiri-desktop-session mir-graphics-drivers-desktop"; UI_NAME="lomiri" ;;
esac

cat << EOF_ENV > build.env
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
UI_PKG="$UI_PKG"
UI_NAME="$UI_NAME"
UBUNTU_RELEASE="noble"
FIRMWARE_STASH="\$HOME/firmware_stash"
EOF_ENV

echo ">>> Configuration locked and saved to build.env."
echo ">>> Pre-flight complete. Proceed to Script 2."
EOF_1

# ==============================================================================
#                       END OF SCRIPT 1: PREFLIGHT
# ==============================================================================





# ==============================================================================
#
#                      START OF SCRIPT 2: PMOS SETUP
#
# ==============================================================================

cat << 'EOF_2' > 2_pmos_setup.sh
#!/bin/bash
set -e
source build.env

echo "======================================================="
echo "   [2/4] pmbootstrap Initialization & Generation"
echo "======================================================="

echo ">>> Pulling latest pmbootstrap from upstream Git..."
mkdir -p "$HOME/.local/src" "$HOME/.local/bin"
if [ ! -d "$HOME/.local/src/pmbootstrap" ]; then
    git clone https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git "$HOME/.local/src/pmbootstrap"
fi
ln -sf "$HOME/.local/src/pmbootstrap/pmbootstrap.py" "$HOME/.local/bin/pmbootstrap"
export PATH="$HOME/.local/bin:$PATH"

DEFAULT_WORK="$HOME/.local/var/pmbootstrap"
if [ -f "$HOME/.config/pmbootstrap.cfg" ]; then
    PM_WORK_DIR=$(pmbootstrap config work 2>/dev/null || echo "$DEFAULT_WORK")
else
    PM_WORK_DIR="$DEFAULT_WORK"
fi

echo "======================================================="
echo "   ATTENTION: MANUAL CONFIGURATION REQUIRED"
echo "======================================================="
echo "You are about to enter the interactive pmbootstrap init phase."
echo ""
echo "CRITICAL INSTRUCTIONS:"
echo "1. Work path: Use the default ($PM_WORK_DIR) or provide your own."
echo "2. Channel: Choose 'edge'."
echo "3. Vendor: Choose 'xiaomi'."
echo "4. Device: Choose 'beryllium'."
echo "5. Display/Kernel: Choose 'tianma' or 'ebbg' depending on your panel."
echo "6. User interface: Choose 'none'."
echo "7. Init system: You MUST choose 'systemd'."
echo "======================================================="
read -p "Press ENTER when you understand and are ready to begin..."

pmbootstrap init
echo ">>> Triggering pmbootstrap rootfs generation..."
pmbootstrap install

PM_WORK_DIR=$(pmbootstrap config work)
PMOS_CHROOT_PATH="$PM_WORK_DIR/chroot_rootfs_xiaomi-beryllium"

echo ">>> Verifying final pmbootstrap chroot generation..."
if [ -d "$PMOS_CHROOT_PATH/lib/modules" ]; then
    echo ">>> pmOS Chroot successfully verified!"
    
    rm -f pmos_harvest
    ln -s "$PMOS_CHROOT_PATH" pmos_harvest
    
    echo ">>> Exporting kernel image for fastboot..."
    pmbootstrap export
    cp /tmp/postmarketOS-export/vmlinuz pmos_boot.img
    
    echo ">>> System linked. Proceed to Script 3 (Firmware Fetcher)."
else
    echo ">>> [ERROR] Could not find the generated pmOS chroot at $PMOS_CHROOT_PATH."
    exit 1
fi
EOF_2

# ==============================================================================
#                       END OF SCRIPT 2: PMOS SETUP
# ==============================================================================





# ==============================================================================
#
#                      START OF SCRIPT 3: FIRMWARE FETCHER
#
# ==============================================================================

cat << 'EOF_3' > 3_firmware_fetcher.sh
#!/bin/bash
set -e
source build.env

echo "======================================================="
echo "   [3/4] Firmware Fetcher (Mobian Extraction)"
echo "======================================================="

if [ -d "$FIRMWARE_STASH" ] && [ "$(ls -A $FIRMWARE_STASH 2>/dev/null)" ]; then
    echo ">>> Found existing firmware stash at $FIRMWARE_STASH. Skipping network fetch."
else
    echo ">>> Local firmware stash is empty."
    echo ">>> Please ensure your Poco F1 is powered on, connected to Wi-Fi,"
    echo ">>> and actively running Mobian."
    echo ""
    read -p "Enter Poco F1 IP Address (e.g., 192.168.1.50): " PHONE_IP
    read -p "Enter Mobian username [default: mobian]: " PHONE_USER
    PHONE_USER=${PHONE_USER:-mobian}
    read -s -p "Enter Mobian password: " PHONE_PASS
    echo ""
    
    echo ">>> [Phone Side] Archiving hardware profiles via SSH..."
    sshpass -p "$PHONE_PASS" ssh -o StrictHostKeyChecking=no "$PHONE_USER@$PHONE_IP" \
        "echo '$PHONE_PASS' | sudo -S tar -czpf ~/mobian_harvest.tar.gz /usr/share/alsa/ucm2/ /etc/ModemManager/ /lib/udev/rules.d/"
    
    echo ">>> [Host Side] Downloading the archive..."
    mkdir -p "$FIRMWARE_STASH"
    sshpass -p "$PHONE_PASS" scp -o StrictHostKeyChecking=no "$PHONE_USER@$PHONE_IP:~/mobian_harvest.tar.gz" "$FIRMWARE_STASH/"
    
    echo ">>> [Host Side] Extracting into stash..."
    tar -xzpf "$FIRMWARE_STASH/mobian_harvest.tar.gz" -C "$FIRMWARE_STASH/"
    
    echo ">>> [Phone Side] Cleaning up temporary files..."
    sshpass -p "$PHONE_PASS" ssh -o StrictHostKeyChecking=no "$PHONE_USER@$PHONE_IP" "rm ~/mobian_harvest.tar.gz"
    
    echo ">>> Firmware successfully stashed in $FIRMWARE_STASH."
fi
echo ">>> Proceed to Script 4 (The Transplant)."
EOF_3

# ==============================================================================
#                       END OF SCRIPT 3: FIRMWARE FETCHER
# ==============================================================================





# ==============================================================================
#
#                      START OF SCRIPT 4: THE TRANSPLANT
#
# ==============================================================================

cat << 'EOF_4' > 4_the_transplant.sh
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
    sudo cp -a "$FIRMWARE_STASH/usr/share/alsa/ucm2/." ubuntu_rootfs/usr/share/alsa/ucm2/ || true
fi
if [ -d "$FIRMWARE_STASH/etc/ModemManager" ]; then
    sudo mkdir -p ubuntu_rootfs/etc/ModemManager/
    sudo cp -a "$FIRMWARE_STASH/etc/ModemManager/." ubuntu_rootfs/etc/ModemManager/ || true
fi
if [ -d "$FIRMWARE_STASH/lib/udev/rules.d" ]; then
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
EOF_4

# ==============================================================================
#                       END OF SCRIPT 4: THE TRANSPLANT
# ==============================================================================


# Make everything executable
chmod +x 1_preflight.sh 2_pmos_setup.sh 3_firmware_fetcher.sh 4_the_transplant.sh

echo ">>> Workspace scripts generated successfully!"
echo ">>> Run './1_preflight.sh' to begin the process."
