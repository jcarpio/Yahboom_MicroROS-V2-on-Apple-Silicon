# Yahboom MicroROS V2 — ROS 2, ArduPilot and Gazebo Integration

**Engineering log and next-step plan**  
**Updated:** 16 October 2026  
**Status:** Development environment validated; physical Yahboom rover not yet received

> **Configuration freeze:** Do not edit, overwrite, rebuild or reflash Yahboom's original robot configuration, firmware, URDF/Xacro, launch files or ROS 2 packages before the physical robot arrives and its stock behavior is documented. All experimental simulation or integration work should be isolated in a separate workspace or package, with a VM snapshot/backups first. The physical Cube Black remains disarmed for bench diagnostics.

## 1. Project objective

Build a small autonomous differential-drive rover, initially based on the Yahboom MicroROS V2, for mapping, obstacle avoidance and agricultural area coverage. The intended prototype should eventually drive parallel coverage passes spaced about **0.50 m** apart, avoid trees and other obstacles, and record completed/uncompleted coverage. The exact coverage spacing must eventually be checked against actual tool width, localization accuracy and safety margins.

The planned technology stack includes:

- **ROS 2 Humble** for robot middleware and integration.
- **Nav2** for route planning, obstacle-aware navigation and motion control.
- **SLAM Toolbox** for mapping/localization using the 2D LiDAR.
- **robot_localization** for appropriate sensor fusion.
- **micro-ROS / ESP32-S3** for onboard interfaces to motors and sensors.
- **ArduPilot Rover / Cube Black** for GNSS-based navigation, monitoring and potential future supervisory autonomy.
- **Gazebo Fortress** for experiments that do not require moving the real robot.

A fundamental integration rule is **one motion-command authority at a time**. The ESP32 motor controller and ArduPilot must never both issue competing commands to the same motors. Any transition to a different control architecture must be deliberate, bench-tested and equipped with an independent emergency stop.

## 2. Physical system and availability

### Yahboom rover — pending delivery

Expected hardware based on the selected Yahboom MicroROS V2 differential-drive configuration:

- Two 12 V geared drive motors with Hall encoders.
- ESP32-S3-based control board supporting micro-ROS.
- IMU.
- T-Mini Plus 360-degree 2D LiDAR (reported specifications: roughly 0.05–12 m and 6–12 Hz; verify once received).
- ESP32-S3 Wi-Fi/PTZ camera.
- Rear support wheel/caster and compact mobile chassis.

These details are planning assumptions until verified against the delivered robot and the manufacturer's documentation.

### Flight controller — already available

- **Cube Black** with **ArduRover 4.7.2**, communicating over an **RFD telemetry radio**.
- Another Cube Orange has shown overheating/burnt-smell symptoms and must not be used or powered for testing without competent hardware inspection.
- Cube Black has reported pre-arm conditions including accelerometer and compass calibration requests, hardware safety switch and radio failsafe. **Do not bypass safety checks or arm for vehicle motion before proper diagnostics and physical safety controls.**

## 3. Development workstation

- **Host:** MacBook Pro, macOS, running UTM.
- **Guest VM:** Ubuntu **22.04.5 LTS, ARM64**, 4 virtual CPUs.
- Initially measured VM RAM: approximately **3.8 GiB total**, **1.5 GiB available**, with swap in use. Increasing to approximately **8 GiB** was recommended if the Mac has enough physical RAM; no confirmation yet that this was done.
- **ROS distribution:** ROS 2 Humble.
- Yahboom source workspace: `~/microros_ws`.
- UTM guest was observed at `192.168.64.7`; the host/gateway at `192.168.64.1` during testing. These addresses may change.

Some existing services or tooling in the prepared Ubuntu image include custom Yahboom ROS packages and a Docker installation. Preserve the working environment rather than upgrading it indiscriminately.

## 4. ArduPilot telemetry successfully connected to ROS 2

### 4.1 Mac-side radio link and forwarding

The RFD serial device was identified as:

```text
/dev/cu.usbserial-AL037S52
```

MAVProxy was run from the macOS Python virtual environment with a **57,600 baud** serial link and forwarded MAVLink packets to the Ubuntu guest:

```bash
source ~/mavproxy-env/bin/activate
mavproxy.py \
  --master=/dev/cu.usbserial-AL037S52 \
  --baudrate=57600 \
  --out=udp:192.168.64.7:14550
```

ArduDeck or other software must release the serial device before MAVProxy opens it. MAVProxy detected an ArduRover 4.7.2 Cube Black, system ID 1, initially in `HOLD` mode.

### 4.2 Ubuntu-side MAVROS connection

On the Ubuntu guest:

```bash
source /opt/ros/humble/setup.bash
source ~/microros_ws/install/setup.bash
ros2 launch mavros apm.launch fcu_url:=udp://0.0.0.0:14550@
```

Observed `/mavros/state`:

```yaml
connected: true
armed: false
guided: false
mode: HOLD
system_status: 5
```

MAVROS successfully received GNSS, IMU and estimated-position topics. `system_status: 5` should not be treated as a ready-to-drive state; pre-arm issues remain to be investigated.

### 4.3 Measured ROS topic frequencies

Measured in this setup over RFD → MAVProxy → UDP → MAVROS:

| ROS 2 topic | Observed rate | Notes |
|---|---:|---|
| `/mavros/global_position/global` | ~3 Hz | Global position estimate |
| `/mavros/imu/data` | ~1 Hz | Processed IMU/orientation stream |
| `/mavros/imu/data_raw` | ~3.05–3.08 Hz | Raw IMU stream |
| `/mavros/local_position/pose` | ~3.0–3.1 Hz | Local pose estimate |

MAVROS also published `/mavros/global_position/local`, while a test of `/mavros/local_position/odom` did not establish usable output. The local/global position covariance seen in earlier tests was not sufficiently precise to presume centimeter-level navigation. One GNSS observation indicated 12 satellites; **RTK FIX was not confirmed**.

The MAVROS console showed repeated timesync warnings (`TM: RTT too high for timesync`) and parameter-request timeouts. These require diagnosis; ROS message rate by itself does not prove acceptable motion-control latency. Avoid blindly increasing telemetry stream parameters over the radio.

**Design consequence:** put fast feedback and obstacle safety on the robot/local network; use RFD telemetry primarily for supervision and appropriate higher-level information.

## 5. micro-ROS agent preparation

A pre-existing launch script referenced an agent listening for UDP on port `8090`:

```bash
ros2 run micro_ros_agent micro_ros_agent udp4 --port 8090 -v4
```

However, the `micro_ros_agent` ROS executable was not installed in the VM at the time of inspection. A Docker image was successfully pulled, and a containerized agent started:

```bash
sudo docker run --rm -it --network host \
  microros/micro-ros-agent:humble \
  udp4 --port 8090 -v4
```

The UDP agent reported that it was listening. **No ESP32 client connection has been demonstrated**, because the Yahboom robot had not yet arrived. UTM NAT and inbound UDP reachability from the eventual robot Wi-Fi network remain open verification tasks.

## 6. ROS 2 navigation software already installed

Package discovery confirmed the presence of:

- Nav2 packages, including `nav2_bringup`, `nav2_controller`, `nav2_planner`, `nav2_costmap_2d`, `nav2_collision_monitor`, `nav2_waypoint_follower`, `nav2_smac_planner`, etc.
- `navigation2`.
- `slam_toolbox`.
- `robot_localization`.

The Yahboom workspace also contains existing launch and configuration files, including:

```text
~/microros_ws/src/microros_v2_bringup/launch/nav2.launch.py
~/microros_ws/src/microros_v2_bringup/launch/slam_toolbox.launch.py
~/microros_ws/src/microros_v2_bringup/launch/state_estimation.launch.py
~/microros_ws/src/microros_v2_bringup/config/nav2_params.yaml
~/microros_ws/src/microros_v2_bringup/config/ekf.yaml
~/microros_ws/src/robot_description/launch/gazebo.launch.py
```

These are *present on disk*; their presence alone does not establish that they work with the currently selected simulator, or that they have been validated on hardware.

## 7. Gazebo installation and successful headless test

### 7.1 Simulator choice and package availability

The stock Yahboom `robot_description/launch/gazebo.launch.py` uses **Gazebo Classic** APIs (`gazebo_ros`, `spawn_entity.py`). Gazebo Classic packages were not available from the configured ARM64 repositories. Rather than change the original robot setup, a separate **Gazebo Fortress / Ignition Gazebo 6** environment was installed via:

```bash
sudo apt install ros-humble-ros-gz
```

Prior APT dry run:

```text
0 upgraded, 211 newly installed, 0 to remove, 62 not upgraded
```

The installed simulator reported:

```text
Gazebo Sim, version 6.18.0
```

### 7.2 Headless world start

Command:

```bash
ign gazebo -s -r -v 3 empty.sdf
```

Verified messages included:

```text
Ignition Gazebo Server v6.18.0
Loading SDF world file [.../worlds/empty.sdf]
World [empty] initialized with [1ms] physics profile.
```

The following Gazebo topics were observed:

```text
/clock
/world/empty/clock
```

An `ign topic -e -t /clock` test showed simulation time advancing.

### 7.3 Gazebo → ROS 2 clock bridge

While Gazebo runs, in another terminal:

```bash
source /opt/ros/humble/setup.bash
ros2 run ros_gz_bridge parameter_bridge \
  '/clock@rosgraph_msgs/msg/Clock[ignition.msgs.Clock'
```

This establishes a **Gazebo-to-ROS one-way bridge** for `/clock`.

Another ROS 2 terminal successfully received:

```yaml
clock:
  sec: 222
  nanosec: 958000000
```

A measurement:

```bash
ros2 topic hz /clock
```

reported roughly **993–996 Hz**, consistent with the Gazebo world using a 1 ms physics step. This is a *message frequency*, not evidence of real-time vehicle-control suitability. During one `ros2 topic echo /clock --once` invocation, ROS reported nine lost-message notifications before receiving a valid clock sample. This warrants eventual QoS/load evaluation but does not invalidate the successful bridge test.

**Validated so far:** Gazebo Fortress server and ROS 2 bridge exchange a simulation clock. **Not yet validated:** Gazebo graphics, spawning the robot, drive plugins, laser/IMU simulation, ROS 2 Nav2 navigation, or real-time performance.

## 8. Yahboom description: important findings

The actual ROS package manifest declares:

```xml
<name>robot_description</name>
```

Located source files:

```text
~/microros_ws/src/robot_description/urdf/microros_v2.urdf.xacro
~/microros_ws/src/robot_description/urdf/camera.urdf.xacro
```

The Gazebo Classic launch file, however, refers to `microros_v2_description_pkg`, which is **not registered** in the tested ROS environment (`ros2 pkg prefix microros_v2_description_pkg` returned `Package not found`). This apparent name inconsistency should be examined when the hardware/model stack is validated. Do not fix it in-place at this stage.

The source meshes and frames include:

| Model part | Mesh/frame |
|---|---|
| Left drive wheel | `lfwheel_Link.STL` |
| Right drive wheel | `rfwheel_Link.STL` |
| Rear supporting wheel | `bwheel_Link.STL` |
| 2D LiDAR housing | `laser_Link.STL`, `laser_frame` |
| IMU housing | `IMU_Link.STL`, `imu_frame` |
| Camera | Defined in `camera.urdf.xacro` |

The joints extracted from `microros_v2.urdf.xacro` were:

| Joint | URDF type | Origin xyz (m) |
|---|---|---|
| `${prefix}lfwheel` | `fixed` | `0.058 0.0857 0.011` |
| `${prefix}rfwheel` | `fixed` | `0.058 -0.0857 0.011` |
| `${prefix}bwheel` | `fixed` | `-0.0665 0 -0.0155` |
| `${prefix}laser` | `fixed` | `-0.028 0 0.13381` |
| `${prefix}IMU` | `fixed` | `-0.047431 -0.00073372 0.074601` |

The lateral separation of the left and right wheel joint origins is **0.1714 m**. This is a model measurement, not yet a calibrated effective wheel separation. The wheel radius, rotation axes, mass and collision geometries need inspection before physical simulation.

**Critical distinction:** the two driving-wheel joints are declared `fixed`, appropriate for a static visualization but not directly usable as actuated joints with Fortress's differential-drive system. A future simulation-specific copy would require appropriately defined rotational joints and simulation plugins. **Do not change the source Xacro in the Yahboom workspace now.**

A prior grep over the two Xacro files showed mesh and joint declarations, but no matched `<plugin>` or `<sensor>` elements in those files. This does not exclude other files or configurations elsewhere in the workspace. No working drive or sensor simulation has been demonstrated.

## 9. Decision: freeze the stock Yahboom configuration

This project will **not modify the actual Yahboom configuration until the rover arrives**. This is the preferred approach because:

1. The supplied Ubuntu image may depend on vendor-specific ROS packages, firmware conventions, topic names, launch-file parameters and ESP32-S3 settings that are not yet fully documented.
2. Real sensor topics, wheel encoder directions, motor signs, chassis dimensions and Wi-Fi connectivity are not yet verified.
3. Changing wheel joints in the stock URDF purely for simulation could affect visualization or other components once the real robot is connected.
4. We already have a working MAVROS integration and an operational development environment worth preserving.

**Permitted meanwhile (isolated and reversible):**

- Read source files, inspect dependencies, and document architecture.
- Test Gazebo Fortress with standalone sample worlds and models.
- Write simulation-specific packages under a **separate workspace**, e.g. `~/rover_sim_ws`, copying only the needed models without overwriting vendor files.
- Run ROS 2/Nav2 unit tests and safe, software-only experiments.
- Take VM snapshots and version-control any original work.

**Deferred until physical delivery and baseline testing:**

- Reflashing ESP32-S3 or changing motor controller firmware.
- Editing stock `robot_description` and `microros_v2_bringup` files.
- Changing wheel type/sign/control authority on the real rover.
- Reconfiguring critical safety and motion parameters without measured baselines.

## 10. Recommended next steps

### Phase A — Before the rover arrives

1. **Protect the environment.** Take a full UTM snapshot/backup and document relevant environment variables, installed ROS packages and Git changes. Increase VM memory only if host resources permit.
2. **Do not touch original Yahboom files.** Inspect the stock description and ROS launch scripts read-only; determine whether the package is correctly built and sourced.
3. **Create an isolated simulator later, if useful.** Use an independent `~/rover_sim_ws` and a copied or minimal differential-drive robot. Keep Gazebo Fortress-specific SDF/plugins away from stock Yahboom packages.
4. **Validate ROS ↔ Gazebo topics.** Confirm clock, simulator command and odometry paths on a sample robot before investing in Nav2 integration.
5. **Design the coverage planner in software.** Define polygon boundaries, tree exclusions, 0.50 m lane generation, row traversal and missed-area reporting, initially without hardware commands.

### Phase B — Hardware arrival: observe stock behavior first

1. Photograph and inventory hardware and firmware versions, wheel dimensions, electronics and power wiring.
2. Review the original documentation and preserve original images/configurations.
3. Verify the robot's own Wi-Fi and micro-ROS communication; identify stock topic names with `ros2 topic list -t` and inspect published message types/rates.
4. With wheels safely off the ground and an independent power cut-off available, test one low-speed motion command at a time; confirm encoder signs and stopping behavior.
5. Check LiDAR scan geometry, IMU orientation and TF tree without changing stock parameters.
6. Record known-good baseline performance and only then decide whether any vendor configuration truly needs adjustment.

### Phase C — Integration and autonomy

1. Use measured wheel geometry and encoder data to configure reliable local odometry.
2. Build/validate localization, SLAM, static and dynamic obstacle handling in ROS 2.
3. Integrate Nav2 with a single authoritative motor-command path and an independent emergency-stop mechanism.
4. Evaluate external GNSS/RTK assistance and MAVROS integration separately, with calibrated ArduPilot sensors and acceptable positional uncertainty.
5. Validate coverage missions at low speed in a controlled area before outdoor field work.

## 11. Known open questions

- Is `robot_description` correctly registered after sourcing `~/microros_ws/install/setup.bash`? (Not yet confirmed in the shared output.)
- What is the real wheel radius and calibrated track width?
- Are motor encoders and IMU already exposed through the vendor's ESP32 micro-ROS firmware, and under which topic names?
- Does the rover use a stable, reachable UDP pathway through the UTM networking setup?
- Are there vendor-provided Gazebo plugins, different model files, or a separate simulator workspace?
- What is the actual RTK GNSS fix status and error distribution?
- How will motion authority and emergency stopping be implemented?
- Can the UTM VM provide adequate CPU/graphics performance when Gazebo and Nav2 run concurrently?

## 12. Reproducible test commands (read-only / simulation)

```bash
# Verify ROS 2 environment
source /opt/ros/humble/setup.bash
source ~/microros_ws/install/setup.bash
ros2 pkg list | grep -E '^(nav2_|navigation2|slam_toolbox|robot_localization)'

# Check actual robot description package name
sed -n '1,12p' ~/microros_ws/src/robot_description/package.xml

# Inspect wheel joints without editing vendor source
grep -A 12 '<joint' \
  ~/microros_ws/src/robot_description/urdf/microros_v2.urdf.xacro

# Start headless Gazebo Fortress (Terminal A)
ign gazebo -s -r -v 3 empty.sdf

# Start unidirectional Gazebo -> ROS clock bridge (Terminal B)
source /opt/ros/humble/setup.bash
ros2 run ros_gz_bridge parameter_bridge \
  '/clock@rosgraph_msgs/msg/Clock[ignition.msgs.Clock'

# Confirm ROS 2 can receive the simulated clock (Terminal C)
source /opt/ros/humble/setup.bash
ros2 topic echo /clock --once
ros2 topic hz /clock
```

Stop foreground diagnostic processes with `Ctrl+C`. Avoid running the real vehicle's motor-control nodes alongside test command publishers until control ownership is unambiguous and a safe test procedure has been prepared.

---

**Bottom line:** The host-to-VM MAVLink/MAVROS connection, key ROS 2 navigation package availability, headless Gazebo Fortress startup, and Gazebo-to-ROS clock bridge have been demonstrated. The physical rover, its stock firmware interfaces and its Gazebo-actuated model **have not yet been tested**. The correct next policy is to preserve Yahboom's original configuration, establish a hardware baseline on arrival, and develop any simulation adaptations independently.
