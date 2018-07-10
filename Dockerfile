FROM golang:1.10
WORKDIR /usr/local/go/src/github.com/percona/mongodb_exporter
COPY . .
RUN make

FROM quay.io/prometheus/busybox
COPY --from=0 /usr/local/go/src/github.com/percona/mongodb_exporter/mongodb_exporter /bin/mongodb_exporter
EXPOSE 9216
ENTRYPOINT [ "/bin/mongodb_exporter" ]
