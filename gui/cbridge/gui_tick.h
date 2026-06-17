#ifndef WORDCARD_GUI_TICK_H
#define WORDCARD_GUI_TICK_H

#ifdef __cplusplus
extern "C" {
#endif

/* 定时器回调：每帧由 Rust 调用，驱动 Lua 协程（如复习队列更新）*/
void wordcard_gui_tick(void *lua_state);

/* 用户操作回调：由 Rust 调用 Lua 处理用户交互 */
void wordcard_gui_on_flip(void *lua_state);
void wordcard_gui_on_answer(void *lua_state, const char *text, int quality);
void wordcard_gui_on_next(void *lua_state);

#ifdef __cplusplus
}
#endif

#endif /* WORDCARD_GUI_TICK_H */
