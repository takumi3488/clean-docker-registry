#!/bin/bash

# --- 設定 ---
KEEP_TAGS=${KEEP_TAGS:-3}

# --- 関数定義 ---

# APIリクエストを送信する関数
api_request() {
    local method="$1"
    local path="$2"
    local accept_header="${3:-application/json}"
    
    curl -s -X "$method" \
         -H "Accept: $accept_header" \
         "$REGISTRY_URL/v2$path"
}

# Digestを取得する関数（マニフェスト削除用）
get_manifest_digest() {
    local repo="$1"
    local tag="$2"
    
    # 新しいAPI仕様に従い、複数のマニフェストタイプをサポート
    curl -s -I \
         -H "Accept: application/vnd.docker.distribution.manifest.v2+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.oci.image.index.v1+json" \
         "$REGISTRY_URL/v2/$repo/manifests/$tag" | \
         grep -i 'docker-content-digest:' | \
         awk '{print $2}' | tr -d '\r'
}

# レジストリ内の全リポジトリを取得
get_repositories() {
    api_request "GET" "/_catalog" | jq -r '.repositories[]' 2>/dev/null
}

# 指定されたリポジトリのタグ一覧を取得
get_tags() {
    local repo="$1"
    api_request "GET" "/$repo/tags/list" | jq -r '.tags[]' 2>/dev/null | sort -V
}

# タグの作成日時を取得してソート（新しい順）
get_tags_with_dates() {
    local repo="$1"
    local temp_file=$(mktemp)
    
    # 単純にタグ名でソート（バージョン順）
    get_tags "$repo" | sort -V -r
}

# マニフェストを削除する関数
delete_manifest() {
    local repo="$1"
    local tag="$2"
    
    echo "  タグ '$tag' を削除中..."
    
    # マニフェストのdigestを取得
    local digest=$(get_manifest_digest "$repo" "$tag")
    
    if [ -z "$digest" ]; then
        echo "    エラー: タグ '$tag' のdigestを取得できませんでした"
        echo "    タグが存在しないか、レジストリがアクセスを拒否している可能性があります"
        return 1
    fi
    
    echo "    Digest: $digest"
    
    # ドライランモードの確認
    if [ "$DRY_RUN" == "true" ]; then
        echo "    [DRY RUN] タグ '$tag' (digest: $digest) を削除予定"
        return 0
    fi
    
    # マニフェストを削除（新しいAPI仕様に従い、digestで削除）
    local response=$(curl -s -w "%{http_code}" -X DELETE \
                    "$REGISTRY_URL/v2/$repo/manifests/$digest")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    case "$http_code" in
        202)
            echo "    ✓ タグ '$tag' を正常に削除しました"
            return 0
            ;;
        404)
            echo "    ! タグ '$tag' は既に削除されているか存在しません"
            return 0
            ;;
        405)
            echo "    ✗ 削除が許可されていません（レジストリで無効化されています）"
            echo "    API仕様: DELETE /v2/<name>/manifests/<digest> が405 Method Not Allowedを返しました"
            return 1
            ;;
        401)
            echo "    ✗ 認証が必要です"
            echo "    レジストリの認証情報を確認してください"
            return 1
            ;;
        403)
            echo "    ✗ アクセスが拒否されました"
            echo "    削除権限がない可能性があります"
            return 1
            ;;
        *)
            echo "    ✗ タグ '$tag' の削除に失敗しました (HTTP $http_code)"
            if [ -n "$body" ]; then
                echo "    レスポンス: $body"
            fi
            echo "    API仕様に準拠したエラーです"
            return 1
            ;;
    esac
}

# メイン処理
main() {
    echo "Docker Registry クリーンアップスクリプト開始"
    echo "レジストリ: $REGISTRY_URL"
    echo "保持するタグ数: $KEEP_TAGS"
    
    # コマンドラインオプションの処理
    if [ "$1" == "--dry-run" ]; then
        DRY_RUN="true"
        echo "ドライランモード: 実際の削除は行いません"
    else
        DRY_RUN="false"
    fi
    
    echo "=================================="
    
    # jqコマンドの存在確認
    if ! command -v jq &> /dev/null; then
        echo "エラー: jqコマンドが見つかりません。インストールしてください。"
        echo "Homebrew: brew install jq"
        echo "Ubuntu/Debian: sudo apt-get install jq"
        exit 1
    fi
    
    # レジストリへの接続確認
    echo "レジストリへの接続を確認中..."
    if ! api_request "GET" "/" > /dev/null; then
        echo "エラー: レジストリに接続できません。URLと認証情報を確認してください。"
        exit 1
    fi
    echo "✓ レジストリに正常に接続しました"
    
    # 削除機能の確認
    echo "削除機能の利用可能性を確認中..."
    
    # API仕様に従い、適切なエンドポイントで削除サポートを確認
    # 実際のマニフェストではなく、存在しないdigestでテストする
    delete_test_response=$(curl -s -w "%{http_code}" -X DELETE \
                          "$REGISTRY_URL/v2/_unknown_/manifests/sha256:0000000000000000000000000000000000000000000000000000000000000000" 2>/dev/null)
    delete_test_code="${delete_test_response: -3}"
    
    case "$delete_test_code" in
        404)
            echo "✓ 削除機能が利用可能です（404 Not Found - 正常な応答）"
            ;;
        405)
            echo "⚠️  警告: レジストリで削除機能が無効化されています（405 Method Not Allowed）"
            if [ "$DRY_RUN" != "true" ]; then
                echo "実際の削除は失敗する可能性があります。まず --dry-run で確認することをお勧めします。"
            fi
            ;;
        401|403)
            echo "✓ 削除機能が利用可能です（認証/認可エラーは正常）"
            ;;
        *)
            echo "⚠️  削除機能の確認で予期しないレスポンス: HTTP $delete_test_code"
            ;;
    esac
    
    echo ""
    
    # 全リポジトリを取得
    repositories=$(get_repositories)
    
    if [ -z "$repositories" ]; then
        echo "リポジトリが見つかりませんでした。"
        exit 0
    fi
    
    total_deleted=0
    
    # 各リポジトリを処理
    while IFS= read -r repo; do
        echo "リポジトリ: $repo"
        echo "----------------------------------------"
        
        # タグを作成日時順で取得（新しい順）
        tags_ordered=$(get_tags_with_dates "$repo")
        
        if [ -z "$tags_ordered" ]; then
            echo "  タグが見つかりませんでした"
            echo ""
            continue
        fi
        
        # タグ数をカウント
        tag_count=$(echo "$tags_ordered" | wc -l)
        echo "  総タグ数: $tag_count"
        
        if [ "$tag_count" -le "$KEEP_TAGS" ]; then
            echo "  保持するタグ数以下のため、削除するタグはありません"
            echo ""
            continue
        fi
        
        # 保持するタグ数を超えた分を削除対象とする
        delete_count=$((tag_count - KEEP_TAGS))
        echo "  削除対象タグ数: $delete_count"
        echo "  保持するタグ (最新$KEEP_TAGS個):"
        
        # 保持するタグを表示
        echo "$tags_ordered" | head -n "$KEEP_TAGS" | while IFS= read -r tag; do
            echo "    - $tag"
        done
        
        echo "  削除するタグ:"
        
        # 削除対象のタグを処理
        echo "$tags_ordered" | tail -n "+$((KEEP_TAGS + 1))" | while IFS= read -r tag; do
            echo "    - $tag"
            if delete_manifest "$repo" "$tag"; then
                total_deleted=$((total_deleted + 1))
            fi
        done
        
        echo ""
    done <<< "$repositories"
    
    echo "=================================="
    echo "クリーンアップ完了"
    echo "削除されたタグ数: $total_deleted"
    echo ""
    echo "重要: Docker Registry V2 API では、マニフェストを削除してもストレージ容量は"
    echo "すぐには解放されません。ガベージコレクションを実行する必要があります:"
    echo ""
    echo "レジストリがDockerコンテナで動いている場合:"
    echo "  docker exec <registry_container> bin/registry garbage-collect /etc/docker/registry/config.yml"
    echo ""
    echo "レジストリが直接実行されている場合:"
    echo "  registry garbage-collect /path/to/config.yml"
    echo ""
    echo "詳細: https://distribution.github.io/distribution/about/garbage-collection/"
}

# スクリプト実行
main "$@"

