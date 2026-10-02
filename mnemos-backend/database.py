import sqlite3
import os
from datetime import datetime

class Database:
    def __init__(self, db_path: str = os.path.expanduser("~/.mnemos/mnemos.db")):
        os.makedirs(os.path.dirname(db_path), exist_ok=True)
        self.conn = sqlite3.connect(db_path, check_same_thread=False)
        self._init_db()
        
    def _init_db(self):
        cursor = self.conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS activity_raw_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                app_name TEXT,
                window_title TEXT,
                ocr_text TEXT,
                audio_transcript TEXT,
                is_summarized BOOLEAN DEFAULT 0
            )
        """)
        # In case the table already exists, try to add the column (ignore error if it exists)
        try:
            cursor.execute("ALTER TABLE activity_raw_logs ADD COLUMN is_summarized BOOLEAN DEFAULT 0")
        except sqlite3.OperationalError:
            pass
        self.conn.commit()
        
    def insert_log(self, timestamp: str, app_name: str, window_title: str, ocr_text: str, audio_transcript: str = ""):
        cursor = self.conn.cursor()
        cursor.execute("""
            INSERT INTO activity_raw_logs (timestamp, app_name, window_title, ocr_text, audio_transcript)
            VALUES (?, ?, ?, ?, ?)
        """, (timestamp, app_name, window_title, ocr_text, audio_transcript))
        self.conn.commit()
        
    def get_unsummarized_logs(self, limit: int = 15):
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT id, timestamp, app_name, window_title, ocr_text, audio_transcript 
            FROM activity_raw_logs 
            WHERE is_summarized = 0
            ORDER BY timestamp ASC
            LIMIT ?
        """, (limit,))
        return cursor.fetchall()
        
    def mark_logs_summarized(self, log_ids: list):
        if not log_ids: return
        cursor = self.conn.cursor()
        placeholders = ','.join('?' * len(log_ids))
        cursor.execute(f"""
            UPDATE activity_raw_logs
            SET is_summarized = 1
            WHERE id IN ({placeholders})
        """, log_ids)
        self.conn.commit()

    def get_last_log(self):
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT app_name, window_title, ocr_text, audio_transcript
            FROM activity_raw_logs
            ORDER BY id DESC
            LIMIT 1
        """)
        return cursor.fetchone()
