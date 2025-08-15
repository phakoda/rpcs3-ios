#pragma once

#if defined (_WIN32)
#include "swapchain_win32.hpp"
#elif defined (ANDROID)
#include "swapchain_android.hpp"
#elif defined (__APPLE__)
#include <TargetConditionals.h>
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#include "swapchain_ios.hpp"
#else
#include "swapchain_macos.hpp"
#endif
#else // Both linux and BSD families
#include "swapchain_unix.hpp"
#endif
