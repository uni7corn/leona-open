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

extern "C" int __system_property_get(const char* key, char* value) {
    const std::string prop = key ? key : "";
    std::string fixture;
    if (prop == "nemud.player_package") {
        fixture = "com.netease.mumu";
    } else if (prop == "nemud.player_engine") {
        fixture = "MuMuPlayer";
    } else if (prop == "nemud.player_uuid") {
        fixture = "8f56b1f4-8d99-4a47-b13a-611d0f337eaa";
    } else {
        value[0] = '\0';
        return 0;
    }

    std::strncpy(value, fixture.c_str(), PROP_VALUE_MAX - 1);
    value[PROP_VALUE_MAX - 1] = '\0';
    return static_cast<int>(std::strlen(value));
}

namespace {

void fail(const std::string& message) {
    std::cerr << "FAIL: " << message << "\n";
    std::exit(1);
}

void expect_true(bool value, const std::string& message) {
    if (!value) fail(message);
}

const leona::Event* first_event(const leona::EventList& events, const std::string& id) {
    for (const auto& event : events) {
        if (event.id == id) return &event;
    }
    return nullptr;
}

}  // namespace

int main() {
    const auto events = leona::detection::scan_environment();
    const auto* metadata =
        first_event(events, "env.emulator.runtime.guest_metadata_props");

    expect_true(metadata != nullptr, "MuMu guest metadata event missing");
    expect_true(
        metadata->evidence.find("nemud.player_uuid=<redacted>") != std::string::npos,
        "MuMu player UUID should be redacted in native evidence");
    expect_true(
        metadata->evidence.find("8f56b1f4-8d99-4a47-b13a-611d0f337eaa") == std::string::npos,
        "MuMu player UUID raw value leaked into native evidence");
    expect_true(
        metadata->evidence.find("metadataPropCount=3") != std::string::npos,
        "metadata prop count should include redacted UUID");

    std::cout << "PASS environment metadata redaction evidence: "
              << metadata->evidence << "\n";
    return 0;
}
