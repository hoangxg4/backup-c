#!/bin/bash
MY_NAME=$(cat /etc/vps_id)
DATE=$(date +%Y%m%d_%H%M)
BACKUP_DIR="/tmp/backup_stage"
ROLLBACK_DIR="/root/backup_rollback"
DRIVE_DEST="gdrive:Coolify_Backups/$MY_NAME"
MARKER_FILE="/etc/vps_last_backup"

mkdir -p $BACKUP_DIR $ROLLBACK_DIR

# --- HÀM THÔNG BÁO DISCORD ---
send_discord() {
    local COLOR=$1
    local STATUS_TITLE=$2
    local DESC=$3
    
    if [ -n "$DISCORD_WEBHOOK" ]; then
        cat <<EOF > /tmp/discord.json
{
  "embeds": [{
    "title": "$STATUS_TITLE",
    "description": "$DESC",
    "color": $COLOR,
    "fields": [
      {"name": "🖥️ Server", "value": "\`$MY_NAME\`", "inline": true},
      {"name": "⚙️ Status", "value": "\`Permanent Delete Active\`", "inline": true}
    ],
    "footer": {"text": "GitOps Backup System • $(date +'%Y-%m-%d %H:%M')"}
  }]
}
EOF
        curl -s -H "Content-Type: application/json" -d @/tmp/discord.json "$DISCORD_WEBHOOK" > /dev/null
    fi
}

case "$1" in
    backup)
        # --- 1. CHỈ BACKUP KHI CÓ THAY ĐỔI ---
        if [ -f "$MARKER_FILE" ]; then
            CHANGES=$(find /var/lib/docker/volumes /data/coolify -type f \
                -not -path "*/logs/*" -not -name "*.log" \
                -newer "$MARKER_FILE" | head -n 1)
            
            if [ -z "$CHANGES" ]; then
                send_discord "8421504" "💤 Skip" "Dữ liệu không đổi. Không có gì để backup."
                exit 0
            fi
        fi

        # --- 2. NÉN VÀ UPLOAD ---
        FILE_NAME="${MY_NAME}_${DATE}.tar.gz"
        tar -czf "$BACKUP_DIR/$FILE_NAME" -C / --exclude="*/logs/*" --exclude="*.log" var/lib/docker/volumes data/coolify
        
        FILE_SIZE=$(du -sh "$BACKUP_DIR/$FILE_NAME" | awk '{print $1}')
        
        # Upload lên Drive
        rclone copy "$BACKUP_DIR/$FILE_NAME" "$DRIVE_DEST"
        rm -f "$BACKUP_DIR/$FILE_NAME"

        # --- 3. DỌN DẸP & XÓA VĨNH VIỄN (TRASH BYPASS) ---
        # Lấy danh sách file, sắp xếp mới nhất lên đầu, lấy các file từ thứ 11 trở đi để xóa
        FILES_TO_DELETE=$(rclone lsf "$DRIVE_DEST" | grep "\.tar\.gz$" | sort -r | tail -n +11)
        
        if [ -n "$FILES_TO_DELETE" ]; then
            for OLD_FILE in $FILES_TO_DELETE; do
                # Flag --drive-use-trash=false sẽ xóa vĩnh viễn, không vào thùng rác
                rclone deletefile "$DRIVE_DEST/$OLD_FILE" --drive-use-trash=false
            done
        fi

        # Cập nhật marker
        touch "$MARKER_FILE"
        
        # Dọn sạch các tàn dư khác nếu có trong thùng rác chung của Drive (cho chắc chắn)
        rclone cleanup "gdrive:" -q >/dev/null 2>&1
        
        send_discord "3066993" "✅ Backup Success" "**File:** \`$FILE_NAME\`\n**Size:** \`$FILE_SIZE\`\n**Retention:** \`10 bản (Xóa vĩnh viễn)\`"
        ;;

    restore)
        FILES=$(rclone lsf "$DRIVE_DEST" | grep "\.tar\.gz$" | sort -r)
        if [ -z "$FILES" ]; then echo "No backup found!"; exit 1; fi

        echo "--- CHỌN BẢN BACKUP ---"
        PS3="Nhập số: "
        select SELECTED_FILE in $FILES; do
            if [ -n "$SELECTED_FILE" ]; then break; fi
        done

        # Tạo rollback local
        tar -czf "$ROLLBACK_DIR/ROLLBACK_${MY_NAME}_${DATE}.tar.gz" -C / var/lib/docker/volumes data/coolify
        
        # Tải về và xả nén
        rclone copy "$DRIVE_DEST/$SELECTED_FILE" "$BACKUP_DIR/"
        tar -xzf "$BACKUP_DIR/$SELECTED_FILE" -C /
        rm -f "$BACKUP_DIR/$SELECTED_FILE"
        
        send_discord "16753920" "🔄 Restore Done" "**Khôi phục từ:** \`$SELECTED_FILE\`"
        echo "🚀 Restore thành công!"
        ;;
esac
