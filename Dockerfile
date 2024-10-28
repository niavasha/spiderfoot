#
# Spiderfoot Dockerfile
#
# http://www.spiderfoot.net
#
# Written by: Michael Pellon <m@pellon.io>
# Updated by: Chandrapal <bnchandrapal@protonmail.com>
# Updated by: Steve Micallef <steve@binarypool.com>
# Updated by: Steve Bate <svc-spiderfoot@stevebate.net>
#    -> Inspired by https://github.com/combro2k/dockerfiles/tree/master/alpine-spiderfoot
# Updated by: Harry Manley <niavasha@gmail.com> - 2024-10-28
#
# Usage:
#
#   sudo docker build -t spiderfoot .
#   sudo docker run -p 5001:5001 --security-opt no-new-privileges spiderfoot
#
# Using Docker volume for spiderfoot data
#
#   sudo docker run -p 5001:5001 -v /mydir/spiderfoot:/var/lib/spiderfoot spiderfoot
#
# Using SpiderFoot remote command line with web server
#
#   docker run --rm -it spiderfoot sfcli.py -s http://my.spiderfoot.host:5001/
#
# Running spiderfoot commands without web server (can optionally specify volume)
#
#   sudo docker run --rm spiderfoot sf.py -h
#
# Running a shell in the container for maintenance
#   sudo docker run -it --entrypoint /bin/sh spiderfoot
#
# Running spiderfoot unit tests in container
#
#   sudo docker build -t spiderfoot-test --build-arg REQUIREMENTS=test/requirements.txt .
#   sudo docker run --rm spiderfoot-test -m pytest --flake8 .

FROM kalilinux/kali-rolling:latest AS build

FROM build

# Place database and logs outside installation directory
ENV SPIDERFOOT_DATA /var/lib/spiderfoot
ENV SPIDERFOOT_LOGS /var/lib/spiderfoot/log
ENV SPIDERFOOT_CACHE /var/lib/spiderfoot/cache
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/venv/bin":$PATH
ENV GOPATH /go
ENV PATH="$GOPATH/bin:$PATH"

ARG REQUIREMENTS=requirements.txt
RUN apt update && apt install -y gcc git curl python3 python3-dev swig libtinyxml-dev \
 python3-dev musl-dev libssl-dev libffi-dev libxslt-dev libxml2-dev libjpeg-dev python3-pip \
 libopenjp2-7-dev  zlib1g-dev cargo rust-all python3-venv golang
RUN python3 -m venv /opt/venv
COPY $REQUIREMENTS requirements.txt ./
RUN mkdir -p "$GOPATH/src" "$GOPATH/bin"
# Install tools/dependencies from apt

RUN apt-get -y update && apt-get -y install nbtscan onesixtyone nmap

# Compile other tools from source
RUN mkdir /tools || true
WORKDIR /tools

RUN git clone --depth=1 https://github.com/blechschmidt/massdns.git \
   && cd massdns && make && make install

RUN GO111MODULE=on go install -v github.com/projectdiscovery/shuffledns/cmd/shuffledns@latest
# Install Golang tools
RUN apt-get -y update && apt-get -y install golang
RUN mkdir -p "$GOPATH/src" "$GOPATH/bin"

# Install Ruby tools for WhatWeb
RUN apt-get -y update && apt-get -y install ruby ruby-dev bundler libyaml-dev nodejs
# Install WhatWeb
RUN git clone https://github.com/urbanadventurer/WhatWeb \
    && gem install rchardet mongo json && cd /tools/WhatWeb \
    && bundle install && cd /tools

RUN groupadd spiderfoot \
    && useradd -u 99 -g spiderfoot -d /home/spiderfoot -s /bin/bash spiderfoot

# Install RetireJS
RUN apt remove -y cmdtest \
    && apt remove -y yarn \
    && curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
    && echo 'deb https://dl.yarnpkg.com/debian/ stable main' |tee /etc/apt/sources.list.d/yarn.list \
    && apt-get update \
    && apt-get install yarn -y \
    && yarn install \
    && curl -fsSL https://deb.nodesource.com/setup_17.x | bash - \
    && apt install -y npm \
    && npm install -g retire

# Install Google Chrome the New Way (Not via apt-key)
RUN apt install -y wget \
    && wget -qO - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/googlechrome-linux-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/googlechrome-linux-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | tee /etc/apt/sources.list.d/google-chrome.list \
    && apt -y update && apt install --allow-unauthenticated -y google-chrome-stable

# Install Wappalyzer
RUN git clone https://github.com/tunetheweb/wappalyzer.git \
    && cd wappalyzer \
    && yarn install && yarn run link

# Install Nuclei
RUN wget https://github.com/projectdiscovery/nuclei/releases/download/v2.6.5/nuclei_2.6.5_linux_amd64.zip \
    && unzip nuclei_2.6.5_linux_amd64.zip \
    && git clone https://github.com/projectdiscovery/nuclei-templates.git


# Install Snallygaster and TruffleHog
RUN pip3 install snallygaster trufflehog

WORKDIR /home/spiderfoot
COPY . .

# Run everything as one command so that only one layer is created
RUN apt update && apt -y install python3 musl openssl libxslt1.1 \
 libtinyxml2-10 libxml2 libjpeg62-turbo zlib1g  libopenjp2-7 \
 cmseek dnstwist nbtscan nmap nmap-common python3-libnmap \
 python3-nmap onesixtyone whatweb wafw00f trufflehog python3-trufflehogregexes pipx bsdmainutils dnsutils coreutils \
    && chmod +x /usr/share/cmseek/cmseek.py \
    && rm -rf /var/cache/apt/* \
    && rm -rf /lib/apt/db \
    && rm -rf /root/.cache \
    && mkdir -p $SPIDERFOOT_DATA || true \
    && mkdir -p $SPIDERFOOT_LOGS || true \
    && mkdir -p $SPIDERFOOT_CACHE || true \
    && chown -R 99 /home/spiderfoot \
    && chown -R 99 $SPIDERFOOT_DATA \
    && chown -R 99 $SPIDERFOOT_LOGS \
    && chown -R 99 $SPIDERFOOT_CACHE

#RUN useradd -u 99 -g spiderfoot -d /home/spiderfoot -s /bin/bash spiderfoot

RUN mkdir -p "$VIRTUAL_ENV" || true
RUN chown -R 99 /tools
RUN chown -R 99 "$VIRTUAL_ENV"
RUN chown -R 99 "/home/spiderfoot"

USER spiderfoot
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
RUN python -m venv "$VIRTUAL_ENV"


# Place database and logs outside installation directory
ENV SPIDERFOOT_DATA /var/lib/spiderfoot
ENV SPIDERFOOT_LOGS /var/lib/spiderfoot/log
ENV SPIDERFOOT_CACHE /var/lib/spiderfoot/cache

COPY . .

ENV PATH="/opt/venv/bin:$PATH"

RUN cat /etc/passwd
RUN cat /etc/passwd

RUN pip3 install -U pip
RUN pip3 install -r "$REQUIREMENTS"

RUN pip3 install dnstwist
# CMSeeK
WORKDIR /tools

RUN git clone https://github.com/drwetter/testssl.sh.git 
RUN git clone https://github.com/Tuhinshubhra/CMSeeK && cd CMSeeK \
    && pip3 install -r requirements.txt && mkdir Results

USER root

RUN echo 'spiderfoot ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    usermod -aG sudo spiderfoot

USER spiderfoot

# Install wafw00f
RUN pipx install git+https://github.com/EnableSecurity/wafw00f.git
WORKDIR /home/spiderfoot
CMD mkdir -p /tools/CMSeeK/Result

EXPOSE 5001

# Run the application.
CMD python -c 'from spiderfoot import SpiderFootDb; \
db = SpiderFootDb({"__database": "/var/lib/spiderfoot/spiderfoot.db"}); \
db.configSet({ \
    "sfp_tool_dnstwist:dnstwistpath": "/opt/venv/bin/dnstwist", \
    "sfp_tool_cmseek:cmseekpath": "/tools/CMSeeK/cmseek.py", \
    "sfp_tool_whatweb:whatweb_path": "/tools/WhatWeb/whatweb", \
    "sfp_tool_wafw00f:wafw00f_path": "/home/spiderfoot/.local/bin/wafw00f", \
    "sfp_tool_onesixtyone:onesixtyone_path": "/usr/bin/onesixtyone", \
    "sfp_tool_retirejs:retirejs_path": "/usr/local/bin/retire", \
    "sfp_tool_testsslsh:testsslsh_path": "/tools/testssl.sh/testssl.sh", \
    "sfp_tool_snallygaster:snallygaster_path": "/opt/venv/bin/snallygaster", \
    "sfp_tool_trufflehog:trufflehog_path": "/usr/bin/trufflehog", \
    "sfp_tool_nuclei:nuclei_path": "/tools/nuclei", \
    "sfp_tool_nuclei:template_path": "/tools/nuclei-templates", \
    "sfp_tool_wappalyzer:wappalyzer_path": "/tools/wappalyzer/src/drivers/npm/cli.js", \
    "sfp_tool_nbtscan:nbtscan_path": "/usr/bin/nbtscan", \
    "sfp_tool_nmap:nmappath": "DISABLED_BECAUSE_NMAP_REQUIRES_ROOT_TO_WORK" \
})' || true && ./sf.py -l 0.0.0.0:5001
