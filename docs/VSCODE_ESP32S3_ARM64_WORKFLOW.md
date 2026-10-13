# Develop and Flash ESP32-S3 Firmware with VS Code and the Yahboom Ubuntu ARM64 UTM Image

> **Audience:** Apple Silicon Mac users developing ESP32-S3 / micro-ROS firmware for Yahboom MicroROS V2.
>
> **Verified in this project (13 October 2026):** ESP-IDF v5.1.2 runs inside Ubuntu 22.04 ARM64 under UTM; the ESP32-S3 Xtensa cross-compiler is installed; the micro-ROS component has a built `libmicroros.a`; a `publisher` firmware example and the project's build wrapper compiled successfully. **Not yet verified on physical hardware:** VS Code Remote-SSH access, UTM USB passthrough, flashing, serial output, or ESP32-to-micro-ROS-Agent communications. Those steps below are instructions to test, not claims of completed tests.

## 1. Architecture: where everything runs

```text
Apple Silicon Mac (macOS)
  └── Visual Studio Code (editor and Remote-SSH client)
        └── SSH connection to Ubuntu 22.04 ARM64 in UTM
              ├── ESP-IDF v5.1.2 (host tools run on ARM64)
              ├── Xtensa compiler (generates ESP32-S3 firmware)
              ├── Yahboom micro-ROS component
              └── ESP-IDF build output (.bin files)
                    └── USB passthrough or another supported flashing path
                          └── ESP32-S3 board
```

The Mac **does not compile ARM64 firmware for the ESP32-S3**. Ubuntu/UTM runs ARM64 *host* tools, which cross-compile firmware for the ESP32-S3's Xtensa CPU. Edit in VS Code on macOS, but **build in Ubuntu** using the prepared toolchain.

## 2. Prerequisites and validated paths

| Component | Location / version in the supplied development environment |
| --- | --- |
| Host | Apple Silicon Mac with UTM |
| Guest | Ubuntu 22.04 ARM64 (`aarch64`), user `yahboom` |
| ESP-IDF | `~/esp/esp-idf` — **v5.1.2** |
| ESP32-S3 compiler | `~/.espressif/tools/xtensa-esp32s3-elf/esp-12.2.0_20230208/` |
| ESP-IDF Python | `~/.espressif/python_env/idf5.1_py3.10_env/` |
| Yahboom micro-ROS component | `~/esp/extra_components/micro_ros_espidf_component/` |
| Compiled target library | `~/esp/extra_components/micro_ros_espidf_component/libmicroros.a` |
| Tested build helper | `~/esp/tools/build-microros-s3.sh` |
| Example project | `~/esp/tests_arm64/publisher` |
| ROS 2 | `/opt/ros/humble` (separate from the ESP-IDF target build) |

Start Ubuntu in UTM, open a guest terminal, and check:

```bash
uname -m                       # Expected: aarch64
source ~/esp/esp-idf/export.sh
idf.py --version               # Expected: ESP-IDF v5.1.2
test -s ~/esp/extra_components/micro_ros_espidf_component/libmicroros.a && echo 'micro-ROS library: present'
test -x ~/esp/tools/build-microros-s3.sh && echo 'Build helper: present'
```

A successful compiler/build check does **not** establish that a particular board, camera, or robot is connected.

## 3. Recommended workflow: VS Code on macOS + Remote-SSH

This avoids constantly copying source files between Mac and guest. The code lives on the **Ubuntu guest disk**; VS Code on macOS edits it remotely.

### 3.1 Enable a private SSH connection in Ubuntu

In the Ubuntu VM terminal:

```bash
sudo apt update
sudo apt install openssh-server
sudo systemctl enable --now ssh
hostname -I
```

Choose the guest IP address reachable from the Mac. UTM networking and address assignment vary; `hostname -I` may report multiple addresses. **Do not open SSH to the public Internet or forward port 22 on your router.** Use the private host-to-guest network. Change any shared/default VM password before using SSH and prefer a personal SSH key for ongoing use.

From **macOS Terminal** (replace the IP):

```bash
ssh yahboom@<GUEST_IP>
```

If it cannot connect, verify `systemctl status ssh` in Ubuntu and the UTM network mode. Depending on UTM networking, guest-to-host reachability or a local port forward might need configuration. Do not assume a particular guest IP or port is always correct.

### 3.2 Connect VS Code

1. Install **Visual Studio Code** on macOS and the Microsoft **Remote - SSH** extension.
2. Open Command Palette (`Cmd+Shift+P`) → **Remote-SSH: Connect to Host…**.
3. Enter `yahboom@<GUEST_IP>` and authenticate with your guest account.
4. Once the remote window opens, select **File → Open Folder…** and choose `/home/yahboom/esp/tests_arm64/publisher`, or your own project directory in Ubuntu.
5. Open **Terminal → New Terminal**. Confirm `uname -m` prints `aarch64`. All subsequent terminal commands in this guide run **in the remote Ubuntu terminal**, not macOS.

The Espressif **ESP-IDF VS Code extension is optional**. If installed in the remote Ubuntu extension host, point it to the *existing* ESP-IDF 5.1.2 installation rather than installing a conflicting copy. Its Build/Flash toolbar actions do **not** automatically invoke Yahboom's custom helper script.

## 4. Edit the firmware

Start with a **copy** of the example instead of editing the reference project:

```bash
mkdir -p ~/esp/tests_arm64/my_publisher
rsync -a --exclude='/build/' \
  ~/esp/tests_arm64/publisher/ \
  ~/esp/tests_arm64/my_publisher/
```

This directory is deliberately under `~/esp/tests_arm64/`: the **tested helper has a narrow path matcher** and is not guaranteed to work with arbitrary project paths. Open `/home/yahboom/esp/tests_arm64/my_publisher` using **VS Code Remote-SSH**.

Useful project files:

```text
my_publisher/
├── CMakeLists.txt          # ESP-IDF project + extra component configuration
├── main/
│   ├── CMakeLists.txt      # Sources registered with ESP-IDF
│   └── main.c              # Example application; exact name may vary
├── sdkconfig              # Target and network / micro-ROS options
└── build/                 # Generated after compilation
```

For this image, the project's top-level `CMakeLists.txt` needs to locate the Yahboom component, generally with:

```cmake
cmake_minimum_required(VERSION 3.16)
set(EXTRA_COMPONENT_DIRS "$ENV{HOME}/esp/extra_components")
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(main)
```

**Prefer preserving the known-working example's existing CMake files.** Its component and networking settings may have additional requirements. Edit `main/main.c` in VS Code, save, then compile in the remote terminal.

For an ESP32-S3 target, check the project configuration:

```bash
grep '^CONFIG_IDF_TARGET=' ~/esp/tests_arm64/my_publisher/sdkconfig
# Expected: CONFIG_IDF_TARGET="esp32s3"
```

Review networking, micro-ROS Agent IP/port, Wi-Fi credentials, ROS Domain ID, message types, and pin assignments **for your actual board**. Historical Yahboom examples used ROS Domain ID **40** and UDP port **8090**, but these are *not* universal defaults. Never publish Wi-Fi passwords or API tokens in `sdkconfig` or source files.

## 5. Compile using the prepared ARM64 toolchain

**For the original tested example:**

```bash
bash ~/esp/tools/build-microros-s3.sh ~/esp/tests_arm64/publisher
```

**For the edited project:**

```bash
bash ~/esp/tools/build-microros-s3.sh ~/esp/tests_arm64/my_publisher
```

This helper checks the guest architecture/ESP32-S3 target, temporarily adjusts a **shared generated micro-ROS toolchain path**, runs `idf.py build`, and restores that toolchain on ordinary exit. The wrapper was tested against an existing `publisher_clean_test` project. **The first build of a newly copied or significantly changed project still needs inspection; success is not guaranteed.**

**Do not run two builds simultaneously**: the wrapper temporarily changes a shared configuration file. A crash, force-kill or power failure could interrupt restoration. Review the shared toolchain file before subsequent builds if one is interrupted.

The build artifacts typically appear in:

```text
~/esp/tests_arm64/my_publisher/build/
├── main.bin
├── bootloader/bootloader.bin
├── partition_table/partition-table.bin
└── flasher_args.json or flash_args   # depends on ESP-IDF project/build
```

Confirm which artifacts were generated:

```bash
find ~/esp/tests_arm64/my_publisher/build -maxdepth 2 \
  -type f -name '*.bin' -ls
```

Avoid manually flashing only `main.bin` at an assumed address: an ESP-IDF project may also require bootloader, partition table, and other images at target-specific offsets. ESP-IDF's `idf.py flash` knows how to use the project's generated flash configuration.

### 5.1 What was verified during migration

- ESP-IDF **v5.1.2** and ESP32-S3 cross-compiler were operational on Ubuntu ARM64.
- The micro-ROS component static library `libmicroros.a` was built (about 11.8 MB).
- The `publisher` sample produced a firmware image (`main.bin`, **823,168 bytes** in the recorded test).
- A clean source-directory rebuild and an incremental wrapper build completed successfully.
- Full physical-board flashing and runtime communication **remain unverified**.

## 6. Connect an ESP32-S3 for flashing

There are **two possible approaches**. Use one and ensure the flashing computer genuinely sees the board. **Back up the original firmware/configuration before overwriting a Yahboom controller**, if recovery matters. Consult Yahboom's board-specific firmware recovery procedure first; a build passing does not mean the firmware is safe for your exact robot.

### Option A — USB passthrough to Ubuntu UTM (ESP-IDF runs entirely in the guest)

1. Stop robot motors, disconnect potentially hazardous actuators, and use a known-good **data-capable** USB cable.
2. Connect the ESP32-S3 controller to your Mac. In UTM, open the running VM's **USB devices** controls and attach the correct USB device to Ubuntu. Interface names and available USB features depend on UTM version and VM configuration.
3. In the **Ubuntu guest** inspect available devices:

```bash
lsusb
ls -l /dev/ttyACM* /dev/ttyUSB* 2>/dev/null
```

4. Reconnect the device and compare before/after. If necessary, inspect:

```bash
sudo dmesg | tail -40
```

5. Confirm the serial device really belongs to the ESP32-S3; do **not** assume `/dev/ttyUSB0` without checking. A board may expose a native USB/JTAG interface (`ttyACM*`) or an external serial bridge (`ttyUSB*`). Enter download mode using the board's documented BOOT/RESET procedure if required.
6. If Linux serial permissions are the only obstacle, inspect `ls -l /dev/ttyACM0` (or the actual device) and, on Ubuntu installations using the `dialout` group, run `sudo usermod -aG dialout "$USER"`, then **log out and back in**. Do not use `chmod 777` on serial devices.
7. From the **remote Ubuntu terminal**, after verifying the correct project and port:

```bash
source ~/esp/esp-idf/export.sh
cd ~/esp/tests_arm64/my_publisher
idf.py -p /dev/ttyACM0 flash       # EXAMPLE ONLY: replace with confirmed port
idf.py -p /dev/ttyACM0 monitor     # EXAMPLE ONLY: replace with confirmed port
```

Press `Ctrl+]` to quit ESP-IDF's serial monitor. If USB passthrough disconnects during reset/bootloader switching, reattach the newly enumerated interface in UTM and retry after confirming the correct port. **Do not flash until the board is identified and a recovery plan exists.**

### Option B — Build in Ubuntu, flash from macOS

If UTM USB passthrough is unreliable, keep the build in Ubuntu and flash through a native macOS serial interface. This is a **proposed alternative, not validated for this image**.

1. Identify the actual ESP32-S3 serial interface on **macOS** (`ls /dev/cu.*` before and after connecting it).
2. Transfer the **complete** built firmware artifacts plus ESP-IDF flash-argument metadata to the Mac with `scp` or VS Code's remote file tools.
3. Use a properly installed, compatible `esptool` / ESP-IDF on the Mac, preserving the **exact offsets and images defined by that project**, and confirm the chip, flash layout, and security settings before flashing. Do **not** guess offsets or run a single-file flash command without the build's flash configuration.

This method separates compilation from flashing; it requires an additional toolchain and careful artifact handling. For first attempts, Option A is easier **if** USB passthrough works.

## 7. Check serial logs and micro-ROS communications

After a successful flash, monitor boot messages. A running firmware image does not automatically establish ROS 2 communications. For network-based micro-ROS, independently check:

- ESP32-S3 Wi-Fi association and IP address.
- The guest VM's reachable IP address (not necessarily the Mac's IP).
- UDP connectivity/firewall and the Agent port configured by the firmware.
- `ROS_DOMAIN_ID` and Yahboom transport/settings consistency.

The micro-ROS Agent is built in a **separate** workspace, so sourcing only `/opt/ros/humble` may not expose its executable:

```bash
source /opt/ros/humble/setup.bash
source ~/microros_agent_ws/install/setup.bash
ros2 pkg executables micro_ros_agent
```

If the firmware uses UDP on port **8090**, the following is a **conditional example**, not a universal command:

```bash
ros2 run micro_ros_agent micro_ros_agent udp4 --port 8090
```

Run `ros2 run micro_ros_agent micro_ros_agent --help` if the installed agent's command-line options differ. Verify actual connection logs before expecting ROS topics. Launching an agent or listing a topic alone does not establish an operating hardware link.

## 8. Troubleshooting

| Symptom | Check / suggested action |
| --- | --- |
| VS Code cannot connect | Confirm guest IP, Ubuntu `ssh` service, UTM private networking, local firewall and host reachability. |
| `idf.py: command not found` | Run `source ~/esp/esp-idf/export.sh` in the **Ubuntu** terminal, not macOS. |
| `uname -m` reports `arm64` on Mac but no `aarch64` in remote shell | VS Code terminal is likely **local**, not connected to Ubuntu. |
| `sdkconfig.h: No such file` | The shared generated toolchain may refer to the wrong project's `build/config`; inspect the helper result. |
| Fast-CDR or unexpected ROS host libraries appear in firmware build | Avoid leaking host ROS environment into the ESP32 cross-build; start a fresh Ubuntu terminal without sourcing ROS 2. |
| New message type compiles headers but fails linking | Rebuild target micro-ROS libraries with required message packages; cached `libmicroros.a` may be insufficient. |
| Serial port absent in Ubuntu | Check USB cable, UTM USB attachment, port re-enumeration, `lsusb`, and `dmesg`. |
| `Permission denied: /dev/tty...` | Inspect the device group; add guest user to `dialout` if applicable, then reconnect/re-login. |
| Flash succeeds, no ROS topics | Check serial logs, network/Agent address, transport and Domain ID. |
| ESP-IDF VS Code Build button behaves differently | Use the project's **explicit build helper in the remote Ubuntu terminal** until the extension tasks have been tested with its shared toolchain setup. |

## 9. Safety, security, and publication notes

- **Back up factory firmware** and identify the correct target board before overwriting the ESP32-S3. Follow Yahboom recovery guidance; flash may erase device-specific settings.
- **Do not energize robot actuators during first flashing and debugging.** Physical motion, servos and pin assignments are outside the scope of the verified build tests.
- Change any distributed/default Ubuntu credentials; do not expose the guest's SSH service publicly.
- Review `sdkconfig`, `sdkconfig.defaults`, source, `.env`, logs and generated output for Wi-Fi passwords and secrets before committing them.
- Keep project sources on Ubuntu's native filesystem. UTM 9p shared folders may not preserve all Linux filesystem behaviors and should **not** be cleaned indiscriminately.
- A working sample build does not guarantee binary compatibility with modified ROS message interfaces, firmware transport options, or different ESP32 variants.

## 10. References

- [Espressif ESP-IDF v5.1.2 programming guide](https://docs.espressif.com/projects/esp-idf/en/v5.1.2/esp32s3/)
- [ESP-IDF VS Code extension documentation](https://docs.espressif.com/projects/vscode-esp-idf-extension/en/latest/)
- [VS Code Remote-SSH documentation](https://code.visualstudio.com/docs/remote/ssh)
- [micro-ROS documentation](https://micro.ros.org/)
- [Yahboom Apple Silicon project](https://github.com/jcarpio/Yahboom_MicroROS-V2-on-Apple-Silicon)
- [UTM VM distribution](https://huggingface.co/datasets/enkire/Yahboom-MicroROS-V2-Ubuntu-22.04-ARM64-UTM)

---

**Documentation status:** build steps are grounded in the verified October 2026 Ubuntu ARM64 migration. Remote editing, USB flashing, serial monitoring and physical robot tests require independent validation with the recipient's hardware and UTM setup.
