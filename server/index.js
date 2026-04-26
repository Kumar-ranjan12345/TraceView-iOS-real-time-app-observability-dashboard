const express = require('express');
const { WebSocketServer } = require('ws');
const http = require('http');
const path = require('path');

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

// Serve dashboard
app.use(express.static(path.join(__dirname, '../dashboard')));
app.use(express.json());

// Store connected clients
const dashboardClients = new Set();
let iosClient = null;

wss.on('connection', (ws, req) => {
  const type = new URL(req.url, 'http://localhost').searchParams.get('type');

  if (type === 'ios') {
    iosClient = ws;
    console.log('📱 iOS app connected');

    ws.on('message', (data) => {
      try {
        const metric = JSON.parse(data);
        // Broadcast to all dashboard clients
        dashboardClients.forEach(client => {
          if (client.readyState === 1) {
            client.send(JSON.stringify(metric));
          }
        });
      } catch (e) {
        console.error('Parse error:', e);
      }
    });

    ws.on('close', () => {
      console.log('📱 iOS app disconnected');
      iosClient = null;
    });

  } else {
    dashboardClients.add(ws);
    console.log(`🖥️  Dashboard connected (${dashboardClients.size} total)`);

    ws.on('close', () => {
      dashboardClients.delete(ws);
    });
  }
});

const PORT = 4000;
server.listen(PORT, () => {
  console.log(`🚀 Dashboard server: http://localhost:${PORT}`);
  console.log(`📡 WebSocket: ws://localhost:${PORT}`);
});
