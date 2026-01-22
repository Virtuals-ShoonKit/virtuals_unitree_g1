#!/usr/bin/env python3
"""
Camera viewer client for Unitree G1 camera stream (ZED ego + RealSense head).

This script connects to the G1 camera server and displays the video feeds.

Usage:
    python3 view_zed_cam.py                          # Use default IP
    python3 view_zed_cam.py --ip 192.168.123.164     # Specify robot IP
    python3 view_zed_cam.py --ip 192.168.123.164 --save  # Save frames
"""

import argparse
import base64
import time
from collections import deque
from typing import Optional

import cv2
import msgpack
import numpy as np
import zmq


def decode_image(image_b64: str) -> np.ndarray:
    """Decode base64 JPEG image to numpy array."""
    color_data = base64.b64decode(image_b64)
    color_array = np.frombuffer(color_data, dtype=np.uint8)
    return cv2.imdecode(color_array, cv2.IMREAD_COLOR)


class CameraViewer:
    """Client for viewing G1 camera streams."""

    def __init__(self, robot_ip: str, port: int = 5555):
        self.robot_ip = robot_ip
        self.port = port
        
        # ZMQ setup
        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.SUB)
        self.socket.setsockopt_string(zmq.SUBSCRIBE, "")
        self.socket.setsockopt(zmq.CONFLATE, True)  # Only keep latest message
        self.socket.setsockopt(zmq.RCVHWM, 3)
        self.socket.setsockopt(zmq.RCVTIMEO, 5000)  # 5 second timeout
        
        # FPS tracking
        self.fps_history = deque(maxlen=30)
        self.last_frame_time = time.time()
        
        # Frame saving
        self.save_frames = False
        self.frame_count = 0
        self.save_dir: Optional[str] = None

    def connect(self):
        """Connect to the camera server."""
        print(f"Connecting to camera server at tcp://{self.robot_ip}:{self.port}...")
        self.socket.connect(f"tcp://{self.robot_ip}:{self.port}")
        print("Connected!")

    def receive_frame(self) -> Optional[dict]:
        """Receive and decode a frame from the server."""
        try:
            packed = self.socket.recv()
            data = msgpack.unpackb(packed)
            
            # Update FPS
            now = time.time()
            self.fps_history.append(now - self.last_frame_time)
            self.last_frame_time = now
            
            return data
        except zmq.Again:
            print("Timeout waiting for frame")
            return None

    def get_fps(self) -> float:
        """Calculate current FPS."""
        if len(self.fps_history) < 2:
            return 0.0
        return 1.0 / (sum(self.fps_history) / len(self.fps_history))

    def enable_save(self, save_dir: str):
        """Enable frame saving."""
        import os
        os.makedirs(save_dir, exist_ok=True)
        self.save_dir = save_dir
        self.save_frames = True
        print(f"Saving frames to: {save_dir}")

    def run(self):
        """Main viewing loop."""
        print("Press 'q' to quit, 's' to toggle frame saving")
        print("Camera feeds:")
        print("  - ego_view: ZED camera")
        print("  - head: RealSense camera")
        print()

        try:
            while True:
                data = self.receive_frame()
                if data is None:
                    continue

                images = data.get("images", {})
                timestamps = data.get("timestamps", {})
                
                if not images:
                    print("No images in frame")
                    continue

                fps = self.get_fps()
                
                # Process each camera feed
                for camera_name, image_b64 in images.items():
                    image = decode_image(image_b64)
                    
                    # The server sends RGB, OpenCV expects BGR
                    image = cv2.cvtColor(image, cv2.COLOR_RGB2BGR)
                    
                    # Add overlay info
                    label = f"{camera_name}"
                    if camera_name == "ego_view":
                        label += " (ZED)"
                    elif camera_name == "head":
                        label += " (RealSense)"
                    
                    cv2.putText(image, label, (10, 30),
                               cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
                    cv2.putText(image, f"FPS: {fps:.1f}", (10, 60),
                               cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)
                    
                    # Show latency if timestamp available
                    if camera_name in timestamps:
                        latency_ms = (time.time() - timestamps[camera_name]) * 1000
                        cv2.putText(image, f"Latency: {latency_ms:.0f}ms", (10, 85),
                                   cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 200, 200), 1)
                    
                    # Display
                    window_name = f"G1 Camera - {camera_name}"
                    cv2.imshow(window_name, image)
                    
                    # Save frame if enabled
                    if self.save_frames and self.save_dir:
                        filename = f"{self.save_dir}/{camera_name}_{self.frame_count:06d}.jpg"
                        cv2.imwrite(filename, image)

                self.frame_count += 1

                # Handle keypresses
                key = cv2.waitKey(1) & 0xFF
                if key == ord('q') or key == 27:  # 'q' or ESC
                    break
                elif key == ord('s'):
                    self.save_frames = not self.save_frames
                    status = "ON" if self.save_frames else "OFF"
                    print(f"Frame saving: {status}")

        except KeyboardInterrupt:
            print("\nStopped by user")

    def close(self):
        """Clean up resources."""
        self.socket.close()
        self.context.term()
        cv2.destroyAllWindows()
        print("Viewer closed")


def main():
    parser = argparse.ArgumentParser(
        description="View G1 camera stream (ZED ego + RealSense head)"
    )
    parser.add_argument("--ip", type=str, default="192.168.123.164",
                        help="Robot IP address (default: 192.168.123.164)")
    parser.add_argument("--port", type=int, default=5555,
                        help="Camera server port (default: 5555)")
    parser.add_argument("--save", action="store_true",
                        help="Enable frame saving")
    parser.add_argument("--save-dir", type=str, default="./captured_frames",
                        help="Directory to save frames (default: ./captured_frames)")
    
    args = parser.parse_args()
    
    viewer = CameraViewer(args.ip, args.port)
    
    try:
        viewer.connect()
        
        if args.save:
            viewer.enable_save(args.save_dir)
        
        viewer.run()
    finally:
        viewer.close()


if __name__ == "__main__":
    main()

