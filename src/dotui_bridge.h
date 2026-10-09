#ifndef DOTUI_BRIDGE_H
#define DOTUI_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint32_t dotui_bg();
uint32_t dotui_card_top();
uint32_t dotui_card_bot();
uint32_t dotui_border();
uint32_t dotui_ink();
uint32_t dotui_muted();
uint32_t dotui_dim();
uint32_t dotui_accent();
uint32_t dotui_warn();
uint32_t dotui_crit();
uint32_t dotui_ok();

#ifdef __cplusplus
}
#endif

#endif
