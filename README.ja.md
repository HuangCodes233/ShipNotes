# ShipNotes

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md)

[![CI](https://github.com/HuangCodes233/ShipNotes/actions/workflows/ci.yml/badge.svg)](https://github.com/HuangCodes233/ShipNotes/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

ShipNotes は、ローカルファイルから多言語の App Store リリースノート、ストア掲載文、スクリーンショットを準備・プレビュー・同期する macOS ネイティブアプリです。

**開発状況：開発者向けの初期プレビュー。** ソースからビルドし、まずデモアカウントでお試しください。署名済みアプリの配布と実サービスでの操作には、追加の検証が必要です。

## 機能

- **リリースノート**：Markdown、YAML、JSON、変更履歴を読み込み、ロケールの対応付け、差分表示、同期前の検証を行います。
- **ストア掲載文**：説明文、キーワード、サブタイトル、プロモーションテキスト、ストア関連 URL をロケールごとに編集できます。
- **スクリーンショット**：フォルダを走査し、デバイスサイズとロケールの充足状況を確認して、アップロードや置き換えをプレビューできます。
- **ローカル下書きと履歴**：アカウント、アプリ、バージョンごとに編集を復元し、同期中の変更を保持します。履歴の検索と JSON/CSV 書き出しに対応。[動作と保存の説明](docs/reliability.md)。
- **任意の AI 機能**：自分の OpenAI 互換サービスまたは Anthropic の認証情報を使い、解析、翻訳、掲載文の改善、画像の言語判定を行えます。
- **Apple Ads**：専用の認証情報でレポートを確認し、キャンペーンやキーワードを管理できます。
- **ネイティブ UI**：英語、簡体字中国語、日本語に対応。macOS 26 以降では Liquid Glass を使い、それ以前の OS ではマテリアル表示に切り替えます。

## 動作・ビルド要件

| 項目 | 要件 |
| --- | --- |
| デプロイ対象 | macOS 14 以降。macOS 14/15 上での実際の動作は追加検証が必要です |
| ビルドツール | Xcode 26 以降、macOS 26 以降の SDK、Swift 6 対応 |
| デモアカウント | 新規インストールでは Apple や AI の認証情報は不要です |
| 実際の App Store へのアクセス | 必要なアプリ権限を持つ、自分の App Store Connect API 認証情報 |
| 任意のサービス | AI API キーと Apple Ads の認証情報をそれぞれ設定します |

完全版の Xcode を使用してください。サードパーティーの Swift パッケージへの依存はありません。

## クイックスタート

アドホック署名でローカルアプリをビルドします。

```sh
git clone https://github.com/HuangCodes233/ShipNotes.git
cd ShipNotes
CONFIG=debug SIGN_IDENTITY=- ./scripts/build-app.sh
open dist/ShipNotes.app
```

初回起動時に **まずはデモを試す**（Explore the demo first）を選択します。

1. サンプルアプリと編集可能なバージョンを選びます。
2. 「リリースノート」で `Examples/release-notes/1.4.0/` をフォルダとして、または `Examples/release-notes/1.5.0.yaml` をファイルとして読み込みます。
3. ロケールを選び、下書きを編集して差分を確認し、「ドライラン」（Dry Run）を実行します。
4. ストア掲載文、スクリーンショット、Apple Ads のワークスペースも確認できます。

設定済みの環境では、起動時に保存済みの認証情報を復元し、実サービスに再接続することがあります。同期前に接続状態と選択中のアプリ・バージョンを確認してください。

## リリースノートのファイル形式

`1.4.0/en-US.md` のようにロケールごとの Markdown ファイルを用意するか、バージョンとロケールのマップを持つ YAML/JSON を使用します。YAML の例：

```yaml
version: 1.5.0
locales:
  en-US: |
    • Added folder watching.
  zh-Hans: |
    • 新增文件夹监听。
  ja: |
    • フォルダ監視を追加しました。
```

[サンプルディレクトリ](Examples/release-notes/)には、多言語の Markdown と YAML が含まれています。変更履歴や複数のメタデータをまとめた文書にも対応し、解釈が曖昧な場合は読み込みプレビューで確認できます。

## サービスへの接続とプライバシー

「設定 → アカウント」で App Store Connect の Issuer ID、Key ID、`.p8` 秘密鍵を入力します。AI と Apple Ads は必要に応じて個別に設定してください。実サービスへの書き込み前に、対象アプリ、バージョン、ロケール、送信内容を確認してください。

認証情報は macOS キーチェーンに保存されます。設定、パス、同期履歴はローカルに保存されます。AI 操作では入力テキストや画像サムネイルを設定済みのプロバイダーに送信します。独自のエンドポイントを指定した場合、その設定のリクエストと認証情報はそのエンドポイントに送られます。非公開素材を扱う前に[認証情報とデータの流れ](docs/privacy-and-data.md)を確認してください。

## 開発

Xcode で `Package.swift` を開くか、SwiftPM を使用します。フォーマット、機能テスト、空白文字のチェックをまとめて実行できます。

```sh
./scripts/check.sh
```

開発用アプリをビルドして起動します。

```sh
./scripts/run-app.sh
```

実行スクリプトは標準で debug ビルドとアドホック署名を使用し、起動前に既存の ShipNotes プロセスを終了します。`--verify`、`--debug`、`--logs`、`--telemetry` も利用できます。Codex Run も同じスクリプトを使用します。

CI は Xcode 26.3 と Xcode 27 でテストを実行し、Xcode 27 で Swift フォーマットを検査します。Gitleaks による Git 履歴のシークレット検査も行います。[開発ガイド](docs/development.md)にコードの構成とチェック方法、[性能プローブ](docs/performance.md)に任意のベンチマーク手順を記載しています。

## パッケージ作成と制限事項

release 構成のローカルアプリを作成します。

```sh
CONFIG=release VERSION=0.1.0 BUILD=1 SIGN_IDENTITY=- ./scripts/build-app.sh
```

出力先は `dist/ShipNotes.app` です。パッケージ作成スクリプトは Developer ID 署名と任意の公証に対応しています。アドホック署名はローカル開発用です。

現在、次の項目は追加検証または実装が必要です。

- App Store Connect、Apple Ads、AI 操作は主にテストダブルで検証しており、実サービスとのエンドツーエンド検証は完了していません。
- Developer ID による配布、公証、別の Mac へのインストールは未検証です。
- Mac App Store 向けのサンドボックス権限と、永続的なセキュリティスコープ付きブックマークは未実装です。
- 以前の macOS での実動作と、自動 UI テストのカバレッジには追加検証が必要です。

継続的に更新する作業一覧は[開発状況](docs/development-status.md)を参照してください。

## コントリビューションとセキュリティ

PR を作成する前に[コントリビューションガイド](CONTRIBUTING.md)を確認してください。不具合報告には最小の再現手順、コミット、macOS/Xcode のバージョン、機密情報を除いたサンプルを含めてください。大きな変更は、まず Issue で相談してください。

脆弱性は[セキュリティ報告手順](SECURITY.md)に従って非公開で報告してください。公開 Issue、画像、ログに認証情報、顧客データ、個人のファイルパスを含めないでください。

## ライセンス

コード、スクリプト、ドキュメントは [MIT ライセンス](LICENSE)で提供します。AI 生成アイコンも、メンテナーが許諾できる権利の範囲で MIT として提供します。[素材のライセンス](docs/asset-licensing.md)に由来を記載しています。ShipNotes の名称とアイコンは、派生版を公式リリースとして表示する許可を与えるものではありません。
