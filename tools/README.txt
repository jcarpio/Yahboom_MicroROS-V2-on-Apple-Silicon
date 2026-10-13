YAHBOOM MICRO-ROS ESP32-S3 BUILD HELPER — APPLE SILICON / UTM
=============================================================

Tool: build-microros-s3.sh
Documentation version: 2026-10-13
Project: https://github.com/jcarpio/Yahboom_MicroROS-V2-on-Apple-Silicon

PURPOSE
-------
This helper builds ESP-IDF / micro-ROS firmware for the ESP32-S3 used by
Yahboom's MicroROS development examples, from an Ubuntu 22.04.5 ARM64
virtual machine on Apple Silicon (UTM). It provides a command-line build
workflow that can be launched from the VM terminal, a VS Code integrated
terminal, or another editor's terminal.

The tested helper temporarily adjusts a project-specific include path in
micro_ros_espidf_component/esp32_toolchain.cmake, calls `idf.py build`, and
restores the previous toolchain file on normal completion or most handled
failures via a Bash EXIT trap.

This is a build helper, NOT a compiler, a micro-ROS Agent, a flasher, a
VS Code extension, or a macOS-native ESP-IDF installation. The compilation
runs INSIDE the ARM64 Linux guest, not in macOS.

TESTED CONFIGURATION
--------------------
Host:       Apple Silicon Mac running UTM (ARM64 Ubuntu guest)
Guest:      Ubuntu 22.04.5 LTS, aarch64
ESP-IDF:    v5.1.2, with ESP32-S3 Xtensa toolchain
ROS:        ROS 2 Humble tooling; micro-ROS source libraries built for ESP32-S3
User:       yahboom
Script:     ~/esp/tools/build-microros-s3.sh
Projects:   ~/esp/tests_arm64/publisher
            ~/esp/tests_arm64/publisher_clean_test
Component:  ~/esp/extra_components/micro_ros_espidf_component

Verified: all 65 micro_ros_src packages completed; `publisher` built;
incremental rebuild succeeded; separate project with no prior `build/`
succeeded using the existing compiled micro-ROS dependencies; the helper
itself passed an incremental build and restored the toolchain checksum.

NOT VERIFIED: hardware flashing, serial/USB passthrough, Wi-Fi or UDP
connectivity, robot behavior, other Yahboom examples, installation from a
completely empty environment, simultaneous builds, or all possible target
configurations. These require separate validation.

PREREQUISITES
-------------
1. Boot the provided/configured Ubuntu ARM64 VM in UTM.
2. Confirm `uname -m` prints `aarch64`.
3. Install/retain ESP-IDF v5.1.2 and its Xtensa ESP32-S3 tools at
   ~/esp/esp-idf and ~/.espressif, respectively.
4. The following must exist and be complete:
   ~/esp/extra_components/micro_ros_espidf_component/libmicroros.a
   ~/esp/extra_components/micro_ros_espidf_component/esp32_toolchain.cmake
5. The firmware project must contain `CMakeLists.txt` and `sdkconfig`, with:
   CONFIG_IDF_TARGET="esp32s3"
6. The project's top-level CMakeLists.txt must register the micro-ROS
   component directory BEFORE including ESP-IDF's project.cmake. For the
   tested VM layout, this is:

      cmake_minimum_required(VERSION 3.16)
      set(EXTRA_COMPONENT_DIRS "$ENV{HOME}/esp/extra_components")
      include($ENV{IDF_PATH}/tools/cmake/project.cmake)
      project(main)

   Adjust the component path if you change the guest's filesystem layout.
7. The helper script must be installed at:
   ~/esp/tools/build-microros-s3.sh

QUICK START
-----------
From a terminal INSIDE Ubuntu ARM64:

   bash ~/esp/tools/build-microros-s3.sh \
       ~/esp/tests_arm64/publisher

Or for the clean-test copy:

   bash ~/esp/tools/build-microros-s3.sh \
       ~/esp/tests_arm64/publisher_clean_test

For your own project, after adapting its sdkconfig and CMakeLists.txt:

   bash ~/esp/tools/build-microros-s3.sh ~/esp/my_projects/my_app

The command returns a nonzero exit code when validation or the build fails.
A successful run prints COMPILACION CORRECTA (as in the currently tested
script) and lists the generated application .bin and its SHA-256.

OUTPUT
------
Under the firmware project's `build/` directory:

   build/main.bin                         application firmware
   build/main.elf                         ELF executable/debug symbols
   build/bootloader/bootloader.bin        bootloader
   build/partition_table/partition-table.bin  partition table

For the tested publisher project, the successful application image was
823,168 bytes (804 KiB), leaving about 21% of its 1 MiB app partition.
The application name `main` comes from `project(main)` and can differ
in other ESP-IDF projects.

DEVELOPING WITH VISUAL STUDIO CODE ON macOS
-------------------------------------------
Recommended, editor-agnostic workflow:

1. Start the Ubuntu ARM64 VM in UTM.
2. Edit source files either (a) inside Ubuntu using its VS Code/editor,
   (b) from macOS using VS Code Remote - SSH into the VM, if you have
   deliberately configured VM networking and SSH, or (c) via a deliberately
   configured shared folder. VM sharing and SSH are NOT assumed to be
   configured. In a shared-folder workflow, copy the project into the VM's
   Linux filesystem before building if needed; avoid building on 9p shares.
3. Keep the actual toolchain and compilation running in Ubuntu. Open a
   terminal within that environment and run the helper with the full
   Linux path to the project.
4. Inspect errors printed by `idf.py`, edit source and repeat the command.
5. Treat flash/monitor as separate steps. USB passthrough and a serial
   device exposed inside the VM must be configured and verified first.

Using the ESP-IDF extension in VS Code is OPTIONAL. Its own Build button
may invoke `idf.py` without this helper's toolchain adjustment. Until a
separate extension configuration has been verified, use the integrated
terminal and execute the helper explicitly. Avoid independent simultaneous
ESP-IDF builds against the shared micro-ROS component.

SIMPLE NEW PROJECT WORKFLOW
---------------------------
Copy the source-only portion of the working publisher as a template:

   mkdir -p ~/esp/my_projects/my_publisher
   rsync -a --exclude='/build/' \
       ~/esp/tests_arm64/publisher/ ~/esp/my_projects/my_publisher/

Edit `main/main.c` (or other source files), configure network settings and
micro-ROS endpoint for YOUR environment, review sdkconfig, and build:

   bash ~/esp/tools/build-microros-s3.sh \
       ~/esp/my_projects/my_publisher

Do not blindly reuse a sample's Wi-Fi password, SSID or Agent address.
The tested original example referred to micro-ROS domain ID 40, UDP port
8090 and a legacy Agent IP address that may be unsuitable for UTM. Never
publish your own credentials in sdkconfig, source code or build logs.

IMPORTANT LIMITATIONS / SAFETY
------------------------------
* The current tested helper recognizes an existing quoted build/config
  path specifically under /home/yahboom/esp/tests_arm64/ in the shared
  toolchain file, then replaces it with the requested project's path.
  If the VM is installed under another username or the toolchain format
  changes, the helper may abort with "ruta del toolchain no encontrada".
  This is an intentionally narrow, TESTED proof of concept; it is not a
  fully location-independent or multi-user build manager.
* The shared component contains generated, target- and project-dependent
  files. Reusing micro-ROS static libraries is appropriate only when the
  ESP-IDF version, chip target and relevant configuration are compatible.
  A new `sdkconfig`, target, transport, or message package may require
  rebuilding micro-ROS; the helper does not ensure that automatically.
* The helper stores a backup of the shared toolchain and installs a Bash
  EXIT trap. A power loss, SIGKILL or unexpected VM crash can interrupt
  restoration; confirm the path in esp32_toolchain.cmake if that happens.
* Never run two copies of this helper or another ESP-IDF build using the
  same micro-ROS component at the same time.
* Build success does not mean the firmware is correct for the physical
  robot. Flashing may overwrite working firmware. Retain a backup first.
* Nothing in these instructions requires removing files from /mnt/share.

TROUBLESHOOTING
---------------
"undefined reference to rcl_publish / rclc_executor_init":
  Check whether libmicroros.a is complete and contains the symbols:
  source ~/esp/esp-idf/export.sh
  xtensa-esp32s3-elf-nm -g --defined-only \
      ~/esp/extra_components/micro_ros_espidf_component/libmicroros.a \
      | grep -E ' (rcl_publish|rclc_executor_init)$'
  Our initial partial library was 955 KiB; rebuilt complete library ~12 MB.
  Size alone is not proof; inspect symbols. Do not delete source trees.

"Could not find fastcdr compatible version ... (64bit)":
  A host ROS 2 ARM64 prefix leaked into the ESP32 cross-build; inspect
  AMENT_PREFIX_PATH, CMAKE_PREFIX_PATH, PYTHONPATH, LD_LIBRARY_PATH and
  stale package CMakeCache.txt files. See the technical annex.

"ModuleNotFoundError: catkin_pkg / em / lark":
  Some ROS build helpers run under ESP-IDF's isolated Python environment.
  Use that environment, not an unrelated macOS or global Python. The
  tested environment required catkin_pkg, EmPy 3.3.4 and Lark 1.2.2.

"Toolchain path not found":
  The proof-of-concept helper's path matcher is intentionally restrictive.
  Inspect esp32_toolchain.cmake and see the annex before adapting it.

"Main binary differs between project directories":
  Our successful builds produced the same four checked ELF sections but
  different image metadata: compilation time, 32-byte ELF SHA field and
  image checksum. The two 823,168-byte images differed in 37 bytes.
  A different SHA-256 alone does NOT mean the application changed.

"Terminal shows > while pasting":
  Bash is waiting for the end of an unfinished quote or here-document.
  Press Ctrl+C, then create/edit a script in nano instead of pasting a
  very long block directly into the shell.

REFERENCE MATERIAL
------------------
ESP-IDF v5.1.2: https://docs.espressif.com/projects/esp-idf/en/v5.1.2/
ESP-IDF VS Code extension: https://docs.espressif.com/projects/vscode-esp-idf-extension/en/latest/
Repository: https://github.com/jcarpio/Yahboom_MicroROS-V2-on-Apple-Silicon

Read APPLE_SILICON_MICROROS_BUILD_ANNEX.md for the migration, root causes,
local patches, reproducibility evidence, safe new-project workflow and
remaining development work.
