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
    cp /tmp/postmarketOS-export/boot.img pmos_boot.img
    
    echo ">>> System linked. Proceed to Script 3 (Firmware Fetcher)."
else
    echo ">>> [ERROR] Could not find the generated pmOS chroot at $PMOS_CHROOT_PATH."
    exit 1
fi
