import sys
import lancedb
from ollama import Client

def main():
    if len(sys.argv) < 3 or sys.argv[1] != "query":
        print("Usage: mnemos query \"<search_term>\"")
        sys.exit(1)
        
    query = sys.argv[2]
    print(f"Searching for: '{query}'")
    
    client = Client(host='http://127.0.0.1:11434')
    try:
        # Generate embedding for the query
        emb_response = client.embeddings(model='all-minilm', prompt=query)
        query_vector = emb_response['embedding']
        
        # Query LanceDB
        import os
        DB_URI = os.path.expanduser("~/.mnemos/lancedb")
        db = lancedb.connect(DB_URI)
        
        if "activity_summaries" not in db.table_names():
            print("No summaries found in database yet.")
            return
            
        table = db.open_table("activity_summaries")
        results = table.search(query_vector).limit(5).to_list()
        
        if not results:
            print("No relevant context found.")
            return
            
        print("\n--- Context Results ---\n")
        for res in results:
            # We get _distance, start_time, end_time, summary_crux
            score = 1.0 - res.get('_distance', 0)
            print(f"Time: {res.get('start_time')} to {res.get('end_time')} (Score: {score:.2f})")
            print(res.get('summary_crux', '').strip())
            print("-" * 30)
            
    except Exception as e:
        print(f"Query failed: {e}")

if __name__ == "__main__":
    main()
