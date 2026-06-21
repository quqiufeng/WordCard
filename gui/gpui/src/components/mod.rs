use gpui::{
    div, px, rgb, AnyElement, App, FontWeight, IntoElement, ParentElement, RenderOnce,
    SharedString, Styled, StyleRefinement, Window,
};
use gpui::prelude::*;
use gpui_component::{h_flex, v_flex};

/// C 函数：请求导航（由 Rust on_mouse_down 调用）
extern "C" {
    fn wordcard_nav_request(dir: i32);
}

pub fn ui_font() -> &'static str {
    "Noto Sans CJK SC, Source Han Sans SC, WenQuanYi Micro Hei, \
     PingFang SC, Microsoft YaHei, sans-serif"
}

pub fn mono_font() -> &'static str {
    "Noto Sans Mono CJK SC, Source Han Mono SC, \
     WenQuanYi Micro Hei Mono, monospace"
}

/* ======================================================================
 * ChapterTree — 左侧章节目录树
 * ====================================================================== */

#[derive(Clone)]
pub struct ChapterNode {
    pub label: SharedString,
    pub path: SharedString,     // 完整路径 chapters/xxx/page_0000
    pub children: Vec<ChapterNode>,
    pub page_count: usize,
}

#[derive(IntoElement)]
pub struct ChapterTree {
    pub chapters: Vec<ChapterNode>,
    pub active_path: SharedString,
    pub collapsed: std::collections::HashSet<usize>,
    style: StyleRefinement,
    children: Vec<AnyElement>,
}

impl ChapterTree {
    pub fn new(chapters: Vec<ChapterNode>) -> Self {
        Self {
            chapters,
            active_path: SharedString::default(),
            collapsed: std::collections::HashSet::new(),
            style: StyleRefinement::default(),
            children: Vec::new(),
        }
    }
    pub fn active(mut self, p: impl Into<SharedString>) -> Self { self.active_path = p.into(); self }
    pub fn collapse(mut self, idx: usize) -> Self { self.collapsed.insert(idx); self }
}

impl RenderOnce for ChapterTree {
    fn render(self, _: &mut Window, _cx: &mut App) -> impl IntoElement {
        v_flex()
            .gap(px(2.0))
            .children(self.chapters.into_iter().enumerate().map(|(idx, ch)| {
                let is_active = ch.path == self.active_path
                    || self.active_path.as_ref().starts_with(ch.path.as_ref());
                let is_collapsed = self.collapsed.contains(&idx);
                let has_children = !ch.children.is_empty();

                let row = div()
                    .px_2()
                    .py(px(4.0))
                    .rounded_md()
                    .bg(if is_active { rgb(0xeef0ff) } else { rgb(0xffffff) })
                    .cursor_pointer()
                    .child(
                        h_flex()
                            .child(
                                div()
                                    .text_sm()
                                    .font_weight(if is_active { FontWeight::BOLD } else { FontWeight::NORMAL })
                                    .text_color(if is_active { rgb(0x6c5ce7) } else { rgb(0x2d3436) })
                                    .font_family(ui_font())
                                    .child(if has_children && !is_collapsed { "📂 " } else if has_children { "📁 " } else { "📄 " }),
                            )
                            .child(
                                div()
                                    .text_sm()
                                    .font_weight(if is_active { FontWeight::BOLD } else { FontWeight::NORMAL })
                                    .text_color(if is_active { rgb(0x6c5ce7) } else { rgb(0x2d3436) })
                                    .font_family(ui_font())
                                    .child(ch.label.clone()),
                            )
                            .child(
                                div()
                                    .ml_1()
                                    .text_sm()
                                    .text_color(rgb(0xb2bec3))
                                    .font_family(ui_font())
                                    .child(format!("({})", ch.page_count)),
                            ),
                    );

                if has_children && !is_collapsed {
                    v_flex()
                        .pl_3()
                        .child(row)
                        .children(ch.children.into_iter().map(|child| {
                            let child_active = child.path == self.active_path;
                            div()
                                .px_2()
                                .py(px(2.0))
                                .pl_4()
                                .rounded_md()
                                .bg(if child_active { rgb(0xf0f0ff) } else { rgb(0xffffff) })
                                .cursor_pointer()
                                .child(
                                    div()
                                        .text_sm()
                                        .text_color(if child_active { rgb(0x6c5ce7) } else { rgb(0x636e72) })
                                        .font_family(ui_font())
                                        .child(child.label),
                                )
                                .into_any_element()
                        }))
                        .into_any_element()
                } else {
                    row.into_any_element()
                }
            }))
    }
}

/* ======================================================================
 * ReaderContent — 右侧阅读区（Markdown 渲染）
 * ====================================================================== */

#[derive(IntoElement)]
pub struct ReaderContent {
    pub content: SharedString,
    pub title: SharedString,
    pub page_info: SharedString,
    style: StyleRefinement,
    children: Vec<AnyElement>,
}

impl ReaderContent {
    pub fn new() -> Self {
        Self {
            content: SharedString::default(),
            title: SharedString::default(),
            page_info: SharedString::default(),
            style: StyleRefinement::default(),
            children: Vec::new(),
        }
    }
    pub fn content(mut self, s: impl Into<SharedString>) -> Self { self.content = s.into(); self }
    pub fn title(mut self, s: impl Into<SharedString>) -> Self { self.title = s.into(); self }
    pub fn page_info(mut self, s: impl Into<SharedString>) -> Self { self.page_info = s.into(); self }
}

impl RenderOnce for ReaderContent {
    fn render(self, _: &mut Window, _cx: &mut App) -> impl IntoElement {
        v_flex()
            .size_full()
            .p_6()
            .child(
                div()
                    .pb_3()
                    .border_b_1()
                    .border_color(rgb(0xe0e0e0))
                    .child(
                        div()
                            .text_xl()
                            .font_weight(FontWeight::BOLD)
                            .text_color(rgb(0x2d3436))
                            .font_family(ui_font())
                            .child(self.title),
                    )
                    .child(
                        div()
                            .mt_1()
                            .text_sm()
                            .text_color(rgb(0xb2bec3))
                            .font_family(ui_font())
                            .child(self.page_info),
                    ),
            )
            .child(
                div()
                    .mt_4()
                    .flex_1()
                    .children(render_markdown(&self.content)),
            )
    }
}

/* ======================================================================
 * NavBar — 底部导航条
 * ====================================================================== */

#[derive(IntoElement)]
pub struct NavBar {
    pub prev_label: SharedString,
    pub next_label: SharedString,
    pub has_prev: bool,
    pub has_next: bool,
    pub progress: (usize, usize),
    style: StyleRefinement,
    children: Vec<AnyElement>,
}

impl NavBar {
    pub fn new() -> Self {
        Self {
            prev_label: SharedString::default(),
            next_label: SharedString::default(),
            has_prev: false, has_next: false,
            progress: (0, 0),
            style: StyleRefinement::default(),
            children: Vec::new(),
        }
    }
    pub fn has_prev(mut self, v: bool) -> Self { self.has_prev = v; self }
    pub fn has_next(mut self, v: bool) -> Self { self.has_next = v; self }
}

impl RenderOnce for NavBar {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let (cur, total) = self.progress;
        h_flex()
            .w_full()
            .px_4()
            .py_3()
            .bg(rgb(0xffffff))
            .border_t_1()
            .border_color(rgb(0xe0e0e0))
            .child(
                div()
                    .flex_1()
                    .px_4()
                    .py_2()
                    .rounded_md()
                    .bg(if self.has_prev { rgb(0xf0f0f3) } else { rgb(0xfafafa) })
                    .text_center()
                    .cursor_pointer()
                    .when(self.has_prev, |this| {
                        this.on_mouse_down(gpui::MouseButton::Left, |_, _window, _cx| {
                            unsafe { wordcard_nav_request(1); }
                        })
                    })
                    .child(
                        div()
                            .text_sm()
                            .text_color(if self.has_prev { rgb(0x2d3436) } else { rgb(0xb2bec3) })
                            .font_family(ui_font())
                            .child(if self.has_prev { format!("◀  {}", self.prev_label) } else { "".into() }),
                    ),
            )
            .child(
                div()
                    .px_4()
                    .text_sm()
                    .text_color(rgb(0xb2bec3))
                    .font_family(ui_font())
                    .child(format!("{}/{}", cur, total)),
            )
            .child(
                div()
                    .flex_1()
                    .px_4()
                    .py_2()
                    .rounded_md()
                    .bg(if self.has_next { rgb(0xf0f0f3) } else { rgb(0xfafafa) })
                    .text_center()
                    .cursor_pointer()
                    .when(self.has_next, |this| {
                        this.on_mouse_down(gpui::MouseButton::Left, |_, _window, _cx| {
                            unsafe { wordcard_nav_request(2); }
                        })
                    })
                    .child(
                        div()
                            .text_sm()
                            .text_color(if self.has_next { rgb(0x2d3436) } else { rgb(0xb2bec3) })
                            .font_family(ui_font())
                            .child(if self.has_next { format!("{}  ▶", self.next_label) } else { "".into() }),
                    ),
            )
    }
}

/* ======================================================================
 * Breadcrumb — 顶部面包屑导航
 * ====================================================================== */

#[derive(IntoElement)]
pub struct Breadcrumb {
    pub book_title: SharedString,
    pub chapter_title: SharedString,
    style: StyleRefinement,
    children: Vec<AnyElement>,
}

impl Breadcrumb {
    pub fn new(book: impl Into<SharedString>) -> Self {
        Self {
            book_title: book.into(),
            chapter_title: SharedString::default(),
            style: StyleRefinement::default(),
            children: Vec::new(),
        }
    }
    pub fn chapter(mut self, s: impl Into<SharedString>) -> Self { self.chapter_title = s.into(); self }
}

impl RenderOnce for Breadcrumb {
    fn render(self, _: &mut Window, _cx: &mut App) -> impl IntoElement {
        h_flex()
            .px_4()
            .py_2()
            .bg(rgb(0xf8f9fa))
            .border_b_1()
            .border_color(rgb(0xe0e0e0))
            .child(
                div()
                    .text_sm()
                    .text_color(rgb(0x6c5ce7))
                    .font_family(ui_font())
                    .font_weight(FontWeight::BOLD)
                    .child(self.book_title),
            )
            .child(
                div()
                    .px_2()
                    .text_sm()
                    .text_color(rgb(0xb2bec3))
                    .font_family(ui_font())
                    .child("›"),
            )
            .child(
                div()
                    .text_sm()
                    .text_color(rgb(0x636e72))
                    .font_family(ui_font())
                    .child(self.chapter_title),
            )
    }
}

/* ======================================================================
 * Markdown 渲染（基础版：标题/段落/列表/代码）
 * ====================================================================== */

fn render_markdown(text: &str) -> Vec<AnyElement> {
    let mut elements: Vec<AnyElement> = Vec::new();
    let mut paragraph = String::new();
    let mut in_code = false;
    let mut code_lang = String::new();
    let mut code_buf = String::new();

    fn flush_para(p: &mut String, els: &mut Vec<AnyElement>) {
        if !p.trim().is_empty() {
            els.push(
                div()
                    .mb_3()
                    .child(p.trim().to_string())
                    .text_base()
                    .text_color(rgb(0x2d3436))
                    .font_family(ui_font())
                    .line_height(px(28.0))
                    .into_any_element(),
            );
        }
        p.clear();
    }

    for line in text.lines() {
        let trimmed = line.trim();
        if in_code {
            if trimmed.starts_with("```") {
                in_code = false;
                flush_para(&mut paragraph, &mut elements);
                elements.push(
                    div()
                        .p_3()
                        .mb_3()
                        .bg(rgb(0xf8f9fa))
                        .rounded_md()
                        .font_family(mono_font())
                        .text_sm()
                        .text_color(rgb(0x2d3436))
                        .child(code_buf.clone())
                        .into_any_element(),
                );
                code_buf.clear();
                continue;
            }
            code_buf.push_str(line);
            code_buf.push('\n');
            continue;
        }
        if trimmed.starts_with("```") {
            in_code = true;
            code_lang = trimmed.trim_start_matches("```").to_string();
            flush_para(&mut paragraph, &mut elements);
            continue;
        }
        if trimmed.starts_with("# ") {
            flush_para(&mut paragraph, &mut elements);
            elements.push(
                div()
                    .mb_3()
                    .child(trimmed.trim_start_matches("# ").to_string())
                    .text_2xl()
                    .font_weight(FontWeight::BOLD)
                    .text_color(rgb(0x2d3436))
                    .font_family(ui_font())
                    .into_any_element(),
            );
        } else if trimmed.starts_with("## ") {
            flush_para(&mut paragraph, &mut elements);
            elements.push(
                div()
                    .mb_3()
                    .child(trimmed.trim_start_matches("## ").to_string())
                    .text_xl()
                    .font_weight(FontWeight::BOLD)
                    .text_color(rgb(0x2d3436))
                    .font_family(ui_font())
                    .into_any_element(),
            );
        } else if trimmed.starts_with("- ") || trimmed.starts_with("* ") {
            flush_para(&mut paragraph, &mut elements);
            elements.push(
                h_flex()
                    .mb_2()
                    .gap_2()
                    .child(
                        div()
                            .text_base()
                            .text_color(rgb(0x6c5ce7))
                            .child("•"),
                    )
                    .child(
                        div()
                            .flex_1()
                            .text_base()
                            .text_color(rgb(0x2d3436))
                            .font_family(ui_font())
                            .child(trimmed.trim_start_matches("- ").trim_start_matches("* ").to_string()),
                    )
                    .into_any_element(),
            );
        } else if trimmed.is_empty() {
            flush_para(&mut paragraph, &mut elements);
        } else {
            if !paragraph.is_empty() { paragraph.push(' '); }
            paragraph.push_str(line);
        }
    }

    flush_para(&mut paragraph, &mut elements);
    if in_code {
        elements.push(
            div()
                .p_3()
                .bg(rgb(0xf8f9fa))
                .rounded_md()
                .font_family(mono_font())
                .text_sm()
                .child(code_buf)
                .into_any_element(),
        );
    }

    elements
}
