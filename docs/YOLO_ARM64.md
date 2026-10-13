# YOLO on Apple Silicon: Ubuntu 22.04 ARM64 / UTM / ROS 2 Humble

**Technical implementation and validation report · 13 October 2026**

> **Validated:** native aarch64 Python environment; PyTorch and Ultralytics imports; YOLO11 Nano `.pt` CPU inference; ROS 2 Python import interoperability. **Not yet validated:** complete Yahboom YOLO ROS node pipeline with real camera/robot, video FPS benchmark, GPU or Apple Neural Engine acceleration.

## 1. Purpose and architecture

The original Yahboom MicroROS V2 educational distribution was built for **Ubuntu x86_64 in VMware**. The new development VM runs **Ubuntu 22.04 ARM64 (aarch64) in UTM on an Apple Silicon Mac**. Python binary environments copied from x86_64 cannot be run as native aarch64 environments; their native extensions must be reinstalled or rebuilt for the guest CPU architecture.

The adaptation retains the Yahboom source workspace while providing an isolated native YOLO environment:

```text
Apple Silicon Mac (UTM host)
    └── Ubuntu 22.04 aarch64 virtual machine (guest)
        ├── /opt/ros/humble                    ROS 2 Humble
        ├── /home/yahboom/microros_ws           Yahboom ROS 2 workspace
        │   └── src/scripts/yolo_env.sh        Activation script (ARM64-adapted)
        ├── /home/yahboom/yolo_arm64_env        Native Python virtual environment
        └── /home/yahboom/MODELS/yolo/yolo11n.pt   Validated YOLO model
```

**Important:** “YOLO for Apple Silicon” here means **Linux ARM64 CPU inference inside a UTM guest**, not a native macOS app or an Apple Metal/Core ML accelerated runtime.

## 2. Recorded environment

| Component | Validated version / setting |
| --- | --- |
| Host CPU | Apple Silicon M4 |
| Virtualization | UTM |
| Guest OS / architecture | Ubuntu 22.04 / `aarch64` |
| ROS | ROS 2 Humble |
| PyTorch | `2.5.1` |
| Torchvision | `0.20.1` |
| Ultralytics | `8.3.200` |
| OpenCV Python | `4.10.0` |
| NumPy | `1.26.4` |
| Pillow | `11.3.0` |
| ONNX Runtime | `1.23.2` (installed, not benchmarked here) |
| Model | YOLO11 Nano, `yolo11n.pt` |
| Inference backend / device | PyTorch, `cpu` |
| Dedicated environment size | Approximately 1.2 GB |

Versions are an **observed working combination**, not a guarantee that mixing other releases will succeed. Python and ROS packages must match the Ubuntu 22.04 ABI.

## 3. Problem encountered during migration

The VMware image included old virtual environments such as:

```text
~/microros_ws/python_env/yolo_env/.venv
~/microros_ws/python_env/mircoros_v2_env/.venv_x86_backup
```

These contained x86_64-native Python extensions (including components of PyTorch and Pillow) and occupied approximately 6 GB. Reusing them under aarch64 would produce architecture incompatibilities. After successful replacement and validation, they were removed; the 60 GiB guest root filesystem then had approximately 29 GiB free.

The `yolo_env.sh` launch script originally pointed at the old x86_64 environment. It was adapted to activate:

```text
/home/yahboom/yolo_arm64_env/bin/activate
```

A copy of the previous activation script was retained as `yolo_env.sh.original` for reference.

## 4. Using the environment included in the VM

Open a **terminal inside the Ubuntu UTM guest** and run:

```bash
source /opt/ros/humble/setup.bash
source "$HOME/microros_ws/install/setup.bash"
source "$HOME/microros_ws/src/scripts/yolo_env.sh"
```

Verify the active Python and its architecture:

```bash
which python
python -c 'import platform,torch,ultralytics; print(platform.machine()); print(torch.__version__); print(ultralytics.__version__)'
```

Expected architecture: `aarch64`. The executable should resolve inside `~/yolo_arm64_env/bin/`.

If recreating the environment independently rather than using the exported VM, use an ARM64 Ubuntu Python virtual environment and install mutually compatible native aarch64 builds. The versions in §2 provide a tested reference. **This document does not claim that a generic, unpinned `pip install` recreates the exact environment**, nor does it reproduce every historical dependency installation command.

## 5. Tested YOLO11 CPU inference

The model and test image were present in the guest:

```text
/home/yahboom/MODELS/yolo/yolo11n.pt
/home/yahboom/Pictures/yahboom (1).jpg
```

After environment activation:

```bash
python - <<'PY'
from ultralytics import YOLO

model = YOLO('/home/yahboom/MODELS/yolo/yolo11n.pt')
results = model.predict(
    '/home/yahboom/Pictures/yahboom (1).jpg',
    imgsz=320,
    device='cpu',
    verbose=False,
    save=False,
)
print('YOLO inference: OK')
print('Detections:', len(results[0].boxes))
PY
```

**Observed outcome:** model loading and CPU inference succeeded, reporting **one detected object**. This is an inference smoke test, not an accuracy benchmark, class-by-class validation, or real-time camera test.

For other images, replace the test-image path. If the `.pt` model is unavailable, obtain weights from a trusted, properly licensed source rather than substituting an unverified file.

## 6. ROS 2 interoperability smoke test

Load ROS before activating the YOLO environment:

```bash
source /opt/ros/humble/setup.bash
source "$HOME/microros_ws/install/setup.bash"
source "$HOME/microros_ws/src/scripts/yolo_env.sh"

python - <<'PY'
import torch
import ultralytics
import rclpy
import cv_bridge
from sensor_msgs.msg import Image
import message_filters
import interfaces.srv
print('YOLO + ROS 2 ARM64: OK')
PY
```

**Observed:** `YOLO + ROS 2 ARM64: OK`.

This establishes that the imported PyTorch/Ultralytics components and ROS 2 bindings can coexist in the same interpreter. It does **not** establish that camera topics, model inference, publishers, robot actions, and all original ROS nodes function as a complete pipeline.

Other ROS 2 Humble packages present in the guest include `common_demo`, `interfaces`, `microros_v2_bringup`, `microros_v2_mediapipe_pkg`, visual-control packages and further Yahboom packages. Their presence alone should not be interpreted as validation of every executable.

## 7. Dependency consistency check

The adapted Python environment passed:

```bash
source "$HOME/microros_ws/src/scripts/yolo_env.sh"
python -m pip check
```

**Observed:** `No broken requirements found.` This checks installed Python package metadata, not native ABI compatibility for every possible library combination. The concrete PyTorch inference test in §5 is therefore important independent evidence.

## 8. Troubleshooting

### `ModuleNotFoundError: No module named 'ultralytics'`

The terminal is probably using the wrong Python interpreter. Check `which python` and activate `~/microros_ws/src/scripts/yolo_env.sh`. Do not install Ultralytics into Ubuntu system Python to work around this.

### `ModuleNotFoundError: No module named 'rclpy'`

First source `/opt/ros/humble/setup.bash`, then `~/microros_ws/install/setup.bash`, and only then activate the YOLO environment. Run the import test from §6. ROS paths and interpreter visibility must be consistent.

### Architecture or shared-library errors

Check:

```bash
uname -m
python -c 'import platform; print(platform.machine())'
```

Both should report `aarch64`. Do not copy `.venv` folders from the old VMware x86_64 image. Reinstall ARM64-native wheels or build native extensions where necessary.

### Inference is slow

The tested backend is CPU-based. Start with `yolo11n.pt`, `imgsz=320`, and avoid multiple concurrently running heavy services. Measure throughput in the specific target VM instead of assuming hardware-independent frame rates.

### An original Yahboom script still references the old environment

Inspect the script rather than applying indiscriminate search-and-replace:

```bash
grep -n 'VENV_ACTIVATE' "$HOME/microros_ws/src/scripts/yolo_env.sh"
```

Expected activation path: `/home/yahboom/yolo_arm64_env/bin/activate`. Any custom project or launch configuration should be reviewed individually.

### Model inference works but camera output is missing

Test the camera publisher and ROS topic separately:

```bash
source /opt/ros/humble/setup.bash
source "$HOME/microros_ws/install/setup.bash"
ros2 topic list -t
ros2 topic info /camera/image_raw --verbose
```

A topic with subscribers but **zero publishers** does not deliver frames. Confirm QoS compatibility, image encodings, camera passthrough/networking, and the expected topic name in the actual application.

## 9. Validation matrix

| Test | Result |
| --- | --- |
| ARM64 Python environment activation | PASS |
| PyTorch 2.5.1 import | PASS |
| Ultralytics 8.3.200 import | PASS |
| `yolo11n.pt` model load | PASS |
| Single-image CPU inference | PASS — one object detected |
| ROS 2 and YOLO Python imports in one environment | PASS |
| `pip check` | PASS |
| Hardware camera stream / image-topic processing through YOLO node | NOT TESTED |
| Physical robot actions following YOLO detections | NOT TESTED |
| Real-time FPS / latency benchmark | NOT TESTED |
| GPU, Metal, Core ML or Neural Engine acceleration | NOT TESTED / NOT CLAIMED |
| ONNX Runtime inference benchmark | NOT TESTED in this validation series |

## 10. Recommended next experiments

1. Feed a real still image into a non-actuating ROS 2 image pipeline and verify its detections.
2. Identify the exact Yahboom YOLO detector node and subscribed/published topics; validate with a synthetic image stream before connecting hardware.
3. Connect a camera and record inference latency, end-to-end FPS, CPU/RAM consumption and QoS behavior.
4. Evaluate ONNX Runtime CPU inference as an alternative backend, with reproducible measurements.
5. Only after review of actuator nodes, test any robot-follow or movement features in a supervised setting with an accessible emergency stop.

## 11. Related documentation

- [UTM image on Hugging Face](https://huggingface.co/datasets/enkire/Yahboom-MicroROS-V2-Ubuntu-22.04-ARM64-UTM)
- [Yahboom Apple Silicon migration project](https://github.com/jcarpio/Yahboom_MicroROS-V2-on-Apple-Silicon)
- [Experimental MediaPipe 0.10.21 ARM64 release](https://github.com/jcarpio/MediaPipe-0.10.21-Linux-ARM64/releases/tag/v0.10.21-arm64-alpha.1)

## 12. Licensing and publication note

The guest integrates components with different upstream licenses. Preserve the relevant license notices and confirm the redistribution terms for Yahboom software, model weights and other third-party binaries. A virtual-machine export can include cached credentials, instance-specific keys, application databases or deleted-file remnants; packaging/compression does not remove these automatically. Before making an archive public, verify its content and publish checksums. This guide documents a community migration, not an official Yahboom release.
