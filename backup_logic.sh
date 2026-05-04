#!/bin/bash

MY_NAME=$(cat /etc/vps_id)
DATE=$(date +%Y%m%d_%H%M)
BACKUP_DIR="/tmp/backup_stage"
ROLLBACK_DIR="/root/backup_rollback"
RCLONE_REMOTE="gdrive"
DRIVE_DEST="$RCLONE_REMOTE:Coolify_Backups/$MY_NAME"
MARKER_FILE="/etc/vps_last_backup.sig"
RCLONE_CONF="/root/.config/rclone/rclone.conf"

mkdir -p "$BACKUP_DIR" "$ROLLBACK_DIR"

# 1. HÀM TẠO CHỮ KÝ DỮ LIỆU (Kiểm tra cực chuẩn)
# Quét toàn bộ file, lấy tên file, dung lượng, thời gian sửa -> Băm ra 1 chuỗi MD5 duy nhất
generate_signature() {
    find /var/lib/docker/volumes /data/coolify -type f \
        -not -path "*/logs/*" -not -name "*.log" \
        -not -path "*/ssh/mux/*" 2>/dev/null \
        -printf '%p %s %T@\n' | sort | md5sum | cut -d' ' -f1
}

case "$1" in
    backup)
        # 2. KIỂM TRA SỰ THAY ĐỔI
        NEW_SIG=$(generate_signature)
        
        # Nếu thư mục rỗng hoàn toàn (VPS mới tinh chưa cài gì) thì bỏ qua luôn
        if [ -z "$NEW_SIG" ] || [ "$NEW_SIG" == "d41d8cd98f00b204e9800998ecf8427e" ]; then
            echo "[BACKUP_STATUS] SKIP"
            exit 0
        fi

        if [ -f "$MARKER_FILE" ]; then
            OLD_SIG=$(cat "$MARKER_FILE")
            if [ "$NEW_SIG" == "$OLD_SIG" ]; then
                echo "[BACKUP_STATUS] SKIP"
                exit 0
            fi
        fi

        # 3. THỰC HIỆN NÉN DỮ LIỆU
        FILE_NAME="${MY_NAME}_${DATE}.tar.gz"
        
        # Thêm --warning=no-file-changed để tránh tar báo lỗi lặt vặt nếu Docker đang ghi đè file lúc nén
        tar -czf "$BACKUP_DIR/$FILE_NAME" -C / \
            --warning=no-file-changed \
            --exclude="*/logs/*" --exclude="*.log" --exclude="data/coolify/ssh/mux/*" \
            var/lib/docker/volumes data/coolify 2>/dev/null
            
        FILE_SIZE=$(du -sh "$BACKUP_DIR/$FILE_NAME" | awk '{print $1}')
        
        # 4. UPLOAD LÊN GOOGLE DRIVE
        # Đẩy log rclone vào file tạm để không làm rối Action Log
        if rclone --config "$RCLONE_CONF" copy "$BACKUP_DIR/$FILE_NAME" "$DRIVE_DEST" -v > /tmp/rclone_upload.log 2>&1; then
            
            # Xóa file nén trên VPS sau khi up xong
            rm -f "$BACKUP_DIR/$FILE_NAME"

            # Xóa file cũ trên Drive (Giữ lại tối đa 10 file mới nhất)
            FILES_TO_DELETE=$(rclone --config "$RCLONE_CONF" lsf "$DRIVE_DEST" | grep "\.tar\.gz$" | sort -r | tail -n +11)
            if [ -n "$FILES_TO_DELETE" ]; then
                for OLD_FILE in $FILES_TO_DELETE; do
                    rclone --config "$RCLONE_CONF" deletefile "$DRIVE_DEST/$OLD_FILE" --drive-use-trash=false
                done
            fi

            # Ghi lại chữ ký mới và dọn dẹp Drive
            echo "$NEW_SIG" > "$MARKER_FILE"
            rclone --config "$RCLONE_CONF" cleanup "$RCLONE_REMOTE:" -q > /dev/null 2>&1
            
            echo "[BACKUP_STATUS] SUCCESS|$FILE_SIZE"
        else
            echo "--> Log rclone lỗi:"
            cat /tmp/rclone_upload.log
            echo "[BACKUP_STATUS] ERROR_UPLOAD"
        fi
        ;;
esac
