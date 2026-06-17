use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use gpui::{
    div, px, rgb, size, App, AppContext, Bounds, Context, Entity, EventEmitter,
    ForegroundExecutor, IntoElement, ParentElement, Render, ScrollHandle,
    Styled, Window, WindowBounds, WindowOptions,
};
use gpui::prelude::FluentBuilder as _;
use gpui_component::{
    button::{Button, ButtonVariants},
    input::{Input, InputEvent, InputState, TabSize},
    scroll::ScrollableElement,
    v_flex, h_flex, Root,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::OnceLock;

mod components;
use components::*;

// ====== WordCard App State ======

/// A single item in the study queue.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CardItem {
    pub item_id: u32,
    pub question: String,
    pub answer: String,
    pub mode: u8,        // 1=flashcard, 2=choice, 3=fillblank, ...
    pub mode_name: String,
    pub explanation: String,
    pub hint: String,
}

/// Learning statistics snapshot.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StudyStats {
    pub mastered: usize,
    pub learning: usize,
    pub new_count: usize,
    pub streak: usize,
    pub today_reviewed: usize,
    pub today_correct: usize,
}

/// Result of a single review submission.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ReviewResult {
    pub correct: bool,
    pub overall: u8,
    pub next_interval: u16,
    pub repetitions: u16,
    pub ease_factor: f32,
    pub recommended_mode: String,
}

/// Opaque handle to the WordCard GUI runtime.
pub struct GuiApp {
    /// Study queue (cards due for review + new cards).
    pub queue: Arc<Mutex<Vec<CardItem>>>,
    pub queue_offset: Arc<Mutex<usize>>,       // current position in queue

    /// Current card being studied (extracted from queue for C API convenience).
    pub current_question: Arc<Mutex<String>>,
    pub current_answer: Arc<Mutex<String>>,
    pub current_mode: Arc<Mutex<u8>>,
    pub current_item_id: Arc<Mutex<u32>>,

    /// Whether the current card has been flipped (answer visible).
    pub flipped: Arc<Mutex<bool>>,

    /// Whether we are waiting for the user to submit an answer.
    pub awaiting_answer: Arc<Mutex<bool>>,

    /// The most recent review result (shown as feedback).
    pub last_result: Arc<Mutex<Option<ReviewResult>>>,

    /// Answer input buffer for spelling/dictation modes.
    pub answer_buffer: Arc<Mutex<String>>,

    /// Stats updated by C callbacks.
    pub stats: Arc<Mutex<StudyStats>>,

    /// Window title.
    pub title: String,

    /// Data directory (where wordcard.db and cache live).
    pub data_dir: PathBuf,

    /// Lua state pointer for timer tick callbacks.
    pub lua_state: *mut c_void,

    /// Weak handle to the WordCardView entity for UI notifications.
    pub view: Mutex<Option<gpui::WeakEntity<WordCardView>>>,

    /// Foreground executor for dispatching UI updates.
    pub executor: Mutex<Option<ForegroundExecutor>>,
}

impl GuiApp {
    fn refresh_ui(&self) {
        // The 16ms timer loop calls cx.notify() each frame.
    }
}

unsafe impl Send for GuiApp {}
unsafe impl Sync for GuiApp {}

// ====== C FFI: App Lifecycle ======

#[no_mangle]
pub extern "C" fn gui_app_create(config_json: *const c_char) -> *mut c_void {
    if config_json.is_null() { return std::ptr::null_mut(); }
    let config_str = unsafe { CStr::from_ptr(config_json).to_string_lossy() };
    let (title, data_dir) = match serde_json::from_str::<Value>(&config_str) {
        Ok(Value::Object(m)) => {
            let t = m.get("title").and_then(|v| v.as_str()).unwrap_or("WordCard").to_string();
            let d = m.get("data_dir").and_then(|v| v.as_str()).map(PathBuf::from).unwrap_or_else(|| PathBuf::from("."));
            (t, d)
        }
        _ => ("WordCard".to_string(), PathBuf::from(".")),
    };

    let app = GuiApp {
        queue: Arc::new(Mutex::new(Vec::new())),
        queue_offset: Arc::new(Mutex::new(0)),
        current_question: Arc::new(Mutex::new(String::new())),
        current_answer: Arc::new(Mutex::new(String::new())),
        current_mode: Arc::new(Mutex::new(1)),
        current_item_id: Arc::new(Mutex::new(0)),
        flipped: Arc::new(Mutex::new(false)),
        awaiting_answer: Arc::new(Mutex::new(false)),
        last_result: Arc::new(Mutex::new(None)),
        answer_buffer: Arc::new(Mutex::new(String::new())),
        stats: Arc::new(Mutex::new(StudyStats {
            mastered: 0, learning: 0, new_count: 0, streak: 0,
            today_reviewed: 0, today_correct: 0,
        })),
        title,
        data_dir,
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

// ====== C FFI: Study Queue ======

/// Set the study queue from C/Lua.
#[no_mangle]
pub extern "C" fn gui_set_queue(app: *mut c_void, queue_json: *const c_char) {
    if app.is_null() || queue_json.is_null() { return; }
    let json_str = unsafe { CStr::from_ptr(queue_json).to_string_lossy() };
    let app: &GuiApp = unsafe { &*(app as *mut GuiApp) };

    if let Ok(items) = serde_json::from_str::<Vec<CardItem>>(&json_str) {
        *app.queue.lock().unwrap() = items;
        *app.queue_offset.lock().unwrap() = 0;
        app.refresh_ui();
    }
}

/// Get the current queue as JSON (for Lua to display).
#[no_mangle]
pub extern "C" fn gui_get_queue(app: *mut c_void) -> *mut c_char {
    if app.is_null() { return std::ptr::null_mut(); }
    let app: &GuiApp = unsafe { &*(app as *mut GuiApp) };
    let queue = app.queue.lock().unwrap();
    string_to_c(serde_json::to_string(&*queue).unwrap_or_else(|_| "[]".to_string()))
}

/// Set the current card (question/answer/mode) for display.
#[no_mangle]
pub extern "C" fn gui_set_current_card(
    app: *mut c_void,
    item_id: u32,
    question: *const c_char,
    answer: *const c_char,
    mode: u8,
) {
    if app.is_null() || question.is_null() || answer.is_null() { return; }
    let q = unsafe { CStr::from_ptr(question).to_string_lossy().to_string() };
    let a = unsafe { CStr::from_ptr(answer).to_string_lossy().to_string() };
    let app: &GuiApp = unsafe { &*(app as *mut GuiApp) };
    *app.current_item_id.lock().unwrap() = item_id;
    *app.current_question.lock().unwrap() = q;
    *app.current_answer.lock().unwrap() = a;
    *app.current_mode.lock().unwrap() = mode;
    *app.flipped.lock().unwrap() = false;
    *app.awaiting_answer.lock().unwrap() = false;
    *app.last_result.lock().unwrap() = None;
    app.refresh_ui();
}

/// Toggle flip state (show answer).
#[no_mangle]
pub extern "C" fn gui_flip_card(app: *mut c_void) {
    if app.is_null() { return; }
    let app: &GuiApp = unsafe { &*(app as *mut GuiApp) };
    let mut f = app.flipped.lock().unwrap();
    *f = !*f;
    app.refresh_ui();
}

/// Set the answer input buffer (for spelling mode).
#[no_mangle]
pub extern "C" fn gui_set_answer(app: *mut c_void, text: *const c_char) {
    if app.is_null() || text.is_null() { return; }
    let t = unsafe { CStr::from_ptr(text).to_string_lossy().to_string() };
    let app: &GuiApp = unsafe { &*(app as *mut GuiApp) };
    *app.answer_buffer.lock().unwrap() = t;
}

/// Submit answer (triggers C callback via Lua tick).
#[no_mangle]
pub extern "C" fn gui_submit_answer(app: *mut c_void) {
    if app.is_null() { return; }
    let app: &GuiApp = unsafe { &*(app as *mut GuiApp) };
    *app.awaiting_answer.lock().unwrap() = false;
    app.refresh_ui();
}

/// Set the review result (shown as feedback after submission).
#[no_mangle]
pub extern "C" fn gui_set_result(app: *mut c_void, result_json: *const c_char) {
    if app.is_null() || result_json.is_null() { return; }
    let json_str = unsafe { CStr::from_ptr(result_json).to_string_lossy() };
    let app: &GuiApp = unsafe { &*(app as *mut GuiApp) };
    if let Ok(r) = serde_json::from_str::<ReviewResult>(&json_str) {
        *app.last_result.lock().unwrap() = Some(r);
        app.refresh_ui();
    }
}

// ====== C FFI: Stats ======

/// Update stats from C/Lua.
#[no_mangle]
pub extern "C" fn gui_set_stats(app: *mut c_void, stats_json: *const c_char) {
    if app.is_null() || stats_json.is_null() { return; }
    let json_str = unsafe { CStr::from_ptr(stats_json).to_string_lossy() };
    let app: &GuiApp = unsafe { &*(app as *mut GuiApp) };
    if let Ok(s) = serde_json::from_str::<StudyStats>(&json_str) {
        *app.stats.lock().unwrap() = s;
        app.refresh_ui();
    }
}

/// Get stats as JSON (for Lua).
#[no_mangle]
pub extern "C" fn gui_get_stats(app: *mut c_void) -> *mut c_char {
    if app.is_null() { return std::ptr::null_mut(); }
    let app: &GuiApp = unsafe { &*(app as *mut GuiApp) };
    let stats = app.stats.lock().unwrap();
    string_to_c(serde_json::to_string(&*stats).unwrap_or_else(|_| "{}".to_string()))
}

/// Get total queue size.
#[no_mangle]
pub extern "C" fn gui_queue_count(app: *mut c_void) -> c_int {
    if app.is_null() { return 0; }
    let app: &GuiApp = unsafe { &*(app as *mut GuiApp) };
    app.queue.lock().unwrap().len() as c_int
}

/// Advance to the next card in queue.
#[no_mangle]
pub extern "C" fn gui_next_card(app: *mut c_void) -> c_int {
    if app.is_null() { return -1; }
    let app: &GuiApp = unsafe { &*(app as *mut GuiApp) };
    let mut off = app.queue_offset.lock().unwrap();
    let queue = app.queue.lock().unwrap();
    *off += 1;
    if *off >= queue.len() { return 0; } // queue exhausted
    let card = &queue[*off];
    *app.current_item_id.lock().unwrap() = card.item_id;
    *app.current_question.lock().unwrap() = card.question.clone();
    *app.current_answer.lock().unwrap() = card.answer.clone();
    *app.current_mode.lock().unwrap() = card.mode;
    *app.flipped.lock().unwrap() = false;
    *app.awaiting_answer.lock().unwrap() = false;
    *app.last_result.lock().unwrap() = None;
    app.refresh_ui();
    1
}

// ====== Internal Helpers ======

fn string_to_c(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(c) => c.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

extern "C" {
    fn wordcard_gui_tick(lua_state: *mut c_void);
}

// ====== WordCardView (Rendering) ======

struct WordCardView {
    app: *mut GuiApp,
    input_state: Entity<InputState>,
    scroll_handle: ScrollHandle,
    queue_len: usize,
    last_question_len: usize,
}

impl Render for WordCardView {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let app = self.app;
        let app_ref: &GuiApp = unsafe { &*app };

        let queue = app_ref.queue.lock().unwrap().clone();
        let offset = *app_ref.queue_offset.lock().unwrap();
        let flipped = *app_ref.flipped.lock().unwrap();
        let awaiting = *app_ref.awaiting_answer.lock().unwrap();
        let q = app_ref.current_question.lock().unwrap().clone();
        let a = app_ref.current_answer.lock().unwrap().clone();
        let mode = *app_ref.current_mode.lock().unwrap();
        let result = app_ref.last_result.lock().unwrap().clone();
        let stats = app_ref.stats.lock().unwrap().clone();
        let answer_buf = app_ref.answer_buffer.lock().unwrap().clone();

        let bg = rgb(0xf5f6fa);
        let border = rgb(0xe0e0e0);
        let ui = components::ui_font();

        // Determine mode name
        let mode_name = match mode {
            1 => "Flashcard", 2 => "Choice", 3 => "Fill in Blank",
            4 => "Spelling", 5 => "Dictation", 6 => "Pronunciation",
            7 => "Matching", 8 => "Speed Review",
            _ => "Study",
        };

        // ---- Left: Main Study Area ----
        let card_area = v_flex()
            .flex_1()
            .p_4()
            .gap_4()
            .bg(bg)
            .child(
                div()
                    .text_sm()
                    .text_color(rgb(0x6c5ce7))
                    .font_family(ui)
                    .child(format!("Mode: {}  |  Card {}/{}", mode_name, offset + 1, queue.len())),
            )
            .child(
                ProgressBar::new(offset, queue.len()),
            )
            .child(
                FlashCard::new(&q, &a).flipped(flipped),
            )
            .child(
                if let Some(r) = result {
                    if r.correct {
                        ScoreBadge::correct(format!("✓ Correct!  (Overall: {}%)", r.overall)).into_any_element()
                    } else {
                        ScoreBadge::wrong(format!("✗ Incorrect  (Overall: {}%)", r.overall)).into_any_element()
                    }
                } else if flipped && !awaiting {
                    v_flex()
                        .gap_2()
                        .child(
                            Button::new("correct")
                                .primary()
                                .label("✓ I Got It Right")
                                .w_full(),
                        )
                        .child(
                            Button::new("wrong")
                                .ghost()
                                .label("✗ I Got It Wrong")
                                .w_full(),
                        )
                        .into_any_element()
                } else if awaiting {
                    AnswerInput::new().placeholder_text(&answer_buf).into_any_element()
                } else {
                    div().into_any_element()
                },
            );

        // ---- Right: Stats Panel ----
        let stats_panel = v_flex()
            .w_1_4()
            .min_w(px(200.0))
            .max_w(px(320.0))
            .h_full()
            .border_l_1()
            .border_color(border)
            .bg(bg)
            .child(StatsWidget::new()
                .mastered(stats.mastered)
                .learning(stats.learning)
                .new_count(stats.new_count)
                .streak(stats.streak)
                .today_reviewed(stats.today_reviewed)
                .today_correct(stats.today_correct),
            )
            .child(
                ReviewQueue::new(
                    queue.iter().skip(offset).take(10).map(|c| c.question.clone().into()).collect()
                ).done_count(offset),
            );

        // ---- Bottom: Input + Status ----
        let status_bar = div()
            .p_2()
            .border_t_1()
            .border_color(border)
            .bg(rgb(0xffffff))
            .child(
                h_flex()
                    .justify_between()
                    .child(
                        div()
                            .text_sm()
                            .text_color(rgb(0xb2bec3))
                            .font_family(ui)
                            .child("WordCard v4.0"),
                    )
                    .child(
                        div()
                            .text_sm()
                            .text_color(rgb(0xb2bec3))
                            .font_family(ui)
                            .child(format!("Streak: {} days", stats.streak)),
                    ),
            );

        let main_area = v_flex()
            .flex_1()
            .size_full()
            .bg(bg)
            .child(card_area)
            .child(status_bar);

        h_flex()
            .size_full()
            .bg(bg)
            .child(main_area)
            .child(stats_panel)
    }
}

impl EventEmitter<InputEvent> for WordCardView {}

// ====== GUI Entry Point ======

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

        let bounds = Bounds::centered(None, size(px(960.0), px(680.0)), cx);
        let title = unsafe { (*app_ptr).title.clone() };

        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                window_min_size: Some(size(px(680.), px(480.))),
                titlebar: Some(gpui::TitlebarOptions {
                    title: Some(title.into()),
                    ..Default::default()
                }),
                ..Default::default()
            },
            move |window, cx| {
                let input_state = cx.new(|cx| {
                    InputState::new(window, cx)
                        .code_editor("markdown")
                        .multi_line(false)
                        .rows(2)
                        .line_number(false)
                        .folding(false)
                        .tab_size(TabSize { tab_size: 4, ..Default::default() })
                });

                let view = cx.new(|cx| {
                    let v = WordCardView {
                        app: app_ptr,
                        input_state,
                        scroll_handle: ScrollHandle::new(),
                        queue_len: 0,
                        last_question_len: 0,
                    };

                    // Timer loop: tick Lua, then refresh UI
                    cx.spawn(async move |this, cx| {
                        loop {
                            cx.background_executor()
                                .timer(Duration::from_millis(16))
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
