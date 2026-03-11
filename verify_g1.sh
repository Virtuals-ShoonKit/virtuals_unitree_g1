#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=============================================="
echo "  Virtuals Unitree G1 Verification"
echo "=============================================="
echo ""

PASS=0
FAIL=0

# Test 1: Inspire Hands (TCP)
echo "[1/2] Testing Inspire Hands (TCP Modbus)..."
echo "----------------------------------------------"

if python3 "$SCRIPT_DIR/external/dfx_inspire_service/test_inspire_tcp.py" 2>/dev/null; then
    echo "✓ Inspire hands test PASSED"
    ((PASS++))
else
    echo "✗ Inspire hands test FAILED (hands may not be connected)"
    ((FAIL++))
fi

echo ""

# Test 2: Service Status
echo "[2/2] Checking Service Status..."
echo "----------------------------------------------"

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
