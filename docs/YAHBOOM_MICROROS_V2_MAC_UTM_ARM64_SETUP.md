# Yahboom MicroROS V2 on Apple Silicon Mac: UTM/QEMU + Ubuntu 22.04 ARM64 + ROS 2 Humble

> **Community-tested integration guide — October 20, 2026**  
> **Audience:** Yahboom MicroROS V2 owners, macOS/UTM users, ROS 2 developers and maintainers of the Ubuntu ARM64 virtual-machine image.  
> **Suggested repository path:** `docs/YAHBOOM_MICROROS_V2_MAC_UTM_ARM64_SETUP.md`

## Overview

This document adapts Yahboom's [*Configure VM and Connect Robot* guide](https://www.yahboom.net/study/MicroROS-V2/20039) (written around VMware) to **UTM/QEMU on Apple Silicon macOS**. It records an **actual successful test** on a MacBook running Ubuntu 22.04 ARM64, ROS 2 Humble, and the Yahboom MicroROS V2 packages.

**Validated in this setup:**

- UTM/QEMU USB passthrough for the MicroROS V2 controller's Silicon Labs CP2102 USB-to-UART interface.
- Serial permission repair (`dialout`) and successful RobotManager configuration writing.
- UTM `Bridged (Advanced)` networking over the Mac's Wi-Fi interface `en0`.
- A separately compiled **native ARM64 `micro_ros_agent`**, made available alongside Yahboom's workspace.
- Camera operation on the ESP32-Lite's own Wi-Fi access point and then successful camera streaming in the Yahboom ROS 2 test launch after network configuration.
- `/imu`, `/scan`, and `/camera/image_raw` message streams received in ROS 2.
- RViz2 LiDAR visualization after correcting the sensor topic's **QoS reliability mismatch**.

**Important scope limitation:** the successful tests used a partially assembled system: controller board, camera, and LiDAR. Wheel motors, encoders, reliable wheel odometry, SLAM navigation, and autonomous driving were **not** validated. This proves a working development and sensor-communication path on macOS/ARM64; it is not an official Yahboom support statement and not evidence of universal compatibility across every Mac/UTM version.

---

## 1. System architecture

```text
                         Local Wi-Fi LAN (example: NOS-149D)
                                  gateway 192.168.1.1
                                       |
          +----------------------------+----------------------------+
          |                            |                            |
  macOS MacBook                 Ubuntu in UTM/QEMU           Yahboom ESP32 board
  192.168.1.48                  192.168.1.52               DHCP-assigned address
          |                     ROS 2 Humble                        |
          |                     micro_ros_agent <-- UDP 8090 -------+
          |                     Yahboom ROS 2 nodes                 |
          |                            |
          |                       camera driver  <------ ESP32-Lite camera
          |                                             DHCP-assigned address
          +-- USB cable / UTM USB passthrough --> CP2102 controller setup
```

**Example addresses are observations, not fixed defaults.** Read the actual addresses before configuring the robot. In this setup the VM had `192.168.1.52/23`, not a manually assigned `/24`. Keep DHCP unless you have an intentional network plan; optionally create router DHCP reservations for stable endpoint addresses.

The camera has two distinct network use cases:

1. **AP mode:** camera advertises `Yahboom_ESP32_WIFI`; we confirmed a working web preview at `http://192.168.4.1` by pressing **Start Stream**.
2. **STA mode:** camera joins the same reachable LAN as Ubuntu and the robot. Use the actual address assigned by DHCP in RobotManager's `camera_ip`; **do not blindly reuse** `192.168.4.1` or the old example `192.168.12.23`.

All devices do **not** strictly need to be on the same SSID or IPv4 subnet if routing/firewalls are configured correctly. Putting them on the same reachable LAN is the simplest setup. ESP32 radios generally require a 2.4 GHz-compatible network; check the router's SSID/band and client isolation settings.

---

## 2. Prerequisites and safety

**Host:** Apple Silicon MacBook with UTM; an Ubuntu 22.04 ARM64 guest configured as a QEMU VM; access to the Mac's physical USB ports and a data-capable cable.

**Guest:** ROS 2 Humble installed under `/opt/ros/humble`, user `yahboom`, Yahboom packages under `~/microros_ws`, and (for this guide) separate micro-ROS agent tools under `~/uros_ws`.

**Robot:** Yahboom MicroROS V2 controller (CP2102 interface), its correct battery/power system, compatible Wi-Fi, ESP32-Lite camera, LiDAR. Your specific vehicle type may differ.

- Put the robot on a safe stand with the wheels clear of the ground for any later motion testing. Keep power-off/emergency-stop access available.
- Power the controller through the manufacturer's intended supply and switch before USB configuration, as shown in the Yahboom guide. Confirm the board's supply and USB/battery coexistence requirements before connecting both; **do not** improvise back-feeding or wiring.
- Never commit Wi-Fi passwords, API keys, Dify tokens, or credentials into the repository, screenshots, or the distributed VM image. Change any credentials that were exposed.
- Avoid running multiple conflicting launches or micro-ROS agents on UDP 8090 simultaneously.

---

## 3. UTM VM configuration on macOS

### 3.1 Confirm QEMU and choose bridged networking

1. Shut down Ubuntu cleanly.
2. Open **UTM → select the VM → Edit → Network**.
3. Select **Network Mode: `Bridged (Advanced)`**.
4. Set **Bridged Interface: `Wi-Fi (en0)`** (or the actual physical Mac interface carrying the local network).
5. Leave **Emulated Network Card: `virtio-net-pci`**. Keep the existing virtual MAC address unless there is a reason to change it.
6. Save and start Ubuntu.

Network bridging over Wi-Fi depends on UTM/QEMU, macOS, network interface, and router behavior; do not assume it works on every host. In our setup it did work. **Shared/NAT networking** previously gave the VM `192.168.64.7`; that private VM address was not automatically reachable from the robot's independent Wi-Fi connection. Bridged mode resolved that issue.

In Ubuntu:

```bash
hostname -I
ip -4 addr show enp0s1
ip route
```

In the successful test:

```text
Mac Wi-Fi:           192.168.1.48
Ubuntu VM:           192.168.1.52/23
Default gateway:     192.168.1.1
```

The other addresses such as `172.17.0.1`, `172.18.0.1`, and `172.19.0.1` were Docker networks, **not** the ESP32 agent's target address.

From a **macOS terminal** (prompt similar to `user@MacBook ~ %`, *not* `yahboom@vm:~$`):

```bash
ipconfig getifaddr en0
ping -c 4 192.168.1.52   # replace with the guest's actual IP
```

The Mac successfully reached the VM with **0% packet loss**, around **0.7 ms** average round-trip time. Pinging the VM's own address **from within Ubuntu** is only a loopback-to-self diagnostic and does not test the bridge from macOS.

If the guest loses connectivity, revert to UTM's previous Shared networking mode and diagnose bridging rather than assigning random static IPs. Test Mac-to-guest reachability first, then robot-to-agent communication.

### 3.2 Pass a USB device from macOS to Ubuntu

Yahboom's VMware documentation shows a VMware USB-connect popup. **UTM is different**: a popup might not appear automatically and the device may need explicit selection in **UTM → USB Devices** or a UTM confirmation dialog. The USB device belongs to either the host or the guest at a time; reassign if macOS or UTM reconnects it.

For the controller:

1. Power on the Yahboom controller using the intended supply and switch.
2. Connect its **USB-C data cable** to the MacBook.
3. From UTM's VM USB device menu, select the connected **CP2102 USB to UART Bridge Controller**. Confirm the prompt if shown.
4. In Ubuntu:

```bash
lsusb
ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
sudo dmesg | tail -30
```

**Observed successful USB controller:**

```text
ID 10c4:ea60 Silicon Labs CP210x UART Bridge
/dev/ttyUSB0
cp210x converter now attached to ttyUSB0
```

If needed, diagnose device detection from **macOS** without relying on `lsusb` (which is usually not installed on macOS):

```bash
system_profiler SPUSBHostDataType
ls -l /dev/cu.*
```

In our case `system_profiler SPUSBDataType` returned no useful data, while `SPUSBHostDataType` showed the Silicon Labs CP2102. Lack of a macOS `/dev/cu.usbserial*` was not a blocker because the device was passed to Linux. USB discovery in macOS does not itself guarantee that UTM has assigned the device to Ubuntu.

### 3.3 Fix `/dev/ttyUSB0` permissions

Observed RobotManager error:

```text
[Errno 13] Permission denied: '/dev/ttyUSB0'
```

The device had permissions `crw-rw---- root dialout`. The logged-in user initially lacked group `dialout`.

```bash
sudo usermod -aG dialout yahboom
```

**Log out of the entire Ubuntu graphical session and log back in.** Running `newgrp dialout` updates only the shell (and child processes), not an already running desktop app. Reattach the USB device through UTM if necessary.

Verify:

```bash
id
ls -l /dev/ttyUSB0
```

Optional non-transmitting open test:

```bash
python3 - <<'PY'
import os
try:
    fd = os.open('/dev/ttyUSB0', os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    print('OK: serial port accessible')
    os.close(fd)
except OSError as e:
    print('ERROR:', e)
PY
```

This test returned `OK`. Do **not** use `chmod 666` or run RobotManager as root as a permanent workaround.

RobotManager also reported that `/dev/microros_board` did not exist and then attempted `/dev/ttyUSB0`; the missing alias was not necessary to solve the actual permission issue.

---

## 4. Configure controller with Yahboom RobotManager

Open the **RobotManager** desktop application inside Ubuntu, with the CP2102 passed through from UTM.

### 4.1 Read and save board settings

1. Choose **Control Board / Board Config**.
2. Select or confirm `/dev/ttyUSB0`.
3. Click **Read Board** first to recover current settings.
4. Record existing PID, odometry, steering/servo calibration and other device parameters before changing anything.
5. Change only the necessary connection parameters:

| Parameter | Meaning | Working-network example |
|---|---|---|
| `wifi_ssid` | Wi-Fi network **the controller joins** in station mode | `NOS-149D` |
| `wifi_passwd` | Wi-Fi password (do not publish it) | `<YOUR_WIFI_PASSWORD>` |
| `agent_ip_addr` | **Ubuntu VM IP** running the micro-ROS Agent | `192.168.1.52` |
| Agent transport port | Must agree with the actual launch configuration | UDP `8090` observed |

A factory SSID like `wifi` in the `wifi_ssid` field should **not** be assumed to be a Wi-Fi network created by the robot. These settings normally describe the Wi-Fi network the ESP32 tries to join.

Click **Apply Config**, then **Verify**. The session logs reported successful configuration writing and a save to `robot_info.json`; where available, also read back and check the actual stored values. Avoid `Reset Defaults` during initial integration.

### 4.2 Controller OLED fields

Use the button next to the controller OLED to cycle through information:

- `self`: the controller ESP32's own Wi-Fi address.
- `agent`: the Ubuntu guest IP configured in `agent_ip_addr`.
- `camera`: the camera's network address, where supported/known.

The `self` address should be reachable from the VM on your network. The `agent` address should match the VM (not the Mac host, unless you explicitly run the agent on macOS instead).

### 4.3 RobotManager Host Settings

Set the actual hardware variant in `CAR_TYPE`:

| Value | Yahboom description |
|---|---|
| `ptz` | Camera with pan/tilt servo |
| `no_ptz` | Fixed camera, no pan/tilt servo |
| `basic_car` | No camera or servo |

Our inspected Host Settings showed `CAR_TYPE=ptz`, `ROS_DOMAIN_ID=40`, and an **old** `camera_ip=192.168.12.23`. Set `CAR_TYPE` to match the **physical assembly**, not solely the image defaults. In **Vision config**, replace any obsolete camera address with its current reachable station-mode IP and click **Save Config**.

`Vision_API_KEY`, `Vision_BASE_URL`, `Vision_MODEL`, `DIFY_API_KEY` and `DIFY_BASE_URL` are higher-level AI integration settings. They are **not required** for basic USB/controller/IMU/LiDAR/camera connectivity. Never publish the secret key values.

---

## 5. Bring up and test the ESP32-Lite camera

The camera we tested identified itself in its web interface as a **GC2145** sensor. Its USB interface was **not** a standard USB Video Class webcam in our tests. A USB port can provide power/configuration/serial without exposing a Linux `/dev/video0` capture device.

### 5.1 Standalone test in AP mode (confirmed working)

1. Power on the camera.
2. On the MacBook, join Wi-Fi SSID **`Yahboom_ESP32_WIFI`**.
3. Open **`http://192.168.4.1`** in a browser.
4. Click **Start Stream**. Live video was successfully observed.
5. The web interface also offered **Get Still**; test image capture if needed.

This is an excellent independent hardware diagnostic: it confirms the web server, Wi-Fi AP, image sensor and stream *without* relying on ROS 2 or the Mac VM.

### 5.2 Connect camera to the same reachable LAN as ROS 2

For integrated operation, configure the camera as a Wi-Fi **station (STA)** on your chosen 2.4 GHz-compatible local network, using its supported manufacturer workflow (camera Wi-Fi settings or RobotManager auto-configuration as applicable). Obtain its actual DHCP address from the camera, router, or controller OLED. AP mode may still exist simultaneously on firmware supporting AP+STA; do not assume it is disabled.

**Do not choose an arbitrary static IP such as `192.168.1.54` without checking DHCP conflicts.** That number is only an illustration. Likewise, the AP address `192.168.4.1` is not automatically reachable from the bridged Ubuntu VM while the Mac is on another Wi-Fi network.

On Ubuntu:

```bash
ping -c 4 <CAMERA_LAN_IP>
curl -I --max-time 5 http://<CAMERA_LAN_IP>/
```

A lack of ICMP replies or an unexpected HTTP `HEAD` result does not, on its own, prove the camera is defective. Use a browser at `http://<CAMERA_LAN_IP>` for the web page and **Start Stream**, then update RobotManager's `camera_ip` to that verified address. The original robot driver tried TCP port `81` on the configured camera IP; an old address caused a timeout.

### 5.3 USB CH341 diagnostic (not the video feed)

When the camera-related USB-serial device was passed through to Ubuntu, we saw:

```text
ID 1a86:7522 QinHeng Electronics USB Serial
ch341-uart converter now attached to ttyUSB0
```

On a subsequent reconnection, however, kernel logs showed:

```text
can't set config #1, error -71
```

This is a USB protocol/configuration error (`EPROTO`) and may reflect transient cable, power, USB passthrough or timing behavior. The video was later confirmed through Wi-Fi; therefore **do not require this CH341 USB device for normal video streaming**, and do not interpret an absent `/dev/video*` as a defective IP camera. Do not overwrite the camera firmware to solve a network-only problem.

Relevant references: [Yahboom ESP32-Lite documentation](https://www.yahboom.net/study/ESP32-Lite/13680) and [Yahboom robot camera course](https://www.yahboom.net/study/MicroROS-V2/20039).

---

## 6. Install/build the missing micro-ROS Agent for Ubuntu ARM64

Our imported image included Yahboom ROS 2 packages but initially **did not have the `micro_ros_agent` package in the sourced ROS environment**. The first connectivity test failed with:

```text
package 'micro_ros_agent' not found
```

APT also returned:

```text
N: Unable to locate package ros-humble-micro-ros-agent
```

This means that package was not located **in the configured repositories on this VM**; it does not prove the package is unavailable everywhere or incompatible with ARM64.

We built the agent separately to avoid disturbing the Yahboom workspace. Official source: [micro-ROS/micro_ros_setup](https://github.com/micro-ROS/micro_ros_setup), branch `humble`.

### 6.1 Required build tooling

The actual VM already contained the necessary ROS build tools and many dependencies. For a clean install, check/install as needed:

```bash
sudo apt update
sudo apt install -y git python3-colcon-common-extensions python3-rosdep \
  build-essential cmake
```

Do not run `sudo rosdep init` if rosdep is already initialized.

### 6.2 Create or reuse `~/uros_ws`

```bash
source /opt/ros/humble/setup.bash
mkdir -p ~/uros_ws/src
cd ~/uros_ws

# Clone ONLY if this directory does not already contain the repository.
if [ ! -d src/micro_ros_setup/.git ]; then
  git clone -b humble https://github.com/micro-ROS/micro_ros_setup.git src/micro_ros_setup
fi

git -C src/micro_ros_setup branch --show-current   # expected: humble
rosdep update
rosdep install --from-paths src --ignore-src -y --rosdistro humble
colcon build --symlink-install
source ~/uros_ws/install/local_setup.bash
```

The clone in our VM was **already present**, on `humble`; trying to clone on top of it gave `destination path ... already exists`. This is harmless: do not delete a working checkout merely because that message appears.

### 6.3 Generate and build the agent

```bash
cd ~/uros_ws
source /opt/ros/humble/setup.bash
source ~/uros_ws/install/local_setup.bash
ros2 run micro_ros_setup create_agent_ws.sh
ros2 run micro_ros_setup build_agent.sh
source ~/uros_ws/install/local_setup.bash
```

The observed output included:

```text
Cloning into 'xrceagent'...
HEAD is now at 57d0862 Release v2.4.2
Finished <<< micro_ros_agent [19.0s]
Summary: 3 packages finished [21.5s]
  1 package had stderr output: micro_ros_agent
```

A developer-oriented **TinyXML2 CMake warning** was printed but did not prevent the successful build. Fix actual build failures based on their logs rather than treating this warning as fatal.

Check installation:

```bash
source /opt/ros/humble/setup.bash
source ~/uros_ws/install/local_setup.bash
ros2 pkg prefix micro_ros_agent
ros2 pkg executables micro_ros_agent
```

Observed installed prefix:

```text
/home/yahboom/uros_ws/install/micro_ros_agent
```

The essential *newly built ROS package* was `micro_ros_agent`; `micro_ros_setup` and dependent packages/tools were used to create and build it. We did **not** establish an exhaustive historical `apt install` list for the custom image, so this guide does not claim any other APT packages were installed during the successful sensor troubleshooting. `mesa-utils` was later suggested for graphics diagnosis (`glxinfo`), not as a mandatory LiDAR driver dependency.

---

## 7. Source ROS environments and launch Yahboom

Yahboom packages existed under `~/microros_ws`, but a fresh shell initially searched only `/opt/ros/humble`, causing:

```text
package 'microros_v2_bringup' not found
```

**Source both workspaces** (and set the domain consistently in every terminal):

```bash
source /opt/ros/humble/setup.bash
source ~/uros_ws/install/local_setup.bash
source ~/microros_ws/install/local_setup.bash
export ROS_DOMAIN_ID=40

ros2 pkg prefix micro_ros_agent
ros2 pkg prefix microros_v2_bringup
```

The observed Yahboom packages included:

```text
microros_v2_bringup
microros_v2_interface_pkg
microros_v2_kcf_follow_pkg
microros_v2_mediapipe_pkg
microros_v2_no_ptz_visual_control_pkg
microros_v2_ptz_visual_control_pkg
```

### 7.1 Connection test

With the controller, LiDAR and camera powered, and RobotManager configured:

```bash
ros2 launch microros_v2_bringup test_connect.launch.py
```

**Leave this terminal running.** The successful launch started the agent listening on **UDP port 8090**, and the related camera/base/state/test nodes. The exact launch graph and port should be verified from the installed Yahboom launch file for other image versions.

If it exits, `/rosout` and `/parameter_events` may be the only topics visible. Launch the robot and perform ROS topic queries from **a second terminal** with the same environment and `ROS_DOMAIN_ID`.

### 7.2 Inspect topics and data rates

```bash
ros2 topic list -t
ros2 topic hz /imu               # Ctrl+C after several seconds
ros2 topic hz /scan              # Ctrl+C
ros2 topic hz /camera/image_raw  # Ctrl+C
```

**Measured on the working Apple Silicon/UTM setup:**

| ROS topic | Type | Measured rate | Notes |
|---|---|---:|---|
| `/imu` | `sensor_msgs/msg/Imu` | ~27.4 Hz | Real messages received |
| `/scan` | `sensor_msgs/msg/LaserScan` | ~19.5 Hz | Real distance samples received |
| `/camera/image_raw` | `sensor_msgs/msg/Image` | ~5.4 fps | Real images received over Wi-Fi |

Additional observed topics included `/battery`, `/beep`, `/camera/camera_info`, `/cmd_ptz_angle`, `/cmd_vel`, `/diagnostics`, `/joint_states`, `/odom`, `/odom_raw`, `/ptz_angle`, `/ptz_status`, `/robot_description`, `/set_pose`, `/tf`, and `/tf_static`. **Topic presence is not equivalent to sensor/motor functionality**: validate messages and physical behavior separately.

A startup warning `topic ... does not appear to be published yet` can occur before the first sensor messages. If sustained, diagnose networking, launch health, ROS domain and QoS.

### 7.3 Camera verification via ROS

```bash
ros2 topic hz /camera/image_raw
ros2 run rqt_image_view rqt_image_view
```

If `rqt_image_view` is not installed, check its availability or install a distro-compatible version. Select `/camera/image_raw` from the GUI and verify real image frames.

---

## 8. LiDAR verification and RViz2 troubleshooting

### 8.1 Confirm measurement geometry

```bash
ros2 topic echo /scan --once --field header
ros2 topic echo /scan --once --field range_min
ros2 topic echo /scan --once --field range_max
ros2 topic echo /scan --once --field angle_min
ros2 topic echo /scan --once --field angle_max
ros2 topic echo /scan --once --field angle_increment
ros2 topic echo /scan --once --field ranges
```

**Measured results:**

| Field | Value |
|---|---|
| `header.frame_id` | `laser_frame` |
| `range_min` | ~0.12 m |
| `range_max` | 8.0 m |
| `angle_min` | ~-3.141593 rad |
| `angle_max` | ~3.135310 rad |
| `angle_increment` | ~0.009425 rad (~0.54°) |
| Scan frequency | ~19.5 Hz |

The scan spans almost a full rotation with roughly 667–668 angular increments/samples depending on endpoint convention. We observed many physically plausible ranges (around 0.3 m through 4.8 m), plus occasional `0.0` values; zero is below the advertised `range_min` and should not be treated as a valid obstacle range.

### 8.2 RViz2 first configuration

Open in a second ROS-configured terminal:

```bash
rviz2
```

Set:

- **Global Options → Fixed Frame:** `laser_frame` (confirmed actual scan frame; avoid `map` until the SLAM TF exists).
- **Add → By topic → `/scan` → LaserScan**.
- **LaserScan → Style:** `Points`; **Size (Pixels):** about `8` for troubleshooting.
- **LaserScan → Alpha:** `1`; **Decay Time:** `1` for trailing points, or `0` for the latest scan.
- Choose **TopDownOrtho** and use zoom as needed.

**Critical proven fix: set `LaserScan → Topic → Reliability Policy` to `Best Effort`.**

We spent time investigating zoom, TF and software OpenGL because RViz showed `Status: OK` but no points. The definitive diagnosis was:

```bash
ros2 topic info /scan --verbose
```

```text
Publisher: micro_ros_task_node  Reliability: BEST_EFFORT
Subscriber: topic_test_node    Reliability: BEST_EFFORT
Subscriber: rviz               Reliability: RELIABLE   <-- incompatible
```

A **RELIABLE** subscriber cannot match a publisher that offers only **BEST_EFFORT**. After changing RViz2's subscription reliability to `Best Effort`, the points immediately became visible. The RViz panel then reported hundreds of received messages and thousands of rendered points.

**Save the fixed RViz configuration:**

```text
File → Save Config As
/home/yahboom/microros_ws/rviz_lidar_yahboom.rviz
```

Reload next time:

```bash
rviz2 -d ~/microros_ws/rviz_lidar_yahboom.rviz
```

### 8.3 OpenGL in the Apple Silicon VM

We ran `glxinfo -B` and found:

```text
OpenGL vendor: Mesa
OpenGL renderer: llvmpipe (LLVM 15.0.7, 128 bits)
OpenGL version: 4.5
```

This VM used CPU-based OpenGL rendering rather than a hardware-accelerated GPU path. It may affect RViz2 performance, **but it was not the cause of the missing scan points**. RViz rendered Axes normally; the actual cause was QoS.

If `glxinfo` is missing, `mesa-utils` may be installed for diagnostics:

```bash
sudo apt install mesa-utils
glxinfo -B
```

Do not force OpenGL versions or alter UTM graphics settings to solve a QoS mismatch.

---

## 9. Partial-assembly limitations: odometry and mapping

At the time of the tests, the robot had the controller board, camera and LiDAR connected, but its wheel motors and encoders were not fully assembled/validated. `/odom` published a near-zero pose, but its covariance contained enormous values (e.g. approximately `1.6e26` for X and `2.6e27` for Y). This is **not proof of usable localization**. Investigate EKF input, odometry source and calibration before navigation.

`/joint_states` contained `cam1` and `cam2` (camera joints, approximately 0° and -45°); this **did not verify wheel encoder publication**.

Yahboom's Mapping demos normally assume motion and appropriate odometry/TF. With the controller/LiDAR held stationary or moved manually without trustworthy odometry, a SLAM map may look unstable, reset, or appear to disappear. First distinguish the **live scan** visualization from the accumulated **occupancy map**, inspect `/map`, `/tf` and `/odom`, and avoid claiming robust mapping performance from the partial assembly.

**Avoid sending motion commands (`/cmd_vel`) until motors, wheel encoders and emergency-stop behavior are confirmed**, with the wheels off the ground for initial tests.

---

## 10. Quick troubleshooting matrix

| Symptom | Likely explanation | Verified/safer action |
|---|---|---|
| `system_profiler SPUSBDataType` empty | macOS report category not useful | Use `system_profiler SPUSBHostDataType` |
| macOS sees CP2102 but Ubuntu does not | USB not assigned to VM | Use UTM USB Devices and confirm passthrough |
| `/dev/ttyUSB0` permission denied | User not in `dialout` (or GUI session stale) | `usermod -aG dialout`, **log out and back in** |
| `src/micro_ros_setup already exists` | Source already checked out | Inspect `git status`, do not reclone/delete |
| `microros_v2_bringup not found` | Yahboom ROS workspace not sourced | Source `~/microros_ws/install/local_setup.bash` |
| `micro_ros_agent not found` | Agent missing from sourced environment | Build via `micro_ros_setup`, source `~/uros_ws/install/local_setup.bash` |
| Agent listening, no ESP32 data | Wi-Fi/subnet/agent address/UDP problem | Check OLED `self`/`agent`, DHCP, bridged network, UDP port |
| Camera timeout to `192.168.12.23:81` | Stale camera IP or wrong network | Verify live camera IP and update Host Settings |
| Camera USB shows CH341, no `/dev/video0` | Camera's USB is serial, not UVC video | Use camera Wi-Fi stream |
| `ch341 ... error -71` | USB protocol/connection failure | Reconnect cleanly, change cable/port, check UTM passthrough |
| `/scan` 19.5 Hz but RViz blank | Subscriber QoS mismatch | Set RViz LaserScan reliability **Best Effort** |
| RViz Fixed Frame `map` error | No `map` transform yet | Set Fixed Frame to actual `laser_frame` for first tests |
| Only `/rosout`, `/parameter_events` | Robot launch stopped or mismatched ROS domain | Keep launch alive, match `ROS_DOMAIN_ID=40` in each shell |
| Mapping appears then disappears | TF/odometry/SLAM configuration or rendering | Compare `/scan`, `/map`, `/odom`, and `/tf`; finish wheel setup |

---

## 11. Reproducible daily start-up checklist

1. Power on controller, camera and LiDAR using the proper manufacturer supplies.
2. Connect Mac to the correct local Wi-Fi; ensure UTM's bridge is mapped to the appropriate interface.
3. Start the Ubuntu 22.04 ARM64 QEMU VM.
4. Check `hostname -I` and verify the agent address still matches RobotManager's setting.
5. In **Terminal A**:

```bash
source /opt/ros/humble/setup.bash
source ~/uros_ws/install/local_setup.bash
source ~/microros_ws/install/local_setup.bash
export ROS_DOMAIN_ID=40
ros2 launch microros_v2_bringup test_connect.launch.py
```

6. In **Terminal B**:

```bash
source /opt/ros/humble/setup.bash
source ~/uros_ws/install/local_setup.bash
source ~/microros_ws/install/local_setup.bash
export ROS_DOMAIN_ID=40
ros2 topic list -t
ros2 topic hz /imu
# stop the previous diagnostic using Ctrl+C, then:
ros2 topic hz /scan
# Ctrl+C, then:
ros2 topic hz /camera/image_raw
```

7. Optionally run RViz2 with your **saved Best Effort LaserScan configuration**.
8. Stop diagnostics with `Ctrl+C` when finished; do not leave conflicting duplicate launch instances running.

### Optional shell setup

A convenience script avoids shell mismatches without automatically modifying `.bashrc`:

```bash
cat > ~/robot_ros_env.sh <<'EOF_ENV'
#!/usr/bin/env bash
source /opt/ros/humble/setup.bash
source "$HOME/uros_ws/install/local_setup.bash"
source "$HOME/microros_ws/install/local_setup.bash"
export ROS_DOMAIN_ID=40
EOF_ENV
```

In each new terminal run `source ~/robot_ros_env.sh` (not `./robot_ros_env.sh`, since the environment must be applied to the current shell).

---

## 12. Validation summary and future work

**Successfully demonstrated on the Mac/UTM ARM64 system:**

- macOS USB discovery → UTM/QEMU USB passthrough → Ubuntu CP2102 serial access.
- RobotManager connection and configuration-writing path after fixing Linux user groups.
- Mac-to-Ubuntu reachability over bridged Wi-Fi.
- ARM64 micro-ROS Agent build and recognition by ROS 2.
- Working ROS topics for IMU, LiDAR and camera.
- Real LiDAR 360° scan ranges and successful RViz visualization with matching QoS.

**Not yet validated:** full motor driving, encoder feedback, wheel-based odometry, stable SLAM maps, navigation, RTK/Pixhawk integration, and camera performance beyond the tested resolution/network.

This is a community-derived **working alternative to the VMware-centric Yahboom instructions** for one verified Apple Silicon Mac + UTM/QEMU + Ubuntu ARM64 configuration. Maintainers and users should retest against their versions before treating the workflow as universally supported.

## References

1. Yahboom — [MicroROS V2: Configure VM and Connect Robot](https://www.yahboom.net/study/MicroROS-V2/20039).
2. Yahboom — [MicroROS V2 learning/documentation index](https://www.yahboom.net/study/MicroROS-V2/20039).
3. Yahboom — [ESP32 WiFi Camera Lite documentation](https://www.yahboom.net/study/ESP32-Lite/13680).
4. micro-ROS — [`micro_ros_setup` (Humble branch)](https://github.com/micro-ROS/micro_ros_setup/tree/humble).
5. ROS 2 — [Quality of Service compatibility](https://docs.ros.org/en/humble/Concepts/Intermediate/About-Quality-of-Service-Settings.html).
6. UTM — [Official project documentation](https://docs.getutm.app/).

---

**Document provenance:** compiled from the user's observed terminals, RobotManager screens, live camera tests and RViz2 debugging session on October 20, 2026, supplemented by the linked manufacturer and upstream documentation. Example device IPs are local test values, not guaranteed defaults. No secrets are included.
