#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <stdint.h>
void wordcard_gui_tick(void *l){(void)l;}
void wordcard_gui_on_flip(void *l){(void)l;}
void wordcard_gui_on_answer(void *l,const char*t,int q){(void)l;(void)t;(void)q;}
void wordcard_gui_on_next(void *l){(void)l;}
int main(){
    void *h=dlopen("libwordcard_gui.so",RTLD_LAZY|RTLD_GLOBAL);
    if(!h){fprintf(stderr,"%s\n",dlerror());return 1;}
    void*(*c)(const char*)=dlsym(h,"gui_app_create");
    int(*r)(void*,void*)=dlsym(h,"gui_run");
    void(*q)(void*,const char*)=dlsym(h,"gui_set_queue");
    void(*s)(void*,uint32_t,const char*,const char*,uint8_t)=dlsym(h,"gui_set_current_card");
    void(*t)(void*,const char*)=dlsym(h,"gui_set_stats");
    void(*f)(void*)=dlsym(h,"gui_app_free");
    if(!c||!r)return 1;
    void*a=c("{\"title\":\"WordCard\",\"data_dir\":\".\"}");
    q(a,"[{\"item_id\":1,\"question\":\"abandon\",\"answer\":\"放弃；抛弃\",\"mode\":1,\"mode_name\":\"flashcard\",\"explanation\":\"\",\"hint\":\"\"},{\"item_id\":2,\"question\":\"ephemeral\",\"answer\":\"短暂的\",\"mode\":1,\"mode_name\":\"flashcard\",\"explanation\":\"\",\"hint\":\"\"},{\"item_id\":3,\"question\":\"ubiquitous\",\"answer\":\"无处不在\",\"mode\":1,\"mode_name\":\"flashcard\",\"explanation\":\"\",\"hint\":\"\"},{\"item_id\":4,\"question\":\"pragmatic\",\"answer\":\"务实的\",\"mode\":1,\"mode_name\":\"flashcard\",\"explanation\":\"\",\"hint\":\"\"}]");
    s(a,1,"abandon","放弃；抛弃",1);
    t(a,"{\"mastered\":12,\"learning\":8,\"new_count\":15,\"streak\":7,\"today_reviewed\":23,\"today_correct\":19}");
    r(a,NULL);
    f(a);dlclose(h);return 0;
}
