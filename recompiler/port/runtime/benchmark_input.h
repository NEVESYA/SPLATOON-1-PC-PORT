#pragma once
#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <filesystem>
#include <sstream>
#include <string>
#include <vector>

// Opt-in deterministic input in presented-frame coordinates, independent of
// how often VPADRead is polled. Normal controller input never uses this path.
namespace rbrew_benchmark {
inline std::atomic<uint32_t> frame{0}, captured_frame{0};
inline std::atomic<bool> profiling{false};
struct Input {
    uint32_t frame = 0, buttons = 0;
    float lx = 0, ly = 0, rx = 0, ry = 0;
    unsigned touched = 0, x = 0, y = 0; // GamePad pixels, 854x480
};
inline std::vector<Input> read_inputs(std::istream& stream) {
    std::vector<Input> inputs;
    std::string line;
    while (std::getline(stream, line)) {
        if (line.empty() || line[0] == '#') continue;
        Input input;
        std::istringstream row(line);
        if (!(row >> std::dec >> input.frame >> std::hex >> input.buttons >> std::dec
                  >> input.lx >> input.ly >> input.rx >> input.ry
                  >> input.touched >> input.x >> input.y) ||
            (!inputs.empty() && input.frame <= inputs.back().frame) ||
            input.touched > 1 || input.x >= 854 || input.y >= 480 ||
            !(input.lx >= -1 && input.lx <= 1 && input.ly >= -1 && input.ly <= 1 &&
              input.rx >= -1 && input.rx <= 1 && input.ry >= -1 && input.ry <= 1)) {
            std::fprintf(stderr, "[benchmark] invalid input script; automation disabled\n");
            return {};
        }
        inputs.push_back(input);
    }
    return inputs;
}
inline const Input* input_at(const std::vector<Input>& inputs, uint32_t index) {
    const auto it = std::upper_bound(inputs.begin(), inputs.end(), index,
        [](uint32_t f, const Input& input) { return f < input.frame; });
    return it == inputs.begin() ? nullptr : &*std::prev(it);
}
inline bool scripted_input(Input& input) {
    static const char* path = std::getenv("RBREW_INPUT_SCRIPT");
    if (!path || !*path) return false;
    static std::vector<Input> inputs;
    static std::filesystem::file_time_type modified{};
    static uint32_t checked = UINT32_MAX;
    const uint32_t bucket = frame.load(std::memory_order_relaxed) / 60;
    if (checked != bucket) {
        checked = bucket;
        std::error_code error;
        const auto stamp = std::filesystem::last_write_time(path, error);
        if (!error && stamp != modified) {
            std::ifstream file(path);
            auto updated = read_inputs(file);
            if (!updated.empty()) { inputs = std::move(updated); modified = stamp; }
        }
    }
    if (inputs.empty()) return false;
    const auto* current = input_at(inputs, frame.load(std::memory_order_relaxed));
    input = current ? *current : Input{};
    return true;
}
}
