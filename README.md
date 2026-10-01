<p align="center"><img src="icon/AppIcon.svg" width="128" alt="TatakiNote のアイコン"></p>

# TatakiNote

TatakiNote は、AI に送る前の文章(叩き台)を書くための、メニューバーに常駐する macOS アプリです。

- ホットキーで入力パネルを開いて文章を書き、確定すると、パネルを開いたときに使っていたアプリの入力欄に文章が入ります。
- パネルでは Enter が改行なので、日本語の変換や改行の途中で、書きかけの文章を誤って送信してしまうことがありません。
- パネルを開いても、使っていたアプリは前面のままです。コピーしていた内容も、挿入の後に元に戻ります。

## 動作環境

macOS 14 以降

## 入手とインストール

1. [Releases](../../releases) から最新の `TatakiNote-<版>.zip` をダウンロードし、開いて `TatakiNote.app` を取り出します。
2. `TatakiNote.app` を「アプリケーション」フォルダに入れて開きます。
3. 初めて開くときに「開けません」などの警告が出たら、「システム設定」の「プライバシーとセキュリティ」を開き、TatakiNote について「このまま開く」を押します。TatakiNote は Apple の公証を受けていないため、初回だけこの確認が要ります。

新しい版に更新するときは、TatakiNote を終了してから同じ手順で「アプリケーション」フォルダの `TatakiNote.app` を置き換えます。アクセシビリティの許可はそのまま引き継がれます。各版の変更点は [Releases](../../releases) に載せています。

## 最初にやること

1. **アクセシビリティを許可する。** 書いた文章を他のアプリに入れるのに要ります。初回の起動時に案内が開くので、手順に沿って許可します。詳しくは[アクセシビリティの許可](docs/features/accessibility.md)を見てください。
2. **パネルを開く。** 文章を入れたいアプリの入力欄を選んでから、ホットキー `⌥⇧Space`(Option + Shift + Space)を押します。ホットキーは設定で変えられます。
3. **書いて確定する。** 確定キーで、書いた文章が元のアプリの入力欄に入ります。確定キーは設定で登録します([確定のキー](docs/features/insert-and-send.md#確定のキー))。

## 使い方

機能ごとの説明は[TatakiNote の使い方](docs/README.md)にまとめています。

- [入力パネル](docs/features/panel.md)
- [入力欄の編集ショートカット](docs/features/text-editing.md)
- [書いた文章を挿入する・送信する](docs/features/insert-and-send.md)
- [入力欄を選んだらパネルを自動で出す](docs/features/auto-show.md)
- [設定ウィンドウ](docs/features/settings.md)
