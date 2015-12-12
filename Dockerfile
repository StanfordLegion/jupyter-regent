# Jupyter with Regent kernel

FROM jupyter/minimal-notebook:4.0

MAINTAINER Elliott Slaughter <slaughter@cs.stanford.edu>

# Install dependencies as root
USER root

# Regent dependencies
RUN apt-get update && \
    apt-get install -y build-essential clang-3.5 libclang-3.5-dev libncurses5-dev llvm-3.5-dev zlib1g-dev && \
    apt-get clean

# Regent
RUN git clone -b master https://github.com/StanfordLegion/legion.git /usr/local/legion && \
    LLVM_CONFIG=llvm-config-3.5 /usr/local/legion/language/install.py && \
    ln -s /usr/local/legion/language/regent.py /usr/bin/regent

# Regent kernel configuration files
RUN mkdir /usr/local/lib/python3.4/dist-packages/notebook/static/components/codemirror/mode/regent
COPY codemirror/regent/regent.js /usr/local/lib/python3.4/dist-packages/notebook/static/components/codemirror/mode/regent/regent.js

RUN mkdir -p /usr/local/share/jupyter/kernels/regent
COPY kernels/regent/kernel.json /usr/local/share/jupyter/kernels/regent/kernel.json
COPY kernels/regent/regentkernel.py /usr/local/share/jupyter/kernels/regent/regentkernel.py

# Install customization as the user
USER jovyan

RUN mkdir -p /home/jovyan/.ipython/profile_default/static/custom
COPY static/custom/custom.js /home/jovyan/.ipython/profile_default/static/custom/custom.js

RUN mkdir /home/jovyan/notebooks
COPY ["notebooks/Getting Started.ipynb", "/home/jovyan/notebooks/Getting Started.ipynb"]
