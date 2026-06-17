#include "gui_tick.h"
#include <lua.h>
#include <lauxlib.h>
#include <stdio.h>

/* 60fps 定时器回调：由 Rust 每帧调用一次 */
void wordcard_gui_tick(void *lua_state) {
    lua_State *L = (lua_State *)lua_state;
    if (!L) return;

    lua_getglobal(L, "gui_tick");
    if (lua_isfunction(L, -1)) {
        if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
            const char *err = lua_tostring(L, -1);
            fprintf(stderr, "[GUI TICK] %s\n", err ? err : "unknown");
            lua_pop(L, 1);
        }
    } else {
        lua_pop(L, 1);
    }
}

/* 用户翻转卡片 */
void wordcard_gui_on_flip(void *lua_state) {
    lua_State *L = (lua_State *)lua_state;
    if (!L) return;

    lua_getglobal(L, "on_flip_card");
    if (lua_isfunction(L, -1)) {
        if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
            const char *err = lua_tostring(L, -1);
            fprintf(stderr, "[GUI FLIP] %s\n", err ? err : "unknown");
            lua_pop(L, 1);
        }
    } else {
        lua_pop(L, 1);
    }
}

/* 用户提交答案 */
void wordcard_gui_on_answer(void *lua_state, const char *text, int quality) {
    lua_State *L = (lua_State *)lua_state;
    if (!L || !text) return;

    lua_getglobal(L, "on_submit_answer");
    if (lua_isfunction(L, -1)) {
        lua_pushstring(L, text);
        lua_pushinteger(L, quality);
        if (lua_pcall(L, 2, 0, 0) != LUA_OK) {
            const char *err = lua_tostring(L, -1);
            fprintf(stderr, "[GUI ANSWER] %s\n", err ? err : "unknown");
            lua_pop(L, 1);
        }
    } else {
        lua_pop(L, 1);
    }
}

/* 用户请求下一张卡片 */
void wordcard_gui_on_next(void *lua_state) {
    lua_State *L = (lua_State *)lua_state;
    if (!L) return;

    lua_getglobal(L, "on_next_card");
    if (lua_isfunction(L, -1)) {
        if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
            const char *err = lua_tostring(L, -1);
            fprintf(stderr, "[GUI NEXT] %s\n", err ? err : "unknown");
            lua_pop(L, 1);
        }
    } else {
        lua_pop(L, 1);
    }
}
