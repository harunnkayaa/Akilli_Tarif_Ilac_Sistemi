# Backend imajı — sürümler sabit, hocanın makinesinde de aynı çalışır.
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Önce bağımlılıklar: kod değişince bu katman cache'ten gelir, build hızlanır.
COPY requirements.lock.txt .
RUN pip install --no-cache-dir -r requirements.lock.txt

# Uygulama kodu + tarif görselleri (app/static/recipes)
COPY app ./app

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
