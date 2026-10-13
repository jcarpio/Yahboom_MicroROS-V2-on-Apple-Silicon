# Technical Annex — Building Yahboom micro-ROS ESP32-S3 Firmware on Apple Silicon

**Project:** [Yahboom_MicroROS-V2-on-Apple-Silicon](https://github.com/jcarpio/Yahboom_MicroROS-V2-on-Apple-Silicon)  
**Environment validated:** Ubuntu 22.04.5 LTS ARM64 in UTM on Apple Silicon; ESP-IDF **v5.1.2**; micro-ROS / ROS 2 Humble; ESP32-S3 Xtensa firmware toolchain  
**Validation date:** 13 October 2026  
**Status:** Firmware **build verified**; on-device execution, USB flashing and ROS communication **not yet verified**.

> **Scope and provenance.** This is a technical record of an actual migration and debugging session, not a claim that every Yahboom example is supported. The existing UTM VM already contained ROS 2 Humble and other robotics tools. The public GitHub repository's live file layout could not be inspected during preparation; adapt the proposed placement and links to its actual structure. This is a community integration, not an official Yahboom or Espressif support claim.

## 1. Why this work was necessary

Yahboom's MicroROS V2 educational platform divides responsibilities between a computer running ROS 2 and an ESP32 microcontroller running micro-ROS. The vendor's VM-oriented materials emphasize a conventional PC/VM workflow and describe macOS as unsupported for the product's supplied development environment. The goal of this project was **not** to run ESP32-S3 firmware natively on Apple Silicon: it was to use an **ARM64 Ubuntu guest in UTM**, hosting native ARM64 build tools that cross-compile for the ESP32-S3's **Xtensa** architecture.

Original working materials came from an **x86_64 VMware Ubuntu** environment. The migration retained Yahboom's sources and required reconstructing architecture-specific tools. Copying x86_64 executables, compiled ROS libraries, cached CMake results or ESP32 binaries into ARM64 indiscriminately is not a viable migration strategy.

### Architecture map

```text
macOS on Apple Silicon (M-series CPU)
   |
   +-- Editor: VS Code, another IDE, or macOS terminal
   |
   +-- UTM: Ubuntu 22.04.5 ARM64 guest (aarch64)
         |
         +-- ESP-IDF 5.1.2 (ARM64 host scripts + native tools)
         +-- Xtensa ESP32-S3 cross-compiler (runs on ARM64)
         +-- micro_ros_dev (host ROS/CMake build tools)
         +-- micro_ros_src (libraries cross-compiled for ESP32-S3)
         +-- build-microros-s3.sh -> idf.py build
                  |
                  +-- bootloader.bin
                  +-- partition-table.bin
                  +-- main.bin (ESP32-S3 firmware)

ESP32-S3 hardware  <-- flashing/USB or other transport: NOT YET TESTED
      |
      +-- micro-ROS Agent on Ubuntu (runtime network integration: NOT YET TESTED)
```

**Crucial distinction:** the VM being ARM64 does **not** make the firmware ARM64. The output image is for **ESP32-S3 / Xtensa**.

## 2. Tested files and version matrix

These are paths within the tested guest under the `yahboom` account; they are **not paths on macOS**:

| Role | Tested path / version |
|---|---|
| Ubuntu | 22.04.5 LTS, `uname -m` = `aarch64` |
| ESP-IDF source | `~/esp/esp-idf`, Git tag `v5.1.2` |
| ESP-IDF Python | `~/.espressif/python_env/idf5.1_py3.10_env` |
| ESP32-S3 cross tools | `~/.espressif/tools/xtensa-esp32s3-elf/esp-12.2.0_20230208/` |
| Yahboom example sources | `~/esp/base_samples`, `~/esp/microROS_samples` |
| ESP-IDF micro-ROS component | `~/esp/extra_components/micro_ros_espidf_component` |
| Host build dependencies | `<component>/micro_ros_dev` |
| Target ROS libraries | `<component>/micro_ros_src` |
| Aggregated static library | `<component>/libmicroros.a` |
| Verified original application | `~/esp/tests_arm64/publisher` |
| Independent source-only copy | `~/esp/tests_arm64/publisher_clean_test` |
| Build helper | `~/esp/tools/build-microros-s3.sh` |
| Build evidence report | `~/esp/ESP32S3_MICROROS_ARM64_BUILD.txt` |

The original `~/esp/microROS_samples/publisher` was preserved. The CMake adjustment required for ARM64 was performed in a **separate example copy**.

## 3. The debugging history: problem, cause and fix

| Stage | Observed symptom | Root cause / corrective action |
|---|---|---|
| ESP-IDF toolchain | x86_64 tools from VMware were unusable on ARM64 | Checked out matching **ESP-IDF v5.1.2** and ran its native ARM64 `install.sh esp32s3`; verified an ordinary ESP32-S3 LED example built successfully. |
| Project CMake discovery | Component path in sample not resolved reliably | In the **test copy only**, changed `set(EXTRA_COMPONENT_DIRS "~/esp/extra_components")` to `set(EXTRA_COMPONENT_DIRS "$ENV{HOME}/esp/extra_components")` before `project.cmake`. |
| Colcon Python dependencies | `ModuleNotFoundError: catkin_pkg`, later `em`, then `lark` | Installed missing modules into **ESP-IDF's isolated Python environment**; observed working versions include **EmPy 3.3.4** and **Lark 1.2.2**. A `catkin_pkg` 1.1.1 install was also used. Do not assume global system Python is sufficient. |
| `libmicroros.mk` | `touch` failed for ROS packages absent from the fetched sources | Guarded five package-specific `touch .../COLCON_IGNORE` operations with a directory existence check. Kept a backup of the original Makefile. |
| Host tool bootstrap | `ament_cmakeConfig.cmake` missing | Completed `micro_ros_dev` host build separately; **62** host packages compiled successfully. The directory-based Make target had incorrectly treated a partial install as complete. |
| ESP-IDF include discovery | ESP32 header `<sdkconfig.h>` not found | Found a stale generated `esp32_toolchain.cmake` referencing an old project's `build/config` path. Regenerated it for the currently built project. |
| Target ROS interfaces | `builtin_interfaces` CMake rejected Fast-CDR `1.0.29 (64bit)` from `/opt/ros/humble` | The ARM64 **host ROS** installation leaked into the **ESP32 cross-build**. Removed inherited ROS environment variables before sourcing `micro_ros_dev/install/local_setup.sh`, and cleared the contaminated `builtin_interfaces` CMake cache. |
| Stale build targets | `idf.py build` continued to link against old static library | `micro_ros_src/install` already existed, so Make considered it current. Touched the source directory, ran `idf.py reconfigure`, and verified **65 micro_ros_src packages** finished successfully. |
| Linking | `undefined reference to rcl_publish`, `rclc_executor_init`, `rmw_uros_options_set_udp_address`, etc. | `libmicroros.a` was only **955 KiB**, assembled while target libraries were incomplete. Regenerated it from the completed installed `.a` files using the component's original Makefile rule. It became **~12 MiB** and exported the required symbols. |
| Independent source-only build | Shared toolchain still pointed to original `publisher/build/config` | Backed up the generated shared toolchain; changed that path for the second example; built successfully from a new directory without `build/`; restored the original toolchain. |
| Developer convenience | Switching projects required a manual toolchain edit | Added a **proof-of-concept build wrapper** with an automatic backup, path replacement, `idf.py build` and EXIT-trap restore. It passed an incremental build and toolchain checksum verification. |

### Relevant Makefile isolation patch

The corrected `micro_ros_src/install` recipe in the tested component includes:

```makefile
cd $(UROS_DIR); \
unset AMENT_PREFIX_PATH CMAKE_PREFIX_PATH COLCON_PREFIX_PATH PYTHONPATH LD_LIBRARY_PATH; \
PATH="$(subst /opt/ros/$(ROS_DISTRO)/bin,,$(PATH))"; \
. ../micro_ros_dev/install/local_setup.sh; \
colcon build ...
```

The actual Makefile also passes the critical **ESP-IDF include flags (`IDF_INCLUDES`)** and the ESP32 toolchain. The ellipsis above is explanatory shorthand, **not a complete Makefile recipe**. Directly running a simplified `colcon build` without the same flags is not equivalent to the original build.

### Why `make clean` was intentionally avoided

The component's `clean` target removes `micro_ros_dev` and `micro_ros_src` trees as well as generated includes and toolchain files. It is **not** a harmless cache-only clean. Rebuilding the components and downloading sources again is potentially slow, space-intensive and vulnerable to upstream changes. Back up the VM or component before changing its Makefile, and avoid broad cleanup commands while troubleshooting.

## 4. Verified outputs and reproducibility evidence

The finished `publisher` run reported:

```text
Summary: 65 packages finished [28.4s]    # target micro-ROS packages
Generated .../publisher/build/main.bin
Project build complete.
main.bin: 823168 bytes (0xc8f80)
Smallest app partition: 0x100000 bytes (1 MiB)
Free app partition space: ~21%
```

Other outputs included a **20,896-byte bootloader** and a **3,072-byte partition table**. The original firmware checksum was:

```text
306930864c9f3b23c33be84162d5be0b59baf61b010f6b3949230feac004c69d  main.bin
```

Three types of build validation took place:

1. **Full working build of the prepared publisher example:** success, `main.bin` produced.
2. **Incremental rebuild of the same project:** success; its SHA-256 matched exactly.
3. **Independent project folder without `build/`:** success while **reusing the existing micro-ROS dependency build**; this was not a clean-room reinstall of ESP-IDF or all 65 micro-ROS packages.

The independent project's application image had the same length but a different overall SHA-256:

```text
publisher:            306930864c9f3b23c33be84162d5be0b59baf61b010f6b3949230feac004c69d
publisher_clean_test: 5758c91a05c06b1ab9003de75408ce87e46ab5f5df51a66106c007697948c51c
```

Detailed comparison identified **37 different bytes of 823,168**: **4 bytes** in the build-time field; **32 consecutive bytes** consistent with ESP-IDF's `app_elf_sha256` metadata field; and **1 byte** at the final image checksum. Both images have the same segment sizes, load addresses, entry point, and ESP-IDF `sdkconfig`. Four ELF sections were independently checked and had identical SHA-256 hashes:

- `.iram0.text`
- `.flash.text`
- `.flash.rodata`
- `.dram0.data`

Thus the comparisons provide strong evidence that the investigated discrepancy is in **build metadata/checksum rather than those checked application sections**. They do not constitute a hardware runtime test or a formal proof of all possible semantic equivalence.

## 5. The build helper: current behavior and scope

**File:** `~/esp/tools/build-microros-s3.sh`

This helper is an optional **Bash wrapper** around the existing native ARM64/ESP32-S3 toolchain. In the version tested, it:

1. Takes **one Linux guest project path** as an argument and resolves it with `realpath`.
2. Requires `uname -m = aarch64`, a root `CMakeLists.txt`, and a `sdkconfig` containing `CONFIG_IDF_TARGET="esp32s3"`.
3. Checks for the shared component's `libmicroros.a` and `esp32_toolchain.cmake`.
4. Backs up the shared generated toolchain to a temporary file within the component.
5. Installs an EXIT trap to restore that file, then sources `~/esp/esp-idf/export.sh`.
6. Restricts build parallelism (`CMAKE_BUILD_PARALLEL_LEVEL=2`, `MAKEFLAGS=-j2`) and sets `COLCON_DEFAULTS_FILE=/dev/null`.
7. Replaces the existing, **hard-coded** quoted toolchain path matching `/home/yahboom/esp/tests_arm64/<name>/build/config` with the requested project's `<project>/build/config`.
8. Runs `idf.py build` in the project directory.
9. Displays the resulting `build/*.bin` and its SHA-256, then restores the original toolchain on exit.

The tested wrapper was invoked as:

```bash
bash ~/esp/tools/build-microros-s3.sh \
  ~/esp/tests_arm64/publisher_clean_test
```

It completed with exit code **0**, and an independent SHA-256 check confirmed the toolchain was restored to its original bytes. The complete helper belongs next to this guide in the release/repository; this document is **not** a substitute for the actual `.sh` file.

**Limitations of the tested script:**

- The path matcher is deliberately narrow and assumes the source path uses `/home/yahboom/esp/tests_arm64/`. It will **not automatically adapt to arbitrary usernames or arbitrary existing source paths**. This is the actual tested behavior, not an advertised general capability.
- It adjusts a generated shared toolchain, not a per-project isolated component. **Do not build projects concurrently.**
- It assumes the precompiled static library is compatible with the selected target, middleware, message types, transport and configuration. It does not automatically establish these conditions or rebuild micro-ROS when they change.
- Its EXIT trap handles normal completion and many errors, but cannot restore the file after a guest crash, `SIGKILL` or power loss. Inspect the toolchain after an interrupted run.
- A successful incremental build does not demonstrate that this helper will configure every brand-new project; project-specific CMake settings must be correct.

**Engineering improvement for a future release:** generate **project-local** or configuration-keyed toolchains and libraries, rather than replacing the shared toolchain file. Add a lock to prevent simultaneous builds and check ESP-IDF version, target, middleware and relevant sdkconfig values before using cached libraries. These changes were **proposed, not implemented/tested** in this session.

## 6. Creating a new ESP32-S3 micro-ROS project

### 6.1 Start with a working source-only template

In the Ubuntu guest:

```bash
mkdir -p ~/esp/my_projects/my_publisher
rsync -a --exclude='/build/' \
  ~/esp/tests_arm64/publisher/ \
  ~/esp/my_projects/my_publisher/
```

This copies source and `sdkconfig` but does **not** copy the project's previous build directory. Treat the copied sample as a starting point rather than production-ready firmware.

### 6.2 Register the component in CMake

In the project's **top-level** `CMakeLists.txt`, before including the ESP-IDF `project.cmake`:

```cmake
cmake_minimum_required(VERSION 3.16)
set(EXTRA_COMPONENT_DIRS "$ENV{HOME}/esp/extra_components")
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(main)
```

A typical `main/CMakeLists.txt` uses an ESP-IDF component registration, for example:

```cmake
idf_component_register(SRCS "main.c" INCLUDE_DIRS ".")
```

The exact `REQUIRES` or `PRIV_REQUIRES` entries depend on the source's headers and components. Prefer starting from the tested example if you depend on its network or micro-ROS setup.

### 6.3 Write your application

Edit `main/main.c` and any other source files. For a basic micro-ROS publisher, the building blocks include a node, message type support, publisher, executor/timer, and a micro-ROS Agent endpoint. Keep the example's working initialization and FreeRTOS task structure while you gradually change its behavior.

**Important:** changing ROS message packages can introduce additional target libraries that the existing `libmicroros.a` does not contain. Do not assume a successful `#include` means every message type will link. Rebuild the micro-ROS target libraries when additional packages are required.

### 6.4 Configure target and networking

The existing verified project has:

```ini
CONFIG_IDF_TARGET="esp32s3"
CONFIG_IDF_TARGET_ESP32S3=y
```

The Yahboom sample configuration previously included micro-ROS domain **40**, Agent UDP port **8090**, and an Agent IP assigned to a previous network. Set the actual Agent IP, network SSID and password according to **your own** VM and ESP32 setup. Check `sdkconfig`, `sdkconfig.defaults`, source files and other configuration files for secrets **before sharing any project or VM**. No network connectivity was validated in this build session.

### 6.5 Build inside the Ubuntu guest

```bash
bash ~/esp/tools/build-microros-s3.sh \
  ~/esp/my_projects/my_publisher
```

Output should appear under the project's `build/` folder, such as `build/main.bin`, `build/bootloader/bootloader.bin` and `build/partition_table/partition-table.bin`.

**Scope note:** this particular path-rewriting helper has only been **executed successfully** against the existing `publisher_clean_test`. For a genuinely new project, check the toolchain path and monitor the first CMake configuration. The standalone `idf.py` workflow can be used after a correctly configured toolchain, but does not itself protect or restore the shared file.

## 7. Workflow from macOS with Visual Studio Code or another editor

The most important rule is: **edit where convenient, build where the installed toolchain lives**.

### Option A — VS Code inside the Ubuntu VM (simplest guest-native setup)

1. Open UTM and boot the Ubuntu ARM64 guest.
2. Open VS Code or another text editor **inside Ubuntu**, if installed.
3. Open the project directory (e.g., `/home/yahboom/esp/my_projects/my_publisher`).
4. Edit files and open the editor's integrated terminal.
5. Run the helper using the **Ubuntu path**. Check the generated `.bin` under `build/`.

The ESP-IDF VS Code extension is **optional** and is not required to execute the script. Its standalone Build command may bypass the helper's backup/path adjustment, so prefer the terminal command until the extension is explicitly configured and tested.

### Option B — VS Code on macOS + Remote - SSH to the Ubuntu guest

Use this if Ubuntu has a reachable SSH service and the UTM network configuration permits a connection. These facilities were **not** verified in this project session.

1. Boot Ubuntu in UTM; ensure its network is reachable from macOS.
2. Configure OpenSSH server and authorized access in the VM according to your security policy. Do not expose it publicly or include credentials/authorized keys in a distributed image.
3. In macOS VS Code, install **Remote - SSH**, connect to the Ubuntu guest, and open the Linux project directory.
4. Use the **remote Linux terminal** in VS Code to run `bash ~/esp/tools/build-microros-s3.sh /home/yahboom/esp/my_projects/my_publisher`.
5. Compiler errors and generated files remain in the Ubuntu guest. VS Code is only the editor/client; **the build does not run under macOS's toolchain**.

This is a suggested workflow, not a claim that SSH or Remote - SSH is already configured in the downloadable VM.

### Option C — VS Code on macOS + UTM shared folder

1. Arrange a supported macOS–UTM shared-folder connection.
2. Edit project files on macOS and transfer/copy them to a local directory in Ubuntu.
3. **Build on the VM's local Linux filesystem**, not directly on a 9p share when avoidable; cross-filesystem metadata, permissions, symlinks and performance can differ.
4. Use the same build helper command in a guest terminal.

**Never run scripts that indiscriminately clean or delete `/mnt/share`.** Shared-folder management is a separate user-controlled task.

### Using the VS Code ESP-IDF extension

Espressif's official extension supports remote/headless setups and ESP-IDF projects, but its extension-managed installation and task flows can differ from the prepared `~/esp/esp-idf` tree. If enabling it in the VM, select/configure the **existing v5.1.2 installation**, confirm the actual Python and tool paths, and **do not assume its Build button uses this helper**. The reliable verified command is still the wrapper in the integrated guest terminal.

- [Espressif VS Code extension installation](https://docs.espressif.com/projects/vscode-esp-idf-extension/en/latest/installation.html)
- [Espressif VS Code project setup](https://docs.espressif.com/projects/vscode-esp-idf-extension/en/latest/startproject.html)

### Flashing and serial monitor (not yet validated)

For a properly connected and identified ESP32-S3, ESP-IDF ordinarily supports `idf.py -p <PORT> flash` and `idf.py -p <PORT> monitor`. However, **USB/serial passthrough in UTM**, board-specific wiring/reset behavior, backup and the correct device path must be established before flashing. Do **not** issue a flashing command merely because the build passed. It may overwrite factory firmware.

## 8. Troubleshooting guide

| Symptom | Diagnostic next action |
|---|---|
| `ModuleNotFoundError` (`catkin_pkg`, `em`, `lark`) | Check the ESP-IDF Python path and install the compatible package inside its isolated venv, not macOS/system Python. |
| `fastcdr` found at `/opt/ros/humble` but rejected as `64bit` | Inspect inherited ROS environment prefixes and contaminated CMake caches. Keep host ROS libraries out of target cross-linking. |
| `fatal error: sdkconfig.h: No such file` | Inspect the shared `esp32_toolchain.cmake` for the correct `<project>/build/config` path. |
| `undefined reference to rcl_publish` and `rclc_*` | Check whether `libmicroros.a` includes the symbols; make sure target library compilation actually finished. |
| Make says `Nothing to be done` although dependencies are missing | The directory-based install target may exist despite a partial build. Check timestamps and library inventory; do not equate a directory's existence with build success. |
| New project appears to compile with the old project's settings | Investigate shared toolchain and other generated cross-project state; avoid concurrent builds. |
| VS Code Build button behaves differently | Invoke the known-good helper from the **Ubuntu terminal** until custom IDE task integration is tested. |
| Terminal shows the `>` prompt after a long paste | The shell is waiting for closing quote/here-document. Use Ctrl+C and edit a script with `nano` or VS Code instead. |
| `main.bin` differs only in SHA-256 | Compare image information, sections and metadata before concluding the executable behavior changed. |

Useful non-destructive checks:

```bash
uname -m
source ~/esp/esp-idf/export.sh
idf.py --version
ls -lh ~/esp/extra_components/micro_ros_espidf_component/libmicroros.a
xtensa-esp32s3-elf-nm -g --defined-only \
  ~/esp/extra_components/micro_ros_espidf_component/libmicroros.a \
  | grep -E ' (rcl_publish|rclc_executor_init)$'
```

## 9. Distribution and security review before publishing a VM

A working developer VM is not automatically safe or legally suitable for public distribution.

- **Secrets:** audit `sdkconfig`, `sdkconfig.defaults`, source files, shell history, Wi-Fi SSIDs/passwords, tokens, SSH keys, `authorized_keys`, network configuration and logs. Avoid printing actual secrets into an issue or documentation.
- **VM identity:** review hostname, user accounts, SSH host keys, cached credentials and any guest integration/automount settings.
- **Shared folders:** do not publish host-specific `/mnt/share` paths or perform automated deletion in the shared host folder.
- **Licenses:** verify license/redistribution permissions for Yahboom material, ROS and Espressif dependencies, third-party examples, media and model weights. Preserve notices; do not infer blanket redistribution permission.
- **Disk images:** deleting sensitive files from a VM does not guarantee their bytes are unrecoverable from a virtual disk image. Consider preparing a sanitized fresh image instead of publishing an arbitrarily reused development disk.
- **Provenance:** label tested functionality precisely. Firmware compilation is validated; physical robot functionality, agent communications, flashing, neural-network acceleration and sample coverage may not be.

## 10. Recommended repository integration

A suggested arrangement (adapt to the actual repository; **not verified as its current layout**):

```text
Yahboom_MicroROS-V2-on-Apple-Silicon/
├── README.md                             # existing project introduction
├── docs/
│   └── APPLE_SILICON_MICROROS_BUILD_ANNEX.md
└── tools/
    ├── build-microros-s3.sh              # actual validated Bash script
    └── README.txt                        # quick tool instructions
```

Suggested snippet to insert in the repository's main `README.md`:

````markdown
### ESP32-S3 firmware development on Apple Silicon

The ARM64 UTM environment includes an ESP-IDF v5.1.2 / micro-ROS build
workflow for ESP32-S3 firmware. The `publisher` sample has been built and
reproduced from a separate source-only project folder. Hardware flashing
and runtime ROS networking remain untested.

- [Build helper instructions](tools/README.txt)
- [Technical migration and troubleshooting annex](docs/APPLE_SILICON_MICROROS_BUILD_ANNEX.md)

Build inside the Ubuntu ARM64 guest:

```sh
bash ~/esp/tools/build-microros-s3.sh ~/esp/tests_arm64/publisher
```
````

**Do not upload only these documents** if users are expected to execute the tool: also include the **actual reviewed `.sh` script** and ensure its assumptions match the distributed image. The script is currently present inside the guest; this annex describes its tested behavior, not a byte-for-byte verified repository copy.

## 11. Further validation roadmap

1. Test the helper with a **different Yahboom micro-ROS example**, not another `publisher` copy.
2. Make the toolchain independent of the `yahboom` username and source project path; introduce a build lock and target/config checks.
3. Verify a full fresh VM install/bootstrap with no prebuilt `micro_ros_src` libraries.
4. Confirm safe ESP32-S3 USB passthrough, backup/restore of factory firmware, and flashing.
5. Test the actual Agent IP, UDP port, domain and communication with the ROS 2 Humble micro-ROS Agent.
6. Sanitize the publicly distributable VM and complete the third-party license review.

## References

- [ESP-IDF v5.1.2 programming guide](https://docs.espressif.com/projects/esp-idf/en/v5.1.2/)
- [ESP-IDF `idf.py` frontend](https://docs.espressif.com/projects/esp-idf/en/v5.1.2/esp32c6/api-guides/tools/idf-py.html)
- [Espressif VS Code extension](https://docs.espressif.com/projects/vscode-esp-idf-extension/en/latest/)
- [Yahboom MicroROS V2 product description](https://category.yahboom.net/es/products/microros-v2)
- [Community repository](https://github.com/jcarpio/Yahboom_MicroROS-V2-on-Apple-Silicon)

---

*This annex is a record of a verified cross-compilation exercise on an existing prepared VM. It is not an official hardware certification or proof of a complete fresh-install reproducible toolchain.*
