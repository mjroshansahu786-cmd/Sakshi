import time
import os
import lancedb
from ollama import Client
from database import Database

# LanceDB setup
DB_URI = os.path.expanduser("~/.mnemos/lancedb")
db = lancedb.connect(DB_URI)

def get_or_create_table():
    try:
        resp = db.list_tables()
        tables = set(getattr(resp, "tables", resp))
    except AttributeError:
        tables = set(db.table_names())
    if "activity_summaries" not in tables:
        # Schema uses a text vector embedding
        import pyarrow as pa
        schema = pa.schema([
            pa.field("vector", pa.list_(pa.float32(), 384)), # BGE-small / all-MiniLM typically uses 384
            pa.field("id", pa.string()),
            pa.field("start_time", pa.string()),
            pa.field("end_time", pa.string()),
            pa.field("summary_crux", pa.string())
        ])
        return db.create_table("activity_summaries", schema=schema)
    return db.open_table("activity_summaries")

def summarize_batch():
    sqlite_db = Database()
    
    # Fetch a large chunk to see if we can group by time
    all_logs = sqlite_db.get_unsummarized_logs(limit=100)
    if not all_logs:
        return False
        
    import datetime
    start_time_dt = datetime.datetime.fromisoformat(all_logs[0][1].replace("Z", "+00:00"))
    
    logs = []
    for log in all_logs:
        log_time = datetime.datetime.fromisoformat(log[1].replace("Z", "+00:00"))
        # Break if we span more than 15 minutes and have enough logs to make a good summary
        if (log_time - start_time_dt).total_seconds() > 15 * 60 and len(logs) > 0:
            break
        logs.append(log)
        # Hard limit to avoid blowing up LLM context window
        if len(logs) >= 20:
            break
            
    start_time = logs[0][1] # index 1 is timestamp
    end_time = logs[-1][1]
    
    # Combine logs into a prompt
    prompt = """Analyze the following raw activity stream of the user's screen (captured via OCR). 
Write a simple, human-readable summary of what the user was actually doing in this time period.
Focus on:
1. What exactly was the user working on?
2. What changed from the previous snapshot?

CRITICAL INSTRUCTIONS:
- The OCR text contains EVERYTHING on the screen, including background UI noise like IDE file explorers (e.g. lists of files/folders), browser tabs, and menus.
- DO NOT assume the user is "editing a file" just because you see filenames in the OCR. 
- Look for active tasks: Are they chatting with an AI assistant? Are they typing commands in a terminal (like git push)? Are they watching a YouTube video? 
- Focus ONLY on the primary active task. Ignore the background UI noise.

Write it in extremely plain, easy-to-understand English. Keep it to 1-2 short, direct sentences. Do NOT use bullet points. Do not say 'The user is...', just describe the activity directly (e.g., 'Chatting with an AI assistant about GitHub setup' or 'Setting up a git repository in the terminal').

Raw Activity Stream:
"""
    log_ids = []
    
    for log in logs:
        log_id, timestamp, app, title, ocr, audio = log
        log_ids.append(log_id)
        prompt += f"[{timestamp}] App: {app} | Window: {title}\n"
        if ocr:
            prompt += f"OCR: {ocr[:200]}...\n"
        if audio:
            prompt += f"Audio: {audio}\n"
        prompt += "---\n"
        
    print(f"Generating summary for {len(logs)} logs from {start_time} to {end_time}...")
    
    client = Client(host='http://127.0.0.1:11434')
    try:
        response = client.generate(model='llama3.2', prompt=prompt)
        summary = response['response']
        print("Summary generated:\n", summary)
        
        # Truncate summary for embeddings just in case Llama went rogue
        safe_summary = summary[:2000]
        
        # Generate embedding
        emb_response = client.embeddings(model='all-minilm', prompt=safe_summary)
        embedding = emb_response['embedding']
        
        # Save to LanceDB
        table = get_or_create_table()
        table.add([{
            "vector": embedding,
            "id": f"summary_{int(time.time())}_{log_ids[-1]}",
            "start_time": start_time,
            "end_time": end_time,
            "summary_crux": summary
        }])
        
        # Mark as summarized in SQLite
        sqlite_db.mark_logs_summarized(log_ids)
        print(f"Summary saved to LanceDB and {len(log_ids)} logs marked as summarized.")
        
        # Save concise summary to daily markdown archive
        import datetime
        def format_time(iso_str):
            try:
                dt = datetime.datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
                return dt.astimezone().strftime("%I:%M %p").lstrip('0')
            except:
                return iso_str
                
        archive_dir = os.path.expanduser("~/Documents/Mnemos_Archive")
        if not os.path.exists(archive_dir):
            os.makedirs(archive_dir)
            
        date_str = start_time.split("T")[0]
        archive_path = os.path.join(archive_dir, f"{date_str}.md")
        
        with open(archive_path, 'a') as af:
            t1 = format_time(start_time)
            t2 = format_time(end_time)
            af.write(f"**{t1} to {t2}**\n\n")
            af.write(f"{summary}\n\n")
            af.write("---\n\n")
            
        return True
        
    except Exception as e:
        print(f"Failed to summarize or embed: {e}")
        return False

def main():
    print("Starting summarizer daemon...")
    while True:
        try:
            processed_any = summarize_batch()
            if not processed_any:
                print("No recent activity to summarize. Waiting 1 minute...")
                time.sleep(60)
        except Exception as e:
            print(f"Fatal error in main loop: {e}")
            time.sleep(60)

if __name__ == "__main__":
    main()
