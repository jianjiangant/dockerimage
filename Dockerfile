ARG ROOT_CONTAINER=horovod/horovod:master

FROM $ROOT_CONTAINER

LABEL maintainer="jianjiang"
ARG NB_USER="atp"
ARG NB_UID="1000"
ARG NB_GID="100"

# Fix DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root
COPY sources.list /etc/apt

# Install all OS dependencies for notebook server that starts but lacks all
# features (e.g., download as all possible file formats)
# Install tini: init for containers
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update --yes && \
    apt-get install --yes --no-install-recommends \
    tini \
    vim \
    ca-certificates \
    sudo \
    locales \
    fonts-liberation \
    run-one && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen

# Configure environment
ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    NB_USER="${NB_USER}" \
    NB_UID=${NB_UID} \
    NB_GID=${NB_GID} \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8
ENV PATH="${CONDA_DIR}/bin:${PATH}" \
    HOME="/home/${NB_USER}"
    #HOME="/work"

RUN mkdir "${HOME}"

# Copy a script that we will use to correct permissions after running certain commands
COPY fix-permissions /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions

# Enable prompt color in the skeleton .bashrc before creating the default NB_USER
# hadolint ignore=SC2016
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc && \
   # Add call to conda init script see https://stackoverflow.com/a/58081608/4413446
   echo 'eval "$(command conda shell.bash hook 2> /dev/null)"' >> /etc/skel/.bashrc

# Create NB_USER with name jovyan user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd -l -m -s /bin/bash -N -u "${NB_UID}" "${NB_USER}" && \
    mkdir -p "${CONDA_DIR}" && \
    chown "${NB_USER}:${NB_GID}" "${CONDA_DIR}" && \
    chmod g+w /etc/passwd && \
    fix-permissions "${HOME}" && \
    fix-permissions "${CONDA_DIR}"

RUN chmod 777 /tmp

COPY conda.conf ${HOME}
RUN mv ~/conda.conf ~/.condarc

USER ${NB_UID}
ARG PYTHON_VERSION=default

# Setup work directory for backward-compatibility
#RUN mkdir "/home/${NB_USER}/work" && \
#    fix-permissions "/home/${NB_USER}"


# Install conda as jovyan and check the sha256 sum provided on the download site
WORKDIR /tmp
ADD Mambaforge-Linux-x86_64.sh /tmp

# ---- Miniforge installer ----
# Check https://github.com/conda-forge/miniforge/releases
# Package Manager and Python implementation to use (https://github.com/conda-forge/miniforge)
# We're using Mambaforge installer, possible options:
# - conda only: either Miniforge3 to use Python or Miniforge-pypy3 to use PyPy
# - conda + mamba: either Mambaforge to use Python or Mambaforge-pypy3 to use PyPy
# Installation: conda, mamba, pip
RUN set -x && \
    # Miniforge installer
    miniforge_arch=$(uname -m) && \
    miniforge_installer="Mambaforge-Linux-${miniforge_arch}.sh" && \
    /bin/bash "${miniforge_installer}" -f -b -p "${CONDA_DIR}" && \
    rm "${miniforge_installer}" && \
    # Conda configuration see https://conda.io/projects/conda/en/latest/configuration.html
    conda config --system --set auto_update_conda false && \
    conda config --system --set show_channel_urls true && \
    if [[ "${PYTHON_VERSION}" != "default" ]]; then mamba install --quiet --yes python="${PYTHON_VERSION}"; fi && \
    mamba list python | grep '^python ' | tr -s ' ' | cut -d ' ' -f 1,2 >> "${CONDA_DIR}/conda-meta/pinned" && \
    # Using conda to update all packages: https://github.com/mamba-org/mamba/issues/1092
    conda update --all --quiet --yes && \
    conda clean --all -f -y && \
    rm -rf "/home/${NB_USER}/.cache/yarn" && \
    fix-permissions "${CONDA_DIR}" && \
    #fix-permissions "/home/${NB_USER}"
    fix-permissions "${HOME}"

# Install Jupyter Notebook, Lab, and Hub
# Generate a notebook server config
# Cleanup temporary files
# Correct permissions
# Do all this in a single RUN command to avoid duplicating all of the
# files across image layers when the permissions change


RUN mamba install --quiet --yes \
    'notebook' \
    'jupyterhub' \
    'jupyterlab' && \
    mamba clean --all -f -y && \
    npm cache clean --force && \
    jupyter notebook --generate-config && \
    jupyter lab clean && \
    rm -rf "/home/${NB_USER}/.cache/yarn" && \
    fix-permissions "${CONDA_DIR}" && \
    #fix-permissions "/home/${NB_USER}"
    fix-permissions "${HOME}"


#RUN conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free/ && \
#	    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main/ && \
#	    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/pytorch/ && \
#	    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge/ && \
#	    conda config --set show_channel_urls yes
#
#RUN conda create -n pytorch && \
#    source activate pytorch && \
#    mamba install --yes  --quiet pytorch==1.7.0 torchvision cudatoolkit=10.1 -c pytorch && \
#    #conda install --yes  pytorch==1.9.0  cudatoolkit=10.1 -c pytorch && \
#    #conda install --yes pytorch torchvision cudatoolkit=10.1 -c pytorch && \
#    pip install ipykernel -i https://pypi.tuna.tsinghua.edu.cn/simple some-package && \
#    mamba clean --all -f -y && \
#    npm cache clean --force && \
#    python -m ipykernel install --user --name pytorch --display-name "pytorch"
#
#RUN conda create -n tensorflow && \
#    source activate tensorflow && \
#    mamba install --yes --quiet tensorflow && \
#    pip install ipykernel -i https://pypi.tuna.tsinghua.edu.cn/simple some-package && \
#    mamba clean --all -f -y && \
#    npm cache clean --force && \
#    python -m ipykernel install --user --name tensorflow --display-name "tensorflow"


## config Tsinghua conda source

#RUN conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free/ && \
#	    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main/ && \
#	    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/pytorch/ && \
#	    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge/ && \
#	    conda config --set show_channel_urls yes



RUN conda create -n pytorch && \
    source activate pytorch && \
   # conda install --yes   pytorch==1.7.0 torchvision cudatoolkit=10.1 -c pytorch && \
    mamba install --yes --quiet pytorch==1.7.1 torchvision==0.8.2 torchaudio==0.7.2 cudatoolkit=10.1 -c pytorch && \

#    conda install --yes  pytorch==1.9.0  cudatoolkit=10.1 -c pytorch && \
    #conda install --yes pytorch torchvision cudatoolkit=10.2 && \
    pip install ipykernel -i https://pypi.tuna.tsinghua.edu.cn/simple some-package && \
    #mamba clean --all -f -y && \
    npm cache clean --force && \
    python -m ipykernel install --user --name pytorch --display-name "pytorch"

RUN conda create -n tensorflow && \
    source activate tensorflow && \
    #mamba install --yes --quiet tensorflow && \
    conda install --yes tensorflow-gpu && \
    pip install ipykernel -i https://pypi.tuna.tsinghua.edu.cn/simple some-package && \
    #mamba clean --all -f -y && \
    #npm cache clean --force && \
    python -m ipykernel install --user --name tensorflow --display-name "tensorflow"

EXPOSE 8888

# Configure container startup
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]

# Copy local files as late as possible to avoid cache busting
COPY start.sh start-notebook.sh start-singleuser.sh /usr/local/bin/
# Currently need to have both jupyter_notebook_config and jupyter_server_config to support classic and lab
COPY jupyter_notebook_config.py /etc/jupyter/

# Fix permissions on /etc/jupyter as root
USER root
RUN mkdir -p /work
RUN chmod 755 /work

#ENV HOME="/home/atp"
#RUN mkdir -p ${HOME}
#RUN fix-permissions ${HOME}


# Prepare upgrade to JupyterLab V3.0 #1205
RUN sed -re "s/c.NotebookApp/c.ServerApp/g" \
    /etc/jupyter/jupyter_notebook_config.py > /etc/jupyter/jupyter_server_config.py && \
    fix-permissions /etc/jupyter/ && \
    rm -rf /usr/local/bin/wget /usr/local/bin/df /usr/local/bin/lsblk /usr/local/bin/mount /usr/local/bin/umount

# Switch back to jovyan to avoid accidental container runs as root
USER ${NB_UID}

#WORKDIR "${HOME}/work"
WORKDIR "/work"

