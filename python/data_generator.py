# data_generator.py
import json
import random
import time
from datetime import datetime
import requests
import threading

class MetricsGenerator:
    def __init__(self):
        self.services = ['web-app', 'api-gateway', 'database', 'cache-redis', 'auth-service']
        self.environments = ['production', 'staging', 'development']
        
    def generate_metrics(self):
        return {
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'service': random.choice(self.services),
            'environment': random.choice(self.environments),
            'response_time': random.uniform(50, 2000),  # ms
            'cpu_usage': random.uniform(10, 90),         # %
            'memory_usage': random.uniform(20, 85),      # %
            'requests_per_sec': random.uniform(10, 500),
            'error_rate': random.uniform(0, 5),          # %
            'status_code': random.choice([200, 200, 200, 200, 404, 500, 502]),
            'host': f"server-{random.randint(1, 10)}"
        }
    
    def send_to_nifi(self, data):
        # Enviamos a un endpoint HTTP que crearemos en NiFi
        try:
            response = requests.post(
                'http://nifi:8081/metrics',  # URL corregida
                json=data,
                headers={'Content-Type': 'application/json'}
            )
            print(f"Sent: {data['service']} - {data['response_time']:.2f}ms")
        except Exception as e:
            print(f"Error sending data: {e}")
    
    def run(self):
        while True:
            metrics = self.generate_metrics()
            self.send_to_nifi(metrics)
            time.sleep(2)  # Envía datos cada 2 segundos

if __name__ == "__main__":
    generator = MetricsGenerator()
    generator.run()
