#include "Input/mouse_gyro_handler.h"

#include <algorithm>

void mouse_gyro_handler::clear()
{
    m_active = false;
    m_reset = false;
    m_gyro_x = DEFAULT_MOTION_X;
    m_gyro_y = DEFAULT_MOTION_Y;
    m_gyro_z = DEFAULT_MOTION_Z;
}

bool mouse_gyro_handler::toggle_enabled()
{
    m_enabled = !m_enabled;
    clear();
    return m_enabled;
}

void mouse_gyro_handler::set_enabled(bool enabled)
{
    m_enabled = enabled;
    clear();
}

void mouse_gyro_handler::set_gyro_active()
{
    m_active = true;
}

void mouse_gyro_handler::set_gyro_reset()
{
    m_active = false;
    m_reset = true;
}

void mouse_gyro_handler::set_gyro_xz(s32 off_x, s32 off_y)
{
    if (!m_active)
    {
        return;
    }

    m_gyro_x = static_cast<u16>(std::clamp(off_x, 0, DEFAULT_MOTION_X * 2 - 1));
    m_gyro_z = static_cast<u16>(std::clamp(off_y, 0, DEFAULT_MOTION_Z * 2 - 1));
}

void mouse_gyro_handler::set_gyro_y(s32 steps)
{
    if (!m_active)
    {
        return;
    }

    m_gyro_y = static_cast<u16>(std::clamp(m_gyro_y + steps, 0, DEFAULT_MOTION_Y * 2 - 1));
}

void mouse_gyro_handler::handle_event(QEvent* event, const QWindow& window)
{
    // The framework has no Qt event loop or desktop mouse window. Device and
    // controller motion are supplied by IOSControllerFeatures instead.
    (void)event;
    (void)window;
}

void mouse_gyro_handler::apply_gyro(const std::shared_ptr<Pad>& pad)
{
    if (!m_enabled || !pad || !pad->is_connected())
    {
        return;
    }

    if (m_reset)
    {
        pad->m_sensors[0].m_value = DEFAULT_MOTION_X;
        pad->m_sensors[1].m_value = DEFAULT_MOTION_Y;
        pad->m_sensors[2].m_value = DEFAULT_MOTION_Z;
        clear();
        return;
    }

    pad->m_sensors[0].m_value = m_gyro_x;
    pad->m_sensors[1].m_value = m_gyro_y;
    pad->m_sensors[2].m_value = m_gyro_z;
}
