// gx2_fps_overlay.h - real-time FPS overlay drawn into presented images.
//
// Measured at actual presentation (gx2vk::present), averaged over half-second
// windows, with the longest frame interval of the window as a stutter hint.
// The text is rasterised on the CPU with a built-in 5x7 font into a small
// opaque strip and copied into the swapchain image's top-left corner after
// the frame's blit: no shaders, pipelines or extra render passes.
#pragma once
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>

namespace gx2vk::overlay {

// Rows top to bottom; bit 4 is the leftmost of five columns.
inline const uint8_t* glyph(char c) {
    static const uint8_t blank[7] = {};
    static const uint8_t digits[10][7] = {
        {0x0E,0x11,0x13,0x15,0x19,0x11,0x0E}, {0x04,0x0C,0x04,0x04,0x04,0x04,0x0E},
        {0x0E,0x11,0x01,0x02,0x04,0x08,0x1F}, {0x1F,0x02,0x04,0x02,0x01,0x11,0x0E},
        {0x02,0x06,0x0A,0x12,0x1F,0x02,0x02}, {0x1F,0x10,0x1E,0x01,0x01,0x11,0x0E},
        {0x06,0x08,0x10,0x1E,0x11,0x11,0x0E}, {0x1F,0x01,0x02,0x04,0x08,0x08,0x08},
        {0x0E,0x11,0x11,0x0E,0x11,0x11,0x0E}, {0x0E,0x11,0x11,0x0F,0x01,0x02,0x0C}};
    static const uint8_t dot[7] = {0,0,0,0,0,0x0C,0x0C};
    static const uint8_t F[7] = {0x1F,0x10,0x10,0x1E,0x10,0x10,0x10};
    static const uint8_t P[7] = {0x1E,0x11,0x11,0x1E,0x10,0x10,0x10};
    static const uint8_t S[7] = {0x0F,0x10,0x10,0x0E,0x01,0x01,0x1E};
    static const uint8_t m[7] = {0,0,0x1A,0x15,0x15,0x11,0x11};
    static const uint8_t s[7] = {0,0,0x0E,0x10,0x0E,0x01,0x1E};
    static const uint8_t a[7] = {0,0,0x0E,0x01,0x0F,0x11,0x0F};
    static const uint8_t x[7] = {0,0,0x11,0x0A,0x04,0x0A,0x11};
    if (c >= '0' && c <= '9') return digits[c - '0'];
    switch (c) {
    case '.': return dot; case 'F': return F; case 'P': return P; case 'S': return S;
    case 'm': return m; case 's': return s; case 'a': return a; case 'x': return x;
    default: return blank;
    }
}

constexpr unsigned kCellWidth = 6, kCellHeight = 9, kPadding = 2;   // in font pixels

// Strip size, in image pixels, for `text` at integer `scale`.
inline void strip_size(const std::string& text, unsigned scale, unsigned& width, unsigned& height) {
    width = unsigned(text.size() * kCellWidth + kPadding * 2 - 1) * scale;
    height = (kCellHeight + kPadding * 2 - 2) * scale;
}

// Fill `out` (width * height 32-bit texels, row pitch = width) with `text`.
inline void rasterize(const std::string& text, unsigned scale, uint32_t foreground, uint32_t background,
                      uint32_t* out, unsigned width, unsigned height) {
    std::fill(out, out + size_t(width) * height, background);
    for (size_t i = 0; i < text.size(); ++i) {
        const uint8_t* rows = glyph(text[i]);
        const unsigned x0 = unsigned(kPadding + i * kCellWidth) * scale, y0 = (kPadding - 1) * scale;
        for (unsigned row = 0; row < 7; ++row) for (unsigned column = 0; column < 5; ++column) {
            if (!(rows[row] >> (4 - column) & 1)) continue;
            for (unsigned dy = 0; dy < scale; ++dy) {
                const unsigned y = y0 + row * scale + dy;
                if (y >= height) continue;
                for (unsigned dx = 0; dx < scale; ++dx) {
                    const unsigned px = x0 + column * scale + dx;
                    if (px < width) out[size_t(y) * width + px] = foreground;
                }
            }
        }
    }
}

// Rolling presentation statistics.
class Stats {
public:
    using Clock = std::chrono::steady_clock;
    // Returns true when the displayed text changed.
    bool presented(Clock::time_point now) {
        if (last_.time_since_epoch().count()) {
            const double interval = std::chrono::duration<double, std::milli>(now - last_).count();
            worst_ = std::max(worst_, interval);
            ++frames_;
        } else window_ = now;
        last_ = now;
        const double elapsed = std::chrono::duration<double>(now - window_).count();
        if (elapsed < 0.5 || !frames_) return false;
        fps_ = frames_ / elapsed;
        char line[64];
        std::snprintf(line, sizeof(line), "FPS %.1f  %.1fms  max %.1fms", fps_, 1000.0 / fps_, worst_);
        text_ = line;
        frames_ = 0; worst_ = 0; window_ = now;
        return true;
    }
    const std::string& text() const { return text_; }
    double fps() const { return fps_; }
private:
    Clock::time_point last_{}, window_{};
    unsigned frames_ = 0;
    double worst_ = 0, fps_ = 0;
    std::string text_ = "FPS --";
};

}  // namespace gx2vk::overlay
