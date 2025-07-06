# Docker Registry クリーンアップスクリプト

Docker Registry内の古いイメージタグを自動削除し、ストレージ容量を節約するためのスクリプトです。

## 機能

- Docker Registry HTTP API V2を使用
- 各リポジトリで最新N個のタグを保持し、古いタグを削除
- ドライランモードで事前確認可能
- 削除権限の自動チェック
- 詳細なログ出力

## 必要な環境

- `bash` シェル
- `curl` コマンド
- `jq` コマンド（JSON処理用）

### jqのインストール

```bash
# macOS (Homebrew)
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq
```

## 使用方法

### 1. 直接実行

#### 設定の編集

以下の環境変数を設定してください：

```bash
# レジストリのURL（認証情報を含む）
REGISTRY_URL="https://username:password@registry.example.com"

# 保持するタグ数（最新のもの）
KEEP_TAGS=3
```

#### スクリプトの実行

##### ドライランモード（推奨：初回実行時）

```bash
./clean_registry.sh --dry-run
```

実際の削除は行わず、削除対象のタグを表示します。

##### 実際の削除実行

```bash
./clean_registry.sh
```

### 2. Dockerを使用

#### Dockerイメージのビルド

```bash
docker build -t registry-cleaner .
```

#### Dockerコンテナでの実行

##### ドライランモード（推奨）

```bash
docker run --rm \
  -e REGISTRY_URL="http://localhost:5000" \
  -e KEEP_TAGS="3" \
  registry-cleaner --dry-run
```

##### 実際の削除実行

```bash
docker run --rm \
  -e REGISTRY_URL="http://localhost:5000" \
  -e KEEP_TAGS="3" \
  registry-cleaner
```

#### 環境変数

- `REGISTRY_URL`: Docker RegistryのベースURL（必須）
- `KEEP_TAGS`: 保持するタグ数（オプション、デフォルト: 3）

## 出力例

```
Docker Registry クリーンアップスクリプト開始
レジストリ: https://***@registry.example.com
保持するタグ数: 3
ドライランモード: 実際の削除は行いません
==================================
✓ レジストリに正常に接続しました
⚠️  警告: レジストリで削除機能が無効化されている可能性があります

リポジトリ: nginx-for-myk8s
----------------------------------------
  総タグ数:       84
  削除対象タグ数: 81
  保持するタグ (最新3個):
    - fe336aa439e1a3cb6851b57f48fca5449bb49f63
    - fb966a0bad2ab74d3152f8bfd9ada20b0683706f
    - f4230408b8e8ec7f1b9ca2f1ac0c0dffb816805a
  削除するタグ:
    - f59c363b92cbdb60a571c414d839342c71d5e104
  タグ 'f59c363b92cbdb60a571c414d839342c71d5e104' を削除中...
    Digest: sha256:0bb9d8393a7e79c2a1e5579cd997b9fc2d3eb3b0dd99e64834ccc7ce8366ab59
    [DRY RUN] タグ 'f59c363b92cbdb60a571c414d839342c71d5e104' を削除予定
```

## Docker Registry の削除設定

レジストリで削除機能を有効にするには、レジストリの設定ファイルに以下を追加してください：

```yaml
# config.yml
storage:
  delete:
    enabled: true
```

レジストリを再起動後、削除機能が利用可能になります。

## ガベージコレクション

マニフェストを削除してもストレージ容量はすぐには解放されません。ガベージコレクションを実行する必要があります：

```bash
# Docker コンテナの場合
docker exec <registry_container_name> bin/registry garbage-collect /etc/docker/registry/config.yml

# または、レジストリサーバー上で直接実行
registry garbage-collect /path/to/config.yml
```

## 注意事項

1. **バックアップ**: 重要なイメージは事前にバックアップを取ってください
2. **ドライラン**: 初回実行時は必ず `--dry-run` オプションで確認してください
3. **権限**: レジストリに削除権限があることを確認してください
4. **タグの順序**: タグは文字列の辞書順でソートされます（セマンティックバージョニングを考慮）

## トラブルシューティング

### HTTP 500 エラー
- レジストリで削除機能が無効化されている
- レジストリの設定で `storage.delete.enabled: true` を設定

### HTTP 405 エラー
- レジストリが削除をサポートしていない
- 読み取り専用モードで動作している

### 認証エラー
- `REGISTRY_URL` の認証情報を確認
- レジストリへのアクセス権限を確認

## ライセンス

MIT License
