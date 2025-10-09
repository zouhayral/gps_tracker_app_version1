# 🚗 GPS Tracker App (Flutter + Traccar)

A Flutter-based mobile app that integrates with a **Traccar** backend API for real-time GPS tracking.  
This document provides setup instructions, features, and implementation details for the **authentication and login** module.

---

## 🧩 Project Overview

**Tech Stack**
- **Frontend:** Flutter (Dart)
- **Backend:** Traccar API (REST)
- **Font:** [Poppins](https://fonts.google.com/specimen/Poppins)
- **Design Language:** Clean, minimal white background + lime green accent (`#A5D72F`)

---

## ✨ Features

- 🔐 User authentication via **Traccar API** (`/api/session`)
- 📋 Fetch and display **user info** from Traccar after login
- 💾 Save **last login email** locally and auto-fill next time
- 🔒 Secure authentication using HTTP Basic Auth (username/password)
- 🧠 Persistent session using local storage (`shared_preferences`)
- 🎨 Clean responsive UI matching design (see image)
- ⚠️ Error handling for invalid credentials and connection issues
- 🚀 Future-ready for GPS tracking and map integration

---

## 🧠 App Flow

1. **Splash Screen → Login Page**
2. **App loads saved email from local storage**
3. **User enters password (email pre-filled)**
4. **Flutter sends `POST /api/session` to Traccar**
5. **If successful:**
   - Store session data locally  
   - Fetch user info from `/api/session`  
   - Save email for next time  
   - Navigate to dashboard  
6. **If failed:** show an error message

---

## 🛠️ Setup Instructions

### 1. Create a new Flutter project
```bash
flutter create gps_tracker_app
cd gps_tracker_app
