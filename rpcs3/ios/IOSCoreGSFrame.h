#pragma once

#include <cstdint>
#include <memory>
#include <string>

class GSFrameBase;

namespace rpcs3::ios
{
struct core_render_metrics
{
    int width = 1;
    int height = 1;
    double refresh_rate = 60.0;
    std::uint64_t generation = 0;
    bool visible = false;
};

bool set_core_render_view(void* native_view, std::string* error = nullptr);
void clear_core_render_view();
bool has_core_render_view();
void refresh_core_render_view();
core_render_metrics get_core_render_metrics();
std::unique_ptr<GSFrameBase> make_core_gs_frame();
}
