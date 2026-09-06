#!/usr/bin/env python3
"""Generates Resources/Strings.resx (en) and Strings.ja.resx from the table below.

Every UI string of the Windows app lives here; Core returns keys, the app resolves them.
Usage: python3 scripts/make_resx.py
"""
import os
import sys
from xml.sax.saxutils import escape

STRINGS = [
    # key, English, Japanese
    ("App_Name", "Nori", "Nori"),
    # ActionGrammar verbs
    ("Verb_Paste", "Paste", "貼り付け"),
    ("Verb_PastePlain", "Paste as plain text", "書式なしで貼り付け"),
    ("Verb_PasteKeepOpen", "Paste and keep Nori open", "貼り付けて Nori を開いたまま"),
    ("Verb_PastePlainKeepOpen", "Paste plain, keep open", "書式なしで貼り付け、開いたまま"),
    ("Verb_Copy", "Copy", "コピー"),
    ("Verb_CopyPlain", "Copy as plain text", "書式なしでコピー"),
    ("Verb_CopyKeepOpen", "Copy, keep open", "コピーして開いたまま"),
    ("Verb_CopyPlainKeepOpen", "Copy plain, keep open", "書式なしでコピー、開いたまま"),
    ("Verb_PastePlainKeepOpen_Item", "Paste item plain, keep open", "項目を書式なしで貼り付け、開いたまま"),
    ("Verb_CopyPlainKeepOpen_Item", "Copy item plain, keep open", "項目を書式なしでコピー、開いたまま"),
    # Hint bar
    ("Hint_Plain", "Plain", "書式なし"),
    ("Hint_Preview", "Preview", "プレビュー"),
    ("Hint_Pin", "Pin", "ピン留め"),
    ("Hint_Delete", "Delete", "削除"),
    ("Hint_PasteItem", "Paste item", "項目を貼り付け"),
    ("Hint_CopyItem", "Copy item", "項目をコピー"),
    ("Hint_Open", "Open", "開く"),
    ("Hint_Reveal", "Reveal", "場所を表示"),
    ("Hint_Clear", "Clear…", "消去…"),
    ("Hint_Same", "Same", "同じ"),
    ("Hint_PasteItemPlain", "Paste item as plain text", "項目を書式なしで貼り付け"),
    ("Hint_PasteItemKeepOpen", "Paste item, keep open", "項目を貼り付け、開いたまま"),
    ("Hint_CopyItemPlain", "Copy item as plain text", "項目を書式なしでコピー"),
    ("Hint_CopyItemKeepOpen", "Copy item, keep open", "項目をコピー、開いたまま"),
    ("Hint_ToPaste", "to paste", "で貼り付け"),
    ("Hint_Move", "Move", "移動"),
    ("Hint_Cancel", "Cancel", "キャンセル"),
    ("Hint_CopyNoTarget", "Copy · no app to paste into", "コピー · 貼り付け先のアプリがありません"),
    # Search row
    ("Search_Placeholder", "Search", "検索"),
    ("Search_Paused", "Capture paused", "記録を一時停止中"),
    ("Search_PausedCountdown", "Capture paused · {0}", "記録を一時停止中 · {0}"),
    # Filter chips
    ("Filter_All", "All", "すべて"),
    ("Filter_Text", "Text", "テキスト"),
    ("Filter_Links", "Links", "リンク"),
    ("Filter_Code", "Code", "コード"),
    ("Filter_Colors", "Colors", "色"),
    ("Filter_Images", "Images", "画像"),
    ("Filter_Files", "Files", "ファイル"),
    # Sections
    ("Section_Pinned", "PINNED", "ピン留め"),
    ("Section_Today", "TODAY", "今日"),
    ("Section_Yesterday", "YESTERDAY", "昨日"),
    ("Section_Earlier", "EARLIER", "それ以前"),
    ("Section_Results", "RESULTS", "検索結果"),
    # Cards
    ("Card_Lines", "{0} lines", "{0} 行"),
    ("Card_Chars", "{0} chars", "{0} 文字"),
    ("Card_RichText", "Rich text", "リッチテキスト"),
    ("Card_Files", "{0} files", "{0} 個のファイル"),
    ("Card_ExpiresIn", "Expires in {0}", "あと {0} で消えます"),
    ("Card_Ghost_Concealed", "Concealed item from {0} wasn't saved", "{0} の非公開項目は保存されませんでした"),
    ("Card_Ghost_ConcealedUnknown", "Concealed item from an app wasn't saved", "アプリの非公開項目は保存されませんでした"),
    ("Card_Ghost_ImageTooLarge", "Image too large ({0}) wasn't saved", "大きすぎる画像 ({0}) は保存されませんでした"),
    ("Card_ImageCaption", "{0} × {1} · PNG · {2}", "{0} × {1} · PNG · {2}"),
    ("Card_Truncated", "Showing first 10,000 characters", "先頭の 10,000 文字を表示しています"),
    ("Card_Meta", "{0} · first copied {1} · last {2} · copied {3}×", "{0} · 初回 {1} · 最終 {2} · {3} 回コピー"),
    ("Card_Copied", "copied {0}×", "{0} 回コピー"),
    ("Expanded_Open", "Open", "開く"),
    ("Expanded_Reveal", "Reveal in Explorer", "エクスプローラーで表示"),
    # Empty states
    ("Empty_NothingTitle", "Nothing copied yet", "まだ何もコピーされていません"),
    ("Empty_NothingBody", "Copy something in any app — it shows up here.", "どのアプリでもコピーすると、ここに表示されます。"),
    ("Empty_NothingHotkey", "{0} opens Nori", "{0} で Nori を開きます"),
    ("Empty_NoMatches", "No matches for “{0}”", "“{0}” に一致する項目はありません"),
    ("Empty_NoMatchesHint", "Enter pastes “{0}” as text · Esc closes", "Enter で “{0}” をテキストとして貼り付け · Esc で閉じる"),
    ("Empty_Filter_Text", "No text yet", "テキストはまだありません"),
    ("Empty_Filter_Link", "No links yet", "リンクはまだありません"),
    ("Empty_Filter_Code", "No code yet", "コードはまだありません"),
    ("Empty_Filter_Color", "No colors yet", "色はまだありません"),
    ("Empty_Filter_Image", "No images yet", "画像はまだありません"),
    ("Empty_Filter_File", "No files yet", "ファイルはまだありません"),
    # Toasts
    ("Toast_Deleted", "Deleted · Ctrl+Z to undo", "削除しました · Ctrl+Z で元に戻す"),
    ("Toast_Copied", "Copied", "コピーしました"),
    ("Toast_Cleared", "Cleared {0} clips", "{0} 件を消去しました"),
    ("Toast_StoreReset", "History could not be opened and was reset", "履歴を開けなかったためリセットしました"),
    # Context menu
    ("Menu_Paste", "Paste", "貼り付け"),
    ("Menu_PastePlain", "Paste as Plain Text", "書式なしで貼り付け"),
    ("Menu_PasteKeepOpen", "Paste and Keep Open", "貼り付けて開いたまま"),
    ("Menu_Copy", "Copy", "コピー"),
    ("Menu_Preview", "Preview", "プレビュー"),
    ("Menu_Pin", "Pin", "ピン留め"),
    ("Menu_Unpin", "Unpin", "ピン留めを解除"),
    ("Menu_OpenInBrowser", "Open in Browser", "ブラウザーで開く"),
    ("Menu_Open", "Open", "開く"),
    ("Menu_Reveal", "Reveal in Explorer", "エクスプローラーで表示"),
    ("Menu_Delete", "Delete", "削除"),
    # Tray
    ("Tray_Open", "Open Nori", "Nori を開く"),
    ("Tray_Pause", "Pause Capture", "記録を一時停止"),
    ("Tray_Pause5", "For 5 Minutes", "5 分間"),
    ("Tray_Pause30", "For 30 Minutes", "30 分間"),
    ("Tray_PauseUntilResume", "Until I Resume", "再開するまで"),
    ("Tray_Resume", "Resume Capture", "記録を再開"),
    ("Tray_PausedCaption", "Paused · {0} left", "一時停止中 · 残り {0}"),
    ("Tray_SkipNext", "Skip Next Copy", "次のコピーを記録しない"),
    ("Tray_NotSaved", "{0} items not saved today", "今日 {0} 件が保存されませんでした"),
    ("Tray_NotSavedOne", "1 item not saved today", "今日 1 件が保存されませんでした"),
    ("Tray_ClearHistory", "Clear History…", "履歴を消去…"),
    ("Tray_Settings", "Settings…", "設定…"),
    ("Tray_About", "About Nori", "Nori について"),
    ("Tray_Quit", "Quit Nori", "Nori を終了"),
    ("Tray_Tooltip", "Nori — {0}", "Nori — {0}"),
    ("Tray_TooltipPaused", "Nori — capture paused", "Nori — 記録を一時停止中"),
    # Clear confirmation
    ("Clear_Title", "Clear History", "履歴を消去"),
    ("Clear_Body", "Remove {0} unpinned clips? Pinned clips stay.", "ピン留めされていない {0} 件を削除しますか？ ピン留めした項目は残ります。"),
    ("Clear_BodyPinned", "Remove all {0} clips, including pinned ones?", "ピン留めを含むすべての {0} 件を削除しますか？"),
    ("Clear_Confirm", "Clear", "消去"),
    ("Clear_IncludePinned", "Also remove pinned clips", "ピン留めした項目も削除する"),
    ("Dialog_Cancel", "Cancel", "キャンセル"),
    ("Dialog_OK", "OK", "OK"),
    # Settings
    ("Settings_Title", "Nori Settings", "Nori の設定"),
    ("Tab_General", "General", "一般"),
    ("Tab_Capture", "Capture", "記録"),
    ("Tab_Privacy", "Privacy", "プライバシー"),
    ("Tab_Look", "Look", "外観"),
    ("Tab_About", "About", "情報"),
    ("General_Hotkey", "Open Nori with", "Nori を開くショートカット"),
    ("General_HotkeyCaption", "In some apps Ctrl+Shift+V means “paste without formatting” — use Shift+Enter inside Nori instead, or pick another shortcut.", "アプリによっては Ctrl+Shift+V が「書式なしで貼り付け」に割り当てられています。その場合は Nori 内で Shift+Enter を使うか、別のショートカットを選んでください。"),
    ("General_StartWithWindows", "Start Nori when I sign in", "サインイン時に Nori を起動"),
    ("General_Position", "Show the panel", "パネルの表示位置"),
    ("Position_Cursor", "At the mouse pointer", "マウスポインターの位置"),
    ("Position_Center", "Center of the screen", "画面の中央"),
    ("Position_Tray", "Near the tray", "タスクトレイの近く"),
    ("General_ShowWelcome", "Show welcome again", "ようこそ画面をもう一度表示"),
    ("Capture_Remember", "Remember", "記録する内容"),
    ("Capture_Text", "Text", "テキスト"),
    ("Capture_Images", "Images", "画像"),
    ("Capture_Files", "Files", "ファイル"),
    ("Capture_KeepUpTo", "Keep up to", "保存する上限"),
    ("Capture_Clips", "clips (pinned clips don't count)", "件 (ピン留めは含まない)"),
    ("Capture_Forget", "Forget clips older than", "この期間より古い項目を削除"),
    ("Forget_Never", "Never", "削除しない"),
    ("Forget_Day", "1 day", "1 日"),
    ("Forget_Week", "1 week", "1 週間"),
    ("Forget_Month", "1 month", "1 か月"),
    ("Capture_LargestImage", "Largest image to keep", "保存する画像の最大サイズ"),
    ("Capture_IgnoreRegex", "Skip text matching these patterns (one regular expression per line)", "次のパターンに一致するテキストは記録しない (1 行に 1 つの正規表現)"),
    ("Privacy_IgnoredApps", "Don't remember copies from", "次のアプリからのコピーは記録しない"),
    ("Privacy_Add", "Add…", "追加…"),
    ("Privacy_Remove", "Remove", "削除"),
    ("Privacy_MaskSecrets", "Hide things that look like passwords or API keys", "パスワードや API キーらしきものを隠す"),
    ("Privacy_MaskSecretsCaption", "Shown masked, never saved to disk, forgotten after 10 minutes", "マスク表示され、ディスクには保存されず、10 分後に消えます"),
    ("Privacy_GhostRows", "Show a note in the list when something wasn't saved", "保存されなかった項目があるときに一覧に表示する"),
    ("Privacy_ClearOnQuit", "Clear history when Nori quits", "Nori の終了時に履歴を消去"),
    ("Privacy_StorageNote", "Clips are stored unencrypted in %LOCALAPPDATA%\\Nori. Use Pause for sensitive work.", "履歴は %LOCALAPPDATA%\\Nori に暗号化されずに保存されます。機密性の高い作業では一時停止を使ってください。"),
    ("Privacy_StorageUsed", "Storage used", "使用中のストレージ"),
    ("Privacy_StorageValue", "{0} · {1} clips · {2} pinned", "{0} · {1} 件 · ピン留め {2} 件"),
    ("Privacy_ClearHistory", "Clear History…", "履歴を消去…"),
    ("Look_AppIcons", "Show app icons on clips", "項目にアプリのアイコンを表示"),
    ("Look_Keycaps", "Show Ctrl+1–9 on clips", "項目に Ctrl+1–9 を表示"),
    ("Look_HintBar", "Show keyboard hints at the bottom of the panel", "パネルの下部にキーボードのヒントを表示"),
    ("About_Version", "Version {0}", "バージョン {0}"),
    ("About_Tagline", "A clipboard history that shows what you copied.", "コピーしたものが何かひと目でわかるクリップボード履歴。"),
    ("About_GitHub", "GitHub", "GitHub"),
    ("About_Inspired", "Inspired by Maccy", "Maccy にインスパイアされました"),
    ("About_License", "MIT License", "MIT ライセンス"),
    ("About_Privacy", "No network access; clips never leave this PC.", "ネットワークにはアクセスしません。履歴がこの PC の外に出ることはありません。"),
    # Welcome
    ("Welcome_Title1", "Nori keeps what you copy", "Nori はコピーしたものを覚えています"),
    ("Welcome_Body1", "Press the shortcut anywhere to see your clipboard history. Pick a clip, press Enter, and it is pasted into the app you were using.", "どこでもショートカットを押すとクリップボードの履歴が開きます。項目を選んで Enter を押すと、使っていたアプリに貼り付けられます。"),
    ("Welcome_Title2", "Start with Windows?", "Windows と一緒に起動しますか？"),
    ("Welcome_Body2", "Nori lives in the tray and watches the clipboard. Start it when you sign in so your history is always there.", "Nori はタスクトレイに常駐してクリップボードを見守ります。サインイン時に起動すれば、履歴がいつでも使えます。"),
    ("Welcome_Next", "Next", "次へ"),
    ("Welcome_Done", "Done", "完了"),
    ("Welcome_Back", "Back", "戻る"),
    ("Welcome_Seed", "Welcome to Nori 👋 Press Enter to paste this.", "Nori へようこそ 👋 Enter を押すとこれが貼り付けられます。"),
    # Hotkeys
    ("Hotkey_CtrlShiftV", "Ctrl+Shift+V", "Ctrl+Shift+V"),
    ("Hotkey_CtrlAltV", "Ctrl+Alt+V", "Ctrl+Alt+V"),
    ("Hotkey_CtrlBacktick", "Ctrl+`", "Ctrl+`"),
    ("Hotkey_Failed", "Nori could not register {0}. Another app may be using it — pick a different shortcut in Settings.", "{0} を登録できませんでした。ほかのアプリが使っている可能性があります。設定で別のショートカットを選んでください。"),
    # Secret labels
    ("Secret_PrivateKey", "Private key", "秘密鍵"),
    ("Secret_AwsAccessKey", "AWS access key", "AWS アクセスキー"),
    ("Secret_GitHubToken", "GitHub token", "GitHub トークン"),
    ("Secret_ApiKey", "API key", "API キー"),
    ("Secret_SlackToken", "Slack token", "Slack トークン"),
    ("Secret_GoogleApiKey", "Google API key", "Google API キー"),
    ("Secret_AccessToken", "Access token", "アクセストークン"),
    ("Secret_CardNumber", "Card number", "カード番号"),
    # Misc
    ("Source_Nori", "Nori", "Nori"),
    ("Source_Unknown", "Unknown app", "不明なアプリ"),
    ("FileDialog_Apps", "Applications (*.exe)|*.exe", "アプリケーション (*.exe)|*.exe"),
    ("FileDialog_Title", "Choose an app to ignore", "記録しないアプリを選択"),
    ("Common_Enabled", "Enabled", "有効"),
    ("Common_Disabled", "Not enabled", "無効"),
]

HEADER = """<?xml version="1.0" encoding="utf-8"?>
<root>
  <resheader name="resmimetype">
    <value>text/microsoft-resx</value>
  </resheader>
  <resheader name="version">
    <value>2.0</value>
  </resheader>
  <resheader name="reader">
    <value>System.Resources.ResXResourceReader, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value>
  </resheader>
  <resheader name="writer">
    <value>System.Resources.ResXResourceWriter, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value>
  </resheader>
"""


def write(path, index):
    keys = set()
    with open(path, "w", encoding="utf-8") as f:
        f.write(HEADER)
        for entry in STRINGS:
            key = entry[0]
            if key in keys:
                sys.exit(f"duplicate key {key}")
            keys.add(key)
            f.write(f'  <data name="{key}" xml:space="preserve">\n    <value>{escape(entry[index])}</value>\n  </data>\n')
        f.write("</root>\n")
    print(f"wrote {path} ({len(keys)} strings)")


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.join(here, "..", "Nori.Windows", "Resources")
    write(os.path.join(root, "Strings.resx"), 1)
    write(os.path.join(root, "Strings.ja.resx"), 2)
