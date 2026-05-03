#!/bin/bash
MY_NAME=$(cat /etc/vps_id)
DATE=$(date +%Y%m%d_%H%M)
BACKUP_DIR="/tmp/backup_stage"
ROLLBACK_DIR="/root/backup_rollback"
MONTH_FOLDER=$(date +%m-%Y)
DRIVE_SERVER_ROOT="gdrive:Coolify_Backups/$MY_NAME"
DRIVE_DEST="$DRIVE_SERVER_ROOT/$MONTH_FOLDER"
MARKER_FILE="/etc/vps_last_backup"

mkdir -p $BACKUP_DIR $ROLLBACK_DIR

# --- HÀM GỬI DISCORD "COOL NGẦU" ---
send_discord() {
    local COLOR=$1
    local STATUS_TITLE=$2
    local DESC=$3
    
    if [ -z "$DISCORD_WEBHOOK" ]; then return 0; fi

    # Tạo JSON cho Discord Embed
    cat <<EOF > /tmp/discord.json
{
  "embeds": [{
    "title": "$STATUS_TITLE",
    "description": "$DESC",
    "color": $COLOR,
    "fields": [
      {"name": "🖥️ Server", "value": "\`$MY_NAME\`", "inline": true},
      {"name": "📂 Month Folder", "value": "\`$MONTH_FOLDER\`", "inline": true}
    ],
    "footer": {"text": "Silent GitOps Backup • $(date +'%Y-%m-%d %H:%M')"}
  }]
}
EOF
    curl -s -H "Content-Type: application/json" -d @/tmp/discord.json "$DISCORD_WEBHOOK" > /dev/null
}

cleanup_gfs() {
    local TAG=$1
    local KEEP_LIMIT=$2
    local ALL_FILES=$(rclone lsf "$DRIVE_SERVER_ROOT" --recursive | grep "_${TAG}_" | sort -r)
    local TO_DELETE=$(echo "$ALL_FILES" | tail -n +$((KEEP_LIMIT + 1)))
    
    for FILE_PATH in $TO_DELETE; do
        if [ -n "$FILE_PATH" ]; then
            rclone deletefile "$DRIVE_SERVER_ROOT/$FILE_PATH"
        fi
    done
}

case "$1" in
    backup)
        # --- 1. CHECK THAY ĐỔI ---
        if [ -f "$MARKER_FILE" ]; then
            CHANGES=$(find /var/lib/docker/volumes /data/coolify -type f \
                -not -path "*/logs/*" -not -name "*.log" \
                -newer "$MARKER_FILE" | head -n 1)
            if [ -z "$CHANGES" ]; then
                send_discord "8421504" "💤 Bỏ Qua Backup" "Không có dữ liệu mới nào được sinh ra (đã loại trừ logs)."
                exit 0
            fi
        fi

        # --- 2. NÉN DAILY & TÍNH DUNG LƯỢNG ---
        DAILY_FILE="${MY_NAME}_D_${DATE}.tar.gz"
        tar -czf "$BACKUP_DIR/$DAILY_FILE" -C / --exclude="*/logs/*" --exclude="*.log" var/lib/docker/volumes data/coolify
        
        # Lấy dung lượng file để báo cáo Discord
        FILE_SIZE=$(du -sh "$BACKUP_DIR/$DAILY_FILE" | awk '{print $1}')
        
        rclone copy "$BACKUP_DIR/$DAILY_FILE" "$DRIVE_DEST"
        rm -f "$BACKUP_DIR/$DAILY_FILE"

        # --- 3. NHÂN BẢN GFS ---
        D_DAY=$(date +%d)
        D_WEEK=$(date +%u)
        TAGS_CREATED="Daily (D)"

        if [ "$D_WEEK" == "7" ]; then
            WEEKLY_FILE="${MY_NAME}_W_${DATE}.tar.gz"
            rclone copyto "$DRIVE_DEST/$DAILY_FILE" "$DRIVE_DEST/$WEEKLY_FILE"
            TAGS_CREATED="$TAGS_CREATED, Weekly (W)"
        fi

        if [ "$D_DAY" == "01" ]; then
            MONTHLY_FILE="${MY_NAME}_M_${DATE}.tar.gz"
            rclone copyto "$DRIVE_DEST/$DAILY_FILE" "$DRIVE_DEST/$MONTHLY_FILE"
            TAGS_CREATED="$TAGS_CREATED, Monthly (M)"
        fi

        # --- 4. DỌN DẸP & XÓA THƯ MỤC RỖNG ---
        cleanup_gfs "D" 4
        cleanup_gfs "W" 7
        cleanup_gfs "M" 4

        # FIX: Dọn sạch các thư mục tháng (04-2026, 03-2026...) nếu bên trong không còn file nào
        rclone rmdirs "$DRIVE_SERVER_ROOT" --leave-root 2>/dev/null || true

        touch "$MARKER_FILE"
        rclone cleanup "gdrive:Coolify_Backups" -q >/dev/null 2>&1
        
        # GỬI THÔNG BÁO THÀNH CÔNG LÊN DISCORD (Màu xanh lá = 3066993)
        send_discord "3066993" "✅ Backup Thành Công" "**Dung lượng:** \`$FILE_SIZE\`\n**Tags:** \`$TAGS_CREATED\`\n**Đã áp dụng quy tắc:** \`4D-7W-4M\`"
        ;;

    restore)
        # (Logic khôi phục giữ nguyên như cũ)
        FILES=$(rclone lsf "$DRIVE_SERVER_ROOT" --recursive | grep "\.tar\.gz$" | sort -r)
        if [ -z "$FILES" ]; then echo "No backup found!"; exit 1; fi

        echo "--- CHỌN BẢN BACKUP ---"
        PS3="Chọn số: "
        select SELECTED_FILE in $FILES; do
            if [ -n "$SELECTED_FILE" ]; then break; fi
        done

        tar -czf "$ROLLBACK_DIR/ROLLBACK_${MY_NAME}_${DATE}.tar.gz" -C / var/lib/docker/volumes data/coolify
        rclone copy "$DRIVE_SERVER_ROOT/$SELECTED_FILE" "$BACKUP_DIR/"
        FILENAME_ONLY=$(basename "$SELECTED_FILE")
        tar -xzf "$BACKUP_DIR/$FILENAME_ONLY" -C /
        rm -f "$BACKUP_DIR/$FILENAME_ONLY"
        
        # Gửi thông báo Restore (Màu vàng = 16753920)
        send_discord "16753920" "🔄 Restore Hoàn Tất" "**File khôi phục:** \`$FILENAME_ONLY\`\nĐã tạo Rollback dự phòng ở VPS."
        echo "🚀 Khôi phục thành công!"
        ;;
esac
