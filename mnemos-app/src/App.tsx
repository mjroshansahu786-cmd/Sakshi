import { useState } from 'react';
import './index.css';

interface ContextResult {
  id: string;
  start_time: string;
  end_time: string;
  summary_crux: string;
  score: number;
}

function App() {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<ContextResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [searched, setSearched] = useState(false);

  const handleSearch = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!query.trim()) return;

    setLoading(true);
    setSearched(true);
    
    try {
      const response = await fetch('http://localhost:8765/query', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ query, limit: 5 }),
      });
      const data = await response.json();
      setResults(data);
    } catch (err) {
      console.error(err);
      setResults([]);
    } finally {
      setLoading(false);
    }
  };

  const formatTime = (isoString: string) => {
    if (!isoString) return 'Unknown';
    const date = new Date(isoString);
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) + ' - ' + date.toLocaleDateString();
  };

  return (
    <div className="app-container">
      <div className="background-glow"></div>
      
      <header className="header">
        <div className="logo-container">
          <div className="logo-icon"></div>
          <h1>Mnemos</h1>
        </div>
        <p className="subtitle">Your localized context engine.</p>
      </header>

      <main className="main-content">
        <form className="search-form" onSubmit={handleSearch}>
          <div className="search-input-wrapper">
            <svg className="search-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="11" cy="11" r="8"></circle>
              <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
            </svg>
            <input 
              type="text" 
              placeholder="What was I reading about Apple Silicon?" 
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              className="search-input"
            />
          </div>
          <button type="submit" className="search-button" disabled={loading}>
            {loading ? <div className="spinner"></div> : 'Recall'}
          </button>
        </form>

        {searched && !loading && results.length === 0 && (
          <div className="no-results fade-in">
            <p>No relevant context found in your memory.</p>
          </div>
        )}

        <div className="timeline-container">
          {results.map((res, idx) => (
            <div 
              key={res.id || idx} 
              className="timeline-item slide-up" 
              style={{ animationDelay: `${idx * 0.1}s` }}
            >
              <div className="timeline-marker"></div>
              <div className="timeline-content">
                <div className="timeline-header">
                  <span className="time">{formatTime(res.start_time)}</span>
                  <span className="score">{(res.score * 100).toFixed(0)}% match</span>
                </div>
                <div className="summary-card">
                  {res.summary_crux.split('\n').map((line, i) => (
                    <p key={i}>{line}</p>
                  ))}
                </div>
              </div>
            </div>
          ))}
        </div>
      </main>
    </div>
  );
}

export default App;
