#ifndef WORDCARD_LUA_ENGINE_H
#define WORDCARD_LUA_ENGINE_H

#include <lua.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 创建 Lua 状态，注册 wordcard + cache 库 */
lua_State *wordcard_lua_open(void);

/* 关闭 Lua 状态 */
void wordcard_lua_close(lua_State *L);

/* 运行 main.lua */
int wordcard_lua_run_main(lua_State *L, const char *main_path);

#ifdef __cplusplus
}
#endif

#endif /* WORDCARD_LUA_ENGINE_H */
