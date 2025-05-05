#!/bin/bash

set -e

KEY_DIR="$HOME/module-signing"
KEY_NAME="MOK"
MODSIGN_CERT="$KEY_DIR/$KEY_NAME.crt"
MODSIGN_KEY="$KEY_DIR/$KEY_NAME.priv"
VMWARE_MODULE_DIR="/lib/modules/$(uname -r)/misc"

echo "🔍 Checking if Secure Boot is enabled..."
if mokutil --sb-state | grep -q "SecureBoot enabled"; then
    echo "✅ Secure Boot is enabled."
else
    echo "⚠️ Secure Boot is not enabled. Module signing is not required."
    exit 0
fi

echo "📦 Checking for required packages..."
sudo apt-get update
sudo apt-get install -y build-essential gcc make linux-headers-$(uname -r) mokutil openssl

echo "📁 Creating directory for keys: $KEY_DIR"
mkdir -p "$KEY_DIR"

if [[ ! -f "$MODSIGN_CERT" || ! -f "$MODSIGN_KEY" ]]; then
    echo "🔐 Generating new MOK key pair..."
    openssl req -new -x509 -newkey rsa:2048 -nodes \
        -keyout "$MODSIGN_KEY" \
        -outform DER \
        -out "$MODSIGN_CERT" \
        -subj "/CN=VMware Module Sign/"
else
    echo "✅ MOK key already exists."
fi

echo "🔧 Rebuilding VMware modules if needed..."
sudo vmware-modconfig --console --install-all

echo "🧠 Looking for VMware modules to sign..."
if [ ! -d "$VMWARE_MODULE_DIR" ]; then
    echo "❌ VMware module directory not found: $VMWARE_MODULE_DIR"
    echo "Make sure VMware is installed and has built its kernel modules."
    exit 1
fi

SIGN_SCRIPT="/usr/src/linux-headers-$(uname -r)/scripts/sign-file"

echo "✍️ Signing VMware modules..."
for module in "$VMWARE_MODULE_DIR"/*.ko; do
    echo "➤ Signing $(basename "$module")"
    sudo "$SIGN_SCRIPT" sha256 "$MODSIGN_KEY" "$MODSIGN_CERT" "$module"
done

echo "🔑 Importing MOK key for Secure Boot..."
sudo mokutil --import "$MODSIGN_CERT"

echo "🚨 IMPORTANT: You will be prompted to set a password for the MOK key."
echo "✅ During reboot, enter the password in the blue MOK manager screen to enroll the key."

read -p "⏎ Press Enter to restart VMware services..."

echo "🔁 Restarting VMware services..."
sudo /etc/init.d/vmware restart

echo -e "\n🎉 Done! Please reboot your machine now to enroll the MOK key via the blue Secure Boot menu.\n"
