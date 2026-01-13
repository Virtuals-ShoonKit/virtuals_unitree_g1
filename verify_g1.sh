#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=============================================="
echo "  Virtuals Unitree G1 Verification"
echo "=============================================="
echo ""

PASS=0
FAIL=0

# Test 1: RealSense Camera
echo "[1/3] Testing RealSense Camera..."
echo "----------------------------------------------"

# Temporarily stop the service to free the camera
sudo systemctl stop g1-realsense 2>/dev/null || true
sleep 1

if python3 "$SCRIPT_DIR/external/GR00T-WholeBodyControl/tests/test_rs_cam.py"; then
    echo "✓ RealSense camera test PASSED"
    ((PASS++))
else
    echo "✗ RealSense camera test FAILED"
    ((FAIL++))
fi

# Restart the service
sudo systemctl start g1-realsense 2>/dev/null || true

echo ""

# Test 2: Inspire Hands (TCP)
echo "[2/3] Testing Inspire Hands (TCP Modbus)..."
echo "----------------------------------------------"

if python3 "$SCRIPT_DIR/external/dfx_inspire_service/test_inspire_tcp.py"; then
    echo "✓ Inspire hands test PASSED"
    ((PASS++))
else
    echo "✗ Inspire hands test FAILED (hands may not be connected)"
    ((FAIL++))
fi

echo ""

# Test 3: Service Status
echo "[3/3] Checking Service Status..."
echo "----------------------------------------------"

echo -n "  g1-realsense: "
if systemctl is-active --quiet g1-realsense; then
    echo "✓ running"
else
    echo "✗ not running"
fi

echo -n "  g1-inspire:   "
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

