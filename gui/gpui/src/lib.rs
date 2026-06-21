use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use gpui::{
    div, px, rgb, size, App, AppContext, Bounds, Context, Entity, EventEmitter,
    ForegroundExecutor, IntoElement, ParentElement, Render, Styled,
    Window, WindowBounds, WindowOptions,
};
use gpui::prelude::FluentBuilder as _;
use gpui_component::{v_flex, h_flex};

mod components;
use components::*;

// ====== 章节树节点（从 Lua/C 传入）======

#[derive(Clone, Debug, serde::Deserialize)]
pub struct ChapterInfo {
    pub label: String,
    pub path: String,         // chapters/xx/page_0000
    pub children: Vec<ChapterInfo>,
    pub page_count: usize,
}

// ====== 阅读器应用状态 ======

pub struct GuiApp {
    pub chapters: Arc<Mutex<Vec<ChapterInfo>>>,
    pub current_path: Arc<Mutex<String>>,
    pub current_title: Arc<Mutex<String>>,
    pub current_content: Arc<Mutex<String>>,
    pub has_next: Arc<Mutex<bool>>,
    pub has_prev: Arc<Mutex<bool>>,
    pub current_idx: Arc<Mutex<usize>>,
    pub total_pages: Arc<Mutex<usize>>,
    pub title: String,
    pub book_title: Arc<Mutex<String>>,

    /// Lua state
    pub lua_state: *mut c_void,
    pub view: Mutex<Option<gpui::WeakEntity<ReaderView>>>,
    pub executor: Mutex<Option<ForegroundExecutor>>,
}

impl GuiApp {
    fn refresh_ui(&self) {}
}

unsafe impl Send for GuiApp {}
unsafe impl Sync for GuiApp {}

// ====== C FFI: 生命周期 ======

#[no_mangle]
pub extern "C" fn gui_app_create(config_json: *const c_char) -> *mut c_void {
    if config_json.is_null() { return std::ptr::null_mut(); }
    let s = unsafe { CStr::from_ptr(config_json).to_string_lossy() };
    let (title, book) = if let Ok(v) = serde_json::from_str::<serde_json::Value>(&s) {
        let t = v.get("title").and_then(|x| x.as_str()).unwrap_or("WordCard Reader");
        let b = v.get("book").and_then(|x| x.as_str()).unwrap_or("Book");
        (t.to_string(), b.to_string())
    } else { ("WordCard Reader".into(), "Book".into()) };

    let app = GuiApp {
        chapters: Arc::new(Mutex::new(Vec::new())),
        current_path: Arc::new(Mutex::new(String::new())),
        current_title: Arc::new(Mutex::new(String::new())),
        current_content: Arc::new(Mutex::new(String::new())),
        has_next: Arc::new(Mutex::new(false)),
        has_prev: Arc::new(Mutex::new(false)),
        current_idx: Arc::new(Mutex::new(0)),
        total_pages: Arc::new(Mutex::new(0)),
        title, book_title: Arc::new(Mutex::new(book)),
        lua_state: std::ptr::null_mut(),
        view: Mutex::new(None),
        executor: Mutex::new(None),
    };
    Box::into_raw(Box::new(app)) as *mut c_void
}

#[no_mangle]
pub extern "C" fn gui_app_free(app: *mut c_void) {
    if !app.is_null() { unsafe { drop(Box::from_raw(app as *mut GuiApp)); } }
}

// ====== C FFI: 加载书籍 ======

#[no_mangle]
pub extern "C" fn gui_set_chapters(app: *mut c_void, json: *const c_char) {
    if app.is_null() || json.is_null() { return; }
    let s = unsafe { CStr::from_ptr(json).to_string_lossy() };
    let app: &GuiApp = unsafe { &*(app as *mut GuiApp) };
    if let Ok(chs) = serde_json::from_str::<Vec<ChapterInfo>>(&s) {
        *app.chapters.lock().unwrap() = chs;
        app.refresh_ui();
    }
}

#[no_mangle]
pub extern "C" fn gui_set_page(app: *mut c_void, path: *const c_char, title: *const c_char, content: *const c_char) {
    if app.is_null() { return; }
    let app: &GuiApp = unsafe { &*(app as *mut GuiApp) };
    let p = if path.is_null() { String::new() } else { unsafe { CStr::from_ptr(path).to_string_lossy().to_string() } };
    let t = if title.is_null() { String::new() } else { unsafe { CStr::from_ptr(title).to_string_lossy().to_string() } };
    let c = if content.is_null() { String::new() } else { unsafe { CStr::from_ptr(content).to_string_lossy().to_string() } };
    *app.current_path.lock().unwrap() = p;
    *app.current_title.lock().unwrap() = t;
    *app.current_content.lock().unwrap() = c;
    app.refresh_ui();
}

#[no_mangle]
pub extern "C" fn gui_set_nav(app: *mut c_void, has_prev: c_int, has_next: c_int, idx: c_int, total: c_int) {
    if app.is_null() { return; }
    let app: &GuiApp = unsafe { &*(app as *mut GuiApp) };
    *app.has_prev.lock().unwrap() = has_prev != 0;
    *app.has_next.lock().unwrap() = has_next != 0;
    *app.current_idx.lock().unwrap() = idx as usize;
    *app.total_pages.lock().unwrap() = total as usize;
    app.refresh_ui();
}

#[no_mangle]
pub extern "C" fn gui_set_book_title(app: *mut c_void, title: *const c_char) {
    if app.is_null() || title.is_null() { return; }
    let app: &GuiApp = unsafe { &*(app as *mut GuiApp) };
    *app.book_title.lock().unwrap() = unsafe { CStr::from_ptr(title).to_string_lossy().to_string() };
    app.refresh_ui();
}

// ====== C FFI: Lua 回调桩 ======

extern "C" {
    fn wordcard_gui_tick(lua_state: *mut c_void);
}

// ====== 页面到字符串 ======

fn string_to_c(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(c) => c.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

// ====== ReaderView ======

struct ReaderView {
    app: *mut GuiApp,
    scroll_handle: gpui::ScrollHandle,
}

impl Render for ReaderView {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let app = self.app;
        let a: &GuiApp = unsafe { &*app };

        let chapters = a.chapters.lock().unwrap().clone();
        let path = a.current_path.lock().unwrap().clone();
        let title = a.current_title.lock().unwrap().clone();
        let content = a.current_content.lock().unwrap().clone();
        let has_next = *a.has_next.lock().unwrap();
        let has_prev = *a.has_prev.lock().unwrap();
        let idx = *a.current_idx.lock().unwrap();
        let total = *a.total_pages.lock().unwrap();
        let book = a.book_title.lock().unwrap().clone();

        let bg = rgb(0xf8f9fa);
        let panel_bg = rgb(0xffffff);
        let border = rgb(0xe0e0e0);

        // 左侧：目录树
        let chap_nodes: Vec<ChapterNode> = chapters.into_iter().map(|c| {
            ChapterNode {
                label: c.label.into(),
                path: c.path.into(),
                children: c.children.into_iter().map(|ch| ChapterNode {
                    label: format!("Page {}", ch.label).into(),
                    path: ch.path.into(),
                    children: Vec::new(),
                    page_count: 1,
                }).collect(),
                page_count: c.page_count,
            }
        }).collect();

        let sidebar = v_flex()
            .w(px(280.0))
            .min_w(px(220.0))
            .h_full()
            .bg(panel_bg)
            .border_r_1()
            .border_color(border)
            .child(
                // 书籍标题
                div()
                    .px_3()
                    .py_3()
                    .border_b_1()
                    .border_color(border)
                    .child(
                        div()
                            .text_base()
                            .font_weight(gpui::FontWeight::BOLD)
                            .text_color(rgb(0x6c5ce7))
                            .font_family(components::ui_font())
                            .child(format!("📖 {}", book)),
                    ),
            )
            .child(
                div()
                    .flex_1()
                    .py_2()
                    .child(ChapterTree::new(chap_nodes).active(path.clone())),
            );

        // 右侧：阅读区
        let reader = v_flex()
            .flex_1()
            .bg(bg)
            .child(
                div()
                    .flex_1()
                    .child(
                        ReaderContent::new()
                            .title(title)
                            .page_info(format!("{}/{}", idx + 1, total))
                            .content(content),
                    ),
            )
            .child({
                let mut nb = NavBar::new();
                nb.progress = (idx.saturating_add(1), total);
                nb.has_prev = has_prev;
                nb.has_next = has_next;
                nb
            });

        h_flex()
            .size_full()
            .bg(bg)
            .child(sidebar)
            .child(reader)
    }
}

impl gpui::EventEmitter<gpui_component::input::InputEvent> for ReaderView {}

// ====== GUI 入口 ======

#[no_mangle]
pub extern "C" fn gui_run(app_ptr: *mut c_void, lua_state: *mut c_void) -> c_int {
    if app_ptr.is_null() { return -1; }
    {
        let app: &mut GuiApp = unsafe { &mut *(app_ptr as *mut GuiApp) };
        app.lua_state = lua_state;
    }
    let app_ptr = app_ptr as *mut GuiApp;

    gpui_platform::application().run(move |cx: &mut App| {
        gpui_component::init(cx);
        cx.activate(true);

        let executor = cx.foreground_executor().clone();
        {
            let app: &mut GuiApp = unsafe { &mut *app_ptr };
            *app.executor.lock().unwrap() = Some(executor);
        }

        let bounds = Bounds::centered(None, size(px(1200.0), px(800.0)), cx);
        let title = unsafe { (*app_ptr).title.clone() };

        cx.open_window(
            WindowOptions {
                window_bounds: Some(gpui::WindowBounds::Windowed(bounds)),
                window_min_size: Some(size(px(800.), px(600.))),
                titlebar: Some(gpui::TitlebarOptions {
                    title: Some(title.into()),
                    ..Default::default()
                }),
                ..Default::default()
            },
            move |_window, cx| {
                let view = cx.new(|cx| {
                    let v = ReaderView {
                        app: app_ptr,
                        scroll_handle: gpui::ScrollHandle::new(),
                    };

                    // 定时器驱动 Lua tick
                    cx.spawn(async move |this, cx| {
                        loop {
                            cx.background_executor()
                                .timer(Duration::from_millis(50))
                                .await;
                            unsafe {
                                let app: &GuiApp = &*app_ptr;
                                if !app.lua_state.is_null() {
                                    wordcard_gui_tick(app.lua_state);
                                }
                            }
                            this.update(cx, |_this, cx| cx.notify()).ok();
                        }
                    }).detach();

                    v
                });

                {
                    let app: &mut GuiApp = unsafe { &mut *app_ptr };
                    *app.view.lock().unwrap() = Some(view.downgrade());
                }

                view
            },
        );
    });
    0
}
