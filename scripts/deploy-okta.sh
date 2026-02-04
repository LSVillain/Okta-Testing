#!/bin/bash
# user-data.sh - Minimal setup
apt-get update
apt-get install -y nodejs

# Create the simplest possible server
cat > /opt/okta.js << 'EOF'
const http = require('http');

const server = http.createServer((req, res) => {
  if (req.url === '/health' && req.method === 'GET') {
    res.writeHead(200);
    res.end('OK');
  } 
  else if (req.url === '/oauth2/token' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      // Simple check - no real parsing
      if (body.includes('admin@demo.com') && body.includes('admin123')) {
        res.writeHead(200);
        res.end('access_token=simple-demo-token');
      } else {
        res.writeHead(401);
        res.end('error');
      }
    });
  }
  else {
    res.writeHead(200);
    res.end('Mock Okta Server\nUse: POST /oauth2/token');
  }
});

server.listen(3001, '0.0.0.0', () => {
  console.log('✅ Simple Okta on :3001');
});
EOF

node /opt/okta.js &