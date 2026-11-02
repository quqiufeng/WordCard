#!/bin/bash
# build.sh — WordCard 原生 CLI（StaticPy，自包含）
# 本地只保留本脚本；C/StaticPy 源码在构建时生成到 ~/.cache。
#
# 用法:
#   bash native/staticpy/cli/build.sh
#   LD_LIBRARY_PATH=native/staticpy/cli:src native/staticpy/cli/wc_cli stats
#   ... wc_cli dump [db] [out]
#   ... wc_cli add <question> <answer> <tags> [db]
#   ... wc_cli review <user_id> <item_id> <quality> [db]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/wordcard-staticpy-cli"
STATICPY_ROOT="${STATICPY_ROOT:-/opt/StaticPy}"
BUILD_COMPILER="$STATICPY_ROOT/staticpy/static_build_comfycli.sh"
FFI="$ROOT/native/staticpy/ffi.static.py"
mkdir -p "$BUILD" /tmp/opencode
[ -f "$BUILD_COMPILER" ] && [ -f "$FFI" ] || { echo "missing StaticPy compiler: $BUILD_COMPILER" >&2; exit 1; }


cat > "$BUILD/wc_cli.static.py" <<'PY'
extern fn wc_cli_version() -> str from "wc_cli"
extern fn wc_cli_stats(db_path: str) -> str from "wc_cli"
extern fn wc_cli_dump(db_path: str, out_path: str) -> int from "wc_cli"
extern fn wc_cli_add(db_path: str, q: str, a: str, tags: str) -> int from "wc_cli"
extern fn wc_cli_review(db_path: str, user_id: int, item_id: int, quality: int) -> int from "wc_cli"
extern fn wc_cli_card(db_path: str, item_id: int, out_path: str) -> int from "wc_cli"
extern fn wc_cli_dict(word: str, dict: str) -> str from "wc_cli"
extern fn wc_cli_list(db_path: str, tag: str, out_path: str) -> int from "wc_cli"
extern fn wc_cli_due(db_path: str, user_id: int, out_path: str) -> int from "wc_cli"
extern fn wc_cli_import(path: str, db: str, name: str, max_words: int) -> int from "wc_cli"
extern fn wc_cli_review_interactive(db_path: str, user_id: int) -> int from "wc_cli"

def main():
    args = list_to_py_list(argv())
    n: int = py_list_length(args)
    cmd: str = "stats"
    if n > 1:
        cmd = py_list_ref(args, 1)
    db: str = "data/wordcard.db"
    if cmd == "stats":
        print(wc_cli_version())
        print(wc_cli_stats(db))
    elif cmd == "dump":
        if n > 2:
            db = py_list_ref(args, 2)
        out: str = "/tmp/opencode/wc_cli_dump.tsv"
        if n > 3:
            out = py_list_ref(args, 3)
        print(wc_cli_dump(db, out))
    elif cmd == "add":
        if n < 5:
            print("usage: wc_cli add <question> <answer> <tags> [db]")
            exit_program(1)
        if n > 5:
            db = py_list_ref(args, 5)
        print(wc_cli_add(db, py_list_ref(args, 2), py_list_ref(args, 3), py_list_ref(args, 4)))
    elif cmd == "import":
        if n < 5:
            print("usage: wc_cli import <path> <db> <name> [max_words]")
            exit_program(1)
        mx: int = 50
        if n > 5: mx = string_to_int(py_list_ref(args, 5))
        print(wc_cli_import(py_list_ref(args, 2), py_list_ref(args, 3),
                            py_list_ref(args, 4), mx))
    elif cmd == "dict":
        if n < 3:
            print("usage: wc_cli dict <word> [dict.tsv]")
            exit_program(1)
        dict: str = "data/wordlists/cet4.tsv"
        if n > 3: dict = py_list_ref(args, 3)
        print(wc_cli_dict(py_list_ref(args, 2), dict))
    elif cmd == "list":
        if n < 3:
            print("usage: wc_cli list <tag> [db] [out.tsv]")
            exit_program(1)
        if n > 3: db = py_list_ref(args, 3)
        out: str = "/tmp/opencode/wc_cli_list.tsv"
        if n > 4: out = py_list_ref(args, 4)
        print(wc_cli_list(db, py_list_ref(args, 2), out))
    elif cmd == "due":
        if n < 3:
            print("usage: wc_cli due <user> [db] [out.tsv]")
            exit_program(1)
        if n > 3: db = py_list_ref(args, 3)
        out: str = "/tmp/opencode/wc_cli_due.tsv"
        if n > 4: out = py_list_ref(args, 4)
        print(wc_cli_due(db, string_to_int(py_list_ref(args, 2)), out))
    elif cmd == "review-interactive":
        if n < 3:
            print("usage: wc_cli review-interactive <user> [db]")
            exit_program(1)
        if n > 3: db = py_list_ref(args, 3)
        print(wc_cli_review_interactive(db, string_to_int(py_list_ref(args, 2))))
    elif cmd == "card":
        if n < 3:
            print("usage: wc_cli card <item_id> [db] [out.png]")
            exit_program(1)
        if n > 3: db = py_list_ref(args, 3)
        out: str = "/tmp/opencode/wc_cli_card.png"
        if n > 4: out = py_list_ref(args, 4)
        print(wc_cli_card(db, string_to_int(py_list_ref(args, 2)), out))
    elif cmd == "review":
        if n < 5:
            print("usage: wc_cli review <user> <item> <quality> [db]")
            exit_program(1)
        if n > 5:
            db = py_list_ref(args, 5)
        print(wc_cli_review(db, string_to_int(py_list_ref(args, 2)),
                            string_to_int(py_list_ref(args, 3)),
                            string_to_int(py_list_ref(args, 4))))
    else:
        print("usage: wc_cli stats|dump|add|review ...")
        exit_program(2)
PY

CC="${CC:-gcc}"
$CC -O2 -fPIC -shared -I"$ROOT/src" "$ROOT/native/src/wc_cli.c" \
  -L"$ROOT/src" -lwordcard -ltxt2png \
  -L"$HERE/../import_book" -lwc_import_book -L"$HERE/../import_wordlist" -lwc_import_wordlist \
  -L"$ROOT/importer/libs" -lmobiparse -lpdfparse -lepubparse -lwordpick \
  -Wl,-rpath,'$ORIGIN/../../../src:$ORIGIN/../import_book:$ORIGIN/../import_wordlist:$ORIGIN/../../../importer/libs' \
  -o "$HERE/libwc_cli.so"

sed '/^extern fn /d' "$BUILD/wc_cli.static.py" > "$BUILD/wc_cli.body.py"
grep -E '^extern fn wc_cli_' "$FFI" > "$BUILD/wc_cli.ffi.py"
cat "$BUILD/wc_cli.ffi.py" "$BUILD/wc_cli.body.py" > "$BUILD/wc_cli.combined.py"
bash "$BUILD_COMPILER" \
  "$BUILD/wc_cli.combined.py" wc_cli >/tmp/opencode/wc_cli_build.log 2>&1
mv -f "$STATICPY_ROOT/wc_cli" "$HERE/wc_cli"
mv -f "$STATICPY_ROOT/wc_cli.so" "$HERE/wc_cli.so"

echo "built: $HERE/wc_cli"
