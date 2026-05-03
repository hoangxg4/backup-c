#!/bin/bash
MY_NAME=$(cat /etc/vps_id)
DATE=$(date +%Y%m%d_%H%M)
BACKUP_DIR="/tmp/backup_stage"
ROLLBACK_DIR="/root/backup_rollback"
DRIVE_BASE="gdrive:Coolify_Backups/$MY_NAME"
MARKER_FILE="/etc/vps_last_backup"

mkdir -p $BACKUP_DIR $ROLLBACK_DIR

case "$1" in
    backup)
        # --- 1. KIỂM TRA THAY ĐỔI (LOẠI TRỪ LOG) ---
        # Loại trừ các folder log của Docker vì chúng thay đổi từng giây
        if [ -f "$MARKER_FILE" ]; then
            CHANGES=$(find /var/lib/docker/volumes /data/coolify -type f \
                -not -path "*/logs/*" -not -name "*.log" \
                -newer "$MARKER_FILE" | head -n 1)
            
            if [ -z "$CHANGES" ]; then
                echo "💤 Không có thay đổi đáng kể (trừ log). Bỏ qua backup."
                exit 0
            fi
        fi

        # --- 2. CHIA LUỒNG LƯU TRỮ (4-7-4) ---
        D_DAY=$(date +%d)
        D_WEEK=$(date +%u)

        if [ "$D_DAY" == "01" ]; then
            B_TYPE="monthly"; KEEP_LIMIT=4
        elif [ "$D_WEEK" == "7" ]; then
            B_TYPE="weekly"; KEEP_LIMIT=7
        else
            B_TYPE="daily"; KEEP_LIMIT=4
        fi

        DRIVE_PATH="$DRIVE_BASE/$B_TYPE"
        FILE_NAME="${MY_NAME}_${B_TYPE}_${DATE}.tar.gz"
        
        # Nén dữ liệu (Loại trừ log để file nhẹ và check thay đổi chuẩn)
        tar -czf "$BACKUP_DIR/$FILE_NAME" -C / \
            --exclude="*/logs/*" --exclude="*.log" \
            var/lib/docker/volumes data/coolify
        
        rclone copy "$BACKUP_DIR/$FILE_NAME" "$DRIVE_PATH"
        rm -f "$BACKUP_DIR/$FILE_NAME"
        
        # Cập nhật marker
        touch "$MARKER_FILE"
        
        # --- 3. DỌN DẸP THEO SỐ LƯỢNG ---
        FILES_TO_DELETE=$(rclone lsf "$DRIVE_PATH" | grep "\.tar\.gz$" | sort -r | tail -n +$((KEEP_LIMIT + 1)))
        for OLD_FILE in $FILES_TO_DELETE; do
            rclone deletefile "$DRIVE_PATH/$OLD_FILE"
        done
        
        rclone cleanup "gdrive:Coolify_Backups" -q >/dev/null 2>&1
        ;;
        
    restore)
        # Logic restore giữ nguyên (Recursive để thấy hết các bản)
        FILES=$(rclone lsf "$DRIVE_BASE" --recursive | grep "\.tar\.gz$" | sort -r)
        if [ -z "$FILES" ]; then echo "No backup found!"; exit 1; fi

        echo "--- CHỌN BẢN BACKUP ---"
        PS3="Chọn số: "
        select SELECTED_FILE in $FILES; do
            if [ -n "$SELECTED_FILE" ]; then break; fi
        done

        tar -czf "$ROLLBACK_DIR/ROLLBACK_${MY_NAME}_${DATE}.tar.gz" -C / var/lib/docker/volumes data/coolify
        rclone copy "$DRIVE_BASE/$SELECTED_FILE" "$BACKUP_DIR/"
        FILENAME_ONLY=$(basename "$SELECTED_FILE")
        tar -xzf "$BACKUP_DIR/$FILENAME_ONLY" -C /
        rm -f "$BACKUP_DIR/$FILENAME_ONLY"
        echo "Restore thành công!"
        ;;
esac
