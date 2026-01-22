#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=============================================="
echo "  Virtuals Unitree G1 Setup"
echo "=============================================="

# Initialize submodules if not already done
echo "[1/8] Initializing submodules..."
git submodule update --init --recursive

# Install system dependencies
echo "[2/8] Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    cmake \
    python3-dev \
    python3-pip \
    python3-zmq \
    python3-numpy \
    python3-opencv \
    libboost-all-dev \
    libspdlog-dev \
    zstd

# Install Python packages
echo "[3/8] Installing Python packages..."
pip3 install --user pyzmq opencv-python pyrealsense2 msgpack msgpack-numpy numpy tyro gymnasium cython

# Install ZED SDK for Jetson Orin
echo "[4/8] Installing ZED SDK for Jetson Orin..."
install_zed_sdk() {
    # Check if ZED SDK is already installed
    if [ -d "/usr/local/zed" ]; then
        echo "ZED SDK already installed, skipping..."
        return 0
    fi

    # Detect L4T version for Jetson
    if [ -f /etc/nv_tegra_release ]; then
        L4T_VERSION=$(head -n 1 /etc/nv_tegra_release | sed 's/.*R\([0-9]*\).*/\1/')
        L4T_REVISION=$(head -n 1 /etc/nv_tegra_release | sed 's/.*REVISION: \([0-9.]*\).*/\1/')
        L4T_FULL="${L4T_VERSION}.${L4T_REVISION}"
        echo "Detected L4T version: $L4T_FULL"
    else
        echo "Warning: Could not detect L4T version. Assuming JetPack 6.x (L4T 36.x)"
        L4T_VERSION="36"
        L4T_FULL="36.4"
    fi

    # Determine ZED SDK version based on L4T version
    ZED_SDK_VERSION="4.2"
    
    if [ "$L4T_VERSION" -ge "36" ]; then
        # JetPack 6.x (L4T 36.x) - Orin with CUDA 12.x
        ZED_INSTALLER="ZED_SDK_Tegra_L4T36.4_v${ZED_SDK_VERSION}.zstd.run"
        ZED_URL="https://download.stereolabs.com/zedsdk/${ZED_SDK_VERSION}/l4t36.4/jetsons"
    elif [ "$L4T_VERSION" -ge "35" ]; then
        # JetPack 5.x (L4T 35.x) - Orin with CUDA 11.x
        ZED_INSTALLER="ZED_SDK_Tegra_L4T35.4_v${ZED_SDK_VERSION}.zstd.run"
        ZED_URL="https://download.stereolabs.com/zedsdk/${ZED_SDK_VERSION}/l4t35.4/jetsons"
    else
        echo "Error: Unsupported L4T version $L4T_VERSION. ZED SDK requires L4T 35.x+ for Orin."
        return 1
    fi

    # Download ZED SDK
    echo "Downloading ZED SDK from $ZED_URL..."
    cd /tmp
    wget -q --show-progress "$ZED_URL" -O "$ZED_INSTALLER" || {
        echo "Failed to download ZED SDK. Please download manually from https://www.stereolabs.com/developers/release"
        return 1
    }

    # Install ZED SDK silently
    echo "Installing ZED SDK..."
    chmod +x "$ZED_INSTALLER"
    ./"$ZED_INSTALLER" -- silent skip_od_module skip_tools

    # Clean up
    rm -f "$ZED_INSTALLER"
    
    echo "ZED SDK installed successfully"
}

install_zed_sdk

# Install ZED Python API
echo "[5/8] Installing ZED Python API..."
if [ -f "/usr/local/zed/get_python_api.py" ]; then
    cd /usr/local/zed
    python3 get_python_api.py
    echo "ZED Python API installed"
else
    echo "Warning: ZED SDK not found at /usr/local/zed. Skipping Python API installation."
fi

cd "$SCRIPT_DIR"

# Build unitree_sdk2
echo "[6/8] Building unitree_sdk2..."
cd "$SCRIPT_DIR/external/unitree_sdk2"
mkdir -p build && cd build
cmake ..
sudo make install
cd "$SCRIPT_DIR"

# Build dfx_inspire_service
echo "[7/8] Building dfx_inspire_service..."
cd "$SCRIPT_DIR/external/dfx_inspire_service"
mkdir -p build && cd build
cmake ..
make -j$(nproc)
cd "$SCRIPT_DIR"

# Disable conflicting Unitree video services
echo "[8/8] Configuring system services..."
if [ -f /unitree/module/video_hub_pc4/videohub_pc4 ]; then
    sudo mv /unitree/module/video_hub_pc4/videohub_pc4 /unitree/module/video_hub_pc4/videohub_pc4.disabled 2>/dev/null || true
fi
if [ -f /unitree/module/video_hub_pc4/videohub_pc4_chest ]; then
    sudo mv /unitree/module/video_hub_pc4/videohub_pc4_chest /unitree/module/video_hub_pc4/videohub_pc4_chest.disabled 2>/dev/null || true
fi
sudo pkill -9 videohub_pc4 2>/dev/null || true

# Create camera service with ZED (ego) + RealSense (head)
echo "Creating camera service (ZED ego + RealSense head)..."
sudo tee /etc/systemd/system/g1-camera.service > /dev/null << EOF
[Unit]
Description=G1 Camera Server (ZED ego + RealSense head)
After=network.target

[Service]
Type=simple
User=unitree
WorkingDirectory=$SCRIPT_DIR/external/GR00T-WholeBodyControl
Environment="PYTHONPATH=$SCRIPT_DIR/external/GR00T-WholeBodyControl"
Environment="LD_LIBRARY_PATH=/usr/local/zed/lib:\$LD_LIBRARY_PATH"
ExecStart=/usr/bin/python3 -m gr00t_wbc.control.sensor.composed_camera --ego_view_camera zed --head_camera realsense --server --port 5555 --fps 30
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create Inspire hand service (TCP version for RH56DFTP hands)
echo "Creating Inspire hand service..."
sudo tee /etc/systemd/system/g1-inspire.service > /dev/null << 'EOF'
[Unit]
Description=G1 Inspire Hand Controller (TCP Modbus)
After=network.target unitree_dds.service
Wants=unitree_dds.service

[Service]
Type=simple
User=root
WorkingDirectory=/home/unitree/virtuals_unitree_g1/external/dfx_inspire_service/build
ExecStartPre=/bin/sleep 10
ExecStart=/home/unitree/virtuals_unitree_g1/external/dfx_inspire_service/build/inspire_g1_tcp
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Remove old realsense-only service if it exists
if systemctl list-unit-files | grep -q g1-realsense.service; then
    sudo systemctl stop g1-realsense 2>/dev/null || true
    sudo systemctl disable g1-realsense 2>/dev/null || true
    sudo rm -f /etc/systemd/system/g1-realsense.service
fi

# Reload and enable services
sudo systemctl daemon-reload
sudo systemctl enable g1-camera
sudo systemctl enable g1-inspire
sudo systemctl start g1-camera
sudo systemctl start g1-inspire

echo ""
echo "=============================================="
echo "  Setup Complete!"
echo "=============================================="
echo ""
echo "Services installed and started:"
echo "  • g1-camera  (ZED ego view + RealSense head on port 5555)"
echo "  • g1-inspire (Inspire hand controller)"
echo ""
echo "Camera configuration:"
echo "  • Ego view:  ZED camera"
echo "  • Head view: RealSense camera"
echo ""
echo "Run ./verify_g1.sh to test the installation."
echo ""
