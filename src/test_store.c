#include "store.h"
#include <stdio.h>
#include <string.h>

int main(void) {
    const char* dir = "/tmp/opencode/wcstore";
    wc_store_t* s = wc_store_open(dir, 64 * 1024 * 1024);
    if (!s) { printf("open failed\n"); return 1; }

    wc_item_t it;
    memset(&it, 0, sizeof(it));
    strcpy(it.question, "abandon");
    strcpy(it.answer, "vt. 放弃, 抛弃");
    strcpy(it.explanation, "He abandoned the ship.");
    strcpy(it.hint, "ә'bændәn");
    strcpy(it.tags, "dict:cet4");
    uint32_t id = wc_store_add_item(s, &it);
    printf("add item id=%u\n", id);

    /* 幂等 */
    uint32_t id2 = wc_store_add_item(s, &it);
    printf("add again id=%u (same=%d)\n", id2, id2 == id);

    wc_item_t got;
    if (wc_store_get_item(s, id, &got) == 0)
        printf("get: %s | %s | %s | %s\n", got.question, got.answer, got.hint, got.tags);
    printf("find_by_word(abandon)=%u\n", wc_store_find_by_word(s, "Abandon"));

    wc_mem_t m;
    wc_store_sm2(s, 1, id, 5, &m);
    printf("after q=5: status=%u reps=%u iv=%u ef=%.2f next=%u overall=%u\n",
           m.status, m.repetitions, m.interval_days, m.ef, m.next_review, m.overall);
    wc_store_sm2(s, 1, id, 5, &m);
    printf("after q=5: reps=%u iv=%u\n", m.repetitions, m.interval_days);
    wc_store_sm2(s, 1, id, 1, &m);
    printf("after q=1: status=%u reps=%u iv=%u forget=%u\n",
           m.status, m.repetitions, m.interval_days, m.forget_count);

    uint32_t due[16];
    size_t n = wc_store_due(s, 1, (uint32_t)time(NULL), due, 16);
    printf("due now=%zu\n", n);
    n = wc_store_due(s, 1, (uint32_t)time(NULL) + 100 * 86400, due, 16);
    printf("due +100d=%zu (expect 1)\n", n);

    wc_store_sync(s);
    wc_store_close(s);
    printf("OK\n");
    return 0;
}
