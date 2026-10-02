import Foundation

struct ContextResult: Codable {
    let id: String?
    let start_time: String?
    let end_time: String?
    let summary_crux: String?
    let score: Double?
}

let sema = DispatchSemaphore(value: 0)
var request = URLRequest(url: URL(string: "http://localhost:8765/query")!)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
let body: [String: Any] = ["query": "antigravity", "limit": 5]
request.httpBody = try! JSONSerialization.data(withJSONObject: body)

URLSession.shared.dataTask(with: request) { data, response, error in
    if let err = error {
        print("NETWORK ERROR: \(err)")
    }
    if let data = data {
        do {
            let res = try JSONDecoder().decode([ContextResult].self, from: data)
            print("DECODE SUCCESS: \(res.count) items")
        } catch {
            print("DECODE ERROR: \(error)")
        }
    }
    sema.signal()
}.resume()

sema.wait()
