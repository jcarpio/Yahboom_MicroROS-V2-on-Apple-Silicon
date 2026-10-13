# Yahboom ROSmaster ROS 2 Humble on Apple Silicon using UTM

**An engineering migration log, beginner-friendly setup guide, verification report, and current-image status**

> **Project status (13 October 2026): functional experimental ARM64 development image.** The Apple Silicon VM runs Ubuntu 22.04 ARM64, ROS 2 Humble, reconstructed Yahboom desktop launchers, navigation/mapping user interfaces, micro-ROS components, and an experimentally built MediaPipe 0.10.21 ARM64 package. Four MediaPipe CPU inference smoke tests passed. The **original Yahboom `hand_detector_node` successfully received synthetic ROS 2 images and displayed the processed output**. Physical robot operation, real-camera recognition, mapping accuracy, and autonomous navigation are **not yet validated**.
>
> **Independent community documentation.** Not affiliated with or endorsed by Yahboom, Canonical, ROS/Open Robotics, Apple, UTM, VMware, Google, or the MediaPipe team.

## Table of contents

1. [Who this is for](#1-who-this-is-for)
2. [What was accomplished](#2-what-was-accomplished)
3. [A beginner's mental model](#3-a-beginners-mental-model)
4. [Hardware, operating systems, and evidence](#4-hardware-operating-systems-and-evidence)
5. [Why the VMware image was not simply booted](#5-why-the-vmware-image-was-not-simply-booted)
6. [Migration approach: fresh ARM64 OS, preserved source](#6-migration-approach-fresh-arm64-os-preserved-source)
7. [UTM setup and shared-folder considerations](#7-utm-setup-and-shared-folder-considerations)
8. [Rebuilding the ROS 2 environment](#8-rebuilding-the-ros-2-environment)
9. [micro-ROS, mapping, navigation, and desktop integration](#9-micro-ros-mapping-navigation-and-desktop-integration)
10. [The MediaPipe ARM64 challenge](#10-the-mediapipe-arm64-challenge)
11. [Reproducing the validated MediaPipe installation](#11-reproducing-the-validated-mediapipe-installation)
12. [Building the original Yahboom MediaPipe ROS 2 package](#12-building-the-original-yahboom-mediapipe-ros-2-package)
13. [End-to-end test: a synthetic ROS 2 camera](#13-end-to-end-test-a-synthetic-ros-2-camera)
14. [Complete verification matrix](#14-complete-verification-matrix)
15. [Known issues, security, and limitations](#15-known-issues-security-and-limitations)
16. [Reusing or distributing the VM image](#16-reusing-or-distributing-the-vm-image)
17. [Troubleshooting](#17-troubleshooting)
18. [Suggested roadmap](#18-suggested-roadmap)
19. [Current state and conclusion](#19-current-state-and-conclusion)
20. [Information needed to finalize a public release](#20-information-needed-to-finalize-a-public-release)
21. [Resources and acknowledgments](#21-resources-and-acknowledgments)

---

## 1. Who this is for

This guide targets robotics students, makers, researchers, and educators who own an **Apple Silicon Mac** and want to explore the Yahboom ROSmaster ROS 2 environment without necessarily owning or powering the robot during initial development. No previous ROS 2 experience is assumed. Readers should, however, be comfortable opening a Linux terminal and running commands.

There are **two different objectives**:

- **Developer/desktop environment:** ROS 2 tooling, Yahboom source packages, visual applications, simulation-oriented experiments, and MediaPipe demonstrations inside an ARM64 Linux VM. Much of this was verified.
- **Robot-connected environment:** camera streams, motor interfaces, LiDAR, networking, SLAM, autonomous navigation, and physical actuation. This is **not yet verified end to end** on the migrated image.

This is a **documented migration and verification record**, not yet a turnkey installer or a downloadable redistributable VM image.

## 2. What was accomplished

The working result is an **Ubuntu 22.04 ARM64 guest running through UTM on an Apple M4 Mac**, replacing a VMware-oriented Ubuntu x86-64 development environment. The original project's ROS 2 source was retained and the platform-specific binaries were rebuilt or installed afresh for ARM64.

Confirmed milestones:

1. Investigated the original x86-64 VMware image and attempted a VMDK-to-QCOW2 migration. The converted image did not become a usable guest in UTM's x86 emulation.
2. Adopted a **clean Ubuntu 22.04 ARM64 installation** as a more maintainable solution; moved source/configuration rather than copying the x86 operating system and native binaries.
3. Reconstructed a usable ROS 2 Humble workspace at `~/microros_ws` and built an initial selection of ARM64 packages.
4. Installed relevant ROS 2 components including **SLAM Toolbox** and **Nav2 Bringup**; compiled a separate **micro-ROS Agent** workspace.
5. Restored five Yahboom desktop launchers: **RobotManager, JoystickControl, KeyboardControl, Mapping, and Navigation**.
6. Built MediaPipe **0.10.21** for Linux aarch64 using a separate **BUILDER** Ubuntu ARM64 VM, and published experimental release artifacts on GitHub.
7. Installed MediaPipe only in a virtual environment on the **main** Yahboom VM, with private native OpenCV libraries and documented compatibility workarounds.
8. Ran **Hands, Pose, Face Mesh, and Holistic** on a blank frame using TensorFlow Lite CPU/XNNPACK.
9. Built Yahboom's `microros_v2_mediapipe_pkg` as a ROS 2 Python package, registering **16 ROS 2 executables**.
10. Started its original `hand_detector_node` under the MediaPipe virtual environment, confirmed its camera subscription, published **20 synthetic 640 × 480 black images**, and saw the `hand_detector` window with an FPS overlay.

**Important nuance:** successful operation with a blank frame demonstrates pipeline execution, **not** successful detection of actual hands or other objects.

## 3. A beginner's mental model

### 3.1 Apple Silicon versus x86-64

Older VMware Linux images often target **x86-64**, the instruction set used by Intel/AMD PCs. Apple M-series processors use **ARM64**, also called **aarch64**. Executables compiled for x86-64 generally **cannot execute directly** in an ARM64 Linux guest. Rebuilding native code and reinstalling matching binary packages is therefore essential.

**UTM** can run ARM64 virtual machines efficiently on Apple Silicon; it can also emulate other CPU architectures, but emulation is a different, often slower and more compatibility-sensitive approach. A virtual disk conversion does **not** translate executables between CPU architectures.

### 3.2 What is ROS 2?

**ROS 2 (Robot Operating System 2)** is a communication and software framework for robots. It is not a replacement for Ubuntu. Common terms:

| Term | Beginner explanation | Example in this project |
| --- | --- | --- |
| **Node** | A program performing one robot-related task | `hand_detector_node` |
| **Topic** | Named channel for asynchronous messages | `/camera/image_raw` |
| **Message type** | Structure of data on a topic | `sensor_msgs/msg/Image` |
| **Publisher** | Program sending messages | Synthetic-camera test node |
| **Subscriber** | Program receiving messages | `hand_detector_node` |
| **Package** | Unit of ROS 2 code, configuration and metadata | `microros_v2_mediapipe_pkg` |
| **Workspace** | Directory containing a collection of packages | `~/microros_ws` |
| **Colcon** | Common ROS 2 build tool | `colcon build` |
| **Launch file** | Configuration that starts nodes/processes | Yahboom mapping/navigation launch files |
| **RViz2** | Visualization program for ROS 2 data | Mapping/Navigation UIs |
| **SLAM** | Simultaneous localization and mapping | Building a map from sensor data |
| **Nav2** | ROS 2 navigation framework | Navigation launch workflow |
| **micro-ROS** | ROS 2-oriented communication for embedded/microcontroller systems | micro-ROS Agent |

A node appearing in `ros2 topic list` **does not mean a sensor is connected**. A topic can exist solely because a node has subscribed to it.

### 3.3 MediaPipe, OpenCV, and cv_bridge

**MediaPipe** runs perception pipelines (hands, body pose, face landmarks, etc.). **OpenCV** provides general image operations and display. **`cv_bridge`** converts between ROS image messages and OpenCV images. In our validated test:

```text
Synthetic ROS 2 image publisher
              |
              v
       /camera/image_raw
      sensor_msgs/msg/Image
              |
              v
     Yahboom hand_detector_node
              |
       ROS 2 cv_bridge
              |
       MediaPipe Hands CPU
              |
       OpenCV rendering
              |
              v
      "hand_detector" window
```

## 4. Hardware, operating systems, and evidence

| Item | Original VMware environment | Main migrated UTM environment | Separate build VM |
| --- | --- | --- | --- |
| Host | VMware-based x86 development setup | Apple Silicon Mac, **M4** | Same Apple Silicon/UTM workflow |
| Guest CPU architecture | **x86-64** | **aarch64 / ARM64** | **aarch64 / ARM64** |
| Guest OS | Ubuntu 22.04 | Ubuntu **22.04** | Ubuntu **22.04** |
| Python | Original details not completely audited | **3.10.12** | Python 3.10 |
| ROS version | Yahboom ROS 2 workspace | **ROS 2 Humble** | Primarily MediaPipe builder |
| Disk | Original virtual disk ~56 GiB | **30 GiB filesystem**; final ~24 GiB used, **5.2 GiB free** | ~60 GiB disk; ~29 GiB free in previous check |
| RAM/vCPU | Original VMware configuration recorded as **8 GiB / 4 CPUs** | **Not confirmed in available final logs** | **Not confirmed** |
| VM username / hostname | Project-specific | `yahboom` / `vm` | `yahboom` / `vm` |
| Role | Source reference | Everyday robot-development VM | Compile MediaPipe ARM64 artifacts |

**Evidence classification used throughout this document:**

- **PASS**: command outputs, build summaries, runtime logs, or screenshots actually observed.
- **STARTED / UI PASS**: process/window successfully opened, but functional robotics behavior not demonstrated.
- **NOT TESTED**: no evidence of real behavior yet.
- **RECONSTRUCTION / GUIDANCE**: a reproducible suggestion based on the successful setup, but not necessarily the exact historical command.

We have intentionally not invented exact UTM CPU, memory, firmware, graphics or network settings where the logs do not establish them.

## 5. Why the VMware image was not simply booted

### The attempted direct-conversion route

The migration initially investigated the original VMware **VMDK** disk. It was converted to **QCOW2** for UTM use and inspected. The conversion reported a valid QCOW2 container (`corrupt: false`), but booting it through UTM's **x86-64 emulation** did not yield a working Ubuntu system. Boot troubleshooting reached errors such as:

```text
No working init found
```

Filesystem troubleshooting also exposed issues concerning the ext4 journal, HTree, inodes and bitmaps. These observations do **not** prove that QCOW2 conversion universally fails; they describe the investigated disk and boot attempt. The original VMDK was preserved.

### Decision

A bootable disk image and a *working robotics distribution* are different things. Even a successfully emulated x86 desktop would not give an efficient native ARM64 environment. We therefore preferred:

1. A new Ubuntu 22.04 **ARM64** guest.
2. A native ROS 2 Humble installation.
3. Copying Yahboom project **source code and configuration**, not incompatible x86 compiled outputs.
4. Selective ARM64 compilation and dependency repairs.
5. Native ARM64 MediaPipe packaging instead of relying on x86 artifacts.

**Lesson:** preserve and migrate *source, configuration, launch files, images and data*; regenerate *architecture-dependent binaries*.

## 6. Migration approach: fresh ARM64 OS, preserved source

### 6.1 Source material

The original project included a workspace at:

```text
/home/yahboom/microros_ws/
├── src/
├── third_party_library/
├── system_cfg/
├── .git/
└── python_env/
```

Some of these paths hold project configuration and reference material rather than ready-to-run ARM64 environments. **Do not copy old virtualenv binaries from x86 and expect them to work**. The migration deliberately excluded or regenerated previous `build/`, `install/` and `log/` products.

### 6.2 Recommended safe transfer pattern

On the **source VM**, stage a portable archive (this is a recommended reproducible command, not a claim that this exact command was historically used):

```bash
cd /home/yahboom
# Review src for private keys, Wi-Fi credentials and user data first.
tar --exclude='microros_ws/build' \
    --exclude='microros_ws/install' \
    --exclude='microros_ws/log' \
    --exclude='microros_ws/.venv' \
    -czf yahboom-source-migration.tar.gz microros_ws
```

Transfer it to the ARM64 VM by a **trusted** shared folder or `scp`. Extract under the appropriate user's home directory. Do not publish `system_cfg`, shell history, network secrets, host keys, tokens, `.git` remotes with credentials, or proprietary Yahboom software without reviewing rights and privacy.

### 6.3 Post-transfer verification

```bash
uname -m             # expected: aarch64
lsb_release -ds      # expected: Ubuntu 22.04...
python3 --version    # validated: Python 3.10.12
find ~/microros_ws/src -maxdepth 2 -name package.xml | head
```

These are diagnostic commands; they do not build anything.

## 7. UTM setup and shared-folder considerations

### 7.1 First-time UTM VM creation

**Generalized reproduction steps (not an exact export of the historical UTM VM settings):**

1. Install UTM on an Apple Silicon Mac.
2. Create a new VM using **virtualization for ARM64**, not an x86-64 guest selected by accident.
3. Boot a legitimate Ubuntu **22.04 ARM64/aarch64** installation image.
4. Allocate enough CPU, RAM and disk for ROS 2, RViz2 and source builds. The current 30 GiB system filesystem works but is **tight**; a larger virtual disk is recommended for new users, especially if compiling libraries locally.
5. Install Ubuntu (server + desktop, or desktop directly), create a non-root user, and apply security updates compatible with Ubuntu 22.04 / ROS 2 Humble.
6. Test networking, clipboard, display, terminal and optional shared-folder functions.
7. Verify `uname -m` returns `aarch64` before installing architecture-specific packages.

**Do not assume:** graphics/OpenGL performance in RViz2, USB passthrough, camera access, CPU/GPU acceleration and networking are equivalent to native Ubuntu hardware. They require individual validation on each host/UTM release.

### 7.2 Shared folder used during the migration

The VMware side used a VMware shared folder available through `vmhgfs-fuse`. In the UTM guest, the shared folder was mounted as **9p**:

```bash
sudo mkdir -p /mnt/share
sudo mount -t 9p -o trans=virtio,version=9p2000.L share /mnt/share
findmnt /mnt/share
```

The share sometimes was **not mounted after reboot** and, in this setup, writing to `/mnt/share` required **`sudo`**. A long multi-command copy appeared to reset/close the terminal, so this was not treated as a reliable transport mechanism. The team later preferred **GitHub Release downloads** for already-published MediaPipe artifacts.

**Recommendation:** for unpublished archives, use `scp` over a trusted connection or an explicitly verified shared-folder workflow. Check file hashes after copying. Avoid changing system-wide permissions just to accommodate a share.

### 7.3 Two VMs, not one

The final arrangement has two conceptually separate guests:

- **Main Yahboom VM (`~/microros_ws`, ~30 GiB filesystem)**: ROS 2, desktop applications and runtime testing.
- **BUILDER VM (`~/build_projects/mediapipe`, ~60 GiB disk)**: memory/disk-intensive native MediaPipe compilation and release packaging.

Both guests used `yahboom@vm` in terminal prompts, so **verify the disk size and expected paths** before running destructive operations.

## 8. Rebuilding the ROS 2 environment

### 8.1 Native installation principles

ROS 2 Humble targets Ubuntu 22.04. Its architecture-specific packages must match **ARM64**. Start from ROS's official Ubuntu installation documentation rather than attempting to transplant `/opt/ros` from an x86 filesystem. The existing main VM has ROS 2 Humble installed at `/opt/ros/humble`.

The essential initialization sequence is:

```bash
source /opt/ros/humble/setup.bash
cd ~/microros_ws
colcon list --names-only
```

The historical effort rebuilt **an initial set of approximately 11 workspace packages** on ARM64. This does **not** mean all Yahboom packages have been compiled or all device drivers have been exercised.

### 8.2 What `colcon` does

A ROS workspace keeps source packages in `src/`. `colcon` produces architecture-specific `build/` and `install/` outputs and logging under `log/`. A common workflow is:

```bash
source /opt/ros/humble/setup.bash
cd ~/microros_ws
colcon list --names-only             # inspect
# Example: only build the known, needed Python package
colcon build --packages-select microros_v2_mediapipe_pkg \
  --symlink-install --event-handlers console_direct+
source ~/microros_ws/install/setup.bash
ros2 pkg executables microros_v2_mediapipe_pkg
```

For newcomers: `--packages-select` deliberately avoids rebuilding every possibly unsupported package; `--symlink-install` facilitates development of Python packages. On a small VM disk, selective builds are especially valuable.

### 8.3 Environment variables

The working shell configuration included:

```bash
export ROS_DOMAIN_ID=40
export CAR_TYPE=ptz
```

`ROS_DOMAIN_ID` determines which DDS discovery domain ROS participants join; **every cooperating ROS device must agree on it**. `CAR_TYPE` is a project-specific Yahboom setting, not a ROS standard. Change it only after confirming your actual hardware model and launch scripts.

For tests, explicitly source both environments:

```bash
source /opt/ros/humble/setup.bash
source ~/microros_ws/install/setup.bash
```

`ros2 node list` and `ros2 topic list -t` are excellent read-only diagnostics, but a discovered topic does not prove it carries messages.

## 9. micro-ROS, mapping, navigation, and desktop integration

### 9.1 micro-ROS Agent

A separate workspace, `~/microros_agent_ws`, was compiled on ARM64. The recorded agent version was **3.0.6** and the agent binary was used/configured with **UDP port 8090** in the project context. Building an agent does not verify communication with a particular microcontroller.

For beginners, the **micro-ROS Agent** connects resource-constrained embedded devices with the broader ROS 2 network. To establish hardware interoperability later, check the actual firmware, transport, firewall, device addressing, Domain ID, and observed agent/client logs.

### 9.2 Mapping and Nav2

The main Ubuntu ARM64 guest had these packages installed:

- `ros-humble-slam-toolbox` — recorded version **2.6.10**.
- `ros-humble-nav2-bringup` — recorded version **1.1.20**.

The Yahboom **Mapping** launcher opened an RViz2/mapping UI. The **Navigation** launcher likewise opened its RViz2/navigation interface. These are valuable **UI/startup checks**, but they are not evidence that a LiDAR map was built, localization converged, a global/local planner ran, or a physical robot reached a goal.

### 9.3 Five Yahboom launchers restored

| Desktop icon | Observed result | What remains unproven |
| --- | --- | --- |
| **RobotManager** | Application launched; Python Textual dependency was installed for it | Robot control/hardware connection |
| **JoystickControl** | Original-style launcher made operational after `.desktop`/GNOME troubleshooting | Joystick hardware and motor actions |
| **KeyboardControl** | Launched; a secondary terminal labeled **Keyboard UI** was consistent with original behavior | Commands reaching a physical robot |
| **Mapping** | Opened RViz2/mapping UI | Real sensor mapping, SLAM map quality |
| **Navigation** | Opened RViz2/navigation UI | Goal execution and autonomous movement |

The original icon graphics were preserved. The desktop wallpaper (a Yahboom JPG, recorded as `yahboom (6).jpg`) was restored under `~/Pictures/Wallpapers`. These changes recovered the familiar educational desktop experience without claiming exact functional parity with the original VMware image.

### 9.4 Other original Python environments

Source-side folders/configuration mentioned a `python_env`, a `microros_v2_env` with application requirements, and a `yolo_env`. Not all of these original x86 virtual environments have been recreated or validated on ARM64. Specifically, **YOLO and every Yahboom AI demonstration are not yet proven working**. Avoid interpreting a successful desktop launch as an audit of all optional AI components.

## 10. The MediaPipe ARM64 challenge

### 10.1 Why this needed a separate project

Yahboom programs make widespread use of MediaPipe's **classic `mp.solutions` API**. The required version was **MediaPipe 0.10.21**, and a suitable readily installable Linux ARM64 wheel was not available for this setup. Rewriting all educational examples to a different API would have been a large change. The project therefore built the existing version for aarch64.

### 10.2 Separate BUILDER environment

| Property | Recorded value |
| --- | --- |
| Upstream source | MediaPipe **v0.10.21** |
| Upstream commit | `cad7f3ab99ebf175947e40c5252c642612aae927` |
| Build tool | Bazel **6.5.0** |
| Guest OS / ABI | Ubuntu 22.04 **aarch64**, CPython **3.10** |
| Source checkout | `~/build_projects/mediapipe` |
| Build virtualenv | `~/build_projects/mediapipe-build-env` |
| Test virtualenv | `~/build_projects/mediapipe-test-env` |
| Wheel output | `dist/mediapipe-0.10.21-cp310-cp310-linux_aarch64.whl` |
| Wheel approximate size | **31 MB** |

The source-build exercise included compatibility edits to `WORKSPACE`, `setup.py`, and `third_party/opencv_linux.BUILD`. Backups of modified files existed on BUILDER. **The complete patch diff/build transcript is not included in this record; do not claim the wheel can be rebuilt from these README commands alone.** A dedicated, version-controlled patch series and exact Bazel invocation should be published as future work.

The wheel contained the expected compiled MediaPipe Python extension components, including `_framework_bindings`, `_pywrap_metadata_version` and `_pywrap_flatbuffers`.

### 10.3 Runtime packaging compromise

The compiled MediaPipe native extension requires **eight OpenCV 3.4.11 libraries**:

```text
libopencv_calib3d.so.3.4
libopencv_core.so.3.4
libopencv_features2d.so.3.4
libopencv_highgui.so.3.4
libopencv_imgcodecs.so.3.4
libopencv_imgproc.so.3.4
libopencv_video.so.3.4
libopencv_videoio.so.3.4
```

These libraries are shipped as a **separate private runtime ZIP**, not placed into `/usr/lib`. The tested Python `cv2` module, however, comes from Ubuntu's **OpenCV 4.5.4** package. This coexistence worked in the observed tests but is **experimental**, and may have ABI or symbol conflicts in other circumstances.

There is also an old generated-Protobuf compatibility problem: with `protobuf==4.25.8`, the tests required:

```bash
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python
```

This uses the slower pure-Python Protobuf implementation as a workaround; it is **not** a permanent upstream fix.

### 10.4 Published experimental assets

The MediaPipe assets were published separately at:

**[MediaPipe 0.10.21 Linux ARM64 — experimental GitHub release](https://github.com/jcarpio/MediaPipe-0.10.21-Linux-ARM64/releases/tag/v0.10.21-arm64-alpha.1)**

Known artifacts:

```text
mediapipe-0.10.21-cp310-cp310-linux_aarch64.whl
mediapipe-0.10.21-opencv34-runtime-linux-aarch64.zip
mediapipe-0.10.21-opencv34-runtime-linux-aarch64.zip.sha256
```

Recorded **SHA-256 values**:

```text
326870054609c45a94ed63ed296d80799ad04979f103067042e1cc251554d880  mediapipe-0.10.21-cp310-cp310-linux_aarch64.whl
8fb325a2350c602d00987a9d40ca37ed921dfc496b3ea6763940cad2eeb83e10  mediapipe-0.10.21-opencv34-runtime-linux-aarch64.zip
```

The OpenCV checksum file originally contained an **absolute BUILDER path**. Running `sha256sum -c` directly on the destination VM failed because that path did not exist; computing the downloaded ZIP hash manually proved an exact match. This is a **path-format problem, not ZIP corruption**.

A preliminary expanded third-party license-audit bundle was also assembled for the MediaPipe repository, but **a collected list of licenses is not a completed legal redistribution audit**.

## 11. Reproducing the validated MediaPipe installation

> This section closely follows the commands whose results were observed on the **main** Yahboom VM. It assumes Ubuntu 22.04 aarch64, Python 3.10, ROS 2 Humble, network access and a system OpenCV Python module. It installs into a **virtualenv**, not into system Python.

### 11.1 Check your platform and system OpenCV

```bash
uname -m
python3 --version
/usr/bin/python3 -c 'import cv2; print(cv2.__version__, cv2.__file__)'
# Validated: aarch64, Python 3.10.12, cv2 4.5.4
```

If system `cv2` is absent, consult Ubuntu/ROS-compatible installation instructions; do not blindly install a second OpenCV wheel over ROS tooling.

### 11.2 Download and verify

```bash
mkdir -p ~/mediapipe_arm64_install
cd ~/mediapipe_arm64_install
BASE='https://github.com/jcarpio/MediaPipe-0.10.21-Linux-ARM64/releases/download/v0.10.21-arm64-alpha.1'
wget "$BASE/mediapipe-0.10.21-cp310-cp310-linux_aarch64.whl"
wget "$BASE/mediapipe-0.10.21-opencv34-runtime-linux-aarch64.zip"
wget "$BASE/mediapipe-0.10.21-opencv34-runtime-linux-aarch64.zip.sha256"
sha256sum mediapipe-0.10.21-cp310-cp310-linux_aarch64.whl
sha256sum mediapipe-0.10.21-opencv34-runtime-linux-aarch64.zip
```

Compare the outputs with the hashes above. **Do not run installation scripts downloaded from a third-party release without reviewing them first.** The original ZIP's `.sha256` file may refer to a BUILDER-only absolute path.

### 11.3 Create an isolated Python virtual environment

```bash
python3 -m venv ~/mediapipe_arm64_env
cd ~/mediapipe_arm64_install
unzip -oq mediapipe-0.10.21-opencv34-runtime-linux-aarch64.zip
VENV="$HOME/mediapipe_arm64_env"
RUNTIME="$HOME/mediapipe_arm64_install/mediapipe-0.10.21-opencv34-runtime-linux-aarch64"
# Read the script before executing it:
cat "$RUNTIME/install_opencv_runtime.sh"
bash "$RUNTIME/install_opencv_runtime.sh" "$VENV"
```

The reviewed runtime installer verifies its internal `SHA256SUMS`, copies native OpenCV libraries into `$VENV/lib/mediapipe-opencv`, and creates a scoped process launcher:

```text
~/mediapipe_arm64_env/run-with-mediapipe-opencv
```

It does **not** modify `/usr/lib` or permanently set `LD_LIBRARY_PATH`.

### 11.4 Install wheel and compatible Python dependencies

```bash
VENV="$HOME/mediapipe_arm64_env"
DIR="$HOME/mediapipe_arm64_install"
"$VENV/bin/python" -m pip install --no-deps \
  "$DIR/mediapipe-0.10.21-cp310-cp310-linux_aarch64.whl"
"$VENV/bin/python" -m pip install \
  'numpy==1.26.4' 'protobuf==4.25.8' \
  absl-py attrs flatbuffers matplotlib sentencepiece
```

Why `--no-deps`? This experimental combination reproduced the classic API CPU tests without pulling unsupported or unnecessary additional builds of JAX/JAXLIB and `opencv-contrib-python`. `pip` warned that `jax`, `jaxlib`, `opencv-contrib-python` and `sounddevice` were missing. **That does not guarantee those packages are optional for every MediaPipe feature.** These tests did not require them.

### 11.5 Expose Ubuntu `cv2` to only this virtualenv

The configuration validated on the main VM was:

```bash
VENV="$HOME/mediapipe_arm64_env"
printf '%s\n' '/usr/lib/python3/dist-packages' \
  > "$VENV/lib/python3.10/site-packages/ubuntu-system-packages.pth"
"$VENV/bin/python" -c 'import cv2; print(cv2.__version__,cv2.__file__)'
```

**Caution:** this `.pth` adds **all** Ubuntu system dist-packages, not only `cv2`, to this virtual environment's module search path. This can expose duplicate packages, cause import collisions and produce Matplotlib's `Axes3D` warning. It was a deliberate temporary engineering compromise; refine it before general release. It does not change system Python, but it does change the virtualenv's import behavior.

### 11.6 Verify native linking

```bash
VENV="$HOME/mediapipe_arm64_env"
SO="$VENV/lib/python3.10/site-packages/mediapipe/python/_framework_bindings.cpython-310-aarch64-linux-gnu.so"
LD_LIBRARY_PATH="$VENV/lib/mediapipe-opencv" ldd "$SO" | grep -E 'opencv|not found'
```

**Observed:** all eight `libopencv_*.so.3.4` resolved to the private virtualenv directory; no `not found` was reported. Library resolution proves only that required shared objects were found; it does not prove every algorithm works.

### 11.7 Run the four CPU inference smoke tests

```bash
VENV="$HOME/mediapipe_arm64_env"
PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python \
"$VENV/run-with-mediapipe-opencv" \
"$VENV/bin/python" - <<'PY'
import mediapipe as mp
import numpy as np
print('MediaPipe:', mp.__version__)
image = np.zeros((480, 640, 3), dtype=np.uint8)
tests = [
    ('Hands', lambda: mp.solutions.hands.Hands(static_image_mode=True)),
    ('Pose', lambda: mp.solutions.pose.Pose(static_image_mode=True)),
    ('Face Mesh', lambda: mp.solutions.face_mesh.FaceMesh(static_image_mode=True)),
    ('Holistic', lambda: mp.solutions.holistic.Holistic(static_image_mode=True)),
]
for name, factory in tests:
    with factory() as model:
        model.process(image)
    print(name, 'OK')
PY
```

**Observed on both BUILDER and the main VM:**

```text
MediaPipe: 0.10.21
Hands OK
Pose OK
Face Mesh OK
Holistic OK
```

The **TensorFlow Lite XNNPACK CPU delegate** initialized. Warnings about `inference_feedback_manager` occurred but did not stop these tests. These tests do **not** measure detection accuracy or performance on camera video.

## 12. Building the original Yahboom MediaPipe ROS 2 package

### 12.1 Locate original code

The source was preserved in:

```text
~/microros_ws/src/microros_v2_mediapipe_pkg/
```

The package imports `mediapipe`, `cv2`, `numpy`, `rclpy`, `cv_bridge`, and ROS message types. The source includes components such as `HandDetector.py`, `PoseDetector.py`, `FaceMesh.py`, `Holistic.py`, `Objectron.py`, `FingerCtrl.py`, and `VirtualPaint.py`.

The workspace also contains MediaPipe-related examples under `common_demo`, and hand/pose detectors in **PTZ** and **non-PTZ** visual-control packages. Their complete functionality is **not** individually validated.

### 12.2 Why `rclpy` must be checked inside the MediaPipe environment

The main system command `ros2` uses `/usr/bin/python3`. The generated `hand_detector_node` entrypoint also had:

```text
#!/usr/bin/python3
```

Consequently, `ros2 run microros_v2_mediapipe_pkg hand_detector_node` would not necessarily use the private MediaPipe virtualenv. Changing the system Python was avoided. Instead, the original Python module's `main()` function was called **explicitly using the virtualenv interpreter**.

### 12.3 Build only the MediaPipe package

```bash
source /opt/ros/humble/setup.bash
cd ~/microros_ws
colcon list --names-only | grep mediapipe
colcon build --packages-select microros_v2_mediapipe_pkg \
  --symlink-install --event-handlers console_direct+
```

**Observed build output:**

```text
Finished <<< microros_v2_mediapipe_pkg [0.53s]
Summary: 1 package finished [0.64s]
```

Then:

```bash
source /opt/ros/humble/setup.bash
source ~/microros_ws/install/setup.bash
ros2 pkg executables microros_v2_mediapipe_pkg
```

**Observed:** **16 registered executables**:

```text
face_detection_node
face_landmarks_node
face_mesh_node
find_hand_node
finger_ctrl_node
finger_trajectory_node
gesture_follow_node
hand_ctrl_node
hand_detector_node
holistic_node
mediapipe_gesture_node
objectron_node
pose_detector_node
pose_follow_node
robot_ctrl_node
virtual_paint_node
```

**Do not confuse registration with validation**: most of these 16 programs have not been run.

### 12.4 Verify combined imports

```bash
source /opt/ros/humble/setup.bash
source ~/microros_ws/install/setup.bash
VENV="$HOME/mediapipe_arm64_env"
PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python \
"$VENV/run-with-mediapipe-opencv" "$VENV/bin/python" -c \
 'import numpy, cv2, rclpy, cv_bridge, mediapipe; print("ROS 2 + MediaPipe: OK")'
```

**Observed:** successful exit code **0**, and `ROS 2 + MediaPipe: OK`.

The **original source modules** `HandDetector`, `PoseDetector`, `FaceMesh`, and `Holistic` also imported successfully from the workspace build tree. This is a module import test, not proof their full runtime nodes work.

### 12.5 Start the original HandDetector safely

The reviewed code initializes MediaPipe Hands, creates a `CvBridge`, and subscribes to `sensor_msgs/msg/Image` on `/camera/image_raw` with **BEST_EFFORT** QoS, depth 1. On image receipt it calls `hands.process`, builds side-by-side input/landmark images, overlays FPS and displays via `cv.imshow()`. This specific node **does not publish motor commands**. It can therefore be used for a non-actuating ROS 2 camera-path demonstration.

**Terminal A (leave running):**

```bash
source /opt/ros/humble/setup.bash
source ~/microros_ws/install/setup.bash
VENV="$HOME/mediapipe_arm64_env"
PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python \
"$VENV/run-with-mediapipe-opencv" \
"$VENV/bin/python" -u -c \
 'from microros_v2_mediapipe_pkg.HandDetector import main; main()'
```

**Observed:**

```text
[hand_detector_node]: HandDetector node started.
[hand_detector_node]: Subscribe image topic: /camera/image_raw
```

Stop the node with `Ctrl+C` in Terminal A when done. Pressing `q` in its OpenCV window invokes the original node's `os._exit(0)` shutdown route.

## 13. End-to-end test: a synthetic ROS 2 camera

### 13.1 First: the topic had no publisher

With HandDetector running:

```bash
source /opt/ros/humble/setup.bash
source ~/microros_ws/install/setup.bash
ros2 topic list -t
ros2 topic info /camera/image_raw --verbose
```

The observed result showed `/camera/image_raw [sensor_msgs/msg/Image]`, **publisher count 0**, **subscription count 1**, subscribed by `hand_detector_node` with `BEST_EFFORT` QoS. That correctly explained why the window did not initially receive frames.

### 13.2 Publish test images without hardware

**Terminal B (while Terminal A remains running):**

```bash
source /opt/ros/humble/setup.bash
source ~/microros_ws/install/setup.bash
VENV="$HOME/mediapipe_arm64_env"
"$VENV/bin/python" -u - <<'PY'
import time
import numpy as np
import rclpy
from rclpy.node import Node
from cv_bridge import CvBridge
from sensor_msgs.msg import Image

rclpy.init()
node = Node('mediapipe_test_camera')
publisher = node.create_publisher(Image, '/camera/image_raw', 10)
bridge = CvBridge()
image = np.zeros((480, 640, 3), dtype=np.uint8)
print('Publishing 20 test images to /camera/image_raw')
try:
    for _ in range(20):
        msg = bridge.cv2_to_imgmsg(image, encoding='bgr8')
        msg.header.stamp = node.get_clock().now().to_msg()
        publisher.publish(msg)
        rclpy.spin_once(node, timeout_sec=0.05)
        time.sleep(0.1)
    print('Publishing completed')
finally:
    node.destroy_node()
    rclpy.shutdown()
PY
```

The test publisher uses the default ROS 2 publisher QoS; the subscriber's `BEST_EFFORT` setting was compatible for this observed exchange.

### 13.3 Observed result

- Terminal B reported **20 images published** and exited normally.
- The separate `hand_detector` OpenCV window opened and rendered a black 2-panel image with a red FPS counter.
- The captured window displayed **`FPS : 3`**.
- There were no visible fatal errors in the screenshot.

**Interpretation:** the original Yahboom node received ROS 2 image messages, converted them with `cv_bridge`, processed them through MediaPipe Hands and displayed the output via OpenCV. A black image contains no hand, so **no real landmark-detection accuracy has been established**. The displayed FPS is **not** a controlled MediaPipe benchmark; it depends on synthetic publication cadence, UI timing and VM scheduling.

This is the **strongest end-to-end test achieved so far** for the migrated AI/ROS environment.

## 14. Complete verification matrix

The distinction between passing a software smoke test and operating a real robot is critical:

| Area | Verification and observed evidence | Status |
| --- | --- | --- |
| Ubuntu ARM64 guest | Running under UTM on Apple M4 | **PASS** |
| ROS 2 Humble install | ROS CLI and Python `rclpy` usable | **PASS** |
| Yahboom workspace source | Source found and enumerated by `colcon` | **PASS** |
| Selected ARM64 ROS packages | Initial workspace subset compiled | **PASS — partial** |
| MediaPipe ROS package build | `1 package finished`, ~0.64 s | **PASS** |
| 16 MediaPipe ROS executables | `ros2 pkg executables` listed them | **PASS — registration only** |
| `rclpy` in MediaPipe virtualenv | `import rclpy` succeeded | **PASS** |
| `cv_bridge` in MediaPipe virtualenv | Import succeeded | **PASS** |
| MediaPipe 0.10.21 | Import and version confirmed | **PASS** |
| OpenCV private runtime | Eight libraries resolved in `ldd` | **PASS** |
| MediaPipe Hands | Blank-image CPU graph processing | **PASS — smoke test** |
| MediaPipe Pose | Blank-image CPU graph processing | **PASS — smoke test** |
| MediaPipe Face Mesh | Blank-image CPU graph processing | **PASS — smoke test** |
| MediaPipe Holistic | Blank-image CPU graph processing | **PASS — smoke test** |
| MediaPipe Objectron | Module import reported on BUILDER | **PASS — import only** |
| Yahboom `HandDetector.py` | Module imported, node initialized | **PASS** |
| Yahboom other AI modules | Pose/FaceMesh/Holistic imported | **PASS — imports only** |
| ROS synthetic camera publisher | Published 20 images | **PASS** |
| ROS camera topic delivery | Subscription confirmed; window responded | **PASS** |
| OpenCV GUI in UTM | `hand_detector` window and FPS rendered | **PASS** |
| Real human hand detection | No real hand image tested yet | **NOT TESTED** |
| Webcam/USB passthrough | No successful stream documented | **NOT TESTED** |
| RobotManager desktop icon | Program launches | **STARTED / UI PASS** |
| JoystickControl icon | Program launches | **STARTED / UI PASS** |
| KeyboardControl icon | Program launches, Keyboard UI visible | **STARTED / UI PASS** |
| Mapping icon | RViz2/mapping UI opens | **STARTED / UI PASS** |
| Navigation icon | RViz2/navigation UI opens | **STARTED / UI PASS** |
| SLAM Toolbox | ROS apt package installed | **PASS — installation only** |
| Nav2 Bringup | ROS apt package installed | **PASS — installation only** |
| micro-ROS Agent | ARM64 workspace compiled | **PASS — build only** |
| Physical ROSmaster connectivity | No robot-end demonstration | **NOT TESTED** |
| Motor/servo actuation | No controlled hardware test | **NOT TESTED** |
| LiDAR mapping | No real sensor map | **NOT TESTED** |
| Autonomous Nav2 goal | No physical run | **NOT TESTED** |
| All original Yahboom demos | Many remain unexecuted | **NOT TESTED** |
| Long-term stability | No stress/soak test | **NOT TESTED** |
| Broad ARM64 platform compatibility | Only this Ubuntu/UTM context verified | **NOT TESTED** |
| Full image security/licensing review | Not performed | **PENDING** |

## 15. Known issues, security, and limitations

### 15.1 System disk is small

The main VM's last observed filesystem was **30 GiB**, **24 GiB used**, with only **5.2 GiB free (82% used)**. Large native compiles, caches, ROS logs, Gazebo assets or machine-learning models can quickly exhaust it. For new image builds, allocate more disk if practical; document partition/LVM expansion correctly before recommending in-place resizing.

### 15.2 Python environment isolation is imperfect

The MediaPipe virtualenv uses a `.pth` file for `/usr/lib/python3/dist-packages`, intentionally exposing Ubuntu's `cv2` and other system modules. This is better than overwriting system Python, but can also create package conflicts. The observed `matplotlib.projections` warning was:

```text
UserWarning: Unable to import Axes3D. This may be due to multiple versions of Matplotlib being installed...
```

It was nonfatal in the tests. **3D Matplotlib functionality is not validated**. ROS `rclpy`, `cv_bridge`, MediaPipe, OpenCV and NumPy imported successfully in the chosen combination.

### 15.3 MediaPipe release is experimental

The wheel has the platform-specific tag `cp310-cp310-linux_aarch64`; it is **not automatically a repaired manylinux wheel**. Its native code uses eight external OpenCV shared libraries. The pure-Python Protobuf compatibility setting is a workaround. GPU acceleration is **not verified**; observed inference used CPU/XNNPACK.

Do not ship this wheel as official, standalone or universally ARM64-compatible. Check dependency licenses and all binary contents before redistribution. Prefer a source-patch/build-guide repository and clearly labeled experimental binary releases until the audit is complete.

### 15.4 ROS and hardware safety

The tested HandDetector only subscribed to images and displayed results. Other original packages include `robot_ctrl_node`, gesture-following and finger-control capabilities. **Do not run unreviewed actuator nodes on powered robot hardware**. For actual robot experiments: use an accessible emergency stop, a safe testing area, conservative motion limits, a secured connection, and supervised testing. Confirm hardware-specific settings before switching `CAR_TYPE`.

### 15.5 VM image privacy and supply chain

Do not upload a raw copy of the present VM without first auditing at least:

- Usernames, passwords, SSH host keys, `~/.ssh`, shell history, credentials and API keys.
- Wi-Fi secrets, connected services, device IDs, network interfaces, cached tokens and browser data.
- Proprietary Yahboom source/assets or binaries and any license limitations on redistribution.
- Third-party apt, pip, Bazel and ROS dependency licenses/notices.
- Huge binary caches, old x86 artifacts, unused build dependencies and personal files.
- Clear checksums, version manifest, and software bill of materials where possible.

The **right to distribute one's own migration guide** is different from the **right to redistribute vendor binaries or a complete original vendor image**.

## 16. Reusing or distributing the VM image

### Suggested distribution model

For a public GitHub project, separate:

```text
rosmaster-ros2-utm-apple-silicon/
├── README.md                    # This guide
├── docs/
│   ├── architecture.md           # UTM VM and ROS architecture
│   ├── migration-log.md          # Exact dated commands and decisions
│   ├── validation.md             # Tests and captured evidence
│   ├── troubleshooting.md
│   ├── security-and-licensing.md
│   └── hardware-testing.md
├── scripts/
│   ├── check-platform.sh         # Proposed, not yet created
│   ├── verify-ros.sh             # Proposed, not yet created
│   ├── install-mediapipe.sh      # Proposed, not yet created
│   └── test-ros-image-path.py    # Proposed, not yet created
├── manifests/
│   └── versions.example.txt      # Proposed, not yet created
├── images/
│   └── README.md                 # Screenshots with permission
├── LICENSE                      # Choose for ORIGINAL documentation/scripts
└── .gitignore
```

**This is a proposed repository structure**, not a claim the files already exist.

Where image distribution rights permit, provide a separately hosted versioned **UTM VM export** with:

- Exact host Mac/UTM version and VM settings.
- Architecture, Ubuntu release, ROS 2 distribution, CPU/RAM/disk allocation.
- Required setup after import and expected first boot.
- SHA-256 hash for the archive.
- Clear statements about whether the image contains Yahboom software/assets.
- Default account policy and instructions to rotate credentials/regenerate SSH keys.
- Test matrix and known limitations.
- Checksums and provenance for experimental MediaPipe binaries.

An alternative with fewer licensing and privacy risks is a **clean-room installation guide plus reproducible setup scripts** that let each user download legitimate upstream/Yahboom dependencies.

### A critical README warning

**Do not claim this is a migrated VMware VMDK that boots natively on Apple Silicon.** This is a newly installed **ARM64 Ubuntu guest with migrated Yahboom source, reconstructed dependencies and selected working applications**.

## 17. Troubleshooting

### `Package 'microros_v2_mediapipe_pkg' not found`

The source can be present while ROS 2 cannot see a built/installed package. Check:

```bash
source /opt/ros/humble/setup.bash
cd ~/microros_ws
colcon list --names-only | grep mediapipe
colcon build --packages-select microros_v2_mediapipe_pkg --symlink-install
source ~/microros_ws/install/setup.bash
ros2 pkg executables microros_v2_mediapipe_pkg
```

This fixed the documented missing-package state: registration was confirmed only **after** selective build and sourcing.

### `import mediapipe` works in venv but ROS `ros2 run` fails

The generated executable used `#!/usr/bin/python3`. **Do not replace `/usr/bin/python3`.** Run the module with the known working virtualenv as shown in §12.5, or develop a dedicated wrapper/launch mechanism.

### `libopencv_*.so.3.4 => not found`

Ensure the private OpenCV runtime installer was run against the correct virtualenv and use the `run-with-mediapipe-opencv` wrapper, which sets `LD_LIBRARY_PATH` only for its child process.

### Protobuf descriptor/import exceptions

Check that the venv uses `protobuf==4.25.8` and start the process with `PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python`. This is a compatibility workaround for old generated `_pb2.py` modules, not a general solution for all dependency stacks.

### Matplotlib `Axes3D` warning

The current venv intentionally exposes system `dist-packages`. Avoid assuming the warning is harmless for 3D visualization code. It did not block the observed MediaPipe/ROS tests.

### Topic exists, but there is no image

```bash
ros2 topic info /camera/image_raw --verbose
```

If **publisher count is 0**, no camera is sending frames. A **subscriber alone creates a visible topic**. Publish a synthetic image as in §13 or connect/configure an appropriate camera source.

### Black `hand_detector` window

A black frame is expected when testing with a black test image. The source image contains no detectable hand. Check publisher counts, terminal output, GUI window and real-camera input separately.

### UTM 9p share missing after reboot

Use `findmnt /mnt/share` to verify mounting; see §7.2. This image required `sudo` for writes to the shared folder, and large commands/copies were problematic. Prefer checksummed transfers or documented scp where appropriate.

### Mapping/Navigation windows open but nothing moves

An RViz2 window does not create live robot data. Verify actual node graph, sensors, transformations (`tf`), odometry, map, localization, navigation lifecycle and motor bridge. **No such end-to-end physical test was demonstrated here**.

## 18. Suggested roadmap

Priorities for making this useful to thousands of Mac users:

1. **Collect an authoritative environment manifest:** UTM version, macOS version, exact Mac chip/ram, VM RAM/vCPU, disk format, graphics settings, networking, installed ROS/apt/pip versions.
2. **Prove portability:** export and re-import into a second clean UTM install or another Apple Silicon Mac (ideally a different M-series generation).
3. **Real-image validation:** feed an actual hand photograph into the ROS image topic; verify landmarks visually and measure model processing latency.
4. **Live camera:** document UTM USB camera passthrough or a network/ROS camera publisher; validate continuous frames.
5. **ROS tests:** exercise PoseDetector, FaceMesh and Holistic as active nodes, and explicitly mark Objectron/gesture/actuation components as pending until tested.
6. **Fix Python packaging:** replace the broad system `.pth` exposure with a narrower, tested bridge strategy; fix old MediaPipe-generated Protobuf files; investigate coherent OpenCV packaging, `auditwheel`, ELF paths and a standards-compliant wheel.
7. **Robot hardware:** connect the actual ROSmaster safely and verify micro-ROS, joystick, keyboard, motor/servo controls, camera, LiDAR, SLAM and Nav2 in an incremental test matrix.
8. **Harden the release:** secret scrub, software provenance, licensing audit, a beginner-friendly installation script, checksums, and automated test scripts.
9. **Record performance data:** CPU use, peak RAM, image processing FPS under a controlled image source, GUI responsiveness and any UTM-specific limitations.
10. **Publish beginner media:** annotated screenshots of UTM creation, GNOME desktop, ROS terminal checks, RViz2 and the `hand_detector` test.

## 19. Current state and conclusion

### What the current Apple Silicon VM *is*

As of **13 October 2026**, this is a **working ARM64 ROS 2 Humble educational development environment** under UTM on an Apple M4 Mac. The original Yahboom development workspace has been restored sufficiently to build and discover selected ROS 2 packages. Five familiar desktop launchers operate at the application/UI level. SLAM Toolbox and Nav2 Bringup are installed. A micro-ROS Agent has been built. MediaPipe 0.10.21, previously an architecture blocker, now imports and runs four CPU inference smoke tests in a private ARM64 virtualenv. Importantly, the **unaltered original HandDetector node** has been launched through that virtualenv, received **synthetic ROS 2 image messages**, and rendered output in an OpenCV window.

### What the current image *is not yet*

It is **not yet a validated turnkey replacement for every feature of the original x86 VMware image**, **not yet a tested real robot-control station**, **not yet validated with a real camera or LiDAR**, **not yet benchmarked**, and **not yet a license-audited VM image ready for redistribution**. MediaPipe's ARM64 wheel is experimental and needs private OpenCV native libraries plus a Protobuf workaround.

## Latest Updates — October 2026

Since the initial Apple Silicon migration, the development environment has gained several important capabilities:

### ESP-IDF 5.1.2 and ESP32-S3 firmware development

Espressif ESP-IDF **v5.1.2** and its native ARM64-hosted Xtensa toolchain have been installed successfully on Ubuntu 22.04.5 running under UTM on an Apple M4 Mac.

The original Yahboom micro-ROS ESP-IDF component was restored and adapted for ARM64 compilation. After resolving Python dependencies, CMake configuration issues, host-versus-target architecture conflicts, and static-library linking errors, **all 65 micro-ROS source packages compiled successfully**.

The `publisher` example produced a valid ESP32-S3 firmware image (`main.bin`, 823,168 bytes). The project was successfully rebuilt incrementally and independently from a clean build directory using the existing micro-ROS libraries.

### Automated micro-ROS build tool

A new utility, **`build-microros-s3.sh`**, simplifies ESP32-S3 firmware development by automatically adjusting the shared micro-ROS toolchain to the selected project, invoking ESP-IDF, and restoring the original configuration afterward.

```bash
bash ~/esp/tools/build-microros-s3.sh ~/esp/tests_arm64/publisher
```

The utility was tested successfully, including verification that the shared toolchain was restored without modification.

Developers can use **Visual Studio Code, VS Code Remote-SSH, or another compatible editor on macOS** to create and edit ESP-IDF projects, while performing the actual ARM64-hosted cross-compilation inside the Ubuntu UTM guest.

### Build reproducibility

Two independent builds of the `publisher` firmware produced identical executable code and data in the four ELF sections examined: `.iram0.text`, `.flash.text`, `.flash.rodata`, and `.dram0.data`.

The final firmware images differed by only **37 bytes**, consistent with build-time metadata, the ELF hash, and the ESP32 image checksum.

### Additional restored resources

The environment also includes restored Yahboom ESP-IDF examples, micro-ROS sample projects, original robot configuration utilities, and recovered AI model resources. ONNX Runtime CPU inference was successfully tested on ARM64 using selected YOLO and tracking models.

### Documentation

The repository now includes dedicated documentation covering the ESP32-S3 build tool, the ARM64 migration challenges, and workflows for creating new projects using macOS and Visual Studio Code.

- [ESP32-S3 micro-ROS build tool](tools/build-microros-s3.sh)
- [Build tool user guide](tools/README.txt)
- [Apple Silicon micro-ROS technical annex](docs/APPLE_SILICON_MICROROS_BUILD_ANNEX.md)

**Validation scope:** Firmware compilation and software-level reproducibility have been demonstrated. Flashing and executing the firmware on physical ESP32-S3 hardware, micro-ROS Agent communication, and complete robot operation remain to be verified.

### Bottom line

**The architecture migration and a meaningful ROS 2–AI end-to-end software demonstration have succeeded.** The most important remaining work is *hardware validation, reproducibility on a fresh Mac/UTM installation, software packaging and responsible redistribution*. For a newcomer who wants to learn ROS 2 and work with Yahboom source on Apple Silicon, the present VM already provides a credible experimental starting point—provided the limitations above are clearly understood.

## 20. Information needed to finalize a public release

Please confirm the following before the document or VM is advertised as a reproducible download:

1. **Mac and UTM:** exact Mac model (M4 variant), RAM, macOS version, UTM version; guest assigned vCPUs/RAM; network mode; display/graphics settings.
2. **VM creation path:** was Ubuntu ARM64 first installed from an official Ubuntu Server ISO and then a GUI added, or was a Desktop ISO used? Which desktop/environment packages were installed?
3. **Image sharing:** will GitHub host *documentation only*, a public VM download, scripts, or all three? Do you have permission to redistribute original Yahboom bundled software and imagery?
4. **Original Yahboom platform:** exact ROSmaster product/version, controller board, camera/PTZ model, LiDAR and motor interfaces, and the official original VMware image version/download source.
5. **ROS/micro-ROS build record:** exact list of the first ARM64 packages, any omitted or modified source files, micro-ROS Agent invocation, and any original launch scripts edited during the migration.
6. **Desktop repair record:** original versus final `.desktop` files and shell scripts for RobotManager/JoystickControl/KeyboardControl/Mapping/Navigation, including any GUI dependencies installed.
7. **MediaPipe reproducibility:** complete Bazel invocation, patches/diffs and relevant build logs from BUILDER so another contributor can compile the identical wheel from source.
8. **Validation artifacts:** permission to publish terminal screenshots and logs, whether to include the screenshot showing the successful `hand_detector` window, and whether any real-camera/hardware tests will follow.
9. **Distribution policy:** preferred repository license for *original material*, maintainer contact, supported UTM/macOS versions and release-update policy.

Missing answers do **not** invalidate the observed success; they distinguish a useful engineering report from a confidently reproducible public release.

## 21. Resources and acknowledgments

- [UTM — macOS virtualization](https://mac.getutm.app/)
- [Ubuntu](https://ubuntu.com/)
- [ROS 2 Humble documentation](https://docs.ros.org/en/humble/)
- [ROS 2 workspace and colcon tutorials](https://docs.ros.org/en/humble/Tutorials/Beginner-Client-Libraries/Colcon-Tutorial.html)
- [micro-ROS](https://micro.ros.org/)
- [Navigation2](https://navigation.ros.org/)
- [SLAM Toolbox](https://github.com/SteveMacenski/slam_toolbox)
- [MediaPipe upstream](https://github.com/google-ai-edge/mediapipe)
- [Experimental MediaPipe 0.10.21 ARM64 release](https://github.com/jcarpio/MediaPipe-0.10.21-Linux-ARM64/releases/tag/v0.10.21-arm64-alpha.1)
- [OpenCV](https://opencv.org/)
- [Bazel](https://bazel.build/)
- [Yahboom](https://www.yahboom.net/)

**Attribution:** Yahboom, ROS, Ubuntu, UTM, MediaPipe, OpenCV, TensorFlow Lite, Bazel and all other third-party projects retain their respective names, copyrights and licenses. This document records an independent interoperability effort. No endorsement is implied.

---

*Document version: initial comprehensive migration report, 2026-10-13. All statements tagged “observed” are grounded in the migration conversations, command outputs, and screenshots available at drafting time; exact unrecorded commands and VM settings must be supplied before declaring the project fully reproducible.*
