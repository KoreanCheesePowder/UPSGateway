FROM python:3.12-alpine
WORKDIR /app
COPY gateway.py /app/gateway.py
RUN mkdir -p /data
CMD ["python", "-u", "/app/gateway.py"]
