FROM ocaml/opam:alpine AS binary
RUN sudo apk update
RUN opam install -y depext
RUN opam depext jbuilder lwt cohttp cohttp-lwt-unix yojson tls sqlite3 camlimages
RUN opam install -y jbuilder lwt cohttp cohttp-lwt-unix tls
RUN opam install -y yojson sqlite3 camlimages
RUN mkdir /home/opam/xkcd
WORKDIR /home/opam/xkcd
RUN sudo apk add git
RUN git clone https://github.com/pNre/Relevant-XKCD-Bot.git .
RUN eval `opam config env` && make

FROM alpine
RUN apk add --no-cache ca-certificates && update-ca-certificates
RUN apk update
RUN apk add sqlite-libs gmp
WORKDIR /app
ENV PORT 8000
EXPOSE 8000
COPY --from=binary /home/opam/xkcd/bin/xkcdbot /app
COPY --from=binary /home/opam/xkcd/bin/xkcdbot-indexer /app
VOLUME ["/database"]
RUN printf "#!/bin/sh\n/app/xkcdbot-indexer /database/comics > /var/log/indexer.log\n" > /etc/periodic/hourly/indexer
RUN chmod +x /etc/periodic/hourly/indexer
CMD ["sh", "-c", "crond && /app/xkcdbot /database/comics xkcd"]
