from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import lancedb
import os
from ollama import Client

app = FastAPI(title="Mnemos Context Engine API")

# Allow CORS for the frontend React app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class QueryRequest(BaseModel):
    query: str
    limit: Optional[int] = 10

class ContextResult(BaseModel):
    id: str
    start_time: str
    end_time: str
    summary_crux: str
    score: float

@app.get("/status")
def status():
    return {"status": "ok", "service": "mnemos-backend"}

@app.post("/query", response_model=List[ContextResult])
def query_context(req: QueryRequest):
    try:
        DB_URI = os.path.expanduser("~/.mnemos/lancedb")
        db = lancedb.connect(DB_URI)
        
        if "activity_summaries" not in db.table_names():
            return []
            
        table = db.open_table("activity_summaries")

        if not req.query.strip():
            all_results = table.search().to_list()
            all_results.sort(key=lambda x: x.get("end_time", ""), reverse=True)
            results = all_results[:req.limit]
            for r in results:
                r['_distance'] = 0.0
        else:
            client = Client(host='http://127.0.0.1:11434')
            emb_response = client.embeddings(model='all-minilm', prompt=req.query)
            query_vector = emb_response['embedding']
            results = table.search(query_vector).limit(req.limit).to_list()
        
        formatted_results = []
        for res in results:
            score = 1.0 - res.get('_distance', 0)
            formatted_results.append(
                ContextResult(
                    id=res.get('id', ''),
                    start_time=res.get('start_time', ''),
                    end_time=res.get('end_time', ''),
                    summary_crux=res.get('summary_crux', ''),
                    score=score
                )
            )
            
        return formatted_results
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8765)
