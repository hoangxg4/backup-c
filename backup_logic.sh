#!/bin/bash
MY_NAME=$(cat /etc/vps_id)
DATE=$(date +%Y%m%d_%H%M)
BACKUP_DIR="/tmp/backup_stage"
ROLLBACK_DIR="/root/backup_rollback"
DRIVE_DEST="gdrive:Coolify_Backups/$MY_NAME"
MARKER_FILE="/etc/vps_last_backup"

mkdir -p $BACKUP_DIR $ROLLBACK_DIR

case "$1" in
    backup)
        # --- 1. KIỂM TRA THAY ĐỔI (BỎ QUA LOGS) ---
        if [ -f "$MARKER_FILE" ]; then
            CHANGES=$(find /var/lib/docker/volumes /data/coolify -type f \
                -not -path "*/logs/*" -not -name "*.log" \
                -not -path "*/ssh/mux/*" \
                -newer "$MARKER_FILE" | head -n 1)
            
            if [ -z "$CHANGES" ]; then
                echo "[BACKUP_STATUS] SKIP"
                exit 0
            fi
        fi

        # --- 2. NÉN DỮ LIỆU (LOẠI BỎ SOCKET VÀ LOGS) ---
        FILE_NAME="${MY_NAME}_${DATE}.tar.gz"
        tar -czf "$BACKUP_DIR/$FILE_NAME" -C / \
            --exclude="*/logs/*" \
            --exclude="*.log" \
            --exclude="data/coolify/ssh/mux/*" \
            var/lib/docker/volumes data/coolify 2>/dev/null
            
        FILE_SIZE=$(du -sh "$BACKUP_DIR/$FILE_NAME" | awk '{print $1}')
        
        # --- 3. UPLOAD VÀ DỌN DẸP ---
        rclone copy "$BACKUP_DIR/$FILE_NAME" "$DRIVE_DEST"
        rm -f "$BACKUP_DIR/$FILE_NAME"

        # Chỉ giữ 10 bản mới nhất, xóa vĩnh viễn các bản cũ (Bypass Trash)
        FILES_TO_DELETE=$(rclone lsf "$DRIVE_DEST" | grep "\.tar\.gz$" | sort -r | tail -n +11)
        if [ -n "$FILES_TO_DELETE" ]; then
            for OLD_FILE in $FILES_TO_DELETE; do
                rclone deletefile "$DRIVE_DEST/$OLD_FILE" --drive-use-trash=false
            done
        fi

        touch "$MARKER_FILE"
        rclone cleanup "gdrive:" -q >/dev/null 2>&1
        
        # Trả kết quả về cho GitHub Actions
        echo "[BACKUP_STATUS] SUCCESS|$FILE_SIZE"
        ;;

    restore)
        FILES=$(rclone lsf "$DRIVE_DEST" | grep "\.tar\.gz$" | sort -r)
        if [ -z "$FILES" ]; then echo "No backup found!"; exit 1; fi

        echo "--- CHỌN BẢN BACKUP ---"
        PS3="Chọn số: "
        select SELECTED_FILE in $FILES; do
            if [ -n "$SELECTED_FILE" ]; then break; fi
        done

        # Tạo rollback local trước khi ghi đè
        tar -czf "$ROLLBACK_DIR/ROLLBACK_${MY_NAME}_${DATE}.tar.gz" -C / var/lib/docker/volumes data/coolify
        
        rclone copy "$DRIVE_DEST/$SELECTED_FILE" "$BACKUP_DIR/"
        tar -xzf "$BACKUP_DIR/$SELECTED_FILE" -C /
        rm -f "$BACKUP_DIR/$SELECTED_FILE"
        echo "🚀 Restore thành công!"
        ;;
esac
