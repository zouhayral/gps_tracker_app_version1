# 👥 User Management (Multi-User Support)

This app relies on **Traccar’s built-in user system** for authentication and device access control. Each user has their own credentials and only sees the devices they have permission to access.

---

## 🔑 User Accounts in Traccar
- Each user can log in with **email + password** (via `POST /api/session`).
- Users can have different roles:
  - **Admin**: Full access to all devices and users.
  - **Standard user**: Access only to devices explicitly assigned.
  - **Readonly**: View-only access.
- Optional: Use Supabase (or another DB) for richer profiles (photos, preferences, etc.) while Traccar remains the source of truth for tracking data.

---

## ➕ Creating a New User
Admin users can create new accounts via **Traccar Web UI** or API.

### Traccar Web UI
1. Log in as an **admin**.
2. Go to **Users → Add**.
3. Enter name, email, password, and role.

### Traccar REST API
```http
POST /api/users
Content-Type: application/json
{
  "name": "Dispatcher A",
  "email": "dispatchA@example.com",
  "password": "secret123",
  "readonly": false,
  "administrator": false
}
```

---

## 📱 Assigning Devices to Users
Devices must be linked to users with **permissions**.

### Web UI
1. Open **Devices → [Select Device] → Permissions**.
2. Assign the device to one or more users.

### REST API
```http
POST /api/permissions
Content-Type: application/json
{
  "deviceId": 12,
  "userId": 5
}
```
➡️ User with `id=5` now sees device `id=12` in their app.

---

## 📲 App Behavior
- On login, the app fetches:
  ```http
  GET /api/devices
  ```
  → Returns only devices assigned to the current user.

- Realtime updates from:
  ```http
  wss://<TRACCAR_BASE_URL>/api/socket
  ```
  → Push positions/events for devices the user has access to.

- Result: No extra app code is needed to support multiple users — permissions are enforced by Traccar.

---

## ✅ Summary
- Create users in Traccar (admin only).
- Assign devices via **permissions**.
- The app automatically limits each user’s view to their devices.
- Optional: Extend with Supabase for richer user profiles.

Automatic Linking (Supabase → Traccar)

## Overview

Our app uses two systems for managing users and devices:

Supabase: Handles authentication, profiles, and application data.
Traccar: Manages GPS devices, positions, and tracking.

To ensure each app user has access to their own devices, we automatically create a linked user in Traccar whenever a new account is created in Supabase.

Flow

User Signup

A new user signs up in the app using Supabase Auth (email + password, or social login).

Edge Function Trigger

Supabase triggers an Edge Function after user signup.

Create Traccar User

The Edge Function sends a request to the Traccar API to create a matching user:
POST http://<TRACCAR_SERVER>/api/users
Authorization: Bearer <ADMIN_TOKEN>
Content-Type: application/json

{
  "name": "New User",
  "email": "user@example.com",
  "password": "supabase_generated_password"
}


Store Traccar User ID

Traccar responds with a userId.
This userId is saved in the Supabase profiles table:
id (uuid)        -- Supabase user id
email (text)     -- User email
traccar_id (int) -- Corresponding Traccar user ID


Device Access

When the user logs in, the app retrieves their traccar_id from Supabase and uses it to fetch devices and positions from Traccar.
Advantages
No manual user creation in Traccar.
Consistent accounts across Supabase and Traccar.
Scalable: works automatically for every new signup.
Security Notes
The Traccar admin token used to create users must be kept secret and only used inside backend functions.
Never expose the admin token in the mobile app.
Device permissions and sharing are still managed in Traccar.
Example Flow Diagram
[ App User Signup ]
        ↓
 [ Supabase Auth ]
        ↓
[ Edge Function Trigger ]
        ↓
 [ Create User in Traccar ]
        ↓
[ Save traccar_id in Supabase ]
        ↓
[ User Logs In → Fetch Devices via Traccar API ]
