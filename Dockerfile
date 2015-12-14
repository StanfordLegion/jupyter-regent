# Regent kernel for Jupyter

FROM stanfordlegion/regent

MAINTAINER Elliott Slaughter <slaughter@cs.stanford.edu>

# Install Dependencies.
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && \
    apt-get install -y python3-pip wget && \
    apt-get clean
RUN pip3 install ipython notebook

# Install Tini.
RUN wget --quiet https://github.com/krallin/tini/releases/download/v0.6.0/tini && \
    echo "d5ed732199c36a1189320e6c4859f0169e950692f451c03e7854243b95f4234b *tini" | sha256sum -c - && \
    mv tini /usr/local/bin/tini && \
    chmod +x /usr/local/bin/tini

# Regent kernel configuration files.
RUN mkdir /usr/local/lib/python3.4/dist-packages/notebook/static/components/codemirror/mode/regent
COPY codemirror/regent/regent.js /usr/local/lib/python3.4/dist-packages/notebook/static/components/codemirror/mode/regent/regent.js

RUN mkdir -p /usr/local/share/jupyter/kernels/regent
COPY kernels/regent/kernel.json /usr/local/share/jupyter/kernels/regent/kernel.json
COPY kernels/regent/regentkernel.py /usr/local/share/jupyter/kernels/regent/regentkernel.py

ENV NB_USER jovyan
ENV NB_UID 1000
RUN useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    mkdir /home/$NB_USER/notebooks && \
    mkdir -p /home/$NB_USER/.ipython/profile_default/static/custom
COPY static/custom/custom.js /home/$NB_USER/.ipython/profile_default/static/custom/custom.js
COPY ["notebooks/Getting Started.ipynb", "/home/$NB_USER/notebooks/Getting Started.ipynb"]
RUN chown -R $NB_USER:users /home/$NB_USER

# Configure container startup.
EXPOSE 8888
WORKDIR /home/$NB_USER/notebooks
ENTRYPOINT ["tini", "--"]
CMD ["su", "$NB_USER", "-c", "jupyter", "notebook"]
