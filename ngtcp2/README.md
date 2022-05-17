# Manual
-----

1. Download Openssl with quic https://github.com/quictls/openssl
2. Unzip it and change directory name to openssl-1.1.1? and put it in openssl after taring it
3. Now there should be a file named openssl-1.1.1?.tar.gz in openssl directory
4. Build Openssl with quic and others `./build.sh`
5. Go to ngtcp2
6. clone [nghttp3](https://github.com/ngtcp2/nghttp3) and [ngtcp2](https://github.com/ngtcp2/ngtcp2)
7. In nghttp3 choose the right tag and run `autoreconf -i && ../configure-nghttp3.sh`
8. In ngtcp2 choose the right tag and run `autoreconf -i && ../configure-ngtcp2.sh`