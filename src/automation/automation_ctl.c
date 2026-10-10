// automation_ctl.c — WordCard UI 自动化控制面的 C 客户端
//
// 连接 Flutter App 暴露的 Unix domain socket，发送 JSON 命令并读取响应。
// 供 LuaJIT FFI 调用（见 gui/flutter/automation/wordcard.lua）。
//
// 协议（JSON Lines）:
//   -> {"cmd":"list"}            <- {"ok":true,"actions":[...]}
//   -> {"cmd":"state"}           <- {"ok":true,"state":{...}}
//   -> {"cmd":"click","id":"..."}<- {"ok":true,"id":"..."}
//   服务端还会主动推送事件行 {"event":"click","id":...}
//
// 编译: see src/Makefile (target: automation → libwordcard_ctl.so)

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

typedef struct {
    int fd;
} wcctl_t;

static int wcctl_readline(int fd, char *out, int outlen) {
    int n = 0;
    while (n < outlen - 1) {
        char ch;
        ssize_t r = recv(fd, &ch, 1, 0);
        if (r <= 0) break;
        if (ch == '\n') break;
        out[n++] = ch;
    }
    out[n] = '\0';
    return n;
}

wcctl_t *wcctl_open(const char *path) {
    if (!path) return NULL;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return NULL;
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return NULL;
    }
    wcctl_t *c = (wcctl_t *)malloc(sizeof(wcctl_t));
    if (!c) { close(fd); return NULL; }
    c->fd = fd;
    // 消费连接建立时的 welcome 行
    char tmp[4096];
    wcctl_readline(fd, tmp, sizeof(tmp));
    return c;
}

void wcctl_close(wcctl_t *c) {
    if (!c) return;
    close(c->fd);
    free(c);
}

// 发送一行请求，读取到含 "ok" 的响应行（跳过中间的事件推送）。返回响应长度或 -1。
int wcctl_call(wcctl_t *c, const char *req, char *out, int outlen) {
    if (!c || !req || !out || outlen <= 0) return -1;
    size_t len = strlen(req);
    char *buf = (char *)malloc(len + 2);
    if (!buf) return -1;
    memcpy(buf, req, len);
    buf[len] = '\n';
    buf[len + 1] = '\0';
    ssize_t s = send(c->fd, buf, len + 1, 0);
    free(buf);
    if (s < 0) return -1;
    for (int i = 0; i < 64; i++) {
        int n = wcctl_readline(c->fd, out, outlen);
        if (n <= 0) return -1;
        if (strstr(out, "\"ok\"")) return n;
    }
    return -1;
}

int wcctl_list(wcctl_t *c, char *out, int outlen) {
    return wcctl_call(c, "{\"cmd\":\"list\"}", out, outlen);
}

int wcctl_state(wcctl_t *c, char *out, int outlen) {
    return wcctl_call(c, "{\"cmd\":\"state\"}", out, outlen);
}

int wcctl_ping(wcctl_t *c, char *out, int outlen) {
    return wcctl_call(c, "{\"cmd\":\"ping\"}", out, outlen);
}

int wcctl_click(wcctl_t *c, const char *id, char *out, int outlen) {
    if (!id) return -1;
    char req[1024];
    snprintf(req, sizeof(req), "{\"cmd\":\"click\",\"id\":\"%s\"}", id);
    return wcctl_call(c, req, out, outlen);
}
