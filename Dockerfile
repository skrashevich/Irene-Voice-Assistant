# syntax=docker/dockerfile:1.5-labs
ARG PYTHON_VERSION=3.9
#
# FROM --platform=$BUILDPLATFORM curlimages/curl:7.85.0 as vosk-downloader
#
# WORKDIR /home/downloader/models
#
# RUN curl https://alphacephei.com/vosk/models/vosk-model-small-ru-0.22.zip -o ./c611af587fcbdacc16bc7a1c6148916c-vosk-model-small-ru-0.22.zip
#
# FROM --platform=$BUILDPLATFORM python:3.9-slim-bullseye as ssl-generator
#
# WORKDIR /home/generator/ssl
#
# RUN openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -sha256 -nodes -days 365 -subj "/C=RU/CN=*"
FROM python:${PYTHON_VERSION}-slim-bullseye as python-base
# Keeps Python from generating .pyc files in the container
ENV PYTHONDONTWRITEBYTECODE 1
# Turns off buffering for easier container logging
ENV PYTHONUNBUFFERED 1
# Don't fall back to legacy build system
ENV PIP_USE_PEP517=1
# Allow pre-release packages
ENV PIP_PRE=1

# Prepare apt for buildkit cache
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
  && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' >/etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt update && apt install -y --no-install-recommends libportaudio2

# Prepare pip for buildkit cache
ARG PIP_CACHE_DIR=/var/cache/buildkit/pip
ENV PIP_CACHE_DIR ${PIP_CACHE_DIR}
RUN mkdir -p ${PIP_CACHE_DIR}
ARG PIP_EXTRA_INDEX_URL
ENV PIP_EXTRA_INDEX_URL ${PIP_EXTRA_INDEX_URL}


FROM python-base as wheels-builder
#RUN groupadd --gid 1001 python && useradd --create-home python --uid 1001 --gid python
#USER python:python
WORKDIR /src

ADD ./requirements-docker.txt ./requirements.txt
RUN --mount=type=cache,target=${PIP_CACHE_DIR} pip wheel --wheel-dir=/wheels -r ./requirements.txt

FROM python-base
ARG PIP_CACHE_DIR=/var/cache/buildkit/pip
ENV PIP_CACHE_DIR ${PIP_CACHE_DIR}
RUN ln -s /bin/uname /usr/local/bin/uname \
    && ln -s /usr/bin/dpkg-split /usr/sbin/dpkg-split \
    && ln -s /usr/bin/dpkg-deb /usr/sbin/dpkg-deb \
    && ln -s /bin/rm /usr/sbin/rm \
    && ln -s /bin/tar /usr/sbin/tar \
    && groupadd --gid 1001 python \
    && useradd --no-log-init -m -u 1001 -g 1001 python

WORKDIR /home/python/irene
COPY --link --from=wheels-builder /src/requirements.txt ./requirements.txt
RUN --mount=type=cache,target=${PIP_CACHE_DIR} --mount=type=bind,source=/wheels,from=wheels-builder,target=/wheels <<EOT
    pip install --find-links=/wheels -r ./requirements.txt
    chown -R python:python /home/python/irene
EOT
USER python
ADD --chown=python:python lingua_franca media mic_client model mpcapi plugins utils webapi_client localhost.crt \
    localhost.key jaa.py vacore.py runva_webapi.py runva_webapi_docker.json /home/python/irene/
ADD --chown=python:python --link docker_plugins /home/python/plugins
#COPY --chown=python:python options_docker ./irene/options


#COPY --link --from=frontend-builder /home/frontend/dist/ ./irene_plugin_web_face_frontend/frontend-dist/
ADD --link https://models.silero.ai/models/tts/ru/v3_1_ru.pt /home/python/irene/silero_model.pt
# ADD --link --chown=1001:1001 https://alphacephei.com/vosk/models/vosk-model-small-ru-0.22.zip /src/irene/vosk-models/c611af587fcbdacc16bc7a1c6148916c-vosk-model-small-ru-0.22.zip
# COPY --link --chown=1001:1001 --from=ssl-generator /home/generator/ssl/ ./ssl/

EXPOSE 5003

#VOLUME /home/python/irene
# ENV IRENE_HOME=/irene
WORKDIR /home/python/irene
#ENTRYPOINT ["python", "-m", "irene", "--default-config", "/home/python/config"]
ENTRYPOINT ["python", "runva_webapi.py"]
#ENTRYPOINT uvicorn runva_webapi:app --proxy-headers --host 0.0.0.0 --port 8089