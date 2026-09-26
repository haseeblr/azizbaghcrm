# Ghar / Flat 6 Cleaners 🏠

A simple web app for managing **flat cleaning rotations, kitchen members, cleaning history, and flatmate administration**.
🌐 **Live App:** [Ghar](https://azizbaghcrm.netlify.app/)

The project is designed for a shared flat where cleaning responsibilities rotate between flatmates.

## ✨ Features

- 📊 Dashboard with current cleaning information
- 📅 Cleaning schedule and rotation
- 🧹 Track cleaning assignments
- 📜 Cleaning history
- 👥 Flatmate management
- 🍳 Kitchen member management
- 🔐 Admin controls
- ⚙️ Application settings
- 📝 Audit log
- 💾 Local storage support for running without a backend
- ☁️ Supabase support for shared/persistent data
- ➕ Admin can add new flatmates

## 🛠️ Tech Stack

- HTML5
- CSS3
- Vanilla JavaScript
- Supabase
- Browser Local Storage

No frontend framework or build step is required.

## 📁 Project Structure

```text
ghar-flatmate-cleaners/
├── index.html
├── security_upgrade_v3.sql
├── README.md
├── robots.txt
└── .gitignore
```

## 🚀 Run Locally

Because this is a static web application, you can run it with any static HTTP server.

### Option 1 — VS Code Live Server

Open the project in VS Code and run `index.html` using the Live Server extension.

### Option 2 — Python

From the project directory:

```bash
python -m http.server 8000
```

Then open:

```text
http://localhost:8000
```

### Option 3 — Node.js

If you have a static server available:

```bash
npx serve .
```

## ☁️ Supabase Setup

The application can use Supabase for shared data and server-side admin operations.

1. Create a Supabase project.
2. Open the Supabase SQL Editor.
3. Run:

```text
security_upgrade_v3.sql
```

4. Configure the Supabase project credentials in `index.html` if required.
5. Open the application through a local/static web server.

> **Security:** Never put a Supabase `service_role` key or other private credentials in frontend code or commit them to GitHub. Only use credentials intended for browser/client-side access.

## 👤 Admin Features

Administrators can manage flatmates from the Admin section, including adding new flatmates.

New flatmates are added to the flatmate list and can subsequently be managed through the existing application UI.

## 💾 Local Mode

The application includes local storage functionality so it can be used without a Supabase backend for local/testing scenarios.

Data stored in browser Local Storage is specific to that browser/device and is not automatically shared with other users.

## 🌐 Deployment

This project can be deployed as a static website using services such as:

- GitHub Pages
- Netlify
- Vercel
- Cloudflare Pages

For a GitHub repository, simply push the project files and configure the repository's static hosting service.

## 📤 Push to GitHub

Create a new GitHub repository, then run the following commands from this folder:

```bash
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin <YOUR_GITHUB_REPOSITORY_URL>
git push -u origin main
```

Replace `<YOUR_GITHUB_REPOSITORY_URL>` with your repository URL.

## 📌 Notes

- The UI is intentionally kept as the original Ghar / Flat 6 Cleaners interface.
- The project does not require a frontend build pipeline.
- `security_upgrade_v3.sql` contains the database/security setup required for the Supabase version.
- Do not commit private keys, passwords, tokens, or `.env` files.

## 📄 License

Add your preferred license here before publishing the project publicly.
