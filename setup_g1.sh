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
    libspdlog-dev

# Install Python packages
echo "[3/6] Installing Python packages..."
pip3 install --user pyzmq opencv-python pyrealsense2 msgpack msgpack-numpy numpy tyro

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

# Disable conflicting Unitree video services
echo "[6/6] Configuring system services..."
if [ -f /unitree/module/video_hub_pc4/videohub_pc4 ]; then
    sudo mv /unitree/module/video_hub_pc4/videohub_pc4 /unitree/module/video_hub_pc4/videohub_pc4.disabled 2>/dev/null || true
fi
if [ -f /unitree/module/video_hub_pc4/videohub_pc4_chest ]; then
    sudo mv /unitree/module/video_hub_pc4/videohub_pc4_chest /unitree/module/video_hub_pc4/videohub_pc4_chest.disabled 2>/dev/null || true
fi
sudo pkill -9 videohub_pc4 2>/dev/null || true

# Create RealSense camera service
echo "Creating RealSense camera service..."
sudo tee /etc/systemd/system/g1-realsense.service > /dev/null << EOF
[Unit]
Description=G1 RealSense Camera Server
After=network.target

[Service]
Type=simple
User=unitree
WorkingDirectory=$SCRIPT_DIR/external/GR00T-WholeBodyControl
Environment="PYTHONPATH=$SCRIPT_DIR/external/GR00T-WholeBodyControl"
ExecStart=/usr/bin/python3 -m gr00t_wbc.control.sensor.composed_camera --head_camera realsense --server --port 5555 --fps 30
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
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/unitree/virtuals_unitree_g1/external/dfx_inspire_service/build
ExecStart=/home/unitree/virtuals_unitree_g1/external/dfx_inspire_service/build/inspire_g1_tcp
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Reload and enable services
sudo systemctl daemon-reload
sudo systemctl enable g1-realsense
sudo systemctl enable g1-inspire
sudo systemctl start g1-realsense
sudo systemctl start g1-inspire

echo ""
echo "=============================================="
echo "  Setup Complete!"
echo "=============================================="
echo ""
echo "Services installed and started:"
echo "  • g1-realsense (RealSense camera server on port 5555)"
echo "  • g1-inspire   (Inspire hand controller)"
echo ""
echo "Run ./verify_g1.sh to test the installation."
echo ""

