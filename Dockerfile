# syntax=docker/dockerfile:1
FROM dzhang55/cs6264:latest

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        vim \
        python3-pip \
        python3-setuptools \
        python-setuptools \
        python3-dev \
        libffi-dev \
        build-essential \
        virtualenvwrapper \
        # **<--- ADD THESE DEPENDENCIES --->**
        **git** \
        **cmake** \
        **libssl-dev** \
        **zlib1g-dev** \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install -U pip setuptools

USER lab1

RUN python3 -m pip install --user ropper
RUN python3 -m pip install --user angr
RUN python3 -m pip install --user pwntools
RUN python3 -m pip install --user pathlib2
