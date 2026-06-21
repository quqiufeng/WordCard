#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <dirent.h>
#include <stdint.h>

/* ====== Rust 引用的符号（空桩）====== */
void wordcard_gui_tick(void *l){(void)l;}
void wordcard_gui_on_flip(void *l){(void)l;}

/* ====== 全局状态 ====== */
static void *g_app = NULL;
static char **g_contents = NULL;    /* 每章内容 */
static char **g_titles = NULL;      /* 每章标题 */
static char **g_paths = NULL;       /* 每章路径 */
static int g_chapter_count = 0;
static int g_current = 0;

/* Rust GUI 函数指针 */
static void *(*gui_set_page)(void*,const char*,const char*,const char*);
static void (*gui_set_nav)(void*,int,int,int,int);
static void (*gui_set_book_title)(void*,const char*);



/* 前向声明 */
void load_chapter(int idx);

/* ====== Rust 导航回调（由 on_mouse_down 触发）====== */
void wordcard_nav_request(int dir) {
    if (dir == 1 && g_current > 0) load_chapter(g_current - 1);
    else if (dir == 2 && g_current < g_chapter_count - 1) load_chapter(g_current + 1);
}

/* ====== 读取文件 ====== */
static char *read_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    rewind(f);
    char *buf = malloc((size_t)len + 1);
    if (!buf) { fclose(f); return NULL; }
    size_t r = fread(buf, 1, (size_t)len, f);
    buf[r] = '\0';
    fclose(f);
    return buf;
}

/* ====== 加载指定章节 ====== */
void load_chapter(int idx) {
    if (idx < 0 || idx >= g_chapter_count) return;
    gui_set_page(g_app, g_paths[idx], g_titles[idx], g_contents[idx]);
    gui_set_nav(g_app, idx > 0, idx < g_chapter_count - 1, idx, g_chapter_count);
    g_current = idx;
}

/* ====== 从路径提取简短标题 ====== */
static const char *short_label(const char *path) {
    const char *p = strrchr(path, '/');
    if (!p) p = path; else p++;
    const char *dot = strchr(p, '.');
    if (dot && dot > p && *(dot-1) >= '0' && *(dot-1) <= '9') return dot + 2;
    return p;
}

/* ====== 主函数 ====== */
int main() {
    /* 扫描 MD 目录 */
    const char *base = "/opt/books/ddia/chapters";
    DIR *dir = opendir(base);
    if (!dir) { fprintf(stderr, "No chapters at %s\n", base); return 1; }

    /* 统计章节数 */
    struct dirent *e;
    while ((e = readdir(dir)) != NULL) {
        if (e->d_name[0] != '.') g_chapter_count++;
    }
    rewinddir(dir);

    g_contents = calloc(g_chapter_count, sizeof(char*));
    g_titles = calloc(g_chapter_count, sizeof(char*));
    g_paths = calloc(g_chapter_count, sizeof(char*));

    int idx = 0;
    while ((e = readdir(dir)) != NULL) {
        if (e->d_name[0] == '.') continue;
        char path[1024];
        snprintf(path, sizeof(path), "%s/%s/page_0000.md", base, e->d_name);
        g_contents[idx] = read_file(path);
        if (!g_contents[idx]) g_contents[idx] = strdup("(empty)");

        g_paths[idx] = strdup(path);
        g_titles[idx] = strdup(short_label(e->d_name));
        idx++;
    }
    closedir(dir);

    printf("Loaded %d chapters\n", g_chapter_count);

    /* 加载 Rust GUI */
    void *h = dlopen("libwordcard_gui.so", RTLD_LAZY | RTLD_GLOBAL);
    if (!h) { fprintf(stderr, "%s\n", dlerror()); return 1; }

    void *(*create)(const char*) = dlsym(h, "gui_app_create");
    int (*run)(void*,void*) = dlsym(h, "gui_run");
    void (*free_app)(void*) = dlsym(h, "gui_app_free");

    gui_set_page = dlsym(h, "gui_set_page");
    gui_set_nav = dlsym(h, "gui_set_nav");
    gui_set_book_title = dlsym(h, "gui_set_book_title");

    if (!create || !run || !gui_set_page) { fprintf(stderr, "symbols missing\n"); return 1; }

    g_app = create("{\"title\":\"WordCard Reader\"}");
    gui_set_book_title(g_app, "Designing Data-Intensive Applications");

    /* 加载第一章 */
    load_chapter(0);

    printf("Launching reader (click ◀ / ▶ to navigate)...\n");
    fflush(stdout);
    run(g_app, NULL);

    /* 清理 */
    free_app(g_app);
    for (int i = 0; i < g_chapter_count; i++) {
        free(g_contents[i]); free(g_titles[i]); free(g_paths[i]);
    }
    free(g_contents); free(g_titles); free(g_paths);
    dlclose(h);
    return 0;
}
