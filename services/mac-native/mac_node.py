#!/usr/bin/env python3
"""
SynapseGrid Mac M2 Native Node
Service natif optimisé pour Apple Silicon avec Metal Performance Shaders
"""

import asyncio
import json
import time
import psutil
import requests
import subprocess
import threading
import signal
import sys
from datetime import datetime
from pathlib import Path

# Configuration
NODE_ID = f"mac-m2-native-{int(time.time())}"
NODE_TYPE = "Mac M2 Native"
GATEWAY_URL = "http://localhost:8080"
NODE_PORT = 8084
UPDATE_INTERVAL = 10
LOG_FILE = "mac_node.log"

class MacM2Node:
    def __init__(self):
        self.node_id = NODE_ID
        self.node_type = NODE_TYPE
        self.status = "starting"
        self.performance_score = 95  # Mac M2 score élevé
        self.jobs_completed = 0
        self.jobs_active = 0
        self.start_time = time.time()
        self.running = True
        self.last_heartbeat = time.time()
        
        # Setup logging
        self.setup_logging()
        
        # Handle shutdown gracefully
        signal.signal(signal.SIGINT, self.shutdown)
        signal.signal(signal.SIGTERM, self.shutdown)
        
    def setup_logging(self):
        """Configure le logging"""
        import logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(LOG_FILE),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
    def get_system_metrics(self):
        """Récupère les métriques système Mac M2"""
        try:
            # CPU Apple Silicon
            cpu_percent = psutil.cpu_percent(interval=0.1)
            cpu_count = psutil.cpu_count(logical=False)
            
            # Mémoire
            memory = psutil.virtual_memory()
            
            # Performance Metal (simulation basée sur charge)
            metal_performance = self.calculate_metal_performance(cpu_percent)
            
            # Température approximative
            temp = self.get_estimated_temperature(cpu_percent)
            
            # Efficacité énergétique (avantage Mac M2)
            energy_efficiency = self.calculate_energy_efficiency(cpu_percent)
            
            return {
                "node_id": self.node_id,
                "node_type": self.node_type,
                "status": self.status,
                "cpu_cores": cpu_count,
                "cpu_usage": round(cpu_percent, 1),
                "memory_total_gb": round(memory.total / (1024**3), 1),
                "memory_used_gb": round(memory.used / (1024**3), 1),
                "memory_percent": round(memory.percent, 1),
                "temperature_c": temp,
                "metal_performance": metal_performance,
                "energy_efficiency": energy_efficiency,
                "performance_score": self.performance_score,
                "jobs_completed": self.jobs_completed,
                "jobs_active": self.jobs_active,
                "uptime_hours": round((time.time() - self.start_time) / 3600, 2),
                "last_seen": datetime.now().isoformat()
            }
        except Exception as e:
            self.logger.error(f"Erreur métriques système: {e}")
            return {}
    
    def calculate_metal_performance(self, cpu_usage):
        """Calcule la performance Metal MPS"""
        # Mac M2 excelle avec Metal - performance inverse de la charge
        base_performance = 95
        load_penalty = cpu_usage * 0.3
        return max(70, base_performance - load_penalty)
    
    def get_estimated_temperature(self, cpu_usage):
        """Estime la température basée sur la charge"""
        # Mac M2 reste relativement cool
        base_temp = 35
        load_temp = cpu_usage * 0.4
        return round(base_temp + load_temp, 1)
    
    def calculate_energy_efficiency(self, cpu_usage):
        """Calcule l'efficacité énergétique (avantage Mac M2)"""
        # Mac M2 très efficace même sous charge
        if cpu_usage < 30:
            return 95
        elif cpu_usage < 60:
            return 88
        else:
            return 75
    
    def register_with_gateway(self):
        """S'enregistre auprès du Gateway"""
        try:
            metrics = self.get_system_metrics()
            response = requests.post(
                f"{GATEWAY_URL}/nodes/register",
                json=metrics,
                timeout=5,
                headers={"Content-Type": "application/json"}
            )
            
            if response.status_code == 200:
                self.status = "active"
                self.logger.info(f"Nœud Mac M2 enregistré: {self.node_id}")
                return True
            else:
                self.logger.warning(f"Échec enregistrement: {response.status_code}")
                return False
                
        except requests.exceptions.RequestException as e:
            self.logger.warning(f"Gateway non disponible: {e}")
            self.status = "disconnected"
            return False
    
    def send_heartbeat(self):
        """Envoie un heartbeat au Gateway"""
        try:
            metrics = self.get_system_metrics()
            response = requests.post(
                f"{GATEWAY_URL}/nodes/heartbeat",
                json=metrics,
                timeout=3
            )
            
            if response.status_code == 200:
                self.last_heartbeat = time.time()
                self.status = "active"
                return True
            else:
                self.logger.warning(f"Heartbeat échoué: {response.status_code}")
                return False
                
        except requests.exceptions.RequestException:
            self.status = "disconnected"
            return False
    
    def simulate_job_processing(self):
        """Simule le traitement de jobs IA"""
        if self.jobs_active > 0:
            # Simule la complétion de jobs
            if time.time() % 15 < 1:  # Toutes les 15 secondes
                completed = min(self.jobs_active, 2)
                self.jobs_active -= completed
                self.jobs_completed += completed
                self.logger.info(f"Jobs complétés: {completed} (Total: {self.jobs_completed})")
        
        # Simule l'arrivée de nouveaux jobs
        if time.time() % 20 < 1 and self.jobs_active < 5:
            new_jobs = 1 if self.status == "active" else 0
            self.jobs_active += new_jobs
            if new_jobs > 0:
                self.logger.info(f"Nouveau job reçu (Actifs: {self.jobs_active})")
    
    def run_status_server(self):
        """Lance un serveur HTTP simple pour le status"""
        from http.server import HTTPServer, BaseHTTPRequestHandler
        import threading
        
        class StatusHandler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == '/status':
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    
                    status_data = {
                        "node_id": self.server.node.node_id,
                        "status": self.server.node.status,
                        "performance": self.server.node.performance_score,
                        "jobs_completed": self.server.node.jobs_completed,
                        "uptime": time.time() - self.server.node.start_time
                    }
                    
                    self.wfile.write(json.dumps(status_data, indent=2).encode())
                else:
                    self.send_response(404)
                    self.end_headers()
            
            def log_message(self, format, *args):
                pass  # Disable default logging
        
        try:
            server = HTTPServer(('localhost', NODE_PORT), StatusHandler)
            server.node = self
            server_thread = threading.Thread(target=server.serve_forever, daemon=True)
            server_thread.start()
            self.logger.info(f"Status server démarré sur http://localhost:{NODE_PORT}/status")
        except Exception as e:
            self.logger.warning(f"Impossible de démarrer le serveur status: {e}")
    
    def run(self):
        """Boucle principale du nœud"""
        self.logger.info(f"🍎 Démarrage du nœud Mac M2 natif: {self.node_id}")
        
        # Démarrer le serveur de status
        self.run_status_server()
        
        # Tentative d'enregistrement initial
        self.register_with_gateway()
        
        # Boucle principale
        while self.running:
            try:
                # Heartbeat périodique
                self.send_heartbeat()
                
                # Simulation de traitement
                self.simulate_job_processing()
                
                # Log périodique
                if int(time.time()) % 60 == 0:  # Toutes les minutes
                    metrics = self.get_system_metrics()
                    self.logger.info(f"📊 CPU: {metrics.get('cpu_usage', 0)}% | "
                                   f"Mém: {metrics.get('memory_percent', 0)}% | "
                                   f"Jobs: {self.jobs_completed} | "
                                   f"Temp: {metrics.get('temperature_c', 0)}°C")
                
                time.sleep(UPDATE_INTERVAL)
                
            except KeyboardInterrupt:
                break
            except Exception as e:
                self.logger.error(f"Erreur dans la boucle principale: {e}")
                time.sleep(5)
        
        self.shutdown()
    
    def shutdown(self, signum=None, frame=None):
        """Arrêt propre du nœud"""
        if self.running:
            self.logger.info("🛑 Arrêt du nœud Mac M2 natif...")
            self.running = False
            self.status = "stopping"
            
            # Désenregistrement du Gateway
            try:
                requests.post(
                    f"{GATEWAY_URL}/nodes/unregister",
                    json={"node_id": self.node_id},
                    timeout=3
                )
            except:
                pass
            
            self.logger.info("✅ Nœud Mac M2 arrêté proprement")
            sys.exit(0)

if __name__ == "__main__":
    node = MacM2Node()
    node.run()
