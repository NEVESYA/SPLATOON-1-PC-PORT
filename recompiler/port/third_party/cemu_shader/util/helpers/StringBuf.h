// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. See LICENSE.txt. Standalone replacement for Cemu StringBuf.
#pragma once
#include "Standalone.h"
#include <charconv>
class StringBuf {
    std::string value;
public:
    explicit StringBuf(uint32 capacity) { value.reserve(capacity); }
    void add(std::string_view s) { value.append(s); }
    // Register numbers and swizzle names dominate emission. A single plain
    // replacement needs no general format parser or temporary string. All
    // richer specifications (hex widths, escapes, etc.) keep std::format.
    template<class T> void addFmt(std::string_view f,const T& argument) {
        const auto arg=shader_format_value(argument);
        using V=std::remove_cv_t<decltype(arg)>;
        if constexpr((std::is_integral_v<V>&&!std::is_same_v<V,char>&&!std::is_same_v<V,bool>)||std::is_convertible_v<V,std::string_view>) {
            const auto at=f.find_first_of("{}");
            if(at!=std::string_view::npos&&f.substr(at,2)=="{}"&&f.find_first_of("{}",at+2)==std::string_view::npos) {
                value.append(f.substr(0,at));
                if constexpr(std::is_integral_v<V>){char digits[32];const auto end=std::to_chars(digits,digits+sizeof(digits),arg).ptr;value.append(digits,end);}
                else value.append(std::string_view(arg));
                value.append(f.substr(at+2));return;
            }
        }
        auto args=std::tuple{arg};
        std::apply([&](auto& v){std::vformat_to(std::back_inserter(value),f,std::make_format_args(v));},args);
    }
    template<class... Args> void addFmt(std::string_view f, const Args&... args) {
        auto values=std::tuple{shader_format_value(args)...};
        std::apply([&](auto&... v){std::vformat_to(std::back_inserter(value),f,std::make_format_args(v...));},values);
    }
    void reset() { value.clear(); }
    uint32 getLen() const { return uint32(value.size()); }
    size_t size() const { return value.size(); }
    const char* c_str() const { return value.c_str(); }
    void shrink_to_fit() { value.shrink_to_fit(); }
};
