#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=============================================="
echo "  Virtuals Unitree G1 Verification"
echo "=============================================="
echo ""

PASS=0
FAIL=0

# Test 1: ZED Camera
echo "[1/4] Testing ZED Camera..."
echo "----------------------------------------------"

# Temporarily stop the service to free the camera
sudo systemctl stop g1-camera 2>/dev/null || true
sleep 1

if python3 -c "
import pyzed.sl as sl
zed = sl.Camera()
params = sl.InitParameters()
params.camera_resolution = sl.RESOLUTION.HD720
params.depth_mode = sl.DEPTH_MODE.NONE
status = zed.open(params)
if status != sl.ERROR_CODE.SUCCESS:
    exit(1)
image = sl.Mat()
for _ in range(5):
    if zed.grab() == sl.ERROR_CODE.SUCCESS:
        zed.retrieve_image(image, sl.VIEW.LEFT)
zed.close()
print('ZED camera OK')
" 2>/dev/null; then
    echo "✓ ZED camera test PASSED"
    ((PASS++))
else
    echo "✗ ZED camera test FAILED"
    ((FAIL++))
fi

echo ""

# Test 2: RealSense Camera
echo "[2/4] Testing RealSense Camera..."
echo "----------------------------------------------"

if python3 "$SCRIPT_DIR/external/GR00T-WholeBodyControl/tests/test_rs_cam.py" 2>/dev/null; then
    echo "✓ RealSense camera test PASSED"
    ((PASS++))
else
    echo "✗ RealSense camera test FAILED"
    ((FAIL++))
fi

# Restart the camera service
sudo systemctl start g1-camera 2>/dev/null || true

echo ""

# Test 3: Inspire Hands (TCP)
echo "[3/4] Testing Inspire Hands (TCP Modbus)..."
echo "----------------------------------------------"

if python3 "$SCRIPT_DIR/external/dfx_inspire_service/test_inspire_tcp.py" 2>/dev/null; then
    echo "✓ Inspire hands test PASSED"
    ((PASS++))
else
    echo "✗ Inspire hands test FAILED (hands may not be connected)"
    ((FAIL++))
fi

echo ""

# Test 4: Service Status
echo "[4/4] Checking Service Status..."
echo "----------------------------------------------"

echo -n "  g1-camera:  "
if systemctl is-active --quiet g1-camera; then
    echo "✓ running"
else
    echo "✗ not running"
fi

echo -n "  g1-inspire: "
if systemctl is-active --quiet g1-inspire; then
    echo "✓ running"
else
    echo "✗ not running"
fi

echo ""
echo "=============================================="
echo "  Summary: $PASS passed, $FAIL failed"
echo "=============================================="
echo ""

if [ $FAIL -eq 0 ]; then
    echo "All tests passed! G1 is ready."
    exit 0
else
    echo "Some tests failed. Check the output above."
    exit 1
fi
