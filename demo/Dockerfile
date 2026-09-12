# FIXTURE: deliberately bad Dockerfile used by scripts/verify.sh to prove hadolint fires.
# Expected findings: DL3007 (:latest), DL3002 (ends as root), DL3020 (ADD over COPY),
# DL3009 (apt lists not cleaned), DL3015 (no --no-install-recommends), DL3064 (secret in ENV).
FROM ubuntu:latest

# DL3064 fires on the variable name, so the value stays an obvious placeholder.
ENV AWS_SECRET_ACCESS_KEY=placeholder-not-a-real-key

RUN apt-get update && apt-get install -y curl

ADD https://example.invalid/installer.sh /tmp/installer.sh

USER root

CMD ["/bin/bash"]
