#!/bin/bash
MY_NAME=$(cat /etc/vps_id)
DATE=$(date +%Y%m%d_%H%M)
BACKUP_DIR="/tmp/backup_stage"
ROLLBACK_DIR="/root/backup_rollback"
DRIVE_DEST="gdrive:Coolify_Backups/$MY_NAME"
MARKER_FILE="/etc/vps_last_backup"
RCLONE_CONF="/root/.config/rclone/rclone.conf"

mkdir -p $BACKUP_DIR $ROLLBACK_DIR

case "$1" in
    backup)
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

        FILE_NAME="${MY_NAME}_${DATE}.tar.gz"
        # Ẩn log của tar vì nó quá dài và không cần thiết
        tar -czf "$BACKUP_DIR/$FILE_NAME" -C / \
            --exclude="*/logs/*" --exclude="*.log" --exclude="data/coolify/ssh/mux/*" \
            var/lib/docker/volumes data/coolify 2>/dev/null
            
        FILE_SIZE=$(du -sh "$BACKUP_DIR/$FILE_NAME" | awk '{print $1}')
        
        echo "--> Bắt đầu upload file $FILE_NAME lên Google Drive..."
        
        # FIX CỐT LÕI: Ép Rclone đọc đúng file config và ĐỂ NGUYÊN LOG để debug
        if rclone --config "$RCLONE_CONF" copy "$BACKUP_DIR/$FILE_NAME" "$DRIVE_DEST" -v; then
            rm -f "$BACKUP_DIR/$FILE_NAME"

            FILES_TO_DELETE=$(rclone --config "$RCLONE_CONF" lsf "$DRIVE_DEST" | grep "\.tar\.gz$" | sort -r | tail -n +11)
            if [ -n "$FILES_TO_DELETE" ]; then
                for OLD_FILE in $FILES_TO_DELETE; do
                    rclone --config "$RCLONE_CONF" deletefile "$DRIVE_DEST/$OLD_FILE" --drive-use-trash=false
                done
            fi

            touch "$MARKER_FILE"
            rclone --config "$RCLONE_CONF" cleanup "gdrive:" -q
            
            echo "[BACKUP_STATUS] SUCCESS|$FILE_SIZE"
        else
            echo "--> LỖI: Upload thất bại, giữ lại file tại $BACKUP_DIR/$FILE_NAME"
            echo "[BACKUP_STATUS] ERROR_UPLOAD"
        fi
        ;;
esac
