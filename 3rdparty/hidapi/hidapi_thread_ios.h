#pragma once

// Darwin does not provide pthread barriers. HIDAPI already carries a
// mutex/condition-variable fallback for older Android targets; select that
// implementation only while its thread-model header is parsed.
#define __ANDROID__ 1
#define __ANDROID_API__ 1
#define __ANDROID_API_N__ 24
#include "hidapi_thread_pthread.h"
#undef __ANDROID_API_N__
#undef __ANDROID_API__
#undef __ANDROID__
