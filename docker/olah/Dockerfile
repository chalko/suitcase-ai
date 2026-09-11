FROM python:3.11-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends git ca-certificates gcc python3-dev && \
    pip install --no-cache-dir olah && \
    apt-get purge -y gcc python3-dev && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

EXPOSE 8090

ENTRYPOINT ["olah-cli"]
CMD ["--repos-path", "/data/cache", "--cache-size-limit", "15GB", "--cache-clean-strategy", "LRU", "--port", "8090", "--host", "0.0.0.0", "--mirror-scheme", "https", "--mirror-netloc", "olah.colt.chalko.com"]
