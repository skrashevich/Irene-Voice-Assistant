# syntax=docker/dockerfile:labs
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
# ENV PIP_PRE=1

# Prepare apt for buildkit cache
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
  && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' >/etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt update && apt install -y --no-install-recommends libportaudio2

# Prepare pip for buildkit cache
ARG PIP_CACHE_DIR=/var/cache/buildkit/pip
ENV PIP_CACHE_DIR ${PIP_CACHE_DIR}
RUN mkdir -p ${PIP_CACHE_DIR} && chmod 777 ${PIP_CACHE_DIR}
ARG PIP_EXTRA_INDEX_URL
ENV PIP_EXTRA_INDEX_URL ${PIP_EXTRA_INDEX_URL}


FROM python-base as wheels-builder
ARG PIP_CACHE_DIR=/var/cache/buildkit/pip
ENV PIP_CACHE_DIR ${PIP_CACHE_DIR}
WORKDIR /src

ADD ./requirements-docker.txt ./requirements.txt
RUN --mount=type=cache,target=${PIP_CACHE_DIR} pip wheel --wheel-dir=/wheels -r ./requirements.txt

FROM python-base

# Create a new user
ARG UNAME=python
ENV UNAME ${UNAME}
ARG UID=1001
ARG GID=1001
RUN groupadd -o -g "${GID}" "${UNAME}" && useradd \
  --no-log-init \
  -m \
  -u ${UID} \
  -g ${GID} \
  "${UNAME}"

WORKDIR /home/${UNAME}/irene
COPY --link --from=wheels-builder /src/requirements.txt ./requirements.txt
RUN --mount=type=bind,source=/wheels,from=wheels-builder,target=/wheels <<EOT
    pip install --find-links=/wheels -r ./requirements.txt
    chown -R ${UNAME}:${UNAME} /home/${UNAME}/irene
EOT
COPY --link --chown=${UNAME} https://models.silero.ai/models/tts/ru/v3_1_ru.pt /home/${UNAME}/irene/silero_model.pt

ADD --chown=${UNAME}:${UNAME} lingua_franca media mic_client model mpcapi plugins utils webapi_client localhost.crt \
    localhost.key jaa.py vacore.py runva_webapi.py runva_webapi_docker.json /home/${UNAME}/irene/
ADD --chown=${UNAME}:${UNAME} --link docker_plugins /home/${UNAME}/plugins
# COPY --chown=python:python options_docker ./irene/options


# COPY --link --from=frontend-builder /home/frontend/dist/ ./irene_plugin_web_face_frontend/frontend-dist/
# ADD --link --chown=1001:1001 https://alphacephei.com/vosk/models/vosk-model-small-ru-0.22.zip /src/irene/vosk-models/c611af587fcbdacc16bc7a1c6148916c-vosk-model-small-ru-0.22.zip
# COPY --link --chown=1001:1001 --from=ssl-generator /home/generator/ssl/ ./ssl/

EXPOSE 5003

#VOLUME /home/python/irene
# ENV IRENE_HOME=/irene
WORKDIR /home/${UNAME}/irene
#ENTRYPOINT ["python", "-m", "irene", "--default-config", "/home/python/config"]
USER ${UNAME}
ENTRYPOINT ["python", "runva_webapi.py"]
#ENTRYPOINT uvicorn runva_webapi:app --proxy-headers --host 0.0.0.0 --port 8089