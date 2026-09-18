FROM python:3.13-slim

WORKDIR /app

ENV APP_HOST=0.0.0.0

COPY requirements.txt .

RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/* \
    && python -m pip install --no-cache-dir --upgrade --force-reinstall \
       "pip>=25.3" "setuptools>=78.1.1" "msgpack>=1.2.1" \
    && python -m pip install --no-cache-dir -r requirements.txt

COPY app ./app

EXPOSE 8080

CMD ["python", "app/app.py"]
