#define _GNU_SOURCE
#include "lua_engine.h"
#include <lauxlib.h>
#include <lualib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>

/* ======================================================================
 * WordCard Lua 引擎
 * 注册 libwordcard.so + libcache.so 的 C 函数到 Lua 全局命名空间
 * Lua 脚本可以直接调用 wc_db_init(), cache_open() 等
 * ====================================================================== */

/* ---------- wordcard API ---------- */

#include "wordcard.h"
#include "cache.h"

/* wc_db_init() → userdata */
static int l_wc_db_init(lua_State *L) {
    wordcard_db_t *db = wc_db_init();
    if (!db) { lua_pushnil(L); return 1; }
    lua_pushlightuserdata(L, db);
    return 1;
}

/* wc_load_db(path) → userdata | nil */
static int l_wc_load_db(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    wordcard_db_t *db = wc_load_db(path);
    if (!db) { lua_pushnil(L); return 1; }
    lua_pushlightuserdata(L, db);
    return 1;
}

/* wc_save_db(db, path) */
static int l_wc_save_db(lua_State *L) {
    wordcard_db_t *db = (wordcard_db_t *)lua_touserdata(L, 1);
    const char *path = luaL_checkstring(L, 2);
    int rc = wc_save_db(db, path);
    lua_pushinteger(L, rc);
    return 1;
}

/* wc_db_free(db) */
static int l_wc_db_free(lua_State *L) {
    wordcard_db_t *db = (wordcard_db_t *)lua_touserdata(L, 1);
    wc_db_free(db);
    return 0;
}

/* wc_add_item(db, question, answer, category) → id */
static int l_wc_add_item(lua_State *L) {
    wordcard_db_t *db = (wordcard_db_t *)lua_touserdata(L, 1);
    const char *q = luaL_checkstring(L, 2);
    const char *a = luaL_checkstring(L, 3);
    int cat = (int)luaL_optinteger(L, 4, CAT_ENGLISH_VOCAB);

    item_entry_t entry = {0};
    strncpy(entry.question, q, sizeof(entry.question) - 1);
    strncpy(entry.answer, a, sizeof(entry.answer) - 1);
    entry.category = cat;

    uint32_t id = wc_add_item(db, &entry);
    lua_pushinteger(L, id);
    return 1;
}

/* wc_create_user(db, uid, name) → id */
static int l_wc_create_user(lua_State *L) {
    wordcard_db_t *db = (wordcard_db_t *)lua_touserdata(L, 1);
    const char *uid = luaL_checkstring(L, 2);
    const char *name = luaL_optstring(L, 3, "");
    uint32_t id = wc_create_user(db, uid, name);
    lua_pushinteger(L, id);
    return 1;
}

/* wc_sm2_update(mastery, quality) */
static int l_wc_sm2_update(lua_State *L) {
    user_item_mastery_t *m = (user_item_mastery_t *)lua_touserdata(L, 1);
    int quality = (int)luaL_checkinteger(L, 2);
    wc_sm2_update(m, quality);
    return 0;
}

/* wc_get_or_create_mastery(db, user_id, item_id) → userdata | nil */
static int l_wc_get_or_create_mastery(lua_State *L) {
    wordcard_db_t *db = (wordcard_db_t *)lua_touserdata(L, 1);
    uint32_t uid = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t iid = (uint32_t)luaL_checkinteger(L, 3);
    user_item_mastery_t *m = wc_get_or_create_mastery(db, uid, iid);
    if (!m) { lua_pushnil(L); return 1; }
    lua_pushlightuserdata(L, m);
    return 1;
}

/* wc_now() → int */
static int l_wc_now(lua_State *L) {
    lua_pushinteger(L, wc_now());
    return 1;
}

/* wc_today() → int (YYYYMMDD) */
static int l_wc_today(lua_State *L) {
    lua_pushinteger(L, wc_today());
    return 1;
}

/* ---------- cache API ---------- */

/* cache_open(dir, max_memory) → userdata | nil */
static int l_cache_open(lua_State *L) {
    const char *dir = luaL_checkstring(L, 1);
    size_t max_mem = (size_t)luaL_optinteger(L, 2, CACHE_MAX_MEMORY_DEFAULT);
    cache_t *c = cache_open(dir, max_mem);
    if (!c) { lua_pushnil(L); return 1; }
    lua_pushlightuserdata(L, c);
    return 1;
}

/* cache_close(cache) */
static int l_cache_close(lua_State *L) {
    cache_t *c = (cache_t *)lua_touserdata(L, 1);
    cache_close(c);
    return 0;
}

/* cache_set(cache, key, value, ttl_ms) → bool */
static int l_cache_set(lua_State *L) {
    cache_t *c = (cache_t *)lua_touserdata(L, 1);
    const char *key = luaL_checkstring(L, 2);
    const char *val = luaL_checkstring(L, 3);
    uint64_t ttl = (uint64_t)luaL_optinteger(L, 4, 0);
    int rc = cache_set(c, key, val, ttl);
    lua_pushboolean(L, rc == CACHE_OK);
    return 1;
}

/* cache_get(cache, key) → string | nil */
static int l_cache_get(lua_State *L) {
    cache_t *c = (cache_t *)lua_touserdata(L, 1);
    const char *key = luaL_checkstring(L, 2);
    const char *val = cache_get(c, key);
    if (val) lua_pushstring(L, val);
    else     lua_pushnil(L);
    return 1;
}

/* ---------- 注册表 ---------- */

static const luaL_Reg wordcard_lib[] = {
    {"wc_db_init", l_wc_db_init},
    {"wc_load_db", l_wc_load_db},
    {"wc_save_db", l_wc_save_db},
    {"wc_db_free", l_wc_db_free},
    {"wc_add_item", l_wc_add_item},
    {"wc_create_user", l_wc_create_user},
    {"wc_sm2_update", l_wc_sm2_update},
    {"wc_get_or_create_mastery", l_wc_get_or_create_mastery},
    {"wc_now", l_wc_now},
    {"wc_today", l_wc_today},
    {NULL, NULL},
};

static const luaL_Reg cache_lib[] = {
    {"cache_open", l_cache_open},
    {"cache_close", l_cache_close},
    {"cache_set", l_cache_set},
    {"cache_get", l_cache_get},
    {NULL, NULL},
};

/* ---------- 初始化 ---------- */

lua_State *wordcard_lua_open(void) {
    lua_State *L = luaL_newstate();
    if (!L) return NULL;

    luaL_openlibs(L);

    /* 注册 wordcard 库 */
    lua_newtable(L);
    luaL_setfuncs(L, wordcard_lib, 0);
    lua_setglobal(L, "wordcard");

    /* 注册 cache 库 */
    lua_newtable(L);
    luaL_setfuncs(L, cache_lib, 0);
    lua_setglobal(L, "cache");

    return L;
}

void wordcard_lua_close(lua_State *L) {
    if (L) lua_close(L);
}

/* loader: 运行 main.lua */
int wordcard_lua_run_main(lua_State *L, const char *main_path) {
    if (luaL_dofile(L, main_path) != LUA_OK) {
        fprintf(stderr, "[LUA ERROR] %s\n", lua_tostring(L, -1));
        lua_pop(L, 1);
        return -1;
    }
    return 0;
}
