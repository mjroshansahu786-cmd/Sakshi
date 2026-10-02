import time
import json
import os
import mlx_whisper
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from database import Database

SPOOL_DIR = os.path.expanduser("~/.mnemos/spool")

class SpoolHandler(FileSystemEventHandler):
    def __init__(self, db: Database):
        self.db = db
        # Pre-load model so it's ready
        print("Preloading mlx-whisper model...")
        self.whisper_model = "mlx-community/whisper-small.en-mlx"
        
    def on_created(self, event):
        if not event.is_directory and event.src_path.endswith(".json"):
            self.process_payload(event.src_path)
            
    def process_payload(self, json_path: str):
        if not os.path.exists(json_path):
            return
            
        try:
            with open(json_path, 'r') as f:
                payload = json.load(f)
                
            audio_transcript = ""
            if payload.get("hasAudio") and payload.get("audioFileName"):
                audio_path = os.path.join(SPOOL_DIR, payload["audioFileName"])
                if os.path.exists(audio_path):
                    print(f"Transcribing audio: {audio_path}")
                    result = mlx_whisper.transcribe(audio_path, path_or_hf_repo=self.whisper_model)
                    audio_transcript = result.get("text", "")
                    os.remove(audio_path)
            
            # Deduplication check
            app_name = payload.get("appName", "")
            window_title = payload.get("windowTitle", "")
            ocr_text = payload.get("ocrText", "")
            
            last_log = self.db.get_last_log()
            if last_log:
                last_app, last_win, last_ocr, last_audio = last_log
                if app_name == last_app and window_title == last_win:
                    if not audio_transcript and not last_audio:
                        import difflib
                        ratio = difflib.SequenceMatcher(None, ocr_text, last_ocr).ratio()
                        if ratio > 0.95:
                            print(f"Skipping log {json_path} - duplicate content (similarity: {ratio:.2f})")
                            os.remove(json_path)
                            return
            
            self.db.insert_log(
                timestamp=payload["timestamp"],
                app_name=app_name,
                window_title=window_title,
                ocr_text=ocr_text,
                audio_transcript=audio_transcript
            )
            
            print(f"Processed and inserted log from {json_path}")
            os.remove(json_path)
            
        except Exception as e:
            print(f"Error processing {json_path}: {e}")

def main():
    if not os.path.exists(SPOOL_DIR):
        os.makedirs(SPOOL_DIR)
        
    db = Database()
    event_handler = SpoolHandler(db)
    
    print("Processing existing files in spool...")
    for filename in sorted(os.listdir(SPOOL_DIR)):
        if filename.endswith(".json"):
            event_handler.process_payload(os.path.join(SPOOL_DIR, filename))
            
    observer = Observer()
    observer.schedule(event_handler, SPOOL_DIR, recursive=False)
    observer.start()
    
    print(f"Watching spool directory: {SPOOL_DIR}")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()

if __name__ == "__main__":
    main()
