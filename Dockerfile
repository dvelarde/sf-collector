#
# Copyright (C) 2022 IBM Corporation.
#
# Authors:
# Frederico Araujo <frederico.araujo@ibm.com>
# Teryl Taylor <terylt@ibm.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ARG FALCO_VER
ARG FALCO_LIBS_VER
ARG FALCO_LIBS_DRIVER_VER
ARG UBI_VER

#-----------------------
# Stage: Libs
#-----------------------
FROM sysflowtelemetry/ubi:mods-${FALCO_LIBS_VER}-${FALCO_VER}-${UBI_VER} AS libs

# install path build args
ARG INSTALL_PATH=/usr/local/sysflow
ARG MODPREFIX=${INSTALL_PATH}/modules

# environment and build args
ARG BUILD_NUMBER=0
ARG DEBUG=0

# build libsysflow
COPY ./modules/sysflow/avro/avsc  /build/modules/sysflow/avro/avsc
COPY ./modules/sysflow/c\+\+/sysflow/sysflow.hh ${MODPREFIX}/include/sysflow/c\+\+/sysflow/sysflow.hh
COPY ./modules/sysflow/c\+\+/sysflow/avsc_sysflow4.hh ${MODPREFIX}/include/sysflow/c\+\+/sysflow/avsc_sysflow4.hh
COPY ./src/libs /build/src/libs
RUN make -C /build/src/libs \
         SYSFLOW_BUILD_NUMBER=$BUILD_NUMBER \
         LIBLOCALPREFIX=${MODPREFIX} \
         FALCOLOCALLIBPREFIX=${MODPREFIX}/lib/falcosecurity \
         FALCOLOCALINCPREFIX=${MODPREFIX}/include/falcosecurity \
         AVRLOCALLIBPREFIX=${MODPREFIX}/lib \
         AVRLOCALINCPREFIX=${MODPREFIX}/include \
         SFLOCALINCPREFIX=${MODPREFIX}/include/sysflow/c++ \
         FSLOCALINCPREFIX=${MODPREFIX}/include/filesystem \
         SCHLOCALPREFIX=${MODPREFIX}/conf \
         DEBUG=${DEBUG} \
         install

#-----------------------
# Stage: Collector
#-----------------------
FROM libs as collector

# environment and build args
ARG BUILD_NUMBER=0
ARG DEBUG=0

# install path build args
ARG INSTALL_PATH=/usr/local/sysflow
ARG MODPREFIX=${INSTALL_PATH}/modules

# build the collector (sysporter)
COPY ./src/collector /build/src/collector
RUN cd /build/src/collector && \
    make SYSFLOW_BUILD_NUMBER=$BUILD_NUMBER \
         LIBLOCALPREFIX=${MODPREFIX} \
         FALCOLOCALLIBPREFIX=${MODPREFIX}/lib/falcosecurity \
         FALCOLOCALINCPREFIX=${MODPREFIX}/include/falcosecurity \
         AVRLOCALLIBPREFIX=${MODPREFIX}/lib \
         AVRLOCALINCPREFIX=${MODPREFIX}/include \
         SFLOCALINCPREFIX=${MODPREFIX}/include/sysflow/c++ \
         FSLOCALINCPREFIX=${MODPREFIX}/include/filesystem \
         SCHLOCALPREFIX=${MODPREFIX}/conf \
         DEBUG=${DEBUG} \
         install

#-----------------------
# Stage: Runtime
#-----------------------
FROM sysflowtelemetry/ubi:base-${FALCO_LIBS_VER}-${FALCO_VER}-${UBI_VER} AS runtime

# environment variables
ARG interval=30
ENV INTERVAL=$interval

ARG filter=
ENV FILTER=$filter

ENV DRIVERPREFIX=/usr/src/falco-

ARG exporterid="local"
ENV EXPORTER_ID=$exporterid

ARG output=
ENV OUTPUT=$output

ARG cripath=
ENV CRI_PATH=$cripath

ARG critimeout=
ENV CRI_TIMEOUT=$critimeout

ARG debug=
ENV DEBUG=$debug

ARG gllogtostderr=1
ENV GLOG_logtostderr=$gllogtostderr

ARG glv=
ENV GLOG_v=$glv

ARG INSTALL_PATH=/usr/local/sysflow

ARG MODPREFIX=${INSTALL_PATH}/modules
ENV HOST_ROOT=/host

ARG sockfile=
ENV SOCK_FILE=

ARG VERSION=dev
ARG RELEASE=dev

ARG nodeip=
ENV NODE_IP=$nodeip

ARG FALCO_VER
ENV FALCO_VERSION=${FALCO_VER}

ARG FALCO_LIBS_VER
ENV FALCO_LIBS_VERSION=${FALCO_LIBS_VER}

ARG FALCO_LIBS_DRIVER_VER
ENV FALCO_LIBS_DRIVER_VERSION=${FALCO_LIBS_DRIVER_VER}

ENV DRIVER_NAME="falco"

ARG samplingRate=
ENV SAMPLING_RATE=$samplingRate

ENV DRIVERS_REPO="https://download.falco.org/driver"

# update labels
LABEL "name"="SysFlow Collector"
LABEL "vendor"="SysFlow"
LABEL "version"="${VERSION}"
LABEL "release"="${RELEASE}"
LABEL "falcolibs-version"="${FALCO_LIBS_VER}"
LABEL "falcodriver-version"="${FALCO_LIBS_DRIVER_VER}"
LABEL "summary"="The SysFlow Collector monitors and collects system call and event information from hosts and exports them in the SysFlow format using Apache Avro object serialization"
LABEL "description"="The SysFlow Collector monitors and collects system call and event information from hosts and exports them in the SysFlow format using Apache Avro object serialization"
LABEL "io.k8s.display-name"="SysFlow Collector"
LABEL "io.k8s.description"="The SysFlow Collector monitors and collects system call and event information from hosts and exports them in the SysFlow format using Apache Avro object serialization"

# update license
COPY ./LICENSE.md /licenses/LICENSE.md

# copy resources
COPY --from=collector ${INSTALL_PATH}/bin/sysporter ${INSTALL_PATH}/bin/sysporter
COPY --from=collector ${INSTALL_PATH}/modules/bin/docker-entry-ubi.sh /docker-entrypoint.sh
COPY --from=collector ${INSTALL_PATH}/modules/bin/docker-entrypoint.sh ${INSTALL_PATH}/modules/bin/docker-entrypoint.sh
COPY --from=collector ${INSTALL_PATH}/modules/bin/falco-driver-loader /usr/bin/falco-driver-loader
COPY --from=collector /falcosrc/ /usr/src/
COPY --from=collector ${INSTALL_PATH}/conf/ ${INSTALL_PATH}/conf/
COPY --from=collector /usr/sbin/dkms /usr/sbin/dkms

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD /usr/local/sysflow/bin/sysporter \
     ${INTERVAL:+-G} $INTERVAL \
     ${OUTPUT:+-w} $OUTPUT \
     ${EXPORTER_ID:+-e} "$EXPORTER_ID" \
     ${FILTER:+-f} "$FILTER" \
     ${CRI_PATH:+-p} ${CRI_PATH} \
     ${CRI_TIMEOUT:+-t} ${CRI_TIMEOUT} \
     ${SOCK_FILE:+-u} ${SOCK_FILE} \
     ${SAMPLING_RATE:+-s} ${SAMPLING_RATE} \
     ${DEBUG:+-d}

#-----------------------
# Stage: Testing
#-----------------------
FROM python:3.9-buster AS testing

# environment and build args
ARG BATS_VERSION=1.1.0

ARG wdir=/usr/local/sysflow
ENV WDIR=$wdir

ARG INSTALL_PATH=/usr/local/sysflow

# Install extra packages for tests
RUN mkdir /tmp/bats && cd /tmp/bats && \
    wget https://github.com/bats-core/bats-core/archive/v${BATS_VERSION}.tar.gz && \
    tar -xzf v${BATS_VERSION}.tar.gz && rm -rf v${BATS_VERSION}.tar.gz && \
    cd bats-core-${BATS_VERSION} && ./install.sh /usr/local && rm -rf /tmp/bats

# install APIs
COPY modules/sysflow/py3 ${INSTALL_PATH}/utils

RUN cd /usr/local/sysflow/utils && \
    python3 -m pip install .

# copy the collector binary
COPY --from=collector ${INSTALL_PATH}/bin/sysporter ${INSTALL_PATH}/bin/

WORKDIR $wdir
ENTRYPOINT ["/usr/local/bin/bats"]
