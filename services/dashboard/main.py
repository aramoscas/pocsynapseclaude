#!/usr/bin/env python3
import http.server
import socketserver

html_content = '''<!DOCTYPE html>
<html>
<head>
    <title>SynapseGrid Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; }
        .header { text-align: center; margin-bottom: 30px; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; }
        .stat-card { background: #007bff; color: white; padding: 20px; border-radius: 8px; text-align: center; }
        .stat-number { font-size: 2em; font-weight: bold; }
        .stat-label { font-size: 0.9em; opacity: 0.9; }
        h1 { color: #333; }
        .links { margin-top: 30px; }
        .links a { display: inline-block; margin: 5px 10px; padding: 10px 15px; background: #28a745; color: white; text-decoration: none; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 SynapseGrid Dashboard</h1>
            <p>Decentralized AI Compute Network</p>
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-number">3</div>
                <div class="stat-label">Active Nodes</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">12</div>
                <div class="stat-label">Jobs Processed</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">450ms</div>
                <div class="stat-label">Avg Latency</div>
            </div>
        </div>
        
        <div class="links">
            <h3>🔗 Quick Links</h3>
            <a href="http://localhost:8080/health">Gateway Health</a>
            <a href="http://localhost:9090">Prometheus</a>
            <a href="http://localhost:3001">Grafana</a>
        </div>
        
        <div style="margin-top: 30px; text-align: center;">
            <p><strong>Status:</strong> <span style="color: green;">HEALTHY</span></p>
            <p>Last Update: <span id="time"></span></p>
        </div>
    </div>
    
    <script>
        document.getElementById('time').textContent = new Date().toLocaleTimeString();
        setInterval(() => {
            document.getElementById('time').textContent = new Date().toLocaleTimeString();
        }, 1000);
    </script>
</body>
</html>'''

class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(html_content.encode())

if __name__ == "__main__":
    PORT = 3000
    with socketserver.TCPServer(("", PORT), DashboardHandler) as httpd:
        print(f"✅ Dashboard serving at port {PORT}")
        httpd.serve_forever()
