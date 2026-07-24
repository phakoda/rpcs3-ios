#include "libusb.h"

#include <cstdlib>
#include <cstring>

struct libusb_context
{
    int unused = 0;
};

struct libusb_device
{
    int unused = 0;
};

struct libusb_device_handle
{
    int unused = 0;
};

extern "C"
{
int libusb_init(libusb_context** context)
{
    if (!context)
    {
        return LIBUSB_ERROR_INVALID_PARAM;
    }

    *context = static_cast<libusb_context*>(std::calloc(1, sizeof(libusb_context)));
    return *context ? LIBUSB_SUCCESS : LIBUSB_ERROR_NO_MEM;
}

void libusb_exit(libusb_context* context)
{
    std::free(context);
}

ptrdiff_t libusb_get_device_list(libusb_context* context, libusb_device*** list)
{
    if (!context || !list)
    {
        return LIBUSB_ERROR_INVALID_PARAM;
    }

    *list = static_cast<libusb_device**>(std::calloc(1, sizeof(libusb_device*)));
    return *list ? 0 : LIBUSB_ERROR_NO_MEM;
}

void libusb_free_device_list(libusb_device** list, int unref_devices)
{
    (void)unref_devices;
    std::free(list);
}

int libusb_get_device_descriptor(libusb_device* device, libusb_device_descriptor* descriptor)
{
    if (!device || !descriptor)
    {
        return LIBUSB_ERROR_INVALID_PARAM;
    }

    std::memset(descriptor, 0, sizeof(*descriptor));
    return LIBUSB_ERROR_NO_DEVICE;
}

uint8_t libusb_get_port_number(libusb_device* device)
{
    (void)device;
    return 0;
}

uint8_t libusb_get_device_address(libusb_device* device)
{
    (void)device;
    return 0;
}

libusb_device* libusb_ref_device(libusb_device* device)
{
    return device;
}

void libusb_unref_device(libusb_device* device)
{
    (void)device;
}

int libusb_open(libusb_device* device, libusb_device_handle** handle)
{
    (void)device;
    if (handle)
    {
        *handle = nullptr;
    }
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

void libusb_close(libusb_device_handle* handle)
{
    (void)handle;
}

int libusb_claim_interface(libusb_device_handle* handle, int interface_number)
{
    (void)handle;
    (void)interface_number;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int libusb_release_interface(libusb_device_handle* handle, int interface_number)
{
    (void)handle;
    (void)interface_number;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int libusb_get_configuration(libusb_device_handle* handle, int* configuration)
{
    (void)handle;
    if (configuration)
    {
        *configuration = 0;
    }
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int libusb_set_configuration(libusb_device_handle* handle, int configuration)
{
    (void)handle;
    (void)configuration;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int libusb_control_transfer(libusb_device_handle* handle, uint8_t request_type, uint8_t request,
    uint16_t value, uint16_t index, unsigned char* data, uint16_t length, unsigned int timeout)
{
    (void)handle;
    (void)request_type;
    (void)request;
    (void)value;
    (void)index;
    (void)data;
    (void)length;
    (void)timeout;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

const char* libusb_error_name(int error_code)
{
    switch (error_code)
    {
    case LIBUSB_SUCCESS: return "success";
    case LIBUSB_ERROR_IO: return "I/O error";
    case LIBUSB_ERROR_INVALID_PARAM: return "invalid parameter";
    case LIBUSB_ERROR_ACCESS: return "access denied";
    case LIBUSB_ERROR_NO_DEVICE: return "no device";
    case LIBUSB_ERROR_NOT_FOUND: return "not found";
    case LIBUSB_ERROR_BUSY: return "busy";
    case LIBUSB_ERROR_TIMEOUT: return "timeout";
    case LIBUSB_ERROR_OVERFLOW: return "overflow";
    case LIBUSB_ERROR_PIPE: return "pipe error";
    case LIBUSB_ERROR_INTERRUPTED: return "interrupted";
    case LIBUSB_ERROR_NO_MEM: return "out of memory";
    case LIBUSB_ERROR_NOT_SUPPORTED: return "not supported on iOS";
    default: return "other libusb error";
    }
}

libusb_transfer* libusb_alloc_transfer(int iso_packets)
{
    if (iso_packets < 0)
    {
        return nullptr;
    }

    const size_t descriptor_count = static_cast<size_t>(iso_packets > 0 ? iso_packets : 1);
    const size_t allocation_size = sizeof(libusb_transfer) +
        (descriptor_count - 1) * sizeof(libusb_iso_packet_descriptor);
    libusb_transfer* transfer = static_cast<libusb_transfer*>(std::calloc(1, allocation_size));
    if (transfer)
    {
        transfer->num_iso_packets = iso_packets;
    }
    return transfer;
}

void libusb_free_transfer(libusb_transfer* transfer)
{
    std::free(transfer);
}

int libusb_submit_transfer(libusb_transfer* transfer)
{
    if (!transfer)
    {
        return LIBUSB_ERROR_INVALID_PARAM;
    }

    transfer->status = LIBUSB_TRANSFER_NO_DEVICE;
    transfer->actual_length = 0;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int libusb_cancel_transfer(libusb_transfer* transfer)
{
    if (!transfer)
    {
        return LIBUSB_ERROR_INVALID_PARAM;
    }

    transfer->status = LIBUSB_TRANSFER_CANCELLED;
    transfer->actual_length = 0;
    if (transfer->callback)
    {
        transfer->callback(transfer);
    }
    return LIBUSB_SUCCESS;
}

int libusb_handle_events_timeout_completed(libusb_context* context, const timeval* timeout, int* completed)
{
    (void)context;
    (void)timeout;
    if (completed)
    {
        *completed = 0;
    }
    return LIBUSB_SUCCESS;
}
}
