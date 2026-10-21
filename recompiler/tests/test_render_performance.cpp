// Only the runtime and authored synthetic inputs are linked. No game entry point.
#include "os/gx2/gx2_render.h"
#include "os/gx2/vk/gx2_vk.h"
#include <cstdio>
#include <stdexcept>
#include <string_view>
#ifdef _WIN32
#include <windows.h>
#include <psapi.h>
#endif
void gx2_render_vk_test_stress(bool push, bool churn);
void gx2_render_vk_test_binding_contracts();
void gx2_render_vk_test_lifetime();
int main(int argc, char** argv) {
    try {
        if(argc!=2)throw std::runtime_error("expected fallback, push, churn, contracts, or lifetime");
        const std::string_view mode=argv[1];
        if(mode!="fallback" && mode!="push" && mode!="churn" && mode!="contracts" && mode!="lifetime")throw std::runtime_error("unknown authored benchmark");
        if(!gx2vk::init(nullptr))return 77;
        gx2_render_init();
        std::printf("{\"device\":\"%s\",\"workload\":\"%s\",\"synthetic\":true}\n",gx2vk::caps().device_name.c_str(),argv[1]);
        if(mode=="contracts")gx2_render_vk_test_binding_contracts();
        else if(mode=="lifetime")gx2_render_vk_test_lifetime();
        else gx2_render_vk_test_stress(mode=="push",mode=="churn");
        if(gx2vk::validation_error_count())throw std::runtime_error("Vulkan validation error");
#ifdef _WIN32
        PROCESS_MEMORY_COUNTERS_EX m{};m.cb=sizeof(m);
        GetProcessMemoryInfo(GetCurrentProcess(),reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&m),sizeof(m));
        std::printf("{\"metric\":\"memory\",\"peak_commit_bytes\":%llu,\"peak_working_set_bytes\":%llu,\"vulkan_owned_bytes\":%llu}\n",
            (unsigned long long)m.PeakPagefileUsage,(unsigned long long)m.PeakWorkingSetSize,(unsigned long long)gx2vk::allocated_bytes());
#endif
        gx2_render_shutdown();
        return 0;
    } catch(const std::exception& e) { std::fprintf(stderr,"render stress failed: %s\n",e.what());return 1; }
}
