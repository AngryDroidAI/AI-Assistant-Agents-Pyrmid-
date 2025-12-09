#!/bin/bash
# Capsule Backend Setup Script with Cleanup
# Creates backend project structure, installs dependencies, and scaffolds files

# Create project folder
mkdir -p backend/routes backend/uploads
cd backend || exit

# Initialize npm project
npm init -y

# Install dependencies
npm install express cors dotenv multer node-fetch ssh2
npm install --save-dev nodemon

# Create .env file
cat > .env << 'EOF'
# Local Ollama API
OLLAMA_URL=http://localhost:11434

# Future external APIs (placeholders)
SEARCH_API_KEY=your-search-key-here
SSH_API_KEY=your-ssh-key-here
VISION_API_KEY=your-vision-key-here

# Server port
PORT=3000
EOF

# Create package.json with scripts
cat > package.json << 'EOF'
{
  "name": "capsule-backend",
  "version": "1.0.0",
  "description": "Capsule backend for Ollama + tools",
  "main": "server.js",
  "type": "module",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js",
    "cleanup": "node cleanup.js"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "dotenv": "^16.4.0",
    "express": "^4.19.2",
    "multer": "^1.4.5",
    "node-fetch": "^3.3.2",
    "ssh2": "^1.15.0"
  },
  "devDependencies": {
    "nodemon": "^3.1.0"
  }
}
EOF

# Create server.js
cat > server.js << 'EOF'
import express from "express";
import cors from "cors";
import dotenv from "dotenv";

import chatRouter from "./routes/chat.js";
import searchRouter from "./routes/search.js";
import sshRouter from "./routes/ssh.js";
import visionRouter from "./routes/vision.js";

dotenv.config();
const app = express();

app.use(cors());
app.use(express.json());

// Routes
app.use("/api/chat", chatRouter);
app.use("/api/search", searchRouter);
app.use("/api/ssh", sshRouter);
app.use("/api/vision", visionRouter);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Capsule backend running on http://localhost:${PORT}`));
EOF

# Create routes/chat.js
cat > routes/chat.js << 'EOF'
import express from "express";
import fetch from "node-fetch";

const router = express.Router();

router.post("/", async (req, res) => {
  const { model, prompt, stream } = req.body;
  try {
    const response = await fetch(`${process.env.OLLAMA_URL}/api/generate`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ model, prompt, stream })
    });
    response.body.pipe(res);
  } catch (err) {
    res.status(500).json({ error: "Ollama backend not reachable" });
  }
});

export default router;
EOF

# Create routes/search.js
cat > routes/search.js << 'EOF'
import express from "express";

const router = express.Router();

// Placeholder search route
router.get("/", async (req, res) => {
  const { q } = req.query;
  // Future: integrate Bing/Google API using SEARCH_API_KEY
  res.json({ results: [`Search results for: ${q}`] });
});

export default router;
EOF

# Create routes/ssh.js
cat > routes/ssh.js << 'EOF'
import express from "express";
import { Client } from "ssh2";

const router = express.Router();

router.post("/", (req, res) => {
  const { host, username, password, command } = req.body;
  const conn = new Client();

  conn.on("ready", () => {
    conn.exec(command, (err, stream) => {
      if (err) return res.status(500).json({ error: err.message });
      let output = "";
      stream.on("data", (data) => (output += data.toString()));
      stream.on("close", () => {
        conn.end();
        res.json({ output });
      });
    });
  }).connect({ host, username, password });
});

export default router;
EOF

# Create routes/vision.js with cleanup
cat > routes/vision.js << 'EOF'
import express from "express";
import multer from "multer";
import fetch from "node-fetch";
import fs from "fs";

const router = express.Router();
const upload = multer({ dest: "uploads/" });

router.post("/", upload.single("file"), async (req, res) => {
  const { prompt } = req.body;
  const filePath = req.file.path;

  try {
    const response = await fetch(`${process.env.OLLAMA_URL}/api/generate`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: "llama3.2-vision:11b",
        prompt: `${prompt}\n[Image: ${filePath}]`,
        stream: false
      })
    });
    const data = await response.json();

    // Cleanup file immediately after use
    fs.unlink(filePath, (err) => {
      if (err) console.error("Cleanup failed:", err);
    });

    res.json({ reply: data.response });
  } catch (err) {
    // Cleanup even if error
    fs.unlink(filePath, () => {});
    res.status(500).json({ error: "Vision model not reachable" });
  }
});

export default router;
EOF

# Create cleanup.js for scheduled purges
cat > cleanup.js << 'EOF'
import fs from "fs";
import path from "path";

const uploadsDir = path.join(process.cwd(), "uploads");

fs.readdir(uploadsDir, (err, files) => {
  if (err) return console.error("Error reading uploads:", err);

  const now = Date.now();
  files.forEach(file => {
    const filePath = path.join(uploadsDir, file);
    fs.stat(filePath, (err, stats) => {
      if (err) return;
      const ageHours = (now - stats.mtimeMs) / (1000 * 60 * 60);
      if (ageHours > 24) {
        fs.unlink(filePath, (err) => {
          if (err) console.error("Failed to delete:", filePath);
          else console.log("Deleted old file:", filePath);
        });
      }
    });
  });
});
EOF

echo "✅ Backend scaffold complete. Run with: npm run dev"
echo "🧹 To cleanup old uploads manually: npm run cleanup"
echo "⏰ To schedule cleanup daily, add cron: 0 2 * * * cd $(pwd) && npm run cleanup"
