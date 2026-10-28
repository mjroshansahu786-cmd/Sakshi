# SAKSHI: Your Personal Visual Memory Assistant

## 🚀 Overview
**SAKSHI** (Sanskrit for "Witness" or "Observer") is an AI-powered, privacy-first macOS application that acts as your personal visual memory assistant. By intelligently capturing and analyzing your screen activity, SAKSHI builds a searchable, semantic timeline of your digital life—allowing you to recall exactly what you were working on, reading, or researching at any moment in time.

## 🧠 The Problem
In the modern digital workplace, knowledge workers constantly switch between contexts, applications, and browser tabs. Finding a specific piece of information from days ago often relies on fragmented browser histories, manual notes, or flawed human memory. Existing "timeline" solutions are either highly invasive to privacy, resource-heavy, or require manual logging.

## 💡 The Solution & Value Proposition
SAKSHI solves this by running a lightweight, intelligent daemon in the background. It takes periodic visual snapshots of your workspace, extracts the text using on-device OCR, and summarizes the activity using local Large Language Models (LLMs). The result is a highly efficient, semantic, and easily searchable activity feed that runs **entirely on your own machine**. 

By abstracting away the manual effort of note-taking and history tracking, SAKSHI allows users to remain in a state of deep work, secure in the knowledge that their context is being preserved.

## 🏗 System Architecture
SAKSHI is built with a decoupled, microservice-inspired architecture designed for maximum performance, extensibility, and user privacy:

1. **Native macOS Application (Swift/SwiftUI)**
   A menu-bar application and Spotlight-like Quick Search overlay. Provides seamless, native controls and lightning-fast search capabilities using global keyboard shortcuts (`⌃ + Space`).
   
2. **Background Daemon (Swift/CoreGraphics/Vision)**
   A highly optimized background worker utilizing `CGGetActiveDisplayList` and `CoreGraphics` to support multi-monitor setups. It performs on-device OCR using Apple's Native Vision framework to extract text without sending images to the cloud.

3. **Data Ingestion & Optimization Pipeline (Python/SQLite)**
   Intelligently deduplicates visual data in real-time (skipping frames where no meaningful screen changes occurred) to optimize storage overhead and battery life.

4. **AI Summarization Engine (Llama 3.2 & LanceDB)**
   Periodically batches OCR data and passes it to a local LLM to generate plain-English summaries of the user's activity. The summaries are vectorized and stored in a LanceDB vector database for semantic search.

## ✨ Key Features
- **Semantic Search**: Ask natural language questions like *"What was I reading about product management yesterday?"* and instantly retrieve that context.
- **Privacy-First (100% Local)**: All OCR, LLM inference, and data storage happen locally on your Mac. No user data is ever sent to the cloud.
- **Multi-Monitor Support**: Intelligently captures and stitches together activity across all active displays for a complete contextual picture.
- **Smart Deduplication**: Only saves data when meaningful changes occur on-screen, drastically reducing CPU usage and disk space.
- **Global Quick Search**: A Spotlight-style overlay (`⌃ + Space`) allows instant retrieval of past contexts without breaking your workflow.
- **Sakshi Companion (Mascot)**: A floating, glowing eye-orb that lives on the right edge of your screen — see below.

## 👁 The Sakshi Companion
The mascot is a floating "witness" orb that watches over your timeline:

- **Always on top**, across every Space and even full-screen apps.
- **Click** the orb → toggles the Quick Search overlay.
- **Right-click** → context menu (Timeline, Pause/Resume, Preferences, Hide, Quit).
- **Drag** it anywhere; it snaps to the nearest screen edge on release.
- **Auto-peek**: after a few idle seconds it tucks itself halfway into the edge so it never blocks your content; hover to wake it.
- **Status-aware**: green pulsing halo while recording (with a ping ring on every capture + a blink every now and then), gray when paused, red when Screen Recording permission is missing.
- Hover shows a status bubble: recording state + time since the last captured frame.
- Its position and on/off state persist across launches (Preferences → Companion).

## 🛠 Build & Install
```bash
cd Mnemos
./scripts/build_app.sh                 # build + install + restart the LaunchAgent
./scripts/build_app.sh --bundle-backend # also embed the Python backend (~1.3 GB) for a portable .app
./scripts/build_app.sh --no-restart     # install without restarting the agent
```

The script assembles `/Applications/SAKSHI.app`, ad-hoc codesigns it, refreshes
`~/Library/LaunchAgents/com.roshan.sakshi.plist` (app logs now go to
`~/.mnemos/logs/app.log`, and the agent relaunches the app if it crashes).

> **Note:** because the app is ad-hoc signed, reinstalling may require re-granting
> **Screen Recording** and **Accessibility** permissions in System Settings →
> Privacy & Security. The app detects missing permissions and shows it in the
> menu bar and on the companion orb.


## 🗺 Product Roadmap
- **Sprint 1 (Completed)**: Core daemon logic, SQLite ingestion, and baseline OCR.
- **Sprint 2 (Completed)**: Local LLM integration, LanceDB semantic vector search, native SwiftUI menu-bar app, and Multi-Monitor panoramic support.
- **Sprint 3 (Upcoming)**: Audio transcription integration (via Whisper) to capture meeting notes and link them to visual context.
- **Sprint 4 (Upcoming)**: Advanced analytics dashboard to visualize time spent across different applications and projects to improve productivity.

---
*This repository serves as a portfolio project showcasing end-to-end Product Management, System Architecture design, and AI integration capabilities.*
