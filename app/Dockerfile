# Pin the Python minor line while still receiving compatible patch fixes.
FROM python:3.13-alpine

# Use a numeric unprivileged identity so Kubernetes can enforce runAsNonRoot.
USER 65534:65534
WORKDIR /app
COPY --chown=65534:65534 app.py /app/app.py

EXPOSE 8080
CMD ["python", "/app/app.py"]
