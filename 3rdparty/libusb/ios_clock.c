#include "libusbi.h"

void usbi_get_monotonic_time(struct timespec *tp)
{
	clock_gettime(CLOCK_MONOTONIC, tp);
}

void usbi_get_real_time(struct timespec *tp)
{
	clock_gettime(CLOCK_REALTIME, tp);
}
