# Virtuals Unitree G1

Additional scripts and dependencies for Unitree G1 integration with Virtuals.

## Quick Start

```bash
ssh unitree@192.168.123.164  # password: 123

git clone --recurse-submodules https://github.com/Virtuals-ShoonKit/virtuals_unitree_g1.git
cd virtuals_unitree_g1
./setup_g1.sh
./verify_g1.sh
```

## What's Included

| Component | Description |
|-----------|-------------|
| `unitree_sdk2` | Unitree SDK for robot communication |
| `GR00T-WholeBodyControl` | Whole-body control policies & teleoperation |
| `dfx_inspire_service` | Inspire RH56DFX dexterous hand controller |

## Services (Auto-start at Boot)

After setup, these services run automatically:

```bash
# Check status
sudo systemctl status g1-realsense
sudo systemctl status g1-inspire

# View logs
journalctl -u g1-realsense -f
journalctl -u g1-inspire -f

# Restart if needed
sudo systemctl restart g1-realsense
sudo systemctl restart g1-inspire
```

## Manual Testing

```bash
# Test RealSense camera
python3 ~/virtuals_unitree_g1/external/GR00T-WholeBodyControl/tests/test_rs_cam.py

# Test Inspire hands
python3 ~/virtuals_unitree_g1/external/dfx_inspire_service/test_inspire_tcp.py
```

## Add expired ros key
```
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys F42ED6FBAB17C654
```

## Network Sharing (from Host PC)

To give G1 internet access from your PC (192.168.123.222):

```bash
# On your PC
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -F
sudo iptables -F FORWARD
sudo iptables -t nat -A POSTROUTING -o <YOUR_INTERFACE> -j MASQUERADE
sudo iptables -A FORWARD -j ACCEPT
```

Then on G1:
```bash
sudo ip route add default via 192.168.123.222
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

## Submodules

- [unitree_sdk2](https://github.com/unitreerobotics/unitree_sdk2)
- [GR00T-WholeBodyControl](https://github.com/Virtuals-ShoonKit/GR00T-WholeBodyControl)
- [dfx_inspire_service](https://github.com/Virtuals-ShoonKit/dfx_inspire_service)
