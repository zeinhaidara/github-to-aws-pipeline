FROM python:3.13-slim

WORKDIR /app

ENV APP_HOST=0.0.0.0

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

EXPOSE 8080

CMD ["python", "app/app.py"]
