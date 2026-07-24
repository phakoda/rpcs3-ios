#pragma once

#include <stddef.h>
#include <stdint.h>
#include <sys/time.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LIBUSB_CALL
#define LIBUSB_API_VERSION 0x01000101
#define LIBUSB_CONTROL_SETUP_SIZE 8

struct libusb_context;
struct libusb_device;
struct libusb_device_handle;
struct libusb_transfer;

typedef struct libusb_context libusb_context;
typedef struct libusb_device libusb_device;
typedef struct libusb_device_handle libusb_device_handle;
typedef struct libusb_transfer libusb_transfer;

enum libusb_error
{
    LIBUSB_SUCCESS = 0,
    LIBUSB_ERROR_IO = -1,
    LIBUSB_ERROR_INVALID_PARAM = -2,
    LIBUSB_ERROR_ACCESS = -3,
    LIBUSB_ERROR_NO_DEVICE = -4,
    LIBUSB_ERROR_NOT_FOUND = -5,
    LIBUSB_ERROR_BUSY = -6,
    LIBUSB_ERROR_TIMEOUT = -7,
    LIBUSB_ERROR_OVERFLOW = -8,
    LIBUSB_ERROR_PIPE = -9,
    LIBUSB_ERROR_INTERRUPTED = -10,
    LIBUSB_ERROR_NO_MEM = -11,
    LIBUSB_ERROR_NOT_SUPPORTED = -12,
    LIBUSB_ERROR_OTHER = -99,
};

enum libusb_transfer_status
{
    LIBUSB_TRANSFER_COMPLETED,
    LIBUSB_TRANSFER_ERROR,
    LIBUSB_TRANSFER_TIMED_OUT,
    LIBUSB_TRANSFER_CANCELLED,
    LIBUSB_TRANSFER_STALL,
    LIBUSB_TRANSFER_NO_DEVICE,
    LIBUSB_TRANSFER_OVERFLOW,
};

enum libusb_transfer_type
{
    LIBUSB_TRANSFER_TYPE_CONTROL = 0,
    LIBUSB_TRANSFER_TYPE_ISOCHRONOUS = 1,
    LIBUSB_TRANSFER_TYPE_BULK = 2,
    LIBUSB_TRANSFER_TYPE_INTERRUPT = 3,
    LIBUSB_TRANSFER_TYPE_BULK_STREAM = 4,
};

#define LIBUSB_TRANSFER_TYPE_MASK 0x03
#define LIBUSB_ENDPOINT_OUT 0x00
#define LIBUSB_ENDPOINT_IN 0x80
#define LIBUSB_REQUEST_TYPE_STANDARD (0x00 << 5)
#define LIBUSB_REQUEST_TYPE_CLASS (0x01 << 5)
#define LIBUSB_REQUEST_TYPE_VENDOR (0x02 << 5)
#define LIBUSB_RECIPIENT_DEVICE 0x00
#define LIBUSB_RECIPIENT_INTERFACE 0x01
#define LIBUSB_RECIPIENT_ENDPOINT 0x02
#define LIBUSB_REQUEST_GET_STATUS 0x00
#define LIBUSB_REQUEST_CLEAR_FEATURE 0x01
#define LIBUSB_REQUEST_SET_FEATURE 0x03
#define LIBUSB_REQUEST_SET_ADDRESS 0x05
#define LIBUSB_REQUEST_GET_DESCRIPTOR 0x06
#define LIBUSB_REQUEST_SET_DESCRIPTOR 0x07
#define LIBUSB_REQUEST_GET_CONFIGURATION 0x08
#define LIBUSB_REQUEST_SET_CONFIGURATION 0x09
#define LIBUSB_REQUEST_GET_INTERFACE 0x0a
#define LIBUSB_REQUEST_SET_INTERFACE 0x0b
#define LIBUSB_REQUEST_SYNCH_FRAME 0x0c

struct libusb_device_descriptor
{
    uint8_t bLength;
    uint8_t bDescriptorType;
    uint16_t bcdUSB;
    uint8_t bDeviceClass;
    uint8_t bDeviceSubClass;
    uint8_t bDeviceProtocol;
    uint8_t bMaxPacketSize0;
    uint16_t idVendor;
    uint16_t idProduct;
    uint16_t bcdDevice;
    uint8_t iManufacturer;
    uint8_t iProduct;
    uint8_t iSerialNumber;
    uint8_t bNumConfigurations;
};

struct libusb_control_setup
{
    uint8_t bmRequestType;
    uint8_t bRequest;
    uint16_t wValue;
    uint16_t wIndex;
    uint16_t wLength;
};

struct libusb_iso_packet_descriptor
{
    unsigned int length;
    unsigned int actual_length;
    enum libusb_transfer_status status;
};

typedef void (LIBUSB_CALL *libusb_transfer_cb_fn)(struct libusb_transfer* transfer);

struct libusb_transfer
{
    libusb_device_handle* dev_handle;
    uint8_t flags;
    unsigned char endpoint;
    unsigned char type;
    unsigned int timeout;
    unsigned char* buffer;
    int length;
    int actual_length;
    libusb_transfer_cb_fn callback;
    void* user_data;
    int num_iso_packets;
    struct libusb_iso_packet_descriptor iso_packet_desc[1];
};

int libusb_init(libusb_context** context);
void libusb_exit(libusb_context* context);
ptrdiff_t libusb_get_device_list(libusb_context* context, libusb_device*** list);
void libusb_free_device_list(libusb_device** list, int unref_devices);
int libusb_get_device_descriptor(libusb_device* device, struct libusb_device_descriptor* descriptor);
uint8_t libusb_get_port_number(libusb_device* device);
uint8_t libusb_get_device_address(libusb_device* device);
libusb_device* libusb_ref_device(libusb_device* device);
void libusb_unref_device(libusb_device* device);
int libusb_open(libusb_device* device, libusb_device_handle** handle);
void libusb_close(libusb_device_handle* handle);
int libusb_claim_interface(libusb_device_handle* handle, int interface_number);
int libusb_release_interface(libusb_device_handle* handle, int interface_number);
int libusb_get_configuration(libusb_device_handle* handle, int* configuration);
int libusb_set_configuration(libusb_device_handle* handle, int configuration);
int libusb_control_transfer(libusb_device_handle* handle, uint8_t request_type, uint8_t request,
    uint16_t value, uint16_t index, unsigned char* data, uint16_t length, unsigned int timeout);
const char* libusb_error_name(int error_code);
libusb_transfer* libusb_alloc_transfer(int iso_packets);
void libusb_free_transfer(libusb_transfer* transfer);
int libusb_submit_transfer(libusb_transfer* transfer);
int libusb_cancel_transfer(libusb_transfer* transfer);
int libusb_handle_events_timeout_completed(libusb_context* context, const struct timeval* timeout, int* completed);

static inline uint16_t libusb_cpu_to_le16(uint16_t value)
{
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
    return (uint16_t)((value << 8) | (value >> 8));
#else
    return value;
#endif
}

static inline void libusb_fill_control_setup(unsigned char* buffer, uint8_t request_type,
    uint8_t request, uint16_t value, uint16_t index, uint16_t length)
{
    struct libusb_control_setup* setup = (struct libusb_control_setup*)buffer;
    setup->bmRequestType = request_type;
    setup->bRequest = request;
    setup->wValue = libusb_cpu_to_le16(value);
    setup->wIndex = libusb_cpu_to_le16(index);
    setup->wLength = libusb_cpu_to_le16(length);
}

static inline void libusb_fill_control_transfer(libusb_transfer* transfer,
    libusb_device_handle* handle, unsigned char* buffer, libusb_transfer_cb_fn callback,
    void* user_data, unsigned int timeout)
{
    const struct libusb_control_setup* setup = (const struct libusb_control_setup*)buffer;
    transfer->dev_handle = handle;
    transfer->endpoint = 0;
    transfer->type = LIBUSB_TRANSFER_TYPE_CONTROL;
    transfer->timeout = timeout;
    transfer->buffer = buffer;
    transfer->length = LIBUSB_CONTROL_SETUP_SIZE + setup->wLength;
    transfer->callback = callback;
    transfer->user_data = user_data;
}

static inline void libusb_fill_bulk_transfer(libusb_transfer* transfer,
    libusb_device_handle* handle, unsigned char endpoint, unsigned char* buffer, int length,
    libusb_transfer_cb_fn callback, void* user_data, unsigned int timeout)
{
    transfer->dev_handle = handle;
    transfer->endpoint = endpoint;
    transfer->type = LIBUSB_TRANSFER_TYPE_BULK;
    transfer->timeout = timeout;
    transfer->buffer = buffer;
    transfer->length = length;
    transfer->callback = callback;
    transfer->user_data = user_data;
}

static inline void libusb_fill_interrupt_transfer(libusb_transfer* transfer,
    libusb_device_handle* handle, unsigned char endpoint, unsigned char* buffer, int length,
    libusb_transfer_cb_fn callback, void* user_data, unsigned int timeout)
{
    transfer->dev_handle = handle;
    transfer->endpoint = endpoint;
    transfer->type = LIBUSB_TRANSFER_TYPE_INTERRUPT;
    transfer->timeout = timeout;
    transfer->buffer = buffer;
    transfer->length = length;
    transfer->callback = callback;
    transfer->user_data = user_data;
}

static inline void libusb_fill_iso_transfer(libusb_transfer* transfer,
    libusb_device_handle* handle, unsigned char endpoint, unsigned char* buffer, int length,
    int packets, libusb_transfer_cb_fn callback, void* user_data, unsigned int timeout)
{
    transfer->dev_handle = handle;
    transfer->endpoint = endpoint;
    transfer->type = LIBUSB_TRANSFER_TYPE_ISOCHRONOUS;
    transfer->timeout = timeout;
    transfer->buffer = buffer;
    transfer->length = length;
    transfer->num_iso_packets = packets;
    transfer->callback = callback;
    transfer->user_data = user_data;
}

#ifdef __cplusplus
}
#endif
