#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=============================================="
echo "  Virtuals Unitree G1 Setup"
echo "=============================================="

# Initialize submodules if not already done
echo "[1/6] Initializing submodules..."
git submodule update --init --recursive

# Install system dependencies
echo "[2/6] Installing system dependencies..."
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
echo "[3/6] Installing Python packages..."
pip3 install --user pyzmq opencv-python pyrealsense2 msgpack msgpack-numpy numpy tyro gymnasium cython

cd "$SCRIPT_DIR"

# Build unitree_sdk2
echo "[4/6] Building unitree_sdk2..."
cd "$SCRIPT_DIR/external/unitree_sdk2"
mkdir -p build && cd build
cmake ..
sudo make install
cd "$SCRIPT_DIR"

# Build dfx_inspire_service
echo "[5/6] Building dfx_inspire_service..."
cd "$SCRIPT_DIR/external/dfx_inspire_service"
mkdir -p build && cd build
cmake ..
make -j$(nproc)
cd "$SCRIPT_DIR"

# Create Inspire hand service
echo "[6/6] Configuring system services..." (TCP version for RH56DFTP hands)
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

# Reload and enable services
sudo systemctl daemon-reload
sudo systemctl enable g1-inspire
sudo systemctl start g1-inspire

echo ""
echo "=============================================="
echo "  Setup Complete!"
echo "=============================================="
echo ""
echo "Services installed and started:"
echo "  • g1-inspire (Inspire hand controller)"
echo ""
echo "Run ./verify_g1.sh to test the installation."
echo ""
