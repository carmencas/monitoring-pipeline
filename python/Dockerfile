FROM python:3.9-slim

WORKDIR /app

RUN apt-get update \
 && apt-get install --no-install-recommends -y netcat-openbsd curl \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY data_generator.py .

CMD ["python", "data_generator.py"]
