FROM hadolint/hadolint:v2.12.1-beta-debian AS hadolint

FROM golang:1.23.4 AS docker-debug

ARG TARGETARCH TARGETOS

WORKDIR /repo

RUN git clone https://github.com/zeromake/docker-debug.git \
    && cd docker-debug \
    && CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -ldflags="-s -w" -o docker-debug ./cmd/docker-debug

FROM codercom/code-server:4.96.2

ARG TARGETARCH

USER root

RUN apt-get update \
    && apt-get install ca-certificates curl \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && groupadd docker \
    && usermod -aG docker coder \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN wget -O /tmp/grype.deb https://github.com/anchore/grype/releases/download/v0.86.1/grype_0.86.1_linux_${TARGETARCH}.deb \
    && apt-get install -y /tmp/grype.deb \
    && rm /tmp/grype.deb \
    && wget -O /tmp/syft.deb https://github.com/anchore/syft/releases/download/v1.18.1/syft_1.18.1_linux_${TARGETARCH}.deb \
    && apt-get install -y /tmp/syft.deb \
    && rm /tmp/syft.deb \
    && wget -O /tmp/dive.deb https://github.com/wagoodman/dive/releases/download/v0.12.0/dive_0.12.0_linux_${TARGETARCH}.deb \
    && apt-get install -y /tmp/dive.deb \
    && rm /tmp/dive.deb \
    && wget -O /tmp/cosign.deb https://github.com/sigstore/cosign/releases/download/v2.4.1/cosign_2.4.1_${TARGETARCH}.deb \
    && apt-get install -y /tmp/cosign.deb \
    && rm /tmp/cosign.deb \
    && wget -O /usr/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-${TARGETARCH} \
    && chmod +x /usr/bin/jq \
    && wget -O /usr/bin/vexctl https://github.com/openvex/vexctl/releases/download/v0.3.0/vexctl-linux-${TARGETARCH} \
    && chmod +x /usr/bin/vexctl \
    && wget -O /usr/bin/vexctl https://github.com/openvex/vexctl/releases/download/v0.3.0/vexctl-linux-${TARGETARCH} \
    && chmod +x /usr/bin/vexctl \
    && wget -O /usr/bin/container-structure-test https://github.com/GoogleContainerTools/container-structure-test/releases/download/v1.19.3/container-structure-test-linux-${TARGETARCH} \
    && chmod +x /usr/bin/container-structure-test

COPY --from=hadolint /bin/hadolint /usr/bin/hadolint
COPY --from=docker-debug --chmod=555 /repo/docker-debug/docker-debug /usr/bin/docker-debug

USER coder