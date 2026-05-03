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
        # --- 1. LOGIC KIỂM TRA FILE THAY ĐỔI ---
        if [ -f "$MARKER_FILE" ]; then
            # Tìm file có thời gian sửa đổi mới hơn file Marker
            CHANGES=$(find /var/lib/docker/volumes /data/coolify -type f -newer "$MARKER_FILE" | head -n 1)
            if [ -z "$CHANGES" ]; then
                echo "💤 Không có dữ liệu nào thay đổi từ lần backup trước. Bỏ qua."
                exit 0
            fi
        fi

        # --- 2. LOGIC GFS (DAILY, WEEKLY, MONTHLY) ---
        D_DAY=$(date +%d)  # Ngày trong tháng (01-31)
        D_WEEK=$(date +%u) # Ngày trong tuần (1-7, 7 là Chủ Nhật)

        if [ "$D_DAY" == "01" ]; then
            B_TYPE="monthly"
            KEEP_LIMIT=4
        elif [ "$D_WEEK" == "7" ]; then
            B_TYPE="weekly"
            KEEP_LIMIT=7
        else
            B_TYPE="daily"
            KEEP_LIMIT=4
        fi

        DRIVE_PATH="$DRIVE_BASE/$B_TYPE"
        FILE_NAME="${MY_NAME}_${B_TYPE}_${DATE}.tar.gz"
        
        echo "📦 Đang nén bản backup loại: [$B_TYPE]"
        tar -czf "$BACKUP_DIR/$FILE_NAME" -C / var/lib/docker/volumes data/coolify
        
        rclone copy "$BACKUP_DIR/$FILE_NAME" "$DRIVE_PATH"
        rm -f "$BACKUP_DIR/$FILE_NAME"
        
        # Cập nhật thời gian cho cột mốc
        touch "$MARKER_FILE"
        
        # --- 3. DỌN DẸP THEO SỐ LƯỢNG (Giữ đúng 4-7-4) ---
        # Lấy danh sách file, sắp xếp mới nhất lên đầu, cắt bỏ N file cần giữ, lấy phần còn lại để xóa
        FILES_TO_DELETE=$(rclone lsf "$DRIVE_PATH" | grep "\.tar\.gz$" | sort -r | tail -n +$((KEEP_LIMIT + 1)))
        
        for OLD_FILE in $FILES_TO_DELETE; do
            rclone deletefile "$DRIVE_PATH/$OLD_FILE"
        done
        
        # Làm sạch thùng rác (ẩn log)
        rclone cleanup "gdrive:Coolify_Backups" -q >/dev/null 2>&1
        ;;
        
    restore)
        # Quét toàn bộ các thư mục con (daily, weekly, monthly) để chọn
        FILES=$(rclone lsf "$DRIVE_BASE" --recursive | grep "\.tar\.gz$" | sort -r)
        
        if [ -z "$FILES" ]; then echo "Error: No backup found!"; exit 1; fi

        echo "--- CHỌN BẢN BACKUP CỦA $MY_NAME ---"
        PS3="Nhập số thứ tự: "
        select SELECTED_FILE in $FILES; do
            if [ -n "$SELECTED_FILE" ]; then break; fi
        done

        echo "🛡️ Tạo local rollback..."
        tar -czf "$ROLLBACK_DIR/ROLLBACK_${MY_NAME}_${DATE}.tar.gz" -C / var/lib/docker/volumes data/coolify
        
        rclone copy "$DRIVE_BASE/$SELECTED_FILE" "$BACKUP_DIR/"
        FILENAME_ONLY=$(basename "$SELECTED_FILE")
        
        echo "🛠️ Đang khôi phục dữ liệu..."
        tar -xzf "$BACKUP_DIR/$FILENAME_ONLY" -C /
        rm -f "$BACKUP_DIR/$FILENAME_ONLY"
        echo "Thành công!"
        ;;
esac
