# Yahboom MicroROS V2 — Dify, Local Ollama LLM, Joystick, Camera and Motion-Control Integration

**Experimental field notes and reproducible follow-up guide — 20 October 2026 (afternoon/evening)**  
**Platform:** Apple Silicon MacBook Pro + UTM/QEMU + Ubuntu 22.04 ARM64 + ROS 2 Humble + Yahboom MicroROS V2 2WD/PTZ  
**Status:** Physical joystick driving **verified**; local Dify–Ollama–ROS integration **verified**; camera capture via LLM `seewhat()` **verified**; LLM-driven physical movement **not yet enabled or verified**.

> **Scope and companion guide.** This is an **addendum**, not a replacement for [`YAHBOOM_MICROROS_V2_MAC_UTM_ARM64_SETUP.md`](YAHBOOM_MICROROS_V2_MAC_UTM_ARM64_SETUP.md). The earlier guide explains UTM networking, USB passthrough, RobotManager, micro-ROS Agent, LiDAR, camera fundamentals and RViz2. This document records the *additional hardware and software experiments conducted later on 20 October 2026*, with observations, exact commands, limitations and next actions. Observed success is distinguished from intended functionality and untested assumptions.

**Project repository:** https://github.com/jcarpio/Yahboom_MicroROS-V2-on-Apple-Silicon  
**Suggested location:** `docs/YAHBOOM_MICROROS_V2_DIFY_OLLAMA_JOYSTICK_LLM_PROGRESS_2026-10-20.md`

---

## 1. Executive summary: what changed this afternoon

We moved from sensor connectivity to a substantially more integrated, **physically assembled mobile robot** and an experimentally working language-model control path.

| Area | New evidence from this session | Confidence / limitation |
|---|---|---|
| Assembled 2WD robot | Two driven wheels were tested using Yahboom's bundled wireless controller and `JoystickControl` | **Physical motor movement confirmed** with joystick; not proof of LLM motor actuation |
| Wireless joystick | USB receiver was passed from macOS to Ubuntu/UTM; `/joy_node` and `/joy_control` appeared | **Working joystick-to-robot driving** as reported and observed by operator |
| ROS production bringup | `ros2 launch microros_v2_bringup car_base.launch.py` produced `/micro_ros_task_node`, `/base_driver`, camera, EKF and state/TF nodes | **ROS discovery confirmed**; real-time operation varies with active applications |
| Camera on LAN | ESP32-Lite was reachable at `192.168.1.53`, HTTP GET on port 80 returned `200 OK`; MJPEG camera stream opened from ROS | **Confirmed for this DHCP address only** |
| Mapping interference | Browser stream initially became unavailable while mapping was active; joystick-only scenario allowed camera viewing | **Observed correlation**, not yet diagnosed as CPU load, stream contention or double launch |
| Standalone ROS camera publisher | `ros2 run microros_v2_bringup camera_driver --ros-args -p camera_url:=http://192.168.1.53:81/stream` | **Opened successfully**, observed ~4–5 FPS |
| Dify and local LLM | Ubuntu Dify API at `http://localhost/v1` talked to an Ollama instance hosted on macOS; Dify connectivity succeeded | **Text decisions and actions confirmed**; no cloud model is required for this specific configured provider |
| Model selection | Ollama `qwen2.5vl:3b` used for multimodal/vision experiments; `llama3.2:latest` had also been tested | Qwen vision model configured in Dify; actual image semantic description **not yet verified** |
| Agent source packages | `multi_brains` / `multi_brains_pre` built and sourced in ROS 2 Humble ARM64 environment | **Agent and `terminal_client` ran successfully** |
| LLM image action | `seewhat()` failed when `/camera/image_raw` had zero publishers; succeeded after starting the camera publisher | **Frame capture action confirmed**; model then unexpectedly attempted `track_kcf()` |
| LLM motion action | Natural-language `move_forward`, `turn_left` and `turn_right` mapped to motion functions | **Commands published on isolated `/utm_test/cmd_vel`**, not physical motion |
| Feedback-loop issue | `max_rounds: 2` made Dify repeat an action; `max_rounds: 1` executed one action per request | **Repetition mitigated for single-step motion**, but completion feedback remains imperfect |
| Safety issue | Current `execute_stop()` does not itself publish an explicit zero `Twist`; line-follower `stop()` returns early when inactive | **Requires correction, verification and independent watchdog** before physical LLM control |
| Wheel odometry | `/odom_raw` published static x/y samples when no wheel movement occurred | **Not sufficient to validate encoder integration or odometric accuracy** |

### Most important conclusion

**The LLM-to-ROS velocity-generation pipeline works.** The end-to-end *physical* LLM-to-motor pipeline is **not** yet established. These are different validation milestones and should never be conflated.

---

## 2. Architecture and boundaries

```text
                 Apple Silicon MacBook Pro / macOS
                 ┌─────────────────────────────────────┐
                 │ Ollama HTTP API :11434             │
                 │ qwen2.5vl:3b (vision-capable)      │
                 │ llama3.2:latest (earlier text test)│
                 └──────────────────┬──────────────────┘
                                    │ LAN / host IP, example 192.168.1.48
                           HTTP API │
                                    ▼
┌──────────────────────────────────────────────────────────────────┐
│ Ubuntu 22.04 ARM64 — UTM bridged VM, example 192.168.1.52      │
│ Docker Dify app API: http://localhost/v1                          │
│ Dify application: microros-v2-en                                  │
│           ▲                                                       │
│           │ ROS 2 multi_brains LLM agent / terminal_client        │
│           │                                                       │
│           ├── LLM motion output: /utm_test/cmd_vel (SAFE TEST)   │
│           │                 (NOT connected to motor subscriber)   │
│           │                                                       │
│           ├── Input: /camera/image_raw ◄── camera_driver         │
│           │                          ◄── ESP32 camera MJPEG      │
│           │                                                       │
│ car_base.launch.py: micro-ROS Agent / base_driver / EKF / camera │
│           │                                                       │
│ /cmd_vel ◄──── base_driver ───────────► micro_ros_task_node       │
│                       ROS 2 to ESP32 via micro-ROS UDP            │
└───────────────────────────────────┬──────────────────────────────┘
                                    │
            ┌───────────────────────┴─────────────────────┐
            │ Yahboom 2WD/PTZ base                       │
            │ ESP32 controller + two drive motors        │
            │ camera ESP32-Lite, LiDAR, IMU              │
            │ wireless USB joystick receiver in Ubuntu  │
            └─────────────────────────────────────────────┘
```

**Network IPs shown above are observations from one LAN, not hardcoded defaults.** The ESP32 camera in the session used `192.168.1.53`; its original code default was `192.168.12.32`. Use the DHCP assignments from the current network. The guest and host IPs may change after reboot.

### 2.1 ROS 2 environment (every new Ubuntu terminal)

```bash
source /opt/ros/humble/setup.bash
source ~/uros_ws/install/local_setup.bash
source ~/microros_ws/install/local_setup.bash
export ROS_DOMAIN_ID=40
```

Symptoms of forgetting to source the environment include:

```text
Package 'multi_brains' not found
```

This was encountered more than once on new terminals and fixed by sourcing the installed workspaces. **No reinstall was necessary.** After a clean Ubuntu reboot, `ros2 node list` was initially empty until launch programs were started.

### 2.2 Avoid simultaneous conflicting launch files

- Use `car_base.launch.py` as the normal connected robot bringup.
- Avoid launching `test_connect.launch.py`, another micro-ROS Agent, or a separate duplicate camera driver at the same time as a launch already creating those nodes.
- `Mapping` may launch additional components; identify its exact launch graph before combining it with a standalone camera stream.
- The `terminal_client` is a front-end. It does not itself connect the LLM to the motor driver.

---

## 3. Local Ollama on macOS and Dify in the ARM64 guest

### 3.1 Actual placement

The language-model inference server is **on macOS**, outside the Ubuntu VM. Dify's API and the ROS 2 client run **inside Ubuntu**. This is deliberate: it lets macOS run Ollama using its native Apple Silicon runtime while the Ubuntu VM operates ROS 2 and the robot integrations.

Observed service locations:

```text
Ollama, macOS:        http://192.168.1.48:11434
Dify API, Ubuntu:     http://localhost/v1
Configured Dify app:  microros-v2-en
ROS domain:           40
```

The public local IP shown is only an example; replace it if macOS receives another address.

### 3.2 Allow LAN access to Ollama

During earlier configuration, Ollama's macOS server was made reachable from the bridged VM by configuring its listening address:

```bash
# macOS terminal — example of the session's setup
launchctl setenv OLLAMA_HOST '0.0.0.0:11434'
```

The Ollama application/service was **restarted** afterward so the environment change took effect. Whether `launchctl setenv` affects the current launch depends on the way Ollama is started; verify rather than assume. Prefer binding to a trusted private interface and apply firewall restrictions as appropriate: `0.0.0.0` means all interfaces. Do not expose port 11434 publicly.

From Ubuntu, verify actual connectivity:

```bash
curl --max-time 10 http://192.168.1.48:11434/api/tags
```

A successful JSON response from `/api/tags` was observed in the working setup. Check the current Mac IP with `ipconfig getifaddr en0` on macOS before treating example addresses as permanent.

### 3.3 Models used in the session

- `llama3.2:latest`: initial text-only model for dialogue/action experiments.
- `qwen2.5vl:3b`: Ollama vision-language model, downloaded locally (approximately 3.2 GB quantized package in the earlier setup). Its reported vision capability made it the candidate for interpreting camera frames.

Useful macOS commands:

```bash
ollama list
curl http://127.0.0.1:11434/api/tags
```

The full Ollama build version, runtime performance and quantization details were **not independently recorded in these field notes**. Do not infer model accuracy from a successful API call.

### 3.4 Dify provider, application and key alignment

Dify was already deployed locally in the Ubuntu VM via Docker. The relevant Dify application is `microros-v2-en`, with the LLM blocks pointed at the local Ollama provider/model. The application was **published** after the model/provider settings were updated.

An earlier setup produced a Dify error equivalent to **“Model is not configured.”** The agent's API key had been associated with the wrong application (`microros-v2-zh` instead of `microros-v2-en`). Updating the key through Yahboom's RobotManager to the intended English application resolved the mismatch. A subsequent call to Dify's `/v1/info` confirmed the selected application; the LLM agent logged:

```text
[DIFY] initializing client: base_url=http://localhost/v1, api_key=app-****
[DIFY] testing connection...
[DIFY] connection successful ✓
```

**Do not copy credentials into GitHub:** the Dify key is stored/configured locally (RobotManager's `robot_info.json` workflow). This document intentionally omits its value. If publishing the VM, scrub actual keys, cookies, environment files and persisted Dify account data, not just the documentation.

Useful diagnostic commands in Ubuntu:

```bash
curl -sS -I http://localhost/v1 || true  # root endpoint may reject HEAD
sudo docker compose -f ~/software/dify/docker/docker-compose.yaml ps
```

The actual integration proof is the working `llm_agent_node` Dify connection and subsequent decision/action responses, not the root `/v1` status by itself. Application model selection and provider configuration are UI-specific; ensure Dify's **provider endpoint is the macOS host LAN address**, not Ubuntu's own `localhost:11434`.

### 3.5 Building / discovering the ROS 2 LLM packages

The working ARM64 ROS 2 workspace included packages `multi_brains` and `multi_brains_pre`. They were previously built using:

```bash
cd ~/microros_ws
colcon build --packages-select multi_brains multi_brains_pre --symlink-install
source install/local_setup.bash
ros2 pkg list | grep multi_brains
```

This is a **known previous success**, not an instruction to rebuild after every restart. The session launched:

```bash
ros2 launch multi_brains llm_agent_control.launch.py \
  config_file:=$HOME/microros_ws/src/multi_brains/config/llm_agent_utm_test.yaml

ros2 run multi_brains terminal_client
```

Later, the safer single-round YAML was used instead (see §8).

---

## 4. Wireless joystick and physical motor validation

### 4.1 Hardware and setup

The robot is now mechanically assembled with its two 12 V-class 520 drive motors. The user connected the **USB receiver supplied with the Yahboom wireless handheld remote** through UTM's USB passthrough to the Ubuntu guest and launched Yahboom's `JoystickControl` application.

When the joystick application ran, ROS 2 listed:

```text
/joy_node
/joy_control
```

The operator reported **successful physical wheel movement through the wireless handheld joystick**. This validates the motors, their power path under that operating configuration, and the joystick application as an overall system. It does **not** validate the LLM's separate ROS 2 velocity path.

### 4.2 Reproducing and diagnosing the receiver

1. Connect the bundled USB dongle to the Mac.
2. Pass the dongle to the Ubuntu guest in **UTM → USB devices**; host ownership and guest ownership are not simultaneous.
3. Power/pair the remote according to its supplied procedure.
4. Launch Yahboom's existing `JoystickControl` application (exact desktop launcher or underlying launch command was not captured).
5. Keep the robot supported with wheels off the ground for first motion tests and keep the power switch reachable.

Check Linux USB/input recognition if necessary:

```bash
lsusb
ls -l /dev/input/js* 2>/dev/null
cat /proc/bus/input/devices
```

Optional (`jstest` only if its package exists, or install the distro `joystick` package):

```bash
jstest /dev/input/js0
```

For ROS diagnostics:

```bash
ros2 node list
ros2 node info /joy_control
ros2 node info /joy_node
ros2 topic info /cmd_vel --verbose
```

The exact node publishers/subscribers of `joy_control` **were not captured** in this session. Do not assume it publishes directly to `/cmd_vel` without inspecting those node interfaces.

### 4.3 Isolation matters

- Joystick driving worked while the browser camera video could also work.
- Before diagnosing LLM movement, stop joystick applications and inspect remaining processes and ROS nodes. Closing a terminal does not establish what happened to every launched subprocess.
- **Avoid two simultaneous motor command sources.** In future integration, use an explicit command multiplexer or exclusive-control mechanism, not competing publishers blindly driving `/cmd_vel`.

Possible checks:

```bash
ps aux | grep -Ei 'joy_node|joy_control|joystick|teleop' | grep -v grep
ros2 node list
```

---

## 5. Camera streaming: browser, ROS publisher, contention and recovery

### 5.1 LAN reachability and the HTTP-method trap

The camera's observed LAN address was `192.168.1.53`. From Ubuntu:

```bash
ping -c 4 192.168.1.53
```

The diagnostic returned 3 replies from 3 packets (0% loss) with sample latencies roughly 25–176 ms. A normal HTTP GET:

```bash
curl -v --connect-timeout 5 --max-time 10 http://192.168.1.53/
```

returned **`HTTP/1.1 200 OK`**, `Content-Type: text/html`, `Content-Encoding: gzip`. `curl` warned about binary/compressed terminal output and then failed writing that output; that warning was **not evidence of a server failure**.

From macOS:

```bash
curl -I http://192.168.1.53/
```

returned **`HTTP/1.1 405 Method Not Allowed`**. This was not a connectivity failure: `curl -I` sends an HTTP **HEAD** request that the ESP32 server did not accept. Prefer a GET with discarded body:

```bash
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' http://192.168.1.53/
```

### 5.2 Streaming port 81 and mapping contention

The MJPEG endpoint used was:

```text
http://192.168.1.53:81/stream
```

macOS `curl` **connected to TCP port 81** but initially received **zero HTTP response bytes** over five seconds; it timed out. The operator later noticed that the **Mapping** application had been active. After stopping the mapping workload, the camera worked while using the joystick application.

**Interpretation:** there was a reproducible *practical interference*, but the cause remains open. Possible explanations include CPU/memory pressure in the VM, network contention, duplicate camera drivers, or an ESP32 MJPEG server/client concurrency limit. No CPU profile, socket trace or controlled A/B experiment was recorded, so do not assert a specific cause.

A useful future A/B test is to hold camera, network and viewer constant while launching only one additional component at a time. Capture:

```bash
ros2 node list
ros2 topic info /camera/image_raw --verbose
ros2 topic hz /camera/image_raw
ps -eo pid,pcpu,pmem,args --sort=-pcpu | head -20
```

### 5.3 Why `seewhat()` initially failed

When the LLM was asked:

```text
Tell me what you can see through your camera. Do not move the robot.
```

Dify chose `seewhat()`, but the action **failed twice**. Inspection of the topic explained the immediate cause:

```text
ros2 topic info /camera/image_raw --verbose
Publisher count: 0
Subscription count: 1
Subscriber: llm_agent_node, BEST_EFFORT
```

The LLM subscribed to images but **no ROS node was publishing images**. Watching the HTTP camera feed in a browser does not automatically create ROS messages.

### 5.4 Start only the camera driver, without Mapping

Source the ROS environment (§2.1) and use:

```bash
ros2 run microros_v2_bringup camera_driver \
  --ros-args -p camera_url:=http://192.168.1.53:81/stream
```

This entry point was verified in:

```text
~/microros_ws/src/microros_v2_bringup/setup.py
  camera_driver = microros_v2_bringup.camera_driver:main
```

The implementation is:

```text
~/microros_ws/src/microros_v2_bringup/microros_v2_bringup/camera_driver.py
```

The session log included:

```text
camera node started, camera_url: http://192.168.1.53:81/stream
Camera not opened, trying reconnect...
IP camera stream opened successfully
```

Warnings such as `ost_file not found: ""` and `No valid ost_file, CameraInfo will not be published` mean the camera calibration file was absent; they did not prevent image streaming. Calibration will matter for geometric computer vision.

Measured:

```bash
ros2 topic hz /camera/image_raw
```

reported instantaneous moving averages around **4.0–5.2 images/s**; rates fluctuated and one sample interval was ~0.615 s. A short startup warning that the topic was not yet publishing was followed by actual messages. Do not mistake a temporary startup warning for persistent camera failure.

**After this fix, `seewhat()` succeeded.** This is a confirmed capture/action success, **not a verified meaningful model description of the image**.

### 5.5 Single-camera ownership guideline

If `car_base.launch.py` already starts `/esp32_ip_camera_publisher`, do **not** also start a standalone `camera_driver` process. Before starting one, check:

```bash
ros2 node list | grep camera
ros2 topic info /camera/image_raw --verbose
```

In the clean full bringup, the session later showed a single `/esp32_ip_camera_publisher` node. When direct browser access fails, checking the ROS image publisher and the Mapping workload is more informative than blindly changing the camera's IP.

---

## 6. Agent behavior: Dify decisions, camera feedback and tool selection

### 6.1 Confirmed Dify and agent lifecycle

The English-language agent boot log included:

```text
Initializing LLM Agent Node...
[CONFIG] cmd_vel_topic=/utm_test/cmd_vel
[CONFIG] image_cache_path=/home/yahboom/microros_ws/cache/llm_camera.jpg
[DIFY] initializing client: base_url=http://localhost/v1
[DIFY] connection successful ✓
LLM Agent Node initialized successfully
```

The API key value is intentionally omitted. The model's text arrived in `terminal_client`, demonstrating local Dify endpoint, agent bridge, ROS messages and conversational UI worked together.

### 6.2 Arithmetic question exposed an unsuitable system prompt

The test:

```text
how much is 1 + 1?
```

returned an irrelevant answer about not having a calculator and being unable to perform arithmetic within “map destinations”. It then invoked `finishtask()`.

This does **not** prove that Qwen cannot do elementary arithmetic. It suggests the Dify workflow/system prompt or decision template is overly specialized for robotic missions. Inspect both the app's instruction template and any hardcoded parsing contract. The precise offending prompt was not exported during the session.

### 6.3 Camera action succeeded, then Dify selected an unwanted tracker

After starting the ROS camera publisher, the agent produced:

```text
[action 1/1] seewhat()
[action 1/1] seewhat() succeeded ✓
[feedback decision] I am tracking the robot.
[action 1/1] track_kcf(200, 200, 400, 400)
[action 1/1] track_kcf(200, 200, 400, 400) failed ✗
```

The user only requested an image description and explicitly forbade movement. A successful `seewhat()` caused a **second Dify decision with the captured image**; the model chose to track an object rather than describe it. The reported rectangle `(200, 200, 400, 400)` was generated by the LLM and not validated as an actual target.

The session located the relevant loop:

```text
~/microros_ws/src/multi_brains/multi_brains/llm_agent_node.py
  process_text_command(): roughly lines 400–560 in tested version
  image_callback(), get_latest_image_snapshot(), wait_for_image_after()
```

Behavior shown by source:

1. `self.dify.call_agent(request_text, robot_feedback=..., image_paths=...)` asks Dify to choose an action.
2. `self.dify.parse_response(...)` parses model actions.
3. `select_round_action(actions)` chooses an action for the current round.
4. `execute_action_batch(...)` attempts execution.
5. `consume_pending_action_feedback()` retrieves optional image feedback.
6. The next iteration calls Dify with feedback and image paths.

The intermediate model-generated claim “I have captured the current view” was **not** by itself proof of image acquisition. The actual success/failure logs were used as evidence.

### 6.4 Disabled YAML features do not remove actions from the registry

The test YAML had:

```yaml
NAVIGATION:
  enable: false
FOLLOW_LINE:
  enable: false
TRACK_KCF:
  enable: false
SYSTEM:
  cmd_vel_topic: /utm_test/cmd_vel
```

But `init_action_registry()` at approximately line 321 still registered these names unconditionally:

```python
self.action_registry = {
    'navigation': self.navigation.execute_navigation,
    'follow_line': self.execute_follow_line,
    'track_kcf': self.kcf.execute_track_kcf,
    'seewhat': self.execute_seewhat,
    'move_forward': self.motion.execute_move_forward,
    'move_backward': self.motion.execute_move_backward,
    'turn_left': self.motion.execute_turn_left,
    'turn_right': self.motion.execute_turn_right,
    'stop': self.execute_stop,
    'servo1_move': self.ptz.execute_servo1_move,
    'servo2_move': self.ptz.execute_servo2_move,
    'servo_init': self.ptz.execute_servo_init,
    'servo_shake': self.ptz.execute_servo_shake,
    'servo_nod': self.ptz.execute_servo_nod,
    'get_current_pose': self.navigation.get_current_pose,
    'observe_surroundings': self.execute_observe_surroundings,
    'finishtask': self.execute_finish_task,
}
```

**Security consequence:** disabling a feature in YAML does not necessarily prevent the LLM from *requesting* its registered action. Whether execution is refused depends on implementation of the downstream controller. The safe approach is **an action allowlist enforced at execution time**, independent of model prompts and independent of the model's compliance with “do not move.” A vision-only allowlist could contain `seewhat` and `finishtask`, after checking camera-preparation and other side-effect paths.

---

## 7. Why the LLM did not move the physical robot

The robot and the LLM were connected to the **same ROS 2 domain**, but their velocity channels were intentionally isolated:

```text
/utm_test/cmd_vel
  Publisher:   llm_agent_node
  Subscriber:  temporary ros2cli echo process
  QoS:         BEST_EFFORT / VOLATILE

/cmd_vel
  Publisher:   base_driver
  Subscriber:  micro_ros_task_node
  QoS:         publisher RELIABLE, subscriber BEST_EFFORT, both VOLATILE
```

These QoS policies are compatible: a `RELIABLE` publisher can satisfy a `BEST_EFFORT` subscriber. This was not the cause of the deliberately absent LLM-driven motion.

The robot controller was previously commanded directly via `/cmd_vel` at a very low linear speed (0.05 m/s) and did not visibly move. **That earlier result does not disprove the motor hardware**, because the bundled joystick subsequently drove the wheels. The physical command routing and any firmware-specific mode/enable conditions still need investigation.

A full bringup from clean Ubuntu used:

```bash
ros2 launch microros_v2_bringup car_base.launch.py
```

The later `ros2 node list` showed:

```text
/base_driver
/ekf_filter_node
/esp32_ip_camera_publisher
/joint_state_publisher
/llm_agent_node
/micro_ros_task_node
/robot_state_publisher
/terminal_client
/transform_listener_impl_...
```

This demonstrates node discovery and compatible communication interfaces, not a complete closed-loop motor-control validation.

---

## 8. Controlled LLM motion tests, feedback-loop repetition, and single-round configuration

### 8.1 First test YAML

File:

```text
~/microros_ws/src/multi_brains/config/llm_agent_utm_test.yaml
```

Observed:

```yaml
FEEDBACK_LOOP:
  max_rounds: 2
NAVIGATION:
  enable: false
FOLLOW_LINE:
  enable: false
TRACK_KCF:
  enable: false
SYSTEM:
  cmd_vel_topic: /utm_test/cmd_vel
  hardware_variant: ptz
```

Use the YAML as a test preset, **not** as a complete hardware interlock. The agent may still orient the PTZ camera and request other registered actions; its output redirect applies to the configured velocity publisher, not necessarily every actuator path.

### 8.2 Unexpected repeated forward and turn actions

In `terminal_client`, the instruction:

```text
move forward
```

produced a model-generated plan `move_forward(0.1, 2)`. The first action returned success; during the second feedback round Dify requested **the same action again**:

```text
['move_forward(0.1, 2)', 'move_forward(0.1, 2)']
Task feedback exceeded 2 rounds; stopped requesting Dify
```

Likewise, `turn left` triggered `turn_left(30, 0.5)` twice and `turn right` triggered `turn_right(45, 0.5)` twice. The angles and speeds were chosen by the model when unspecified. This could double commanded angular displacement if used for real motion.

### 8.3 Create an isolated single-round test preset

Preserve the two-round vision preset and create a separate motion-only test preset:

```bash
cp ~/microros_ws/src/multi_brains/config/llm_agent_utm_test.yaml \
   ~/microros_ws/src/multi_brains/config/llm_agent_utm_single.yaml

sed -i 's/max_rounds: 2/max_rounds: 1/' \
   ~/microros_ws/src/multi_brains/config/llm_agent_utm_single.yaml

grep -n -E 'max_rounds:|cmd_vel_topic:' \
  ~/microros_ws/src/multi_brains/config/llm_agent_utm_single.yaml
```

Observed:

```text
5:   max_rounds: 1
131: cmd_vel_topic: /utm_test/cmd_vel
```

Launch:

```bash
ros2 launch multi_brains llm_agent_control.launch.py \
  config_file:=$HOME/microros_ws/src/multi_brains/config/llm_agent_utm_single.yaml
```

The test:

```text
turn left 30 degrees at 0.2 rad/s
```

produced:

```text
[action 1/1] turn_left(30, 0.2)
[action 1/1] turn_left(30, 0.2) succeeded ✓
['turn_left(30, 0.2)']
```

The user entered the instruction twice on separate occasions; **each request independently executed one action**, rather than repeating within one request.

**Remaining drawback:** the client still displayed `Task feedback exceeded 1 rounds; stopped requesting Dify` because the loop reaches its maximum without a normal conversational completion. Single-round mode is a useful *testing workaround*, not the complete solution. Multi-round tasks such as `seewhat()` followed by analysis require a different completion policy.

### 8.4 ROS 2 velocity output verified

While the client submitted the turn command, another Ubuntu terminal ran:

```bash
ros2 topic echo /utm_test/cmd_vel
```

The recorded output contained multiple:

```yaml
linear:
  x: 0.0
angular:
  z: 0.2
```

followed by messages containing:

```yaml
linear:
  x: 0.0
angular:
  z: 0.0
```

This establishes a **working LLM → Dify → multi_brains ROS 2 velocity stream**, including zero messages at the end of the observed example. The zero messages were observed; the code path responsible for them needs scrutiny (§9). Physical LLM motion was intentionally absent.

### 8.5 ROS `echo` timing pitfall

`ros2 topic echo` waits for *new* messages. When launched after an action completed, it printed nothing, which was initially misinterpreted as a missing publisher. Starting `echo` before asking Dify to move revealed the stream. For static endpoint counts inspect:

```bash
ros2 topic info /utm_test/cmd_vel --verbose
```

---

## 9. Source-level safety audit: motion limits and stop behavior

### 9.1 `motion_controller.py` details

Examined file:

```text
~/microros_ws/src/multi_brains/multi_brains/controllers/motion_controller.py
```

Source-level observations:

- `execute_move_forward(speed, duration)` validates positive finite speed/duration then calls `_execute_velocity(...)`.
- `execute_move_backward(...)` negates linear X.
- `execute_turn_left(angle, speed)` uses a positive angular Z; `execute_turn_right(...)` uses a negative angular Z.
- Validation rejects malformed, nonfinite, nonpositive and over-limit parameters.
- Commands are published approximately **every 0.1 seconds** (~10 Hz) until the computed duration expires.
- The loop polls `self.node.should_interrupt()`.
- After a timed motion, the code calls `self.node.execute_stop(recenter_camera=False)`.
- Turning is **time-based/open-loop**, using `math.radians(angle)/speed`, not closed-loop wheel/IMU angle feedback.

The observed YAML effective test limits were:

```yaml
MOTION:
  max_linear_speed: 0.5
  max_angular_speed: 1.5
  max_duration_sec: 60.0
  max_turn_angle_deg: 720.0
SYSTEM:
  cmd_vel_topic: /utm_test/cmd_vel
  hardware_variant: ptz
```

Those are **not conservative limits** for initial physical LLM tests. Proposed engineering targets for *further bench testing* were 0.05 m/s linear, 0.2 rad/s angular, 2 seconds maximum movement, and 30 degrees maximum requested turn. These limits are **proposals only**, not yet implemented or validated on hardware.

Example: 30° at 0.2 rad/s gives `radians(30)/0.2 ≈ 2.62 s`. Actual physical angle may differ due to traction, battery voltage, load and motor dynamics; current function does not measure achieved yaw.

### 9.2 Critical discovery: `execute_stop()` lacks a direct zero-velocity publish

In the examined `llm_agent_node.py`, approximately lines 1005–1011:

```python
def execute_stop(self, recenter_camera: bool = True) -> bool:
    self.kcf.stop_active_kcf_tracking()
    self.follow_line_controller.stop()
    if self._parse_bool_flag(recenter_camera, default=True):
        self.ptz.recenter_after_stop()
    return True
```

No `Twist()` zero publish appears **directly** in that function.

In `controllers/follow_line_controller.py`, around line 291:

```python
def stop(self) -> None:
    with self._state_lock:
        if not self.active:
            return
        self._stop_requested = True
        self._finish_reason = 'stop_requested'
        self._finished_event.set()
    self._publish_zero_twist()
```

**Consequence:** when line-following is inactive, this particular `stop()` returns **without invoking its zero-Twist publication**. We also saw zero-Twist samples after ordinary motions, so another path (for example a separate publisher, controller behavior, or a different execution branch) may generate them. The exact origin has **not** been demonstrated. Do not claim that stops always fail, or that the sampled zero messages prove the stop path is safe.

**Recommended fix to implement and test, not yet applied:** ensure that every stop or abort path explicitly publishes a zero `geometry_msgs/msg/Twist` via the agent's actual `cmd_vel_pub`, and use `try/finally` around timed movements where appropriate. Confirm the correct publisher attribute and imports in the source before patching. Avoid duplicating control paths without thought; test the node with a disconnected motor output topic first.

Even with this correction, **a network crash or ESP32 comms failure can prevent delivery of a stop message**. A robot-side timeout/watchdog and a hardware-accessible emergency stop are separate requirements.

### 9.3 Action allowlist, velocity interlock and exclusivity

Before enabling real LLM motion:

1. Restrict action names by an **enforced execution-time allowlist**; initially allow only basic commands plus `finishtask`, or for camera-only operation allow `seewhat` + `finishtask`.
2. Fix normal task completion so a completed motion is not repeated on Dify feedback.
3. Introduce a separate **ROS bridge/interlock** between `/utm_test/cmd_vel` and `/cmd_vel`, with velocity clamping, a strict command-age timeout and automatic zero output on timeout/disarm.
4. Design a motor command **source arbiter**, since `base_driver`, joystick control and an LLM bridge must not race for a shared output topic.
5. Verify the **ESP32 firmware's own loss-of-command timeout** and physical emergency stop; do not rely on Ubuntu or Dify responsiveness for safety.
6. First bench-test the interlock with the motor power removed; only then perform a very short powered test with the wheels suspended and clear of obstacles/persons.
7. Require explicit operator enable/disarm rather than directly routing arbitrary model actions to `/cmd_vel`.

No live bridge, execution-time allowlist, independent watchdog, or LLM-driven wheel test was completed during this session.

---

## 10. Odometry, servo/PTZ and complementary ROS findings

### 10.1 Odom samples

The robot published `/odom_raw`. During a stationary period the reported position remained constant:

```yaml
x: 0.08095274120569229
y: -0.008643720299005508
z: 0.0
```

These numbers are **an odometry estimate**, not proof of ~8 cm measured wheel travel. The wheels were not moving during the logged period, and manual rotation was not verified (the operator reported that the wheels did not move in the attempted test). Encoder functionality and velocity odometry therefore remain unproven; do not diagnose encoder hardware from this sample alone.

### 10.2 Base driver parameters

The recorded `/base_driver` parameter dump included:

```yaml
camera_type: ptz
min_linear_speed: 0.03
min_angular_speed: 0.2
odom_linear_speed: 0.15
odom_angular_speed: 0.5
odom_timeout: 30.0
precise_adjust_max_angular_vel: 0.5
precise_adjust_max_linear_vel: 0.12
```

These are `base_driver` ROS parameters, **not necessarily the motor firmware's PWM/deadband thresholds**. Earlier direct ROS command tests at 0.03–0.05 m/s produced no visible motor motion, whereas wireless joystick driving subsequently succeeded. Future investigation should inspect the joystick control route, any firmware operating modes and motor command safety gates.

### 10.3 Camera preparation may move servos

Agent progress often logged:

```text
[preparing] adjusting camera to face forward...
```

The test YAML directed wheel velocity to `/utm_test/cmd_vel`, but PTZ functions such as `servo_init`, `servo1_move` and `servo2_move` exist in the action registry. They may command real hardware independently of the wheel velocity redirect. Consequently, a “virtual motor test” is **not automatically a completely no-actuation test**; physically disarm motors and understand PTZ side effects if safety matters.

---

## 11. Reproducible launch recipes

### 11.1 Inspect an empty reboot state

From Ubuntu after a clean reboot:

```bash
source /opt/ros/humble/setup.bash
source ~/uros_ws/install/local_setup.bash
source ~/microros_ws/install/local_setup.bash
export ROS_DOMAIN_ID=40
ros2 node list
```

The session initially showed no nodes. This is normal before launching anything.

### 11.2 Robot bringup — hardware connected, not LLM-driven

With the robot configured, powered and physically safe:

```bash
ros2 launch microros_v2_bringup car_base.launch.py
```

Check in another sourced terminal:

```bash
ros2 node list
ros2 topic info /cmd_vel --verbose
ros2 topic info /camera/image_raw --verbose
```

If the production launch owns the camera, do not start another camera publisher.

### 11.3 LLM-only test with no robot motor control

In terminal A:

```bash
ros2 launch multi_brains llm_agent_control.launch.py \
  config_file:=$HOME/microros_ws/src/multi_brains/config/llm_agent_utm_single.yaml
```

In terminal B (after sourcing the environment):

```bash
ros2 topic echo /utm_test/cmd_vel
```

In terminal C (after sourcing):

```bash
ros2 run multi_brains terminal_client
```

Example prompt:

```text
turn left 30 degrees at 0.2 rad/s
```

**Expected validation:** one `turn_left(30, 0.2)` for one request, multiple outgoing `angular.z: 0.2` messages and subsequent observed zero messages. The single-round client may still report a feedback-round limit; record that as a workflow defect. Do not infer that the actual robot turned.

### 11.4 Vision test without Mapping

Make sure a publisher exists:

```bash
ros2 topic info /camera/image_raw --verbose
```

If count is zero and there is no `car_base.launch.py` camera driver, start the standalone process using the **current camera DHCP IP**:

```bash
ros2 run microros_v2_bringup camera_driver \
  --ros-args -p camera_url:=http://192.168.1.53:81/stream
```

Then:

```bash
ros2 topic hz /camera/image_raw
```

For image feedback, the original `max_rounds: 2` configuration can allow a capture and second Dify inference, but **do not enable the old unrestricted action execution on real moving hardware**. Implement an allowlist first.

### 11.5 CLI diagnostics for publication and QoS

```bash
ros2 node list
ros2 topic list -t | grep -E 'cmd_vel|camera|odom|scan'
ros2 topic info /cmd_vel --verbose
ros2 topic info /utm_test/cmd_vel --verbose
ros2 topic info /camera/image_raw --verbose
ros2 topic hz /camera/image_raw
```

Run topic `echo` before initiating an action. Stop it with `Ctrl+C` after gathering a small sample.

### 11.6 Troubleshooting matrix

| Symptom | Likely explanation based on session | Next check |
|---|---|---|
| `Package 'multi_brains' not found` | New shell not sourced | Source ROS base and both workspaces, verify `ROS_DOMAIN_ID=40` |
| LLM starts but ESP32 node absent | `car_base.launch.py` / Agent not started after reboot | Launch normal robot bringup; check UDP Agent and robot's IP settings |
| Browser HEAD returns HTTP 405 | Camera server does not support HEAD | Try GET; 405 does **not** imply network disconnection |
| HTTP port 81 connects then times out | Stream unavailable/blocked/contention | Check mapping app, duplicate consumers, ROS camera stream and ESP32 connectivity |
| `seewhat() failed` with zero image publishers | No ROS camera node | Start standalone camera driver or normal bringup, but not both |
| `seewhat() succeeded`, then `track_kcf()` | Dify feedback loop selects another registered tool | Dify prompt + execution-time allowlist; do not turn on motors |
| LLM says motion succeeded but no wheel movement | Test velocity topic is isolated from motor topic | Verify `/utm_test/cmd_vel` vs `/cmd_vel`; **do not bridge blindly** |
| `ros2 topic echo` initially blank | Echo launched after completed action | Start echo before prompt; use topic info for endpoint discovery |
| Move/turn action repeated twice | Two Dify feedback rounds | Single-round test preset; later fix normal completion |
| “Task feedback exceeded 1 rounds” | Feedback loop reaches cap instead of clean finish | Fix Dify protocol / agent end conditions |
| Sensor streams work but motor test does not | Different control path, mode, deadband or supply | Verify joystick route, firmware, motor enable and watchdog |
| Static `/odom_raw` while stopped | No position change observed | Move by a known safe method, validate encoder feedback properly |

---

## 12. Prioritized follow-up work

### Priority 0 — safety and deterministic completion

1. Confirm the agent's actual `cmd_vel_pub` field and its `Twist` import; explicitly publish zero on stop/abort/normal completion, with tests proving the message is sent.
2. Add a verified robot-side watchdog for stale velocity commands and an accessible hardware stop/disarm.
3. Add a real action allowlist, including any side-effecting camera-preparation paths.
4. Fix Dify feedback: a completed timed motor action should terminate with a normal user-facing response, not be selected again.
5. Keep the LLM wheel output isolated until all four conditions are verified.

### Priority 1 — controlled robot integration

6. Inspect `ros2 node info /joy_control` while joystick works, and record its topic/service behavior.
7. Characterize direct `/cmd_vel` behavior and confirm whether joystick uses a different motor-control route.
8. Build an independent, normally disarmed velocity bridge with clamps, watchdog, deadman, status reporting and single-owner arbitration.
9. Bench-test one bounded movement with suspended wheels, verified zero output and external stop; then assess wheel odometry.

### Priority 2 — useful multimodal assistant

10. Audit and simplify Dify `microros-v2-en` system/tool instructions; remove unrelated map-destination constraints for ordinary conversation.
11. Test a Qwen vision response that describes actual camera content after `seewhat()`, **without requesting tracking or movement**.
12. Characterize the camera/Mapping conflict by recording node graph, frame rate, host/VM CPU load and active MJPEG client count.
13. Record reproducible versions for Ollama, Dify, Qwen, `multi_brains`, ROS 2 and the actual Yahboom joystick launch command.
14. Confirm camera calibration availability for accurate future vision-guided robotics and SLAM work.

---

## 13. Verification checklist for a future session

- [x] Apple Silicon ↔ bridged Ubuntu network (covered in earlier guide)
- [x] ESP32 + micro-ROS Agent node discovery
- [x] Physical joystick driving of two-wheel Yahboom base
- [x] Concurrent joystick operation and camera viewing (operator reported)
- [x] Camera HTTP GET working at example LAN IP
- [x] Standalone ROS MJPEG camera publisher working (~4–5 FPS)
- [x] Dify application aligned with the English-language LLM agent key
- [x] Local macOS Ollama reachable from Ubuntu VM
- [x] `multi_brains` agent running and returning Dify actions
- [x] `seewhat()` successfully captures a camera frame when ROS camera publisher runs
- [x] Model motion requests generate `Twist` messages on the isolated test topic
- [x] One-round test configuration avoids repetition *within a single request*
- [ ] Meaningful camera description from Qwen after image capture
- [ ] Normal, non-error completion after a single movement
- [ ] Comprehensive action allowlist and PTZ side-effect controls
- [ ] Verified stop command on all termination paths
- [ ] Independent robot-side motor watchdog and hardware emergency stop
- [ ] Physical LLM-controlled wheel movement
- [ ] Verified motor encoders, wheel odometry and navigation
- [ ] Root cause of Mapping/camera-stream interaction

---

## 14. Selected source and documentation pointers

### Local files inspected during the session

```text
~/microros_ws/src/multi_brains/config/llm_agent_utm_test.yaml
~/microros_ws/src/multi_brains/config/llm_agent_utm_single.yaml
~/microros_ws/src/multi_brains/multi_brains/llm_agent_node.py
~/microros_ws/src/multi_brains/multi_brains/controllers/motion_controller.py
~/microros_ws/src/multi_brains/multi_brains/controllers/follow_line_controller.py
~/microros_ws/src/microros_v2_bringup/microros_v2_bringup/camera_driver.py
~/microros_ws/src/microros_v2_bringup/launch/car_base.launch.py
~/microros_ws/src/microros_v2_bringup/launch/bringup_app.launch.py
~/microros_ws/src/microros_v2_bringup/setup.py
```

### Reference projects

- [Project GitHub repository](https://github.com/jcarpio/Yahboom_MicroROS-V2-on-Apple-Silicon)
- [Yahboom MicroROS V2 documentation](https://www.yahboom.net/study/MicroROS-V2/20039)
- [ROS 2 Humble QoS concepts](https://docs.ros.org/en/humble/Concepts/Intermediate/About-Quality-of-Service-Settings.html)
- [Ollama](https://ollama.com/)
- [Dify](https://github.com/langgenius/dify)
- [micro-ROS](https://micro.ros.org/)

**Evidence provenance:** This addendum is based on the actual command outputs, user observations, application behavior and Python/YAML source excerpts shared during the 20 October 2026 session, plus established setup information discussed previously. It does not claim that proposed improvements were implemented. Secrets have been omitted. Capture new logs after any software, network or firmware changes because line numbers and available actions may differ across versions.
