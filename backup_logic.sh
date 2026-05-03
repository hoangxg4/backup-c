#!/bin/bash
# Script lưu tại: /usr/local/bin/vps-manager

MY_NAME=$(cat /etc/vps_id)
DATE=$(date +%Y%m%d_%H%M)
BACKUP_DIR="/tmp/backup_stage"
ROLLBACK_DIR="/root/backup_rollback"
DRIVE_BASE="gdrive:Coolify_Backups"
DRIVE_PATH="$DRIVE_BASE/$(date +%Y-%m)"

mkdir -p $BACKUP_DIR $ROLLBACK_DIR

case "$1" in
    backup)
        FILE_NAME="${MY_NAME}_${DATE}.tar.gz"
        tar -czf "$BACKUP_DIR/$FILE_NAME" /var/lib/docker/volumes /data/coolify
        rclone copy "$BACKUP_DIR/$FILE_NAME" "$DRIVE_PATH"
        rm -f "$BACKUP_DIR/$FILE_NAME"
        
        # Dọn dẹp: Giữ 7 ngày và xóa sạch thùng rác Drive
        rclone delete "$DRIVE_BASE" --min-age 7d --rmdirs
        rclone cleanup "$DRIVE_BASE"
        ;;
        
    restore)
        # Tìm file trên Drive (Recursive tìm mọi tháng)
        FILES=$(rclone lsf "$DRIVE_BASE" --recursive | grep "^.*/${MY_NAME}_" | sort -r)
        
        if [ -z "$FILES" ]; then echo "Error: No backup found!"; exit 1; fi

        echo "--- CHỌN BẢN BACKUP ĐỂ RESTORE ---"
        PS3="Nhập số thứ tự: "
        select SELECTED_FILE in $FILES; do
            if [ -n "$SELECTED_FILE" ]; then break; fi
        done

        # Rollback local trước khi đè dữ liệu
        echo "🛡️ Creating local rollback..."
        tar -czf "$ROLLBACK_DIR/ROLLBACK_${MY_NAME}_${DATE}.tar.gz" /var/lib/docker/volumes /data/coolify
        
        # Download & Extract
        rclone copy "$DRIVE_BASE/$SELECTED_FILE" "$BACKUP_DIR/"
        FILENAME_ONLY=$(basename "$SELECTED_FILE")
        
        echo "🛠️ Restoring data..."
        tar -xzf "$BACKUP_DIR/$FILENAME_ONLY" -C /
        rm -f "$BACKUP_DIR/$FILENAME_ONLY"
        echo "Success! Rollback location: $ROLLBACK_DIR"
        ;;
esac
