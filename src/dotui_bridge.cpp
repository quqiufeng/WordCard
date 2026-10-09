#include "dotui_bridge.h"
#include "dotui.h"

#include <cstring>
#include <string>

extern "C" {

uint32_t dotui_bg() {
    cv::Scalar c = dotui::bg();
    return (uint8_t(c[2]) << 16) | (uint8_t(c[1]) << 8) | uint8_t(c[0]);
}

uint32_t dotui_card_top() {
    cv::Scalar c = dotui::card_top();
    return (uint8_t(c[2]) << 16) | (uint8_t(c[1]) << 8) | uint8_t(c[0]);
}

uint32_t dotui_card_bot() {
    cv::Scalar c = dotui::card_bot();
    return (uint8_t(c[2]) << 16) | (uint8_t(c[1]) << 8) | uint8_t(c[0]);
}

uint32_t dotui_border() {
    cv::Scalar c = dotui::border();
    return (uint8_t(c[2]) << 16) | (uint8_t(c[1]) << 8) | uint8_t(c[0]);
}

uint32_t dotui_ink() {
    cv::Scalar c = dotui::ink();
    return (uint8_t(c[2]) << 16) | (uint8_t(c[1]) << 8) | uint8_t(c[0]);
}

uint32_t dotui_muted() {
    cv::Scalar c = dotui::muted();
    return (uint8_t(c[2]) << 16) | (uint8_t(c[1]) << 8) | uint8_t(c[0]);
}

uint32_t dotui_dim() {
    cv::Scalar c = dotui::dim();
    return (uint8_t(c[2]) << 16) | (uint8_t(c[1]) << 8) | uint8_t(c[0]);
}

uint32_t dotui_accent() {
    cv::Scalar c = dotui::accent();
    return (uint8_t(c[2]) << 16) | (uint8_t(c[1]) << 8) | uint8_t(c[0]);
}

uint32_t dotui_warn() {
    cv::Scalar c = dotui::warn();
    return (uint8_t(c[2]) << 16) | (uint8_t(c[1]) << 8) | uint8_t(c[0]);
}

uint32_t dotui_crit() {
    cv::Scalar c = dotui::crit();
    return (uint8_t(c[2]) << 16) | (uint8_t(c[1]) << 8) | uint8_t(c[0]);
}

uint32_t dotui_ok() {
    cv::Scalar c = dotui::ok();
    return (uint8_t(c[2]) << 16) | (uint8_t(c[1]) << 8) | uint8_t(c[0]);
}

} // extern "C"
