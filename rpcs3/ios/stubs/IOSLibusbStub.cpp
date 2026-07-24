#include "libusb.h"

#include <cstdlib>
#include <cstring>

struct libusb_context
{
    int reserved = 0;
};

struct libusb_device
{
    int reserved = 0;
};

struct libusb_device_handle
{
    int reserved = 0;
};

extern "C"
{
int libusb_init(libusb_context** context)
{
    if (!context)
    {
        return LIBUSB_ERROR_INVALID_PARAM;
    }

    *context = new (std::nothrow) libusb_context{};
    return *context ? LIBUSB_SUCCESS : LIBUSB_ERROR_NO_MEM;
}

void libusb_exit(libusb_context* context)
{
    delete context;
}

ssize_t libusb_get_device_list(libusb_context* context, libusb_device*** list)
{
    (void)context;
    if (!list)
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
    (void)device;
    if (descriptor)
    {
        std::memset(descriptor, 0, sizeof(*descriptor));
    }
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

uint8_t libusb_get_bus_number(libusb_device* device)
{
    (void)device;
    return 0;
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

int libusb_set_interface_alt_setting(libusb_device_handle* handle, int interface_number, int alternate_setting)
{
    (void)handle;
    (void)interface_number;
    (void)alternate_setting;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int libusb_clear_halt(libusb_device_handle* handle, unsigned char endpoint)
{
    (void)handle;
    (void)endpoint;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int libusb_reset_device(libusb_device_handle* handle)
{
    (void)handle;
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

libusb_transfer* libusb_alloc_transfer(int iso_packets)
{
    if (iso_packets < 0)
    {
        return nullptr;
    }

    const std::size_t descriptor_count = iso_packets > 0 ? static_cast<std::size_t>(iso_packets) : 1;
    const std::size_t allocation_size = sizeof(libusb_transfer) +
        (descriptor_count - 1) * sizeof(libusb_iso_packet_descriptor);
    auto* transfer = static_cast<libusb_transfer*>(std::calloc(1, allocation_size));
    if (transfer)
    {
        transfer->num_iso_packets = iso_packets;
        transfer->status = LIBUSB_TRANSFER_COMPLETED;
    }
    return transfer;
}

void libusb_free_transfer(libusb_transfer* transfer)
{
    if (!transfer)
    {
        return;
    }

    if ((transfer->flags & LIBUSB_TRANSFER_FREE_BUFFER) != 0)
    {
        std::free(transfer->buffer);
    }
    std::free(transfer);
}

int libusb_submit_transfer(libusb_transfer* transfer)
{
    (void)transfer;
    return LIBUSB_ERROR_NOT_SUPPORTED;
}

int libusb_cancel_transfer(libusb_transfer* transfer)
{
    if (!transfer)
    {
        return LIBUSB_ERROR_INVALID_PARAM;
    }

    transfer->status = LIBUSB_TRANSFER_CANCELLED;
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

const char* libusb_error_name(int error_code)
{
    switch (error_code)
    {
    case LIBUSB_SUCCESS: return "LIBUSB_SUCCESS";
    case LIBUSB_ERROR_IO: return "LIBUSB_ERROR_IO";
    case LIBUSB_ERROR_INVALID_PARAM: return "LIBUSB_ERROR_INVALID_PARAM";
    case LIBUSB_ERROR_ACCESS: return "LIBUSB_ERROR_ACCESS";
    case LIBUSB_ERROR_NO_DEVICE: return "LIBUSB_ERROR_NO_DEVICE";
    case LIBUSB_ERROR_NOT_FOUND: return "LIBUSB_ERROR_NOT_FOUND";
    case LIBUSB_ERROR_BUSY: return "LIBUSB_ERROR_BUSY";
    case LIBUSB_ERROR_TIMEOUT: return "LIBUSB_ERROR_TIMEOUT";
    case LIBUSB_ERROR_OVERFLOW: return "LIBUSB_ERROR_OVERFLOW";
    case LIBUSB_ERROR_PIPE: return "LIBUSB_ERROR_PIPE";
    case LIBUSB_ERROR_INTERRUPTED: return "LIBUSB_ERROR_INTERRUPTED";
    case LIBUSB_ERROR_NO_MEM: return "LIBUSB_ERROR_NO_MEM";
    case LIBUSB_ERROR_NOT_SUPPORTED: return "LIBUSB_ERROR_NOT_SUPPORTED";
    default: return "LIBUSB_ERROR_OTHER";
    }
}
}
