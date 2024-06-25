ARG BUILD_FROM
FROM $BUILD_FROM

# Create working directory
RUN mkdir -p /app
WORKDIR /app

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Copy requirements.txt to force Docker not to use the cache
COPY requirements.txt /app

ENV PYTHONUNBUFFERED=1
RUN apk add --update --no-cache python3 py3-pip python3-dev
RUN find /usr/lib/ -name 'EXTERNALLY-MANAGED' -exec rm {} \;
RUN /usr/bin/python3 -m pip install --no-cache pip wheel setuptools

# Install app dependencies
RUN python3 -m pip install -r requirements.txt

# Copy app source
COPY . /app

# Define entrypoint of the app
# Define entrypoint of the app
ENTRYPOINT ["python3", "-u", "extractor.py", "-c", "/ssl/traefik/acme.json", "-d", "/ssl"]
