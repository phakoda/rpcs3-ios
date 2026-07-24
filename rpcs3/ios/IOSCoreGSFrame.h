#pragma once

#include <memory>
#include <string>

class GSFrameBase;

namespace rpcs3::ios
{
bool set_core_render_view(void* native_view, std::string* error = nullptr);
void clear_core_render_view();
bool has_core_render_view();
std::unique_ptr<GSFrameBase> make_core_gs_frame();
}
