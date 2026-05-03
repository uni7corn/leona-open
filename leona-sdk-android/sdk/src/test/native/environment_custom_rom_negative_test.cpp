#include "../../main/cpp/detection/environment_detector.h"

#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <sys/system_properties.h>

namespace leona {

GlobalState& globals() {
  static GlobalState state;
  return state;
}

}  // namespace leona

extern "C" int __system_property_get(const char*, char* value) {
  value[0] = '\0';
  return 0;
}

namespace {

void fail(const std::string& message) {
  std::cerr << "FAIL: " << message << "\n";
  std::exit(1);
}

void expect_true(bool value, const std::string& message) {
  if (!value) fail(message);
}

const leona::Event* first_event(const leona::EventList& events,
                                const std::string& id) {
  for (const auto& event : events) {
    if (event.id == id) return &event;
  }
  return nullptr;
}

void set_fixture(const char* key, const char* value) {
  if (::setenv(key, value, 1) != 0) {
    fail(std::string("setenv failed for ") + key);
  }
}

}  // namespace

int main() {
  set_fixture("LEONA_ENV_PROP_RO_PRODUCT_MANUFACTURER", "Google");
  set_fixture("LEONA_ENV_PROP_RO_PRODUCT_BRAND", "generic");
  set_fixture("LEONA_ENV_PROP_RO_PRODUCT_MODEL", "Pixel 6 AOSP");
  set_fixture("LEONA_ENV_PROP_RO_PRODUCT_NAME", "aosp_arm64");
  set_fixture("LEONA_ENV_PROP_RO_PRODUCT_DEVICE", "gsi_arm64");
  set_fixture(
      "LEONA_ENV_PROP_RO_BUILD_FINGERPRINT",
      "generic/aosp_arm64/gsi_arm64:15/AP3A/userdebug/test-keys");
  set_fixture("LEONA_ENV_PROP_RO_BUILD_TYPE", "userdebug");
  set_fixture("LEONA_ENV_PROP_RO_BUILD_TAGS", "test-keys");
  set_fixture("LEONA_ENV_PROP_RO_BOOT_VERIFIEDBOOTSTATE", "orange");
  set_fixture("LEONA_ENV_PROP_RO_BOOT_VBMETA_DEVICE_STATE", "unlocked");
  set_fixture("LEONA_ENV_PROP_RO_BOOT_FLASH_LOCKED", "0");
  set_fixture("LEONA_ENV_PROP_RO_BOOT_VERITYMODE", "eio");
  set_fixture("LEONA_ENV_PROP_RO_GSID_IMAGE_RUNNING", "1");
  set_fixture("LEONA_ENV_PROP_RO_TREBLE_ENABLED", "true");
  set_fixture("LEONA_ENV_PROP_RO_KERNEL_QEMU", "0");
  set_fixture("LEONA_ENV_PROP_RO_BOOT_QEMU", "0");
  set_fixture("LEONA_ENV_PROP_QEMU_HW_MAINKEYS", "0");

  set_fixture(
      "LEONA_ENV_FILE__PROC_CPUINFO",
      "Hardware\t: Google Tensor\n"
      "Features\t: fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics\n"
      "CPU implementer\t: 0x41\n"
      "CPU part\t: 0xd44\n"
      "BogoMIPS\t: 38.40\n");
  set_fixture("LEONA_ENV_FILE__PROC_CMDLINE",
              "androidboot.hardware=gs101 "
              "androidboot.verifiedbootstate=orange "
              "androidboot.vbmeta.device_state=unlocked\n");
  set_fixture(
      "LEONA_ENV_FILE__PROC_MOUNTS",
      "/dev/block/dm-1 /system erofs ro,seclabel,relatime 0 0\n"
      "/dev/block/dm-2 /vendor ext4 ro,seclabel,relatime 0 0\n"
      "tmpfs /dev tmpfs rw,seclabel,nosuid,relatime 0 0\n"
      "binder /dev/binderfs binder rw,relatime 0 0\n");
  set_fixture(
      "LEONA_ENV_FILE__PROC_NET_ROUTE",
      "Iface Destination Gateway Flags RefCnt Use Metric Mask MTU Window IRTT\n"
      "wlan0 00000000 0100A8C0 0003 0 0 0 00000000 0 0 0\n");
  set_fixture("LEONA_ENV_DIR__SYS_BUS_VIRTIO_DEVICES", "platform\n");

  const auto events = leona::detection::scan_environment();

  for (const auto& event : events) {
    expect_true(
        event.id.rfind("env.emulator.", 0) != 0 &&
            event.id.rfind("environment.emulator.", 0) != 0 &&
            event.id != "environment.emulator",
        "physical custom AOSP/GSI fixture must not emit emulator evidence: " +
            event.id);
  }

  expect_true(first_event(events, "env.emulator.runtime.qemu_kernel") == nullptr,
              "ro.kernel.qemu=0 must not emit qemu kernel evidence");
  expect_true(first_event(events, "env.emulator.runtime.qemu_boot") == nullptr,
              "ro.boot.qemu=0 must not emit qemu boot evidence");
  expect_true(
      first_event(events, "env.emulator.kernel.virtual_boot_args") == nullptr,
      "custom ROM boot args must not emit virtual boot evidence");
  expect_true(first_event(events, "env.emulator.cpu.hypervisor_flag") == nullptr,
              "physical CPU fixture must not emit hypervisor evidence");
  expect_true(
      first_event(events, "env.emulator.cpu.dummy_virt_hardware") == nullptr,
      "physical CPU fixture must not emit dummy virt evidence");
  expect_true(first_event(events, "env.emulator.sysfs.virtio_devices") == nullptr,
              "custom ROM fixture must not emit virtio sysfs evidence");
  expect_true(
      first_event(events, "env.emulator.fs.virtio_9p_shared_mount") == nullptr,
      "custom ROM fixture must not emit virtio 9p evidence");
  expect_true(first_event(events, "env.emulator.net.qemu_nat_subnet") == nullptr,
              "192.168.x route must not emit qemu NAT evidence");

  std::cout << "PASS custom ROM/GSI native environment negative fixture\n";
  return 0;
}
