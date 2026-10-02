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
- **Global Quick Search**: A Spotlight-style overlay allows instant retrieval of past contexts without breaking your workflow.

## 🗺 Product Roadmap
- **Sprint 1 (Completed)**: Core daemon logic, SQLite ingestion, and baseline OCR.
- **Sprint 2 (Completed)**: Local LLM integration, LanceDB semantic vector search, native SwiftUI menu-bar app, and Multi-Monitor panoramic support.
- **Sprint 3 (Upcoming)**: Audio transcription integration (via Whisper) to capture meeting notes and link them to visual context.
- **Sprint 4 (Upcoming)**: Advanced analytics dashboard to visualize time spent across different applications and projects to improve productivity.

---
*This repository serves as a portfolio project showcasing end-to-end Product Management, System Architecture design, and AI integration capabilities.*
